import Foundation

public enum NetworkAvailability: String, Codable, Equatable, Sendable {
    case available
    case unavailable
    case unsupported
}

public struct NetworkMetric<T: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public let availability: NetworkAvailability
    public let value: T?
    public let source: String
    public let detail: String?

    public init(
        availability: NetworkAvailability,
        value: T? = nil,
        source: String,
        detail: String? = nil
    ) {
        self.availability = availability
        self.value = value
        self.source = source
        self.detail = detail
    }

    public static func available(_ value: T, source: String) -> Self {
        Self(availability: .available, value: value, source: source)
    }

    public static func unavailable(source: String, detail: String) -> Self {
        Self(availability: .unavailable, source: source, detail: detail)
    }

    public static func unsupported(source: String, detail: String) -> Self {
        Self(availability: .unsupported, source: source, detail: detail)
    }
}

public enum NetworkInterfaceKind: String, Codable, Equatable, Sendable {
    case wiFi
    case ethernet
    case cellular
    case loopback
    case other
    case unknown
}

public struct NetworkInterfaceHealthSnapshot: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let kind: NetworkInterfaceKind
    public let isUp: Bool
    public let ipv4Addresses: [String]
    public let ipv6Addresses: [String]
    public let receivedBytes: UInt64
    public let sentBytes: UInt64
    public let inputErrors: UInt64
    public let outputErrors: UInt64
    public let droppedPackets: UInt64

    public init(
        name: String,
        kind: NetworkInterfaceKind,
        isUp: Bool,
        ipv4Addresses: [String] = [],
        ipv6Addresses: [String] = [],
        receivedBytes: UInt64 = 0,
        sentBytes: UInt64 = 0,
        inputErrors: UInt64 = 0,
        outputErrors: UInt64 = 0,
        droppedPackets: UInt64 = 0
    ) {
        self.id = name
        self.name = name
        self.kind = kind
        self.isUp = isUp
        self.ipv4Addresses = ipv4Addresses
        self.ipv6Addresses = ipv6Addresses
        self.receivedBytes = receivedBytes
        self.sentBytes = sentBytes
        self.inputErrors = inputErrors
        self.outputErrors = outputErrors
        self.droppedPackets = droppedPackets
    }
}

public enum NetworkPathStatus: String, Codable, Equatable, Sendable {
    case satisfied
    case unsatisfied
    case requiresConnection
    case unknown
}

public struct NetworkPathSnapshot: Codable, Equatable, Sendable {
    public let status: NetworkPathStatus
    public let activeInterface: String?
    public let activeInterfaceKind: NetworkInterfaceKind
    public let isExpensive: Bool
    public let isConstrained: Bool

    public init(
        status: NetworkPathStatus,
        activeInterface: String?,
        activeInterfaceKind: NetworkInterfaceKind,
        isExpensive: Bool,
        isConstrained: Bool
    ) {
        self.status = status
        self.activeInterface = activeInterface
        self.activeInterfaceKind = activeInterfaceKind
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
    }
}

public struct DNSResolverSnapshot: Codable, Equatable, Sendable {
    public let servers: [String]
    public let source: String
    public let isConfigured: Bool

    public init(servers: [String], source: String, isConfigured: Bool) {
        self.servers = servers
        self.source = source
        self.isConfigured = isConfigured
    }
}

public struct DNSBenchmarkServer: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let address: String

    public init(name: String, address: String) {
        self.id = address
        self.name = name
        self.address = address
    }
}

