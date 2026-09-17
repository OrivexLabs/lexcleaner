import Foundation

public enum HardwareAvailability: String, Codable, Equatable, Sendable {
    case available
    case unavailable
    case unsupported
}

public struct HardwareMetricStatus: Codable, Equatable, Sendable {
    public let availability: HardwareAvailability
    public let source: String
    public let detail: String?

    public init(availability: HardwareAvailability, source: String, detail: String? = nil) {
        self.availability = availability
        self.source = source
        self.detail = detail
    }
}

public struct HardwareInfo: Codable, Equatable, Sendable {
    public let status: HardwareMetricStatus
    public let modelIdentifier: String?
    public let isAppleSilicon: Bool?
    public let physicalCoreCount: Int?
    public let logicalCoreCount: Int?
    public let performanceCoreCount: Int?
    public let efficiencyCoreCount: Int?
    public let physicalMemoryBytes: UInt64?

    public init(
        status: HardwareMetricStatus,
        modelIdentifier: String?,
        isAppleSilicon: Bool?,
        physicalCoreCount: Int?,
        logicalCoreCount: Int?,
        performanceCoreCount: Int?,
        efficiencyCoreCount: Int?,
        physicalMemoryBytes: UInt64?
    ) {
        self.status = status
        self.modelIdentifier = modelIdentifier
        self.isAppleSilicon = isAppleSilicon
        self.physicalCoreCount = physicalCoreCount
        self.logicalCoreCount = logicalCoreCount
        self.performanceCoreCount = performanceCoreCount
        self.efficiencyCoreCount = efficiencyCoreCount
        self.physicalMemoryBytes = physicalMemoryBytes
    }
}

public enum ThermalState: String, Codable, Equatable, Sendable {
    case nominal
    case fair
    case serious
    case critical
}

public struct ThermalSnapshot: Codable, Equatable, Sendable {
    public let status: HardwareMetricStatus
    public let state: ThermalState?
    public let lowPowerModeEnabled: Bool?

    public init(status: HardwareMetricStatus, state: ThermalState?, lowPowerModeEnabled: Bool?) {
        self.status = status
        self.state = state
        self.lowPowerModeEnabled = lowPowerModeEnabled
    }
}

public enum PowerSourceKind: String, Codable, Equatable, Sendable {
    case internalBattery
    case ac
    case ups
    case unknown
}

public struct BatterySnapshot: Codable, Equatable, Sendable {
    public let status: HardwareMetricStatus
    public let capacityStatus: HardwareMetricStatus
    public let cycleCountStatus: HardwareMetricStatus
    public let healthStatus: HardwareMetricStatus
    public let sourceKind: PowerSourceKind?
    public let isPresent: Bool?
    public let isCharging: Bool?
    public let currentCapacity: Int?
    public let maximumCapacity: Int?
    public let designCapacity: Int?
    public let nominalCapacity: Int?
    public let chargePercent: Double?
    public let cycleCount: Int?
    public let health: String?
    public let healthCondition: String?
    public let voltageMillivolts: Int?
    public let currentMilliamps: Int?
    public let temperatureCelsius: Double?
    public let timeRemainingMinutes: Int?

    public init(
        status: HardwareMetricStatus,
        capacityStatus: HardwareMetricStatus,
        cycleCountStatus: HardwareMetricStatus,
        healthStatus: HardwareMetricStatus,
        sourceKind: PowerSourceKind?,
        isPresent: Bool?,
        isCharging: Bool?,
        currentCapacity: Int?,
        maximumCapacity: Int?,
        designCapacity: Int?,
        nominalCapacity: Int?,
        chargePercent: Double?,
        cycleCount: Int?,
        health: String?,
        healthCondition: String?,
        voltageMillivolts: Int?,
        currentMilliamps: Int?,
        temperatureCelsius: Double?,
        timeRemainingMinutes: Int?
    ) {
        self.status = status
        self.capacityStatus = capacityStatus
        self.cycleCountStatus = cycleCountStatus
        self.healthStatus = healthStatus
        self.sourceKind = sourceKind
        self.isPresent = isPresent
        self.isCharging = isCharging
        self.currentCapacity = currentCapacity
        self.maximumCapacity = maximumCapacity
        self.designCapacity = designCapacity
        self.nominalCapacity = nominalCapacity
        self.chargePercent = chargePercent
        self.cycleCount = cycleCount
        self.health = health
        self.healthCondition = healthCondition
        self.voltageMillivolts = voltageMillivolts
        self.currentMilliamps = currentMilliamps
        self.temperatureCelsius = temperatureCelsius
        self.timeRemainingMinutes = timeRemainingMinutes
    }
}

public enum StorageDiskKind: String, Codable, Equatable, Sendable {
    case internalDisk
    case externalDisk
    case unknown
}

public enum StorageVolumeRole: String, Codable, Equatable, Sendable {
    case system
    case data
    case preboot
    case recovery
    case vm
    case update
    case xART
    case hardware
    case other
    case unknown
}

public enum StorageCapacityScope: String, Codable, Equatable, Sendable {
    /// APFS volume sizes are reported by the storage stack, but their capacity is shared.
    /// Only the containing APFS container owns capacity in the user-facing totals.
    case sharedContainer
}

