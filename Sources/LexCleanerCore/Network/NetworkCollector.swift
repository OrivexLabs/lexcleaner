import CFNetwork
import Darwin
import Foundation
import Network
import SystemConfiguration

public struct NetworkSamplingConfiguration: Codable, Equatable, Sendable {
    public let probeHost: String
    public let probePort: UInt16
    public let probeCount: Int
    public let timeout: TimeInterval

    public static let standard = Self(
        uncheckedProbeHost: "1.1.1.1",
        uncheckedProbePort: 443,
        uncheckedProbeCount: 5,
        uncheckedTimeout: 2
    )

    private init(uncheckedProbeHost: String, uncheckedProbePort: UInt16, uncheckedProbeCount: Int, uncheckedTimeout: TimeInterval) {
        self.probeHost = uncheckedProbeHost
        self.probePort = uncheckedProbePort
        self.probeCount = uncheckedProbeCount
        self.timeout = uncheckedTimeout
    }

    public init(
        probeHost: String = "1.1.1.1",
        probePort: UInt16 = 443,
        probeCount: Int = 5,
        timeout: TimeInterval = 2
    ) throws {
        guard !probeHost.isEmpty, probePort > 0, (1...20).contains(probeCount), (0.2...10).contains(timeout) else {
            throw NetworkCollectorError.invalidConfiguration
        }
        self.init(uncheckedProbeHost: probeHost, uncheckedProbePort: probePort, uncheckedProbeCount: probeCount, uncheckedTimeout: timeout)
    }
}

public enum NetworkCollectorError: Error, LocalizedError, Equatable, Sendable {
    case invalidConfiguration
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration: return "Network sampling configuration is invalid."
        case .cancelled: return "Network sampling was cancelled."
        }
    }
}

public struct NetworkHealthCollector: Sendable {
    public let configuration: NetworkSamplingConfiguration

    public init(configuration: NetworkSamplingConfiguration = .standard) {
        self.configuration = configuration
    }

    public func collect() async throws -> NetworkHealthSnapshot {
        try Task.checkCancellation()
        async let path = readPath()
        async let interfaces = readInterfaces()
        async let dns = readDNS()
        async let gateway = readGateway()
        async let proxy = readProxy()
        let resolvedPath = try await path
        let resolvedInterfaces = await interfaces
        let resolvedDNS = await dns
        let resolvedGateway = await gateway
        let resolvedProxy = await proxy
        let resolvedVPN = NetworkMetric<String>.unavailable(
            source: "Network.framework NWPath",
            detail: "VPN state is not reliably exposed to an ordinary macOS app without Network Extension configuration access."
        )
        let latency = try await probeTCP()
        let packetLoss = NetworkMetric<Double>.unsupported(
            source: "Network.framework public API",
            detail: "ICMP echo packet loss is not exposed to an ordinary macOS app through the public APIs used here. TCP probe failures are reported separately and are not packet loss."
        )
        let issues = buildIssues(
            path: resolvedPath,
            dns: resolvedDNS,
            gateway: resolvedGateway,
            proxy: resolvedProxy,
            latency: latency,
            interfaces: resolvedInterfaces
        )
        let scoreValue = NetworkStatistics.score(
            latencyMilliseconds: latency.medianLatencyMilliseconds,
            jitterMilliseconds: latency.jitterMilliseconds,
            failureRate: latency.failureRate
        )
        let score = NetworkHealthScore(
            value: scoreValue,
            availability: scoreValue == nil ? .unavailable : .available,
            detail: scoreValue == nil ? "A score requires successful TCP probe samples." : "Derived from TCP probe latency, jitter and failure rate; ICMP loss is not included."
        )
        return NetworkHealthSnapshot(
            timestamp: Date(),
            path: resolvedPath,
            interfaces: resolvedInterfaces,
            dns: resolvedDNS,
            gateway: resolvedGateway,
            proxy: resolvedProxy,
            vpn: resolvedVPN,
            latency: latency,
            packetLossPercentage: packetLoss,
            score: score,
            issues: issues
        )
    }

    public func benchmarkDNS(_ servers: [DNSBenchmarkServer]) async throws -> [DNSBenchmarkResult] {
        var results: [DNSBenchmarkResult] = []
        for server in servers {
            try Task.checkCancellation()
            results.append(try await benchmark(server))
        }
        return results
    }

