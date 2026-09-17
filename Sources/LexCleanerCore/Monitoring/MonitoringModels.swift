import Foundation

public enum MonitoringError: Error, LocalizedError, Sendable, Equatable {
    case invalidSamplingInterval
    case cpuStatisticsUnavailable(Int32)
    case memoryStatisticsUnavailable(Int32)
    case processStatisticsUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidSamplingInterval:
            return "Sampling interval must be at least 0.1 seconds."
        case let .cpuStatisticsUnavailable(status):
            return "CPU statistics are unavailable (Mach status \(status))."
        case let .memoryStatisticsUnavailable(status):
            return "Memory statistics are unavailable (Mach status \(status))."
        case .processStatisticsUnavailable:
            return "Process statistics are unavailable."
        }
    }
}

public enum MemoryPressureLevel: String, Codable, Sendable, Hashable {
    case normal
    case warning
    case critical
    case unknown
}

public enum MemoryPressureSource: String, Codable, Sendable, Hashable {
    case derivedFromPublicVMStatistics
    case unknown
}

public struct CPUSnapshot: Codable, Sendable, Hashable {
    public let timestamp: Date
    public let totalUsagePercent: Double
    public let userUsagePercent: Double
    public let systemUsagePercent: Double
    public let idleUsagePercent: Double
    public let perCoreUsagePercent: [Double]

    public init(
        timestamp: Date,
        totalUsagePercent: Double,
        userUsagePercent: Double,
        systemUsagePercent: Double,
        idleUsagePercent: Double,
        perCoreUsagePercent: [Double]
    ) {
        self.timestamp = timestamp
        self.totalUsagePercent = totalUsagePercent
        self.userUsagePercent = userUsagePercent
        self.systemUsagePercent = systemUsagePercent
        self.idleUsagePercent = idleUsagePercent
        self.perCoreUsagePercent = perCoreUsagePercent
    }
}

public struct MemorySnapshot: Codable, Sendable, Hashable {
    public let timestamp: Date
    public let physicalMemoryBytes: UInt64
    public let usedMemoryBytes: UInt64
    public let availableMemoryBytes: UInt64
    public let wiredMemoryBytes: UInt64
    public let compressedMemoryBytes: UInt64
    public let swapTotalBytes: UInt64
    public let swapUsedBytes: UInt64
    public let pressure: MemoryPressureLevel
    public let pressureSource: MemoryPressureSource

    public init(
        timestamp: Date,
        physicalMemoryBytes: UInt64,
        usedMemoryBytes: UInt64,
        availableMemoryBytes: UInt64,
        wiredMemoryBytes: UInt64,
        compressedMemoryBytes: UInt64,
        swapTotalBytes: UInt64,
        swapUsedBytes: UInt64,
        pressure: MemoryPressureLevel,
        pressureSource: MemoryPressureSource
    ) {
        self.timestamp = timestamp
        self.physicalMemoryBytes = physicalMemoryBytes
        self.usedMemoryBytes = usedMemoryBytes
        self.availableMemoryBytes = availableMemoryBytes
        self.wiredMemoryBytes = wiredMemoryBytes
        self.compressedMemoryBytes = compressedMemoryBytes
        self.swapTotalBytes = swapTotalBytes
        self.swapUsedBytes = swapUsedBytes
        self.pressure = pressure
        self.pressureSource = pressureSource
    }
}

public struct DiskSnapshot: Codable, Sendable, Hashable {
    public let timestamp: Date
    public let volumePath: URL
    public let totalBytes: UInt64
    public let usedBytes: UInt64
    public let availableBytes: UInt64
    public let cumulativeReadBytes: UInt64
    public let cumulativeWrittenBytes: UInt64
    public let readBytesPerSecond: Double
    public let writeBytesPerSecond: Double
    public let ioStatisticsAvailable: Bool

    public init(
        timestamp: Date,
        volumePath: URL,
        totalBytes: UInt64,
        usedBytes: UInt64,
        availableBytes: UInt64,
        cumulativeReadBytes: UInt64,
        cumulativeWrittenBytes: UInt64,
        readBytesPerSecond: Double,
        writeBytesPerSecond: Double,
        ioStatisticsAvailable: Bool
    ) {
        self.timestamp = timestamp
        self.volumePath = volumePath
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.availableBytes = availableBytes
        self.cumulativeReadBytes = cumulativeReadBytes
        self.cumulativeWrittenBytes = cumulativeWrittenBytes
        self.readBytesPerSecond = readBytesPerSecond
        self.writeBytesPerSecond = writeBytesPerSecond
        self.ioStatisticsAvailable = ioStatisticsAvailable
    }
}

public struct NetworkInterfaceSnapshot: Codable, Sendable, Hashable {
    public let name: String
    public let cumulativeReceivedBytes: UInt64
    public let cumulativeSentBytes: UInt64
    public let downloadBytesPerSecond: Double
    public let uploadBytesPerSecond: Double

    public init(
        name: String,
        cumulativeReceivedBytes: UInt64,
        cumulativeSentBytes: UInt64,
        downloadBytesPerSecond: Double,
        uploadBytesPerSecond: Double
    ) {
        self.name = name
        self.cumulativeReceivedBytes = cumulativeReceivedBytes
        self.cumulativeSentBytes = cumulativeSentBytes
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
    }
}

public struct NetworkSnapshot: Codable, Sendable, Hashable {
    public let timestamp: Date
    public let interfaces: [NetworkInterfaceSnapshot]
    public let cumulativeReceivedBytes: UInt64
    public let cumulativeSentBytes: UInt64
    public let downloadBytesPerSecond: Double
    public let uploadBytesPerSecond: Double

    public init(
        timestamp: Date,
        interfaces: [NetworkInterfaceSnapshot],
        cumulativeReceivedBytes: UInt64,
        cumulativeSentBytes: UInt64,
        downloadBytesPerSecond: Double,
        uploadBytesPerSecond: Double
    ) {
        self.timestamp = timestamp
        self.interfaces = interfaces
        self.cumulativeReceivedBytes = cumulativeReceivedBytes
        self.cumulativeSentBytes = cumulativeSentBytes
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
    }
}

public struct ProcessSnapshot: Codable, Sendable, Hashable {
    public let pid: Int32
    public let name: String
    public let cpuUsagePercent: Double
    public let residentMemoryBytes: UInt64

    public init(pid: Int32, name: String, cpuUsagePercent: Double, residentMemoryBytes: UInt64) {
        self.pid = pid
        self.name = name
        self.cpuUsagePercent = cpuUsagePercent
        self.residentMemoryBytes = residentMemoryBytes
    }
}

public struct MonitoringSnapshot: Codable, Sendable, Hashable {
    public let timestamp: Date
    public let cpu: CPUSnapshot
    public let memory: MemorySnapshot
    public let disk: DiskSnapshot
    public let network: NetworkSnapshot
    public let processes: [ProcessSnapshot]

    public init(
        timestamp: Date,
        cpu: CPUSnapshot,
        memory: MemorySnapshot,
        disk: DiskSnapshot,
        network: NetworkSnapshot,
        processes: [ProcessSnapshot]
    ) {
        self.timestamp = timestamp
        self.cpu = cpu
        self.memory = memory
        self.disk = disk
        self.network = network
        self.processes = processes
    }
}