public struct DNSBenchmarkResult: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let server: DNSBenchmarkServer
    public let medianLatencyMilliseconds: Double?
    public let p95LatencyMilliseconds: Double?
    public let jitterMilliseconds: Double?
    public let timeoutCount: Int
    public let probeCount: Int
    public let failureRate: Double?
    public let availability: NetworkAvailability
    public let detail: String?

    public init(
        server: DNSBenchmarkServer,
        medianLatencyMilliseconds: Double?,
        p95LatencyMilliseconds: Double?,
        jitterMilliseconds: Double?,
        timeoutCount: Int,
        probeCount: Int,
        failureRate: Double?,
        availability: NetworkAvailability,
        detail: String? = nil
    ) {
        self.id = server.id
        self.server = server
        self.medianLatencyMilliseconds = medianLatencyMilliseconds
        self.p95LatencyMilliseconds = p95LatencyMilliseconds
        self.jitterMilliseconds = jitterMilliseconds
        self.timeoutCount = timeoutCount
        self.probeCount = probeCount
        self.failureRate = failureRate
        self.availability = availability
        self.detail = detail
    }
}

public struct NetworkProbeStatistics: Codable, Equatable, Sendable {
    public let target: String
    public let port: UInt16
    public let medianLatencyMilliseconds: Double?
    public let p95LatencyMilliseconds: Double?
    public let jitterMilliseconds: Double?
    public let successfulProbes: Int
    public let probeCount: Int
    public let failureRate: Double?
    public let availability: NetworkAvailability
    public let detail: String?

    public init(
        target: String,
        port: UInt16,
        medianLatencyMilliseconds: Double?,
        p95LatencyMilliseconds: Double?,
        jitterMilliseconds: Double?,
        successfulProbes: Int,
        probeCount: Int,
        failureRate: Double?,
        availability: NetworkAvailability,
        detail: String? = nil
    ) {
        self.target = target
        self.port = port
        self.medianLatencyMilliseconds = medianLatencyMilliseconds
        self.p95LatencyMilliseconds = p95LatencyMilliseconds
        self.jitterMilliseconds = jitterMilliseconds
        self.successfulProbes = successfulProbes
        self.probeCount = probeCount
        self.failureRate = failureRate
        self.availability = availability
        self.detail = detail
    }
}

public enum NetworkIssueSeverity: String, Codable, Equatable, Sendable {
    case info
    case warning
    case critical
}

public struct NetworkIssue: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let severity: NetworkIssueSeverity
    public let titleKey: String
    public let detailKey: String
    public let detailValue: String?

    public init(id: String, severity: NetworkIssueSeverity, titleKey: String, detailKey: String, detailValue: String? = nil) {
        self.id = id
        self.severity = severity
        self.titleKey = titleKey
        self.detailKey = detailKey
        self.detailValue = detailValue
    }
}

public struct NetworkHealthScore: Codable, Equatable, Sendable {
    public let value: Int?
    public let availability: NetworkAvailability
    public let detail: String?

    public init(value: Int?, availability: NetworkAvailability, detail: String? = nil) {
        self.value = value
        self.availability = availability
        self.detail = detail
    }
}

public struct NetworkHealthSnapshot: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let path: NetworkPathSnapshot
    public let interfaces: [NetworkInterfaceHealthSnapshot]
    public let dns: DNSResolverSnapshot
    public let gateway: NetworkMetric<String>
    public let proxy: NetworkMetric<String>
    public let vpn: NetworkMetric<String>
    public let latency: NetworkProbeStatistics
    public let packetLossPercentage: NetworkMetric<Double>
    public let score: NetworkHealthScore
    public let issues: [NetworkIssue]

    public init(
        timestamp: Date,
        path: NetworkPathSnapshot,
        interfaces: [NetworkInterfaceHealthSnapshot],
        dns: DNSResolverSnapshot,
        gateway: NetworkMetric<String>,
        proxy: NetworkMetric<String>,
        vpn: NetworkMetric<String>,
        latency: NetworkProbeStatistics,
        packetLossPercentage: NetworkMetric<Double>,
        score: NetworkHealthScore,
        issues: [NetworkIssue]
    ) {
        self.timestamp = timestamp
        self.path = path
        self.interfaces = interfaces
        self.dns = dns
        self.gateway = gateway
        self.proxy = proxy
        self.vpn = vpn
        self.latency = latency
        self.packetLossPercentage = packetLossPercentage
        self.score = score
        self.issues = issues
    }
}

