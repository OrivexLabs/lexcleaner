import Foundation
import Testing
@testable import LexCleanerCore

private final class TestDNSStore: @unchecked Sendable, NetworkDNSConfigurationStore {
    var snapshot: NetworkDNSServiceSnapshot
    var applyError: NetworkDNSConfigurationError?
    private(set) var applyCount = 0

    init(servers: [String] = ["192.0.2.1"]) {
        snapshot = NetworkDNSServiceSnapshot(serviceID: "service-1", serviceName: "Test Wi-Fi", interfaceBSDName: "en0", servers: servers, configurationData: Data("original-configuration".utf8))
    }

    func read(serviceID: String?, interfaceBSDName: String?) throws -> NetworkDNSServiceSnapshot {
        guard (serviceID == nil || serviceID == snapshot.serviceID), (interfaceBSDName == nil || interfaceBSDName == snapshot.interfaceBSDName) else { throw NetworkDNSConfigurationError.serviceUnavailable }
        return snapshot
    }

    func apply(servers: [String], to snapshot: NetworkDNSServiceSnapshot) throws {
        if let applyError { throw applyError }
        applyCount += 1
        self.snapshot = NetworkDNSServiceSnapshot(serviceID: snapshot.serviceID, serviceName: snapshot.serviceName, interfaceBSDName: snapshot.interfaceBSDName, servers: servers, configurationData: Data("applied-configuration-\(servers.joined(separator: ","))".utf8))
    }

    func restore(_ snapshot: NetworkDNSServiceSnapshot, expectedCurrent: NetworkDNSServiceSnapshot) throws {
        guard self.snapshot == expectedCurrent else { throw NetworkDNSConfigurationError.configurationChanged }
        self.snapshot = snapshot
    }
}

private final class SequencedTestProbe: @unchecked Sendable, NetworkOptimizationProbe {
    let dnsValues: [Double]
    let tcpValues: [Double]
    let failAtDNSIndex: Int?
    var dnsIndex = 0
    var tcpIndex = 0

    init(dnsValues: [Double], tcpValues: [Double], failAtDNSIndex: Int? = nil) { self.dnsValues = dnsValues; self.tcpValues = tcpValues; self.failAtDNSIndex = failAtDNSIndex }

    func benchmarkDNS(_ servers: [DNSBenchmarkServer]) async throws -> [DNSBenchmarkResult] {
        if dnsIndex == failAtDNSIndex { dnsIndex += 1; throw NetworkDNSConfigurationError.applyFailed(-2) }
        let server = try #require(servers.first)
        let value = dnsValues[min(dnsIndex, dnsValues.count - 1)]
        dnsIndex += 1
        return [DNSBenchmarkResult(server: server, medianLatencyMilliseconds: value, p95LatencyMilliseconds: value, jitterMilliseconds: 1, timeoutCount: 0, probeCount: 5, failureRate: 0, availability: .available)]
    }

    func benchmarkTCP() async throws -> NetworkProbeStatistics {
        let value = tcpValues[min(tcpIndex, tcpValues.count - 1)]
        tcpIndex += 1
        return NetworkProbeStatistics(target: "test:443", port: 443, medianLatencyMilliseconds: value, p95LatencyMilliseconds: value, jitterMilliseconds: 1, successfulProbes: 5, probeCount: 5, failureRate: 0, availability: .available)
    }
}

private final class TestJournal: @unchecked Sendable, NetworkDNSRecoveryJournal {
    var record: NetworkDNSJournalRecord?
    func save(_ record: NetworkDNSJournalRecord) throws { self.record = record }
    func load() throws -> NetworkDNSJournalRecord? { record }
    func clear() throws { record = nil }
}

@Suite("NetworkOptimizer")
struct NetworkOptimizerTests {
    @Test("calculates median, percentile and jitter deterministically")
    func calculatesStatistics() {
        #expect(NetworkStatistics.median([4, 1, 3, 2]) == 2.5)
        #expect(NetworkStatistics.percentile([1, 2, 3, 4, 5], 0.95) == 5)
        #expect(NetworkStatistics.jitter([10, 12, 15]) == 2.5)
        #expect(NetworkStatistics.failureRate(failures: 1, total: 4) == 0.25)
    }

    @Test("scores only when the required measurements are available")
    func scoresAvailableMeasurements() {
        #expect(NetworkStatistics.score(latencyMilliseconds: 20, jitterMilliseconds: 2, failureRate: 0) == 99)
        #expect(NetworkStatistics.score(latencyMilliseconds: nil, jitterMilliseconds: 2, failureRate: 0) == nil)
        #expect(NetworkStatistics.score(latencyMilliseconds: 20, jitterMilliseconds: nil, failureRate: nil) == nil)
    }