public struct StorageVolumeSnapshot: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let role: StorageVolumeRole
    public let capacityScope: StorageCapacityScope
    public let reportedSizeBytes: UInt64?
    public let isMounted: Bool?

    // Advanced details. They are intentionally not required by ordinary UI copy.
    public let bsdName: String?
    public let uuid: String?
    public let volumeGroupUUID: String?

    public init(
        id: String,
        displayName: String,
        role: StorageVolumeRole,
        capacityScope: StorageCapacityScope = .sharedContainer,
        reportedSizeBytes: UInt64?,
        isMounted: Bool? = nil,
        bsdName: String?,
        uuid: String?,
        volumeGroupUUID: String?
    ) {
        self.id = id
        self.displayName = displayName
        self.role = role
        self.capacityScope = capacityScope
        self.reportedSizeBytes = reportedSizeBytes
        self.isMounted = isMounted
        self.bsdName = bsdName
        self.uuid = uuid
        self.volumeGroupUUID = volumeGroupUUID
    }
}

public struct StorageContainerSnapshot: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let capacityBytes: UInt64?
    public let volumes: [StorageVolumeSnapshot]

    // Advanced details. A container can have more than one physical store.
    public let bsdName: String?
    public let uuid: String?
    public let physicalStoreBSDNames: [String]

    public init(
        id: String,
        displayName: String,
        capacityBytes: UInt64?,
        volumes: [StorageVolumeSnapshot],
        bsdName: String?,
        uuid: String?,
        physicalStoreBSDNames: [String]
    ) {
        self.id = id
        self.displayName = displayName
        self.capacityBytes = capacityBytes
        self.volumes = volumes
        self.bsdName = bsdName
        self.uuid = uuid
        self.physicalStoreBSDNames = physicalStoreBSDNames
    }
}

public struct StoragePhysicalDiskSnapshot: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let kind: StorageDiskKind
    public let capacityBytes: UInt64?
    public let containers: [StorageContainerSnapshot]

    // Advanced details. BSD names are attachment identifiers, not disk identity.
    public let bsdName: String?
    public let uuid: String?
    public let vendor: String?
    public let revision: String?
    public let isRemovable: Bool?
    public let isEjectable: Bool?
    public let isWritable: Bool?

    public init(
        id: String,
        displayName: String,
        kind: StorageDiskKind,
        capacityBytes: UInt64?,
        containers: [StorageContainerSnapshot],
        bsdName: String?,
        uuid: String?,
        vendor: String?,
        revision: String?,
        isRemovable: Bool?,
        isEjectable: Bool?,
        isWritable: Bool?
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.capacityBytes = capacityBytes
        self.containers = containers
        self.bsdName = bsdName
        self.uuid = uuid
        self.vendor = vendor
        self.revision = revision
        self.isRemovable = isRemovable
        self.isEjectable = isEjectable
        self.isWritable = isWritable
    }
}

public struct StorageHealthSnapshot: Codable, Equatable, Sendable {
    public let status: HardwareMetricStatus
    public let physicalDisks: [StoragePhysicalDiskSnapshot]
    public let smartStatus: HardwareMetricStatus
    public let wearStatus: HardwareMetricStatus

    public init(
        status: HardwareMetricStatus,
        physicalDisks: [StoragePhysicalDiskSnapshot],
        smartStatus: HardwareMetricStatus,
        wearStatus: HardwareMetricStatus
    ) {
        self.status = status
        self.physicalDisks = physicalDisks
        self.smartStatus = smartStatus
        self.wearStatus = wearStatus
    }
}

public struct SensorSnapshot: Codable, Equatable, Sendable {
    public let status: HardwareMetricStatus
    public let valuesCelsius: [String: Double]

    public init(status: HardwareMetricStatus, valuesCelsius: [String: Double]) {
        self.status = status
        self.valuesCelsius = valuesCelsius
    }
}

public struct FanSnapshot: Codable, Equatable, Sendable {
    public let status: HardwareMetricStatus
    public let fanRPM: [Double]

    public init(status: HardwareMetricStatus, fanRPM: [Double]) {
        self.status = status
        self.fanRPM = fanRPM
    }
}

public struct PowerSnapshot: Codable, Equatable, Sendable {
    public let status: HardwareMetricStatus
    public let totalWatts: Double?
    public let cpuWatts: Double?
    public let gpuWatts: Double?
    public let aneWatts: Double?

    public init(status: HardwareMetricStatus, totalWatts: Double?, cpuWatts: Double?, gpuWatts: Double?, aneWatts: Double?) {
        self.status = status
        self.totalWatts = totalWatts
        self.cpuWatts = cpuWatts
        self.gpuWatts = gpuWatts
        self.aneWatts = aneWatts
    }
}

public struct HardwareSnapshot: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let hardware: HardwareInfo
    public let thermal: ThermalSnapshot
    public let battery: BatterySnapshot
    public let storage: StorageHealthSnapshot
    public let sensors: SensorSnapshot
    public let fans: FanSnapshot
    public let power: PowerSnapshot

    public init(
        timestamp: Date,
        hardware: HardwareInfo,
        thermal: ThermalSnapshot,
        battery: BatterySnapshot,
        storage: StorageHealthSnapshot,
        sensors: SensorSnapshot,
        fans: FanSnapshot,
        power: PowerSnapshot
    ) {
        self.timestamp = timestamp
        self.hardware = hardware
        self.thermal = thermal
        self.battery = battery
        self.storage = storage
        self.sensors = sensors
        self.fans = fans
        self.power = power
    }
}