public struct NetworkApplicationUsage: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let processName: String
    public let pid: Int32?
    public let receivedBytes: UInt64?
    public let sentBytes: UInt64?
    public let availability: NetworkAvailability
    public let detail: String?

    public init(
        processName: String,
        pid: Int32?,
        receivedBytes: UInt64?,
        sentBytes: UInt64?,
        availability: NetworkAvailability,
        detail: String? = nil
    ) {
        self.id = pid.map(String.init) ?? processName
        self.processName = processName
        self.pid = pid
        self.receivedBytes = receivedBytes
        self.sentBytes = sentBytes
        self.availability = availability
        self.detail = detail
    }
}

public enum NetworkOptimizationKind: String, Codable, Equatable, Sendable {
    case dns
}

public enum NetworkOptimizationStatus: String, Codable, Equatable, Sendable {
    case planned
    case applied
    case rolledBack
    case requiresAdministrator
    case unsupported
    case failed
}

public struct NetworkOptimizationPlan: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let kind: NetworkOptimizationKind
    public let createdAt: Date
    public let originalDNS: [String]
    public let proposedDNS: [String]
    public let targetServiceID: String?
    public let targetServiceName: String?
    public let targetInterface: String?
    public let requiresAdministrator: Bool
    public let status: NetworkOptimizationStatus

    public init(
        id: UUID = UUID(),
        kind: NetworkOptimizationKind,
        createdAt: Date = Date(),
        originalDNS: [String],
        proposedDNS: [String],
        targetServiceID: String? = nil,
        targetServiceName: String? = nil,
        targetInterface: String? = nil,
        requiresAdministrator: Bool,
        status: NetworkOptimizationStatus = .planned
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.originalDNS = originalDNS
        self.proposedDNS = proposedDNS
        self.targetServiceID = targetServiceID
        self.targetServiceName = targetServiceName
        self.targetInterface = targetInterface
        self.requiresAdministrator = requiresAdministrator
        self.status = status
    }
}

public struct NetworkOptimizationResult: Codable, Equatable, Sendable {
    public let status: NetworkOptimizationStatus
    public let before: NetworkProbeStatistics?
    public let after: NetworkProbeStatistics?
    public let beforeDNS: [DNSBenchmarkResult]
    public let afterDNS: [DNSBenchmarkResult]
    public let improved: Bool?
    public let rollbackVerified: Bool?
    public let detail: String

    public init(
        status: NetworkOptimizationStatus,
        before: NetworkProbeStatistics? = nil,
        after: NetworkProbeStatistics? = nil,
        beforeDNS: [DNSBenchmarkResult] = [],
        afterDNS: [DNSBenchmarkResult] = [],
        improved: Bool? = nil,
        rollbackVerified: Bool? = nil,
        detail: String
    ) {
        self.status = status
        self.before = before
        self.after = after
        self.beforeDNS = beforeDNS
        self.afterDNS = afterDNS
        self.improved = improved
        self.rollbackVerified = rollbackVerified
        self.detail = detail
    }
}

public struct NetworkOptimizerSnapshot: Codable, Equatable, Sendable {
    public let health: NetworkHealthSnapshot
    public let dnsBenchmarks: [DNSBenchmarkResult]
    public let applicationUsage: [NetworkApplicationUsage]
    public let optimizationPlan: NetworkOptimizationPlan?

    public init(
        health: NetworkHealthSnapshot,
        dnsBenchmarks: [DNSBenchmarkResult] = [],
        applicationUsage: [NetworkApplicationUsage] = [],
        optimizationPlan: NetworkOptimizationPlan? = nil
    ) {
        self.health = health
        self.dnsBenchmarks = dnsBenchmarks
        self.applicationUsage = applicationUsage
        self.optimizationPlan = optimizationPlan
    }
}