    public func benchmarkTCP() async throws -> NetworkProbeStatistics {
        var values: [Double] = []
        var failures = 0
        for _ in 0..<configuration.probeCount {
            try Task.checkCancellation()
            do {
                values.append(try await TCPProbeSession(
                    host: configuration.probeHost,
                    port: configuration.probePort,
                    timeout: configuration.timeout
                ).run())
            } catch {
                if Task.isCancelled { throw NetworkCollectorError.cancelled }
                failures += 1
            }
        }
        let total = values.count + failures
        return NetworkProbeStatistics(
            target: "\(configuration.probeHost):\(configuration.probePort)",
            port: configuration.probePort,
            medianLatencyMilliseconds: values.isEmpty ? nil : NetworkStatistics.median(values),
            p95LatencyMilliseconds: values.isEmpty ? nil : NetworkStatistics.percentile(values, 0.95),
            jitterMilliseconds: values.isEmpty ? nil : NetworkStatistics.jitter(values),
            successfulProbes: values.count,
            probeCount: total,
            failureRate: NetworkStatistics.failureRate(failures: failures, total: total),
            availability: values.isEmpty ? .unavailable : .available,
            detail: "TCP connect probe; not ICMP packet loss."
        )
    }

    private func benchmark(_ server: DNSBenchmarkServer) async throws -> DNSBenchmarkResult {
        var values: [Double] = []
        var failures = 0
        for index in 0..<configuration.probeCount {
            if Task.isCancelled { break }
            do {
                let value = try await DNSProbeSession(
                    address: server.address,
                    timeout: configuration.timeout,
                    queryID: UInt16(index + 1)
                ).run()
                values.append(value)
            } catch {
                if Task.isCancelled { throw NetworkCollectorError.cancelled }
                failures += 1
            }
        }
        let total = values.count + failures
        guard !values.isEmpty else {
            return DNSBenchmarkResult(
                server: server,
                medianLatencyMilliseconds: nil,
                p95LatencyMilliseconds: nil,
                jitterMilliseconds: nil,
                timeoutCount: failures,
                probeCount: total,
                failureRate: NetworkStatistics.failureRate(failures: failures, total: total),
                availability: .unavailable,
                detail: "No DNS response was received before the probe timeout."
            )
        }
        return DNSBenchmarkResult(
            server: server,
            medianLatencyMilliseconds: NetworkStatistics.median(values),
            p95LatencyMilliseconds: NetworkStatistics.percentile(values, 0.95),
            jitterMilliseconds: NetworkStatistics.jitter(values),
            timeoutCount: failures,
            probeCount: total,
            failureRate: NetworkStatistics.failureRate(failures: failures, total: total),
            availability: .available,
            detail: nil
        )
    }

    private func probeTCP() async throws -> NetworkProbeStatistics {
        var values: [Double] = []
        var failures = 0
        for _ in 0..<configuration.probeCount {
            if Task.isCancelled { break }
            do {
                values.append(try await TCPProbeSession(
                    host: configuration.probeHost,
                    port: configuration.probePort,
                    timeout: configuration.timeout
                ).run())
            } catch {
                if Task.isCancelled { throw NetworkCollectorError.cancelled }
                failures += 1
            }
        }
        let total = values.count + failures
        guard !values.isEmpty else {
            return NetworkProbeStatistics(
                target: "\(configuration.probeHost):\(configuration.probePort)",
                port: configuration.probePort,
                medianLatencyMilliseconds: nil,
                p95LatencyMilliseconds: nil,
                jitterMilliseconds: nil,
                successfulProbes: 0,
                probeCount: total,
                failureRate: NetworkStatistics.failureRate(failures: failures, total: total),
                availability: .unavailable,
                detail: "The TCP probe target did not respond before the timeout."
            )
        }
        return NetworkProbeStatistics(
            target: "\(configuration.probeHost):\(configuration.probePort)",
            port: configuration.probePort,
            medianLatencyMilliseconds: NetworkStatistics.median(values),
            p95LatencyMilliseconds: NetworkStatistics.percentile(values, 0.95),
            jitterMilliseconds: NetworkStatistics.jitter(values),
            successfulProbes: values.count,
            probeCount: total,
            failureRate: NetworkStatistics.failureRate(failures: failures, total: total),
            availability: .available,
            detail: "TCP connect probe; not ICMP packet loss."
        )
    }

