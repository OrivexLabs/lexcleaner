import Foundation
import Security
import SystemConfiguration

public enum NetworkDNSConfigurationError: Error, LocalizedError, Equatable, Sendable {
    case invalidServer(String)
    case serviceUnavailable
    case ambiguousService
    case configurationChanged
    case authorizationRequired
    case authorizationCancelled
    case applyFailed(Int32)
    case verificationFailed
    case journalFailed
    case rollbackFailed

    public var errorDescription: String? {
        switch self {
        case .invalidServer: return "The proposed DNS server address is invalid."
        case .serviceUnavailable: return "The selected network service is unavailable."
        case .ambiguousService: return "The selected network interface maps to multiple network services."
        case .configurationChanged: return "The network configuration changed before the operation completed."
        case .authorizationRequired: return "Administrator authorization is required."
        case .authorizationCancelled: return "Administrator authorization was cancelled."
        case .applyFailed: return "The DNS configuration could not be applied."
        case .verificationFailed: return "The DNS configuration could not be verified after the change."
        case .journalFailed: return "The recovery journal could not be written safely."
        case .rollbackFailed: return "The original DNS configuration could not be restored."
        }
    }
}

public struct NetworkDNSServiceSnapshot: Codable, Equatable, Sendable {
    public let serviceID: String
    public let serviceName: String
    public let interfaceBSDName: String
    public let servers: [String]
    public let configurationData: Data

    public init(
        serviceID: String,
        serviceName: String,
        interfaceBSDName: String,
        servers: [String],
        configurationData: Data
    ) {
        self.serviceID = serviceID
        self.serviceName = serviceName
        self.interfaceBSDName = interfaceBSDName
        self.servers = servers
        self.configurationData = configurationData
    }
}

public protocol NetworkDNSConfigurationStore: Sendable {
    func read(serviceID: String?, interfaceBSDName: String?) throws -> NetworkDNSServiceSnapshot
    func apply(servers: [String], to snapshot: NetworkDNSServiceSnapshot) throws
    func restore(_ snapshot: NetworkDNSServiceSnapshot, expectedCurrent: NetworkDNSServiceSnapshot) throws
}

public protocol NetworkOptimizationProbe: Sendable {
    func benchmarkDNS(_ servers: [DNSBenchmarkServer]) async throws -> [DNSBenchmarkResult]
    func benchmarkTCP() async throws -> NetworkProbeStatistics
}

extension NetworkHealthCollector: NetworkOptimizationProbe {}

public protocol NetworkDNSRecoveryJournal: Sendable {
    func save(_ record: NetworkDNSJournalRecord) throws
    func load() throws -> NetworkDNSJournalRecord?
    func clear() throws
}

public enum NetworkDNSJournalState: String, Codable, Equatable, Sendable {
    case pending
    case active
}

public struct NetworkDNSJournalRecord: Codable, Equatable, Sendable {
    public let plan: NetworkOptimizationPlan
    public let snapshot: NetworkDNSServiceSnapshot
    public let state: NetworkDNSJournalState

    public init(plan: NetworkOptimizationPlan, snapshot: NetworkDNSServiceSnapshot, state: NetworkDNSJournalState) {
        self.plan = plan
        self.snapshot = snapshot
        self.state = state
    }
}

public struct NetworkOptimizationService: Sendable {
    private let store: any NetworkDNSConfigurationStore
    private let probe: any NetworkOptimizationProbe
    private let journal: any NetworkDNSRecoveryJournal

    public init(
        store: any NetworkDNSConfigurationStore = SystemNetworkDNSConfigurationStore(),
        probe: any NetworkOptimizationProbe = NetworkHealthCollector(),
        journal: any NetworkDNSRecoveryJournal = FileNetworkDNSRecoveryJournal()
    ) {
        self.store = store
        self.probe = probe
        self.journal = journal
    }

    public func makeDNSPlan(
        current: [String],
        proposed: [String],
        targetServiceID: String? = nil,
        targetServiceName: String? = nil,
        targetInterface: String? = nil
    ) -> NetworkOptimizationPlan? {
        let current = current.filter { !$0.isEmpty }
        let proposed = proposed.filter { !$0.isEmpty }
        guard !current.isEmpty, !proposed.isEmpty, current != proposed,
              proposed.allSatisfy(Self.isValidServerAddress) else { return nil }
        return NetworkOptimizationPlan(
            kind: .dns,
            originalDNS: current,
            proposedDNS: proposed,
            targetServiceID: targetServiceID,
            targetServiceName: targetServiceName,
            targetInterface: targetInterface,
            requiresAdministrator: true
        )
    }