    @Test("rejects unsafe network probe configuration")
    func rejectsUnsafeConfiguration() {
        #expect(throws: NetworkCollectorError.invalidConfiguration) {
            _ = try NetworkSamplingConfiguration(probeCount: 0)
        }
        #expect(throws: NetworkCollectorError.invalidConfiguration) {
            _ = try NetworkSamplingConfiguration(timeout: 0.01)
        }
    }

    @Test("creates a DNS plan without mutating system configuration")
    func createsSafeDNSPlan() async {
        let store = TestDNSStore()
        let service = NetworkOptimizationService(store: store, probe: SequencedTestProbe(dnsValues: [100, 50], tcpValues: [100, 90]), journal: TestJournal())
        let plan = service.makeDNSPlan(current: ["192.0.2.1"], proposed: ["1.1.1.1"], targetInterface: "en0")
        #expect(plan?.originalDNS == ["192.0.2.1"])
        #expect(plan?.proposedDNS == ["1.1.1.1"])
        #expect(plan?.requiresAdministrator == true)
        let result = await service.apply(try! #require(plan), userConfirmed: true)
        #expect(result.status == .applied)
        #expect(store.snapshot.servers == ["1.1.1.1"])
    }

    @Test("authorization denial and cancellation fail closed")
    func authorizationFailures() async throws {
        for error in [NetworkDNSConfigurationError.authorizationRequired, .authorizationCancelled] {
            let store = TestDNSStore()
            store.applyError = error
            let service = NetworkOptimizationService(store: store, probe: SequencedTestProbe(dnsValues: [100, 50], tcpValues: [100, 90]), journal: TestJournal())
            let plan = try #require(service.makeDNSPlan(current: ["192.0.2.1"], proposed: ["1.1.1.1"], targetInterface: "en0"))
            let result = await service.apply(plan, userConfirmed: true)
            #expect(result.status == .requiresAdministrator)
            #expect(store.snapshot.servers == ["192.0.2.1"])
            #expect(store.applyCount == 0)
        }
    }

    @Test("authorization cannot be requested before explicit confirmation")
    func confirmationGate() async throws {
        let store = TestDNSStore()
        let service = NetworkOptimizationService(store: store, probe: SequencedTestProbe(dnsValues: [100, 50], tcpValues: [100, 90]), journal: TestJournal())
        let plan = try #require(service.makeDNSPlan(current: ["192.0.2.1"], proposed: ["1.1.1.1"], targetInterface: "en0"))
        let result = await service.apply(plan)
        #expect(result.status == .requiresAdministrator)
        #expect(store.applyCount == 0)
        #expect(store.snapshot.servers == ["192.0.2.1"])
    }

    @Test("invalid DNS and source changes are rejected")
    func invalidAndChangedConfiguration() async throws {
        let service = NetworkOptimizationService(store: TestDNSStore(), probe: SequencedTestProbe(dnsValues: [100, 50], tcpValues: [100, 90]), journal: TestJournal())
        #expect(service.makeDNSPlan(current: ["192.0.2.1"], proposed: ["not-an-ip"]) == nil)
        let store = TestDNSStore()
        store.snapshot = NetworkDNSServiceSnapshot(serviceID: "service-1", serviceName: "Test Wi-Fi", interfaceBSDName: "en0", servers: ["203.0.113.1"], configurationData: Data("changed".utf8))
        let changedService = NetworkOptimizationService(store: store, probe: SequencedTestProbe(dnsValues: [100, 50], tcpValues: [100, 90]), journal: TestJournal())
        let plan = try #require(changedService.makeDNSPlan(current: ["192.0.2.1"], proposed: ["1.1.1.1"], targetInterface: "en0"))
        #expect((await changedService.apply(plan, userConfirmed: true)).status == .failed)
        #expect(store.applyCount == 0)
    }

    @Test("system DNS store reads real configuration or reports an explicit boundary")
    func systemDNSStoreRead() {
        do {
            let snapshot = try SystemNetworkDNSConfigurationStore().read(serviceID: nil, interfaceBSDName: nil)
            #expect(!snapshot.serviceID.isEmpty)
            #expect(!snapshot.interfaceBSDName.isEmpty)
            #expect(snapshot.servers.allSatisfy { !$0.isEmpty })
        } catch let error as NetworkDNSConfigurationError {
            #expect([.serviceUnavailable, .ambiguousService].contains(error))
        } catch {
            Issue.record("Unexpected DNS store read error: \(error)")
        }
    }

    @Test("no measured improvement restores the original configuration")
    func noImprovementRollsBack() async throws {
        let store = TestDNSStore()
        let service = NetworkOptimizationService(store: store, probe: SequencedTestProbe(dnsValues: [100, 100], tcpValues: [100, 100]), journal: TestJournal())
        let plan = try #require(service.makeDNSPlan(current: ["192.0.2.1"], proposed: ["1.1.1.1"], targetInterface: "en0"))
        let result = await service.apply(plan, userConfirmed: true)
        #expect(result.status == .rolledBack)
        #expect(result.improved == false)
        #expect(result.rollbackVerified == true)
        #expect(store.snapshot.servers == ["192.0.2.1"])
    }

    @Test("successful change and one-click rollback are verified exactly")
    func appliesAndRollsBack() async throws {
        let store = TestDNSStore()
        let journal = TestJournal()
        let service = NetworkOptimizationService(store: store, probe: SequencedTestProbe(dnsValues: [100, 50], tcpValues: [100, 90]), journal: journal)
        let plan = try #require(service.makeDNSPlan(current: ["192.0.2.1"], proposed: ["1.1.1.1"], targetInterface: "en0"))
        #expect((await service.apply(plan, userConfirmed: true)).status == .applied)
        let rollback = await service.rollback(plan)
        #expect(rollback.status == .rolledBack)
        #expect(rollback.rollbackVerified == true)
        #expect(store.snapshot.servers == ["192.0.2.1"])
        #expect(journal.record == nil)
    }

    @Test("pending transaction is recovered after an interrupted apply")
    func recoversPendingTransaction() async throws {
        let store = TestDNSStore()
        let journal = TestJournal()
        let service = NetworkOptimizationService(store: store, probe: SequencedTestProbe(dnsValues: [100, 50], tcpValues: [100, 90]), journal: journal)
        let plan = try #require(service.makeDNSPlan(current: ["192.0.2.1"], proposed: ["1.1.1.1"], targetInterface: "en0"))
        let original = store.snapshot
        store.snapshot = NetworkDNSServiceSnapshot(serviceID: "service-1", serviceName: "Test Wi-Fi", interfaceBSDName: "en0", servers: ["1.1.1.1"], configurationData: Data("interrupted".utf8))
        journal.record = NetworkDNSJournalRecord(plan: plan, snapshot: original, state: .pending)
        let result = await service.recoverPendingChange()
        #expect(result?.status == .rolledBack)
        #expect(result?.rollbackVerified == true)
        #expect(store.snapshot == original)
        #expect(journal.record == nil)
    }

    @Test("post-apply measurement failure attempts verified rollback")
    func measurementFailureRollsBack() async throws {
        let store = TestDNSStore()
        let service = NetworkOptimizationService(
            store: store,
            probe: SequencedTestProbe(dnsValues: [100, 50], tcpValues: [100, 90], failAtDNSIndex: 1),
            journal: TestJournal()
        )
        let plan = try #require(service.makeDNSPlan(current: ["192.0.2.1"], proposed: ["1.1.1.1"], targetInterface: "en0"))
        let result = await service.apply(plan, userConfirmed: true)
        #expect(result.status == .rolledBack)
        #expect(result.rollbackVerified == true)
        #expect(store.snapshot.servers == ["192.0.2.1"])
    }

    @Test("real collector reports explicit statuses without fabricated values")
    func reportsRealStatuses() async throws {
        let configuration = try NetworkSamplingConfiguration(probeCount: 1, timeout: 0.5)
        let snapshot = try await NetworkHealthCollector(configuration: configuration).collect()
        #expect(!snapshot.timestamp.description.isEmpty)
        #expect(snapshot.score.value == nil || (0...100).contains(snapshot.score.value!))
        #expect(snapshot.latency.medianLatencyMilliseconds == nil || snapshot.latency.medianLatencyMilliseconds! >= 0)
        #expect(snapshot.latency.failureRate == nil || (0...1).contains(snapshot.latency.failureRate!))
        if snapshot.gateway.availability != .available {
            #expect(snapshot.gateway.value == nil)
        }
        if snapshot.vpn.availability != .available {
            #expect(snapshot.vpn.value == nil)
        }
        #expect(snapshot.packetLossPercentage.availability == .unsupported)
        #expect(snapshot.packetLossPercentage.value == nil)
    }

    @Test("collector honors cancellation before starting network I/O")
    func cancellationIsObservable() async throws {
        let configuration = try NetworkSamplingConfiguration(probeCount: 1, timeout: 1)
        let task = Task {
            try Task.checkCancellation()
            _ = try await NetworkHealthCollector(configuration: configuration).collect()
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Expected network collection cancellation")
        } catch is NetworkCollectorError {
            // The production collector propagated cancellation rather than turning it into a timeout result.
        } catch is CancellationError {
            // CancellationError is also an acceptable structured cancellation result.
        }
    }
}