    private func readPath() async throws -> NetworkPathSnapshot {
        try await PathMonitorSession().run()
    }

    private func readInterfaces() async -> [NetworkInterfaceHealthSnapshot] {
        await Task.detached(priority: .utility) {
            InterfaceReader.read()
        }.value
    }

    private func readDNS() async -> DNSResolverSnapshot {
        await Task.detached(priority: .utility) {
            let store = SCDynamicStoreCreate(nil, "LexCleaner.Network" as CFString, nil, nil)
            let key = "State:/Network/Global/DNS" as CFString
            let settings = store.flatMap { SCDynamicStoreCopyValue($0, key) as? [String: Any] }
            let servers = (settings?["ServerAddresses"] as? [String] ?? []).filter { !$0.isEmpty }
            return DNSResolverSnapshot(servers: servers, source: "SystemConfiguration State:/Network/Global/DNS", isConfigured: !servers.isEmpty)
        }.value
    }

    private func readGateway() async -> NetworkMetric<String> {
        await Task.detached(priority: .utility) {
            let store = SCDynamicStoreCreate(nil, "LexCleaner.Network" as CFString, nil, nil)
            let key = "State:/Network/Global/IPv4" as CFString
            let settings = store.flatMap { SCDynamicStoreCopyValue($0, key) as? [String: Any] }
            if let router = settings?["Router"] as? String, !router.isEmpty {
                return .available(router, source: "SystemConfiguration State:/Network/Global/IPv4")
            }
            return .unavailable(source: "SystemConfiguration State:/Network/Global/IPv4", detail: "Default gateway was not reported.")
        }.value
    }

    private func readProxy() async -> NetworkMetric<String> {
        await Task.detached(priority: .utility) {
            guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
                return NetworkMetric<String>.unavailable(source: "CFNetworkCopySystemProxySettings", detail: "System proxy settings are unavailable.")
            }
            let keys: [(String, String)] = [("HTTPEnable", "HTTP"), ("HTTPSEnable", "HTTPS"), ("SOCKSEnable", "SOCKS")]
            let enabled = keys.compactMap { key, label in
                (settings[key] as? NSNumber)?.boolValue == true ? label : nil
            }
            if enabled.isEmpty {
                return .available("none", source: "CFNetworkCopySystemProxySettings")
            }
            return .available(enabled.joined(separator: ", "), source: "CFNetworkCopySystemProxySettings")
        }.value
    }

    private func buildIssues(
        path: NetworkPathSnapshot,
        dns: DNSResolverSnapshot,
        gateway: NetworkMetric<String>,
        proxy: NetworkMetric<String>,
        latency: NetworkProbeStatistics,
        interfaces: [NetworkInterfaceHealthSnapshot]
    ) -> [NetworkIssue] {
        var issues: [NetworkIssue] = []
        if path.status != .satisfied {
            issues.append(NetworkIssue(id: "path.unsatisfied", severity: .critical, titleKey: "network.issue.pathTitle", detailKey: "network.issue.pathDetail", detailValue: path.status.rawValue))
        }
        if dns.servers.isEmpty {
            issues.append(NetworkIssue(id: "dns.notConfigured", severity: .warning, titleKey: "network.issue.dnsTitle", detailKey: "network.issue.dnsDetail"))
        }
        if gateway.availability != .available {
            issues.append(NetworkIssue(id: "gateway.unavailable", severity: .info, titleKey: "network.issue.gatewayTitle", detailKey: "network.issue.gatewayDetail"))
        }
        if latency.availability == .available, let failureRate = latency.failureRate, failureRate > 0 {
            issues.append(NetworkIssue(id: "probe.failure", severity: failureRate >= 0.5 ? .critical : .warning, titleKey: "network.issue.probeTitle", detailKey: "network.issue.probeDetail", detailValue: "\(Int((failureRate * 100).rounded()))"))
        }
        let interfaceErrors = interfaces.reduce(0) { $0 + $1.inputErrors + $1.outputErrors + $1.droppedPackets }
        if interfaceErrors > 0 {
            issues.append(NetworkIssue(id: "interface.errors", severity: .warning, titleKey: "network.issue.interfaceTitle", detailKey: "network.issue.interfaceDetail", detailValue: "\(interfaceErrors)"))
        }
        if proxy.value != nil, proxy.value != "none" {
            issues.append(NetworkIssue(id: "proxy.active", severity: .info, titleKey: "network.issue.proxyTitle", detailKey: "network.issue.proxyDetail"))
        }
        return issues
    }
}