    public func apply(_ plan: NetworkOptimizationPlan, userConfirmed: Bool = false) async -> NetworkOptimizationResult {
        guard userConfirmed else {
            return NetworkOptimizationResult(
                status: .requiresAdministrator,
                detail: "Explicit user confirmation is required before administrator authorization; no setting was changed."
            )
        }
        guard plan.kind == .dns,
              !plan.originalDNS.isEmpty,
              !plan.proposedDNS.isEmpty,
              plan.proposedDNS.allSatisfy(Self.isValidServerAddress) else {
            return failure(.invalidServer(plan.proposedDNS.first ?? ""), detail: "Invalid DNS server configuration.")
        }

        var snapshot: NetworkDNSServiceSnapshot
        do {
            snapshot = try store.read(serviceID: plan.targetServiceID, interfaceBSDName: plan.targetInterface)
            guard snapshot.servers == plan.originalDNS else {
                return failure(.configurationChanged, detail: "The selected network service changed before authorization; no setting was changed.")
            }

            let beforeDNS = try await benchmark(servers: plan.originalDNS, label: "Original DNS")
            let beforeTCP = try await probe.benchmarkTCP()
            try Task.checkCancellation()

            try journal.save(NetworkDNSJournalRecord(plan: plan, snapshot: snapshot, state: .pending))
            do {
                try store.apply(servers: plan.proposedDNS, to: snapshot)
            } catch let error as NetworkDNSConfigurationError {
                _ = reconcileFailedApply(plan: plan, snapshot: snapshot)
                return failure(error, before: beforeTCP, beforeDNS: beforeDNS, detail: error.localizedDescription)
            } catch {
                _ = reconcileFailedApply(plan: plan, snapshot: snapshot)
                return failure(.applyFailed(-1), before: beforeTCP, beforeDNS: beforeDNS, detail: error.localizedDescription)
            }

            do {
                let afterSnapshot = try store.read(serviceID: snapshot.serviceID, interfaceBSDName: snapshot.interfaceBSDName)
                guard afterSnapshot.servers == plan.proposedDNS else {
                    return rollbackAfterFailure(plan: plan, snapshot: snapshot, before: beforeTCP, beforeDNS: beforeDNS, error: .verificationFailed)
                }

                let afterDNS = try await benchmark(servers: plan.proposedDNS, label: "Proposed DNS")
                let afterTCP = try await probe.benchmarkTCP()
                let improved = Self.isImprovement(beforeDNS: beforeDNS, afterDNS: afterDNS, beforeTCP: beforeTCP, afterTCP: afterTCP)
                guard improved else {
                    let rollback = tryRestore(snapshot: snapshot, plan: plan)
                    if rollback {
                        return NetworkOptimizationResult(
                            status: .rolledBack,
                            before: beforeTCP,
                            after: afterTCP,
                            beforeDNS: beforeDNS,
                            afterDNS: afterDNS,
                            improved: false,
                            rollbackVerified: true,
                            detail: "The measured result did not improve; the original DNS configuration was restored."
                        )
                    }
                    return NetworkOptimizationResult(
                        status: .failed,
                        before: beforeTCP,
                        after: afterTCP,
                        beforeDNS: beforeDNS,
                        afterDNS: afterDNS,
                        improved: false,
                        rollbackVerified: false,
                        detail: "The measured result did not improve and the original DNS configuration could not be verified after rollback."
                    )
                }

                try journal.save(NetworkDNSJournalRecord(plan: plan, snapshot: snapshot, state: .active))
                return NetworkOptimizationResult(
                    status: .applied,
                    before: beforeTCP,
                    after: afterTCP,
                    beforeDNS: beforeDNS,
                    afterDNS: afterDNS,
                    improved: true,
                    detail: "The DNS configuration was applied after authorization and improved the measured result."
                )
            } catch is CancellationError {
                let restored = tryRestore(snapshot: snapshot, plan: plan)
                return NetworkOptimizationResult(status: restored ? .rolledBack : .failed, before: beforeTCP, beforeDNS: beforeDNS, improved: false, rollbackVerified: restored, detail: "The DNS measurement was cancelled after the change; rollback was attempted and verified when possible.")
            } catch {
                let restored = tryRestore(snapshot: snapshot, plan: plan)
                return NetworkOptimizationResult(status: restored ? .rolledBack : .failed, before: beforeTCP, beforeDNS: beforeDNS, improved: false, rollbackVerified: restored, detail: "The DNS change could not complete; rollback was attempted and verified when possible.")
            }
        } catch is CancellationError {
            return NetworkOptimizationResult(status: .failed, detail: "The DNS operation was cancelled; no unverified change was accepted.")
        } catch let error as NetworkDNSConfigurationError {
            return failure(error, detail: error.localizedDescription)
        } catch {
            return failure(.applyFailed(-1), detail: error.localizedDescription)
        }
    }

    public func rollback(_ plan: NetworkOptimizationPlan) async -> NetworkOptimizationResult {
        do {
            guard let record = try journal.load(), record.plan.id == plan.id else {
                return NetworkOptimizationResult(status: .unsupported, detail: "No active DNS change is recorded for this plan.")
            }
            let current = try store.read(serviceID: record.snapshot.serviceID, interfaceBSDName: record.snapshot.interfaceBSDName)
            guard current.servers == plan.proposedDNS else {
                return failure(.configurationChanged, detail: "The selected network service changed; rollback was refused.")
            }
            try store.restore(record.snapshot, expectedCurrent: current)
            let restored = try store.read(serviceID: record.snapshot.serviceID, interfaceBSDName: record.snapshot.interfaceBSDName)
            guard restored.servers == record.snapshot.servers,
                  restored.configurationData == record.snapshot.configurationData else {
                return NetworkOptimizationResult(status: .failed, rollbackVerified: false, detail: "Rollback was not accepted because the complete original DNS configuration did not match.")
            }
            try journal.clear()
            return NetworkOptimizationResult(status: .rolledBack, rollbackVerified: true, detail: "The complete original DNS configuration was restored and verified.")
        } catch let error as NetworkDNSConfigurationError {
            return failure(error, detail: error.localizedDescription)
        } catch {
            return NetworkOptimizationResult(status: .failed, rollbackVerified: false, detail: error.localizedDescription)
        }
    }

    public func recoverPendingChange() async -> NetworkOptimizationResult? {
        do {
            guard let record = try journal.load(), record.state == .pending else { return nil }
            let current = try store.read(serviceID: record.snapshot.serviceID, interfaceBSDName: record.snapshot.interfaceBSDName)
            if current.servers == record.snapshot.servers {
                try journal.clear()
                return nil
            }
            guard current.servers == record.plan.proposedDNS else {
                return failure(.configurationChanged, detail: "A pending DNS transaction found an unexpected network configuration and was left untouched.")
            }
            try store.restore(record.snapshot, expectedCurrent: current)
            let restored = try store.read(serviceID: record.snapshot.serviceID, interfaceBSDName: record.snapshot.interfaceBSDName)
            guard restored.servers == record.snapshot.servers,
                  restored.configurationData == record.snapshot.configurationData else {
                return NetworkOptimizationResult(status: .failed, rollbackVerified: false, detail: "A pending DNS transaction could not be verified after recovery.")
            }
            try journal.clear()
            return NetworkOptimizationResult(status: .rolledBack, rollbackVerified: true, detail: "An incomplete DNS transaction was safely rolled back and verified.")
        } catch let error as NetworkDNSConfigurationError {
            return failure(error, detail: error.localizedDescription)
        } catch {
            return NetworkOptimizationResult(status: .failed, rollbackVerified: false, detail: error.localizedDescription)
        }
    }

    private func benchmark(servers: [String], label: String) async throws -> [DNSBenchmarkResult] {
        try await probe.benchmarkDNS(servers.map { DNSBenchmarkServer(name: label, address: $0) })
    }

    private func tryRestore(snapshot: NetworkDNSServiceSnapshot, plan: NetworkOptimizationPlan) -> Bool {
        do {
            let current = try store.read(serviceID: snapshot.serviceID, interfaceBSDName: snapshot.interfaceBSDName)
            guard current.servers == plan.proposedDNS else { return false }
            try store.restore(snapshot, expectedCurrent: current)
            let restored = try store.read(serviceID: snapshot.serviceID, interfaceBSDName: snapshot.interfaceBSDName)
            let verified = restored.servers == snapshot.servers && restored.configurationData == snapshot.configurationData
            if verified { try journal.clear() }
            return verified
        } catch {
            return false
        }
    }