private final class PathMonitorSession: @unchecked Sendable {
    private let lock = NSLock()
    private let monitor = NWPathMonitor()
    private var continuation: CheckedContinuation<NetworkPathSnapshot, Error>?
    private var finished = false

    func run() async throws -> NetworkPathSnapshot {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NetworkPathSnapshot, Error>) in
                lock.lock()
                self.continuation = continuation
                lock.unlock()

                let queue = DispatchQueue(label: "com.lexcleaner.network.path", qos: .utility)
                monitor.pathUpdateHandler = { [weak self] path in
                    guard let self else { return }
                    let active = path.availableInterfaces.first(where: { path.usesInterfaceType($0.type) })
                    finish(.success(NetworkPathSnapshot(
                        status: pathStatus(path.status),
                        activeInterface: active?.name,
                        activeInterfaceKind: interfaceKind(active?.type),
                        isExpensive: path.isExpensive,
                        isConstrained: path.isConstrained
                    )))
                }
                monitor.start(queue: queue)
            }
        } onCancel: {
            finish(.failure(NetworkCollectorError.cancelled))
        }
    }

    private func finish(_ result: Result<NetworkPathSnapshot, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        monitor.cancel()
        continuation?.resume(with: result)
    }
}

final class TCPProbeSession: @unchecked Sendable {
    private let host: String
    private let port: UInt16
    private let timeout: TimeInterval
    private let lock = NSLock()
    private var connection: NWConnection?
    private var continuation: CheckedContinuation<Double, Error>?
    private var finished = false

    init(host: String, port: UInt16, timeout: TimeInterval) {
        self.host = host
        self.port = port
        self.timeout = timeout
    }

    func run() async throws -> Double {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Double, Error>) in
                lock.lock()
                self.continuation = continuation
                guard let networkPort = NWEndpoint.Port(rawValue: port) else {
                    continuation.resume(throwing: NetworkCollectorError.invalidConfiguration)
                    return
                }
                let connection = NWConnection(host: NWEndpoint.Host(host), port: networkPort, using: .tcp)
                self.connection = connection
                lock.unlock()
                let started = DispatchTime.now().uptimeNanoseconds
                let queue = DispatchQueue(label: "com.lexcleaner.network.probe", qos: .utility)
                connection.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
                        finish(.success(elapsed))
                    case .failed(let error):
                        finish(.failure(error))
                    case .cancelled:
                        finish(.failure(NetworkCollectorError.cancelled))
                    default:
                        break
                    }
                }
                connection.start(queue: queue)
                queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                    self?.finish(.failure(ProbeError.timeout))
                }
            }
        } onCancel: {
            finish(.failure(NetworkCollectorError.cancelled))
        }
    }

    private func finish(_ result: Result<Double, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        let connection = self.connection
        lock.unlock()
        connection?.cancel()
        continuation?.resume(with: result)
    }
}

private final class DNSProbeSession: @unchecked Sendable {
    private let address: String
    private let timeout: TimeInterval
    private let queryID: UInt16
    private let lock = NSLock()
    private var connection: NWConnection?
    private var continuation: CheckedContinuation<Double, Error>?
    private var finished = false

    init(address: String, timeout: TimeInterval, queryID: UInt16) {
        self.address = address
        self.timeout = timeout
        self.queryID = queryID
    }

    func run() async throws -> Double {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Double, Error>) in
                lock.lock()
                self.continuation = continuation
                let connection = NWConnection(host: NWEndpoint.Host(address), port: 53, using: .udp)
                self.connection = connection
                lock.unlock()
                let started = DispatchTime.now().uptimeNanoseconds
                let queue = DispatchQueue(label: "com.lexcleaner.network.dns", qos: .utility)
                connection.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        let query = DNSProbeSession.query(id: queryID)
                        connection.send(content: query, completion: .contentProcessed { error in
                            if let error { self.finish(.failure(error)); return }
                            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, error in
                                if let error { self.finish(.failure(error)); return }
                                guard let data, data.count >= 12 else { self.finish(.failure(ProbeError.invalidResponse)); return }
                                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
                                self.finish(.success(elapsed))
                            }
                        })
                    case .failed(let error):
                        finish(.failure(error))
                    case .cancelled:
                        finish(.failure(NetworkCollectorError.cancelled))
                    default:
                        break
                    }
                }
                connection.start(queue: queue)
                queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                    self?.finish(.failure(ProbeError.timeout))
                }
            }
        } onCancel: {
            finish(.failure(NetworkCollectorError.cancelled))
        }
    }

    private func finish(_ result: Result<Double, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        let connection = self.connection
        lock.unlock()
        connection?.cancel()
        continuation?.resume(with: result)
    }

    private static func query(id: UInt16) -> Data {
        var bytes: [UInt8] = [UInt8(id >> 8), UInt8(id & 0xff), 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        for label in ["example", "com"] {
            bytes.append(UInt8(label.utf8.count))
            bytes.append(contentsOf: label.utf8)
        }
        bytes.append(contentsOf: [0x00, 0x00, 0x01, 0x00, 0x01])
        return Data(bytes)
    }
}

private enum ProbeError: Error {
    case timeout
    case invalidResponse
}

private enum InterfaceReader {
    static func read() -> [NetworkInterfaceHealthSnapshot] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else { return [] }
        defer { freeifaddrs(first) }
        var values: [String: Accumulator] = [:]
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let item = current.pointee
            guard let address = item.ifa_addr else { pointer = item.ifa_next; continue }
            let name = String(cString: item.ifa_name)
            var value = values[name] ?? Accumulator(name: name)
            value.isUp = (item.ifa_flags & UInt32(IFF_UP)) != 0
            switch Int32(address.pointee.sa_family) {
            case AF_INET:
                value.ipv4.append(numericAddress(address, length: socklen_t(MemoryLayout<sockaddr_in>.size)))
            case AF_INET6:
                value.ipv6.append(numericAddress(address, length: socklen_t(MemoryLayout<sockaddr_in6>.size)))
            case AF_LINK:
                if let data = item.ifa_data?.assumingMemoryBound(to: if_data.self).pointee {
                    value.received = UInt64(data.ifi_ibytes)
                    value.sent = UInt64(data.ifi_obytes)
                    value.inputErrors = UInt64(data.ifi_ierrors)
                    value.outputErrors = UInt64(data.ifi_oerrors)
                    value.dropped = UInt64(data.ifi_iqdrops)
                }
            default:
                break
            }
            values[name] = value
            pointer = item.ifa_next
        }
        return values.values.sorted { $0.name < $1.name }.map { value in
            NetworkInterfaceHealthSnapshot(
                name: value.name,
                kind: value.name == "lo0" ? .loopback : .unknown,
                isUp: value.isUp,
                ipv4Addresses: Array(Set(value.ipv4)).sorted(),
                ipv6Addresses: Array(Set(value.ipv6)).sorted(),
                receivedBytes: value.received,
                sentBytes: value.sent,
                inputErrors: value.inputErrors,
                outputErrors: value.outputErrors,
                droppedPackets: value.dropped
            )
        }
    }

    private static func numericAddress(_ address: UnsafePointer<sockaddr>, length: socklen_t) -> String {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        var copy = address.pointee
        let result = withUnsafePointer(to: &copy) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo($0, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            }
        }
        return result == 0 ? String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) : ""
    }

    private struct Accumulator {
        let name: String
        var isUp = false
        var ipv4: [String] = []
        var ipv6: [String] = []
        var received: UInt64 = 0
        var sent: UInt64 = 0
        var inputErrors: UInt64 = 0
        var outputErrors: UInt64 = 0
        var dropped: UInt64 = 0
    }
}

private func pathStatus(_ status: NWPath.Status) -> NetworkPathStatus {
    switch status {
    case .satisfied: return .satisfied
    case .unsatisfied: return .unsatisfied
    case .requiresConnection: return .requiresConnection
    @unknown default: return .unknown
    }
}

private func interfaceKind(_ type: NWInterface.InterfaceType?) -> NetworkInterfaceKind {
    guard let type else { return .unknown }
    switch type {
    case .wifi: return .wiFi
    case .wiredEthernet: return .ethernet
    case .cellular: return .cellular
    case .loopback: return .loopback
    case .other: return .other
    @unknown default: return .unknown
    }
}