    private func reconcileFailedApply(plan: NetworkOptimizationPlan, snapshot: NetworkDNSServiceSnapshot) -> Bool? {
        guard let current = try? store.read(serviceID: snapshot.serviceID, interfaceBSDName: snapshot.interfaceBSDName) else { return nil }
        if current.servers == snapshot.servers {
            try? journal.clear()
            return true
        }
        if current.servers == plan.proposedDNS {
            return tryRestore(snapshot: snapshot, plan: plan)
        }
        return nil
    }

    private func rollbackAfterFailure(
        plan: NetworkOptimizationPlan,
        snapshot: NetworkDNSServiceSnapshot,
        before: NetworkProbeStatistics,
        beforeDNS: [DNSBenchmarkResult],
        error: NetworkDNSConfigurationError
    ) -> NetworkOptimizationResult {
        let restored = tryRestore(snapshot: snapshot, plan: plan)
        return NetworkOptimizationResult(
            status: restored ? .rolledBack : .failed,
            before: before,
            beforeDNS: beforeDNS,
            improved: false,
            rollbackVerified: restored,
            detail: restored ? "The DNS change failed verification and the original configuration was restored." : error.localizedDescription
        )
    }

    private func failure(
        _ error: NetworkDNSConfigurationError,
        before: NetworkProbeStatistics? = nil,
        beforeDNS: [DNSBenchmarkResult] = [],
        detail: String
    ) -> NetworkOptimizationResult {
        let status: NetworkOptimizationStatus
        switch error {
        case .authorizationRequired, .authorizationCancelled: status = .requiresAdministrator
        case .serviceUnavailable, .ambiguousService: status = .unsupported
        default: status = .failed
        }
        return NetworkOptimizationResult(status: status, before: before, beforeDNS: beforeDNS, detail: detail)
    }

    private static func isValidServerAddress(_ address: String) -> Bool {
        var v4 = in_addr()
        var v6 = in6_addr()
        return address.withCString { inet_pton(AF_INET, $0, &v4) == 1 }
            || address.withCString { inet_pton(AF_INET6, $0, &v6) == 1 }
    }

    private static func isImprovement(
        beforeDNS: [DNSBenchmarkResult],
        afterDNS: [DNSBenchmarkResult],
        beforeTCP: NetworkProbeStatistics,
        afterTCP: NetworkProbeStatistics
    ) -> Bool {
        guard let beforeDNS = beforeDNS.first(where: { $0.availability == .available }),
              let afterDNS = afterDNS.first(where: { $0.availability == .available }),
              let beforeMedian = beforeDNS.medianLatencyMilliseconds,
              let afterMedian = afterDNS.medianLatencyMilliseconds,
              let beforeP95 = beforeDNS.p95LatencyMilliseconds,
              let afterP95 = afterDNS.p95LatencyMilliseconds,
              let beforeDNSJitter = beforeDNS.jitterMilliseconds,
              let afterDNSJitter = afterDNS.jitterMilliseconds,
              let beforeTCPMedian = beforeTCP.medianLatencyMilliseconds,
              let afterTCPMedian = afterTCP.medianLatencyMilliseconds,
              let beforeTCPP95 = beforeTCP.p95LatencyMilliseconds,
              let afterTCPP95 = afterTCP.p95LatencyMilliseconds,
              let beforeTCPJitter = beforeTCP.jitterMilliseconds,
              let afterTCPJitter = afterTCP.jitterMilliseconds else { return false }
        let beforeFailures = beforeDNS.failureRate ?? 1
        let afterFailures = afterDNS.failureRate ?? 1
        let beforeTCPFailures = beforeTCP.failureRate ?? 1
        let afterTCPFailures = afterTCP.failureRate ?? 1
        guard afterFailures <= beforeFailures,
              afterDNS.timeoutCount <= beforeDNS.timeoutCount,
              afterTCPFailures <= beforeTCPFailures,
              afterP95 <= beforeP95 * 1.05,
              afterDNSJitter <= beforeDNSJitter * 1.05,
              afterTCPP95 <= beforeTCPP95 * 1.05,
              afterTCPJitter <= beforeTCPJitter * 1.05 else { return false }
        let dnsImproved = afterMedian < beforeMedian * 0.95
            || afterP95 < beforeP95 * 0.95
            || afterDNSJitter < beforeDNSJitter * 0.95
        let tcpImproved = afterTCPMedian < beforeTCPMedian * 0.95
            || afterTCPP95 < beforeTCPP95 * 0.95
            || afterTCPJitter < beforeTCPJitter * 0.95
        return dnsImproved || tcpImproved
    }
}

public final class SystemNetworkDNSConfigurationStore: @unchecked Sendable, NetworkDNSConfigurationStore {
    public init() {}

    public func read(serviceID: String?, interfaceBSDName: String?) throws -> NetworkDNSServiceSnapshot {
        try withPreferences(authorized: false) { prefs in
            guard let set = SCNetworkSetCopyCurrent(prefs),
                  let services = SCNetworkSetCopyServices(set) as? [SCNetworkService] else {
                throw NetworkDNSConfigurationError.serviceUnavailable
            }
            let matches = services.filter { service in
                guard let interface = SCNetworkServiceGetInterface(service),
                      let bsdName = (SCNetworkInterfaceGetBSDName(interface) as String?)?.lowercased() else { return false }
                let serviceMatches = serviceID == nil || SCNetworkServiceGetServiceID(service) as String? == serviceID
                let interfaceMatches = interfaceBSDName == nil || bsdName == interfaceBSDName?.lowercased()
                return serviceMatches && interfaceMatches
            }
            guard matches.count == 1, let service = matches.first else {
                throw matches.isEmpty ? NetworkDNSConfigurationError.serviceUnavailable : NetworkDNSConfigurationError.ambiguousService
            }
            guard let interface = SCNetworkServiceGetInterface(service),
                  let bsdName = SCNetworkInterfaceGetBSDName(interface),
                  let serviceID = SCNetworkServiceGetServiceID(service),
                  let serviceName = SCNetworkServiceGetName(service),
                  let dns = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeDNS as CFString),
                  let rawConfiguration = SCNetworkProtocolGetConfiguration(dns) else {
                throw NetworkDNSConfigurationError.serviceUnavailable
            }
            let configuration = rawConfiguration as NSDictionary
            let servers = (configuration[kSCPropNetDNSServerAddresses as String] as? [String]) ?? []
            let data = try PropertyListSerialization.data(fromPropertyList: configuration, format: .binary, options: 0)
            return NetworkDNSServiceSnapshot(
                serviceID: serviceID as String,
                serviceName: serviceName as String,
                interfaceBSDName: bsdName as String,
                servers: servers,
                configurationData: data
            )
        }
    }

    public func apply(servers: [String], to snapshot: NetworkDNSServiceSnapshot) throws {
        try mutate(servers: servers, snapshot: snapshot, restoring: false)
    }

    public func restore(_ snapshot: NetworkDNSServiceSnapshot, expectedCurrent: NetworkDNSServiceSnapshot) throws {
        guard let propertyList = try PropertyListSerialization.propertyList(from: snapshot.configurationData, options: [], format: nil) as? [String: Any] else {
            throw NetworkDNSConfigurationError.verificationFailed
        }
        try mutate(configuration: propertyList, snapshot: snapshot, expectedCurrent: expectedCurrent)
    }

    private func mutate(servers: [String], snapshot: NetworkDNSServiceSnapshot, restoring: Bool) throws {
        guard servers.allSatisfy(NetworkOptimizationService.isValidAddressForStore) else {
            throw NetworkDNSConfigurationError.invalidServer(servers.first ?? "")
        }
        guard let propertyList = try PropertyListSerialization.propertyList(from: snapshot.configurationData, options: [], format: nil) as? [String: Any] else {
            throw NetworkDNSConfigurationError.verificationFailed
        }
        var configuration = propertyList
        configuration[kSCPropNetDNSServerAddresses as String] = servers
        try mutate(configuration: configuration, snapshot: snapshot, expectedCurrent: snapshot)
        _ = restoring
    }

    private func mutate(configuration: [String: Any], snapshot: NetworkDNSServiceSnapshot, expectedCurrent: NetworkDNSServiceSnapshot) throws {
        try withPreferences(authorized: true) { prefs in
            guard let set = SCNetworkSetCopyCurrent(prefs),
                  let services = SCNetworkSetCopyServices(set) as? [SCNetworkService],
                  let service = services.first(where: { SCNetworkServiceGetServiceID($0) as String? == snapshot.serviceID }),
                  let interface = SCNetworkServiceGetInterface(service),
                  let interfaceName = SCNetworkInterfaceGetBSDName(interface) as String?,
                  let protocolRef = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeDNS as CFString) else {
                throw NetworkDNSConfigurationError.serviceUnavailable
            }
            guard interfaceName.caseInsensitiveCompare(snapshot.interfaceBSDName) == .orderedSame else {
                throw NetworkDNSConfigurationError.configurationChanged
            }
            guard SCPreferencesLock(prefs, true) else { throw NetworkDNSConfigurationError.applyFailed(SCError()) }
            defer { _ = SCPreferencesUnlock(prefs) }
            guard let currentConfiguration = SCNetworkProtocolGetConfiguration(protocolRef),
                  let currentData = try? PropertyListSerialization.data(fromPropertyList: currentConfiguration as NSDictionary, format: .binary, options: 0),
                  configurationsEqual(currentData, expectedCurrent.configurationData) else {
                throw NetworkDNSConfigurationError.configurationChanged
            }
            guard SCNetworkProtocolSetConfiguration(protocolRef, configuration as CFDictionary) else {
                throw NetworkDNSConfigurationError.applyFailed(SCError())
            }
            guard SCPreferencesCommitChanges(prefs), SCPreferencesApplyChanges(prefs) else {
                throw NetworkDNSConfigurationError.applyFailed(SCError())
            }
        }
    }

    private func configurationsEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard let left = try? PropertyListSerialization.propertyList(from: lhs, options: [], format: nil) as? NSDictionary,
              let right = try? PropertyListSerialization.propertyList(from: rhs, options: [], format: nil) as? NSDictionary else { return false }
        return left.isEqual(to: right as? [AnyHashable: Any] ?? [:])
    }

    private func withPreferences<T>(authorized: Bool, body: (SCPreferences) throws -> T) throws -> T {
        if !authorized {
            guard let prefs = SCPreferencesCreate(nil, "LexCleaner.NetworkDNS" as CFString, nil) else {
                throw NetworkDNSConfigurationError.serviceUnavailable
            }
            return try body(prefs)
        }

        var authorization: AuthorizationRef?
        var status = AuthorizationCreate(nil, nil, [], &authorization)
        guard status == errAuthorizationSuccess, let authorization else {
            throw status == errAuthorizationCanceled ? NetworkDNSConfigurationError.authorizationCancelled : NetworkDNSConfigurationError.authorizationRequired
        }
        defer { _ = AuthorizationFree(authorization, [.destroyRights]) }

        status = kAuthorizationRightExecute.withCString { name in
            var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { itemPointer in
                var rights = AuthorizationRights(count: 1, items: itemPointer)
                return AuthorizationCopyRights(authorization, &rights, nil, [.interactionAllowed, .extendRights], nil)
            }
        }
        guard status == errAuthorizationSuccess else {
            if status == errAuthorizationCanceled { throw NetworkDNSConfigurationError.authorizationCancelled }
            throw NetworkDNSConfigurationError.authorizationRequired
        }
        guard let prefs = SCPreferencesCreateWithAuthorization(nil, "LexCleaner.NetworkDNS" as CFString, nil, authorization) else {
            throw NetworkDNSConfigurationError.authorizationRequired
        }
        return try body(prefs)
    }
}

extension NetworkOptimizationService {
    fileprivate static func isValidAddressForStore(_ address: String) -> Bool {
        isValidServerAddress(address)
    }
}

public final class FileNetworkDNSRecoveryJournal: @unchecked Sendable, NetworkDNSRecoveryJournal {
    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LexCleaner", isDirectory: true)
            .appendingPathComponent("network-dns-transaction.json")
    }

    public func save(_ record: NetworkDNSJournalRecord) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(record)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    public func load() throws -> NetworkDNSJournalRecord? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try JSONDecoder().decode(NetworkDNSJournalRecord.self, from: Data(contentsOf: fileURL))
    }

    public func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
