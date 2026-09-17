import Foundation
import Darwin
import IOKit
import IOKit.ps
import IOKit.pwr_mgt

struct HardwareCollector: Sendable {
    func collect(at timestamp: Date = Date()) -> HardwareSnapshot {
        HardwareSnapshot(
            timestamp: timestamp,
            hardware: collectHardwareInfo(),
            thermal: collectThermal(),
            battery: collectBattery(),
            storage: collectStorage(),
            sensors: SensorSnapshot(
                status: HardwareMetricStatus(
                    availability: .unsupported,
                    source: "Apple Silicon temperature sensor API audit",
                    detail: "SMC/IOHID/IOReport sensor keys are not a stable public product API"
                ),
                valuesCelsius: [:]
            ),
            fans: FanSnapshot(
                status: HardwareMetricStatus(
                    availability: .unsupported,
                    source: "Apple Silicon fan API audit",
                    detail: "Fan RPM requires device-specific SMC access"
                ),
                fanRPM: []
            ),
            power: PowerSnapshot(
                status: HardwareMetricStatus(
                    availability: .unsupported,
                    source: "Apple Silicon power API audit",
                    detail: "powermetrics/IOReport power counters are not a stable public API"
                ),
                totalWatts: nil,
                cpuWatts: nil,
                gpuWatts: nil,
                aneWatts: nil
            )
        )
    }

    private func collectHardwareInfo() -> HardwareInfo {
        let model = readSysctlString("hw.model")
        let arm64 = readSysctlInt("hw.optional.arm64").map { $0 == 1 }
        let physical = readSysctlInt("hw.physicalcpu")
        let logical = readSysctlInt("hw.logicalcpu")
        let performance = readSysctlInt("hw.perflevel0.physicalcpu")
        let efficiency = readSysctlInt("hw.perflevel1.physicalcpu")
        let memory = ProcessInfo.processInfo.physicalMemory
        let valuesAreValid = (physical ?? 0) > 0 && (logical ?? 0) >= (physical ?? 0) && memory > 0
        return HardwareInfo(
            status: HardwareMetricStatus(
                availability: valuesAreValid ? .available : .unavailable,
                source: "sysctl and Foundation ProcessInfo",
                detail: valuesAreValid ? nil : "one or more hardware properties were unavailable"
            ),
            modelIdentifier: model,
            isAppleSilicon: arm64,
            physicalCoreCount: physical,
            logicalCoreCount: logical,
            performanceCoreCount: performance,
            efficiencyCoreCount: efficiency,
            physicalMemoryBytes: memory > 0 ? memory : nil
        )
    }

    private func collectThermal() -> ThermalSnapshot {
        let processInfo = ProcessInfo.processInfo
        let state: ThermalState
        switch processInfo.thermalState {
        case .nominal: state = .nominal
        case .fair: state = .fair
        case .serious: state = .serious
        case .critical: state = .critical
        @unknown default:
            return ThermalSnapshot(
                status: HardwareMetricStatus(availability: .unavailable, source: "Foundation ProcessInfo.thermalState", detail: "unknown thermal state"),
                state: nil,
                lowPowerModeEnabled: processInfo.isLowPowerModeEnabled
            )
        }
        return ThermalSnapshot(
            status: HardwareMetricStatus(availability: .available, source: "Foundation ProcessInfo.thermalState"),
            state: state,
            lowPowerModeEnabled: processInfo.isLowPowerModeEnabled
        )
    }

    private func collectBattery() -> BatterySnapshot {
        guard let unmanagedPowerInfo = IOPSCopyPowerSourcesInfo() else {
            return unavailableBattery(detail: "IOPSCopyPowerSourcesInfo returned nil")
        }
        let powerInfo = unmanagedPowerInfo.takeRetainedValue()
        guard let unmanagedPowerSources = IOPSCopyPowerSourcesList(powerInfo),
              let powerSources = unmanagedPowerSources.takeUnretainedValue() as? [Any],
              !powerSources.isEmpty else {
            return unavailableBattery(detail: "no power sources reported by this Mac")
        }

        let descriptions: [[String: Any]] = powerSources.compactMap { source in
            let source = source as CFTypeRef
            guard let description = IOPSGetPowerSourceDescription(powerInfo, source) else { return nil }
            return description.takeUnretainedValue() as? [String: Any]
        }
        guard let description = descriptions.first(where: { dictionary in
            (dictionary[kIOPSIsPresentKey] as? NSNumber)?.boolValue ?? true
        }) ?? descriptions.first else {
            return unavailableBattery(detail: "power source description unavailable")
        }

        let type = description[kIOPSTypeKey] as? String
        let state = description[kIOPSPowerSourceStateKey] as? String
        let kind: PowerSourceKind
        switch type {
        case kIOPSInternalBatteryType: kind = .internalBattery
        case kIOPSUPSType: kind = .ups
        default: kind = state == kIOPSACPowerValue ? .ac : .unknown
        }
        let present = (description[kIOPSIsPresentKey] as? NSNumber)?.boolValue ?? true
        let currentCapacity = integerValue(description[kIOPSCurrentCapacityKey])
        let maximumCapacity = integerValue(description[kIOPSMaxCapacityKey])
        let chargePercent = validatedChargePercent(current: currentCapacity, maximum: maximumCapacity)
        let temperature = doubleValue(description[kIOPSTemperatureKey])
        let cycleCount = readLegacyCycleCount()
        let capacityStatus = HardwareMetricStatus(
            availability: chargePercent == nil ? .unavailable : .available,
            source: "IOKit IOPowerSources capacity keys",
            detail: chargePercent == nil ? "current/max capacity missing or outside a valid range" : nil
        )
        let cycleCountStatus = HardwareMetricStatus(
            availability: cycleCount == nil ? .unavailable : .available,
            source: "IOKit IOPMCopyBatteryInfo cycle count key",
            detail: cycleCount == nil ? "cycle count not published by this power source" : nil
        )
        let health = description[kIOPSBatteryHealthKey] as? String
        let healthCondition = description[kIOPSBatteryHealthConditionKey] as? String
        let healthStatus = HardwareMetricStatus(
            availability: health == nil && healthCondition == nil ? .unavailable : .available,
            source: "IOKit IOPowerSources health keys",
            detail: health == nil && healthCondition == nil ? "health fields not published by this power source" : nil
        )
        let availability: HardwareAvailability = present ? .available : .unavailable
        return BatterySnapshot(
            status: HardwareMetricStatus(
                availability: availability,
                source: "IOKit IOPowerSources",
                detail: present ? nil : "power source is not present"
            ),
            capacityStatus: capacityStatus,
            cycleCountStatus: cycleCountStatus,
            healthStatus: healthStatus,
            sourceKind: kind,
            isPresent: present,
            isCharging: (description[kIOPSIsChargingKey] as? NSNumber)?.boolValue,
            currentCapacity: currentCapacity,
            maximumCapacity: maximumCapacity,
            designCapacity: integerValue(description[kIOPSDesignCapacityKey]),
            nominalCapacity: integerValue(description[kIOPSNominalCapacityKey]),
            chargePercent: chargePercent,
            cycleCount: cycleCount,
            health: health,
            healthCondition: healthCondition,
            voltageMillivolts: integerValue(description[kIOPSVoltageKey]),
            currentMilliamps: integerValue(description[kIOPSCurrentKey]),
            temperatureCelsius: temperature,
            timeRemainingMinutes: integerValue(description[kIOPSTimeToEmptyKey])
        )
    }

    private func collectStorage() -> StorageHealthSnapshot {
        let matching = IOServiceMatching("IOMedia")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return StorageHealthSnapshot(
                status: HardwareMetricStatus(availability: .unavailable, source: "IOKit IOMedia", detail: "matching services unavailable"),
                physicalDisks: [],
                smartStatus: unsupportedSMARTStatus,
                wearStatus: unsupportedWearStatus
            )
        }
        defer { IOObjectRelease(iterator) }
        var records: [StorageMediaRecord] = []
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            guard let properties = registryProperties(for: service),
                  let registryID = registryEntryID(for: service) else { continue }
            let provider = providerProperties(for: service)
            records.append(StorageMediaRecord(
                registryID: registryID,
                parentMediaIDs: mediaAncestorIDs(for: service),
                className: registryClassName(for: service),
                registryName: registryName(for: service),
                fullName: stringProperty("FullName", properties: properties),
                bsdName: stringProperty("BSD Name", properties: properties),
                uuid: stringProperty("UUID", properties: properties),
                content: stringProperty("Content", properties: properties),
                contentHint: stringProperty("Content Hint", properties: properties),
                role: storageRole(properties["Role"]),
                volumeGroupUUID: stringProperty("VolGroupUUID", properties: properties),
                sizeBytes: unsignedValue(properties["Size"]),
                isWhole: (properties["Whole"] as? NSNumber)?.boolValue ?? false,
                isLeaf: (properties["Leaf"] as? NSNumber)?.boolValue ?? false,
                isRemovable: (properties["Removable"] as? NSNumber)?.boolValue,
                isEjectable: (properties["Ejectable"] as? NSNumber)?.boolValue,
                isWritable: (properties["Writable"] as? NSNumber)?.boolValue,
                model: stringProperty("Product Name", properties: properties) ?? stringProperty("Product Name", properties: provider),
                vendor: stringProperty("Vendor Name", properties: properties) ?? stringProperty("Vendor Name", properties: provider),
                revision: stringProperty("Product Revision Level", properties: properties) ?? stringProperty("Product Revision Level", properties: provider)
            ))
        }
        let physicalDisks = StorageTopologyBuilder.build(records: records)
        return StorageHealthSnapshot(
            status: HardwareMetricStatus(
                availability: physicalDisks.isEmpty ? .unavailable : .available,
                source: "IOKit IOMedia",
                detail: physicalDisks.isEmpty ? "no physical disk topology reported" : nil
            ),
            physicalDisks: physicalDisks,
            smartStatus: unsupportedSMARTStatus,
            wearStatus: unsupportedWearStatus
        )
    }

    private func registryProperties(for service: io_service_t) -> [String: Any]? {
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties,
              let dictionary = properties.takeRetainedValue() as? [String: Any] else { return nil }
        return dictionary
    }

    private func providerProperties(for service: io_service_t) -> [String: Any] {
        var parent: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(parent) }
        return registryProperties(for: parent) ?? [:]
    }

    private func registryEntryID(for service: io_service_t) -> UInt64? {
        var identifier: UInt64 = 0
        return IORegistryEntryGetRegistryEntryID(service, &identifier) == KERN_SUCCESS ? identifier : nil
    }

    private func registryClassName(for service: io_service_t) -> String {
        var buffer = [CChar](repeating: 0, count: 128)
        guard IOObjectGetClass(service, &buffer) == KERN_SUCCESS else { return "" }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private func registryName(for service: io_service_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 128)
        guard IORegistryEntryGetName(service, &buffer) == KERN_SUCCESS else { return nil }
        let name = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private func mediaAncestorIDs(for service: io_service_t) -> [UInt64] {
        var result: [UInt64] = []
        var cursor: io_registry_entry_t = service
        var ownsCursor = false
        defer {
            if ownsCursor { IOObjectRelease(cursor) }
        }

        while true {
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(cursor, kIOServicePlane, &parent) == KERN_SUCCESS else { break }
            if ownsCursor { IOObjectRelease(cursor) }
            cursor = parent
            ownsCursor = true
            guard IOObjectConformsTo(cursor, "IOMedia") != 0 else { continue }
            if let identifier = registryEntryID(for: cursor) { result.append(identifier) }
        }
        return result
    }

    private func unavailableBattery(detail: String) -> BatterySnapshot {
        BatterySnapshot(
            status: HardwareMetricStatus(availability: .unavailable, source: "IOKit IOPowerSources", detail: detail),
            capacityStatus: unavailableBatteryStatus(detail: "capacity unavailable"),
            cycleCountStatus: unavailableBatteryStatus(detail: "cycle count unavailable"),
            healthStatus: unavailableBatteryStatus(detail: "health unavailable"),
            sourceKind: nil,
            isPresent: false,
            isCharging: nil,
            currentCapacity: nil,
            maximumCapacity: nil,
            designCapacity: nil,
            nominalCapacity: nil,
            chargePercent: nil,
            cycleCount: nil,
            health: nil,
            healthCondition: nil,
            voltageMillivolts: nil,
            currentMilliamps: nil,
            temperatureCelsius: nil,
            timeRemainingMinutes: nil
        )
    }

    private func readLegacyCycleCount() -> Int? {
        var info: Unmanaged<CFArray>?
        guard IOPMCopyBatteryInfo(mach_port_t(MACH_PORT_NULL), &info) == kIOReturnSuccess,
              let info,
              let dictionaries = info.takeRetainedValue() as? [[String: Any]] else { return nil }
        return dictionaries.lazy.compactMap { integerValue($0[kIOBatteryCycleCountKey]) }.first(where: { $0 >= 0 })
    }
}

struct StorageMediaRecord: Equatable, Sendable {
    let registryID: UInt64
    let parentMediaIDs: [UInt64]
    let className: String
    let registryName: String?
    let fullName: String?
    let bsdName: String?
    let uuid: String?
    let content: String?
    let contentHint: String?
    let role: StorageVolumeRole?
    let volumeGroupUUID: String?
    let sizeBytes: UInt64?
    let isWhole: Bool
    let isLeaf: Bool
    let isRemovable: Bool?
    let isEjectable: Bool?
    let isWritable: Bool?
    let model: String?
    let vendor: String?
    let revision: String?
}

enum StorageTopologyBuilder {
    private static let apfsContainerType = "EF57347C-0000-11AA-AA11-00306543ECAC"
    private static let apfsVolumeType = "41504653-0000-11AA-AA11-00306543ECAC"

    static func build(records: [StorageMediaRecord]) -> [StoragePhysicalDiskSnapshot] {
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.registryID, $0) })
        let physicalRecords = records.filter(isPhysicalDisk)

        return physicalRecords.compactMap { physical in
            let containers = records
                .filter { isAPFSContainer($0) && $0.parentMediaIDs.contains(physical.registryID) }
                .reduce(into: [String: StorageMediaRecord]()) { result, container in
                    let key = normalizedIdentifier(container.uuid) ?? container.bsdName ?? "media-\(container.registryID)"
                    if result[key] == nil { result[key] = container }
                }
                .values
                .sorted { ($0.bsdName ?? "") < ($1.bsdName ?? "") }
                .map { container in
                    makeContainer(container, records: records, byID: byID, physical: physical)
                }

            let kind: StorageDiskKind
            if physical.isRemovable == true || physical.isEjectable == true {
                kind = .externalDisk
            } else if physical.isRemovable == false || physical.isEjectable == false {
                kind = .internalDisk
            } else {
                kind = .unknown
            }

            let displayName = cleanDisplayName(physical.model ?? physical.registryName)
                ?? (kind == .externalDisk ? "External disk" : kind == .internalDisk ? "Internal disk" : "Storage disk")
            return StoragePhysicalDiskSnapshot(
                id: normalizedIdentifier(physical.uuid) ?? "physical-\(physical.registryID)",
                displayName: displayName,
                kind: kind,
                capacityBytes: physical.sizeBytes,
                containers: containers,
                bsdName: physical.bsdName,
                uuid: physical.uuid,
                vendor: physical.vendor,
                revision: physical.revision,
                isRemovable: physical.isRemovable,
                isEjectable: physical.isEjectable,
                isWritable: physical.isWritable
            )
        }
        .sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind == .internalDisk }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    private static func makeContainer(
        _ container: StorageMediaRecord,
        records: [StorageMediaRecord],
        byID: [UInt64: StorageMediaRecord],
        physical: StorageMediaRecord
    ) -> StorageContainerSnapshot {
        let volumeRecords = records
            .filter { isAPFSVolume($0) && $0.parentMediaIDs.contains(container.registryID) }
            .reduce(into: [String: StorageMediaRecord]()) { result, volume in
                let key = normalizedIdentifier(volume.uuid) ?? volume.bsdName ?? "media-\(volume.registryID)"
                if result[key] == nil { result[key] = volume }
            }
            .values
            .sorted { ($0.bsdName ?? "") < ($1.bsdName ?? "") }

        let volumes = volumeRecords.map { volume in
            StorageVolumeSnapshot(
                id: normalizedIdentifier(volume.uuid) ?? "volume-\(volume.registryID)",
                displayName: cleanDisplayName(volume.fullName ?? volume.registryName ?? volume.bsdName) ?? "APFS Volume",
                role: volume.role ?? .unknown,
                capacityScope: .sharedContainer,
                reportedSizeBytes: volume.sizeBytes,
                bsdName: volume.bsdName,
                uuid: volume.uuid,
                volumeGroupUUID: volume.volumeGroupUUID
            )
        }

        let physicalStoreNames = container.parentMediaIDs
            .compactMap { byID[$0] }
            .filter { $0.registryID != physical.registryID }
            .compactMap(\.bsdName)
            .sorted()

        return StorageContainerSnapshot(
            id: normalizedIdentifier(container.uuid) ?? "container-\(container.registryID)",
            displayName: "APFS Container",
            capacityBytes: container.sizeBytes,
            volumes: volumes,
            bsdName: container.bsdName,
            uuid: container.uuid,
            physicalStoreBSDNames: physicalStoreNames
        )
    }

    private static func isPhysicalDisk(_ record: StorageMediaRecord) -> Bool {
        record.isWhole && !isAPFSContainer(record) && record.className != "AppleAPFSVolume" && record.className != "AppleAPFSSnapshot"
    }

    private static func isAPFSContainer(_ record: StorageMediaRecord) -> Bool {
        record.isWhole && (record.className == "AppleAPFSMedia" || matchesType(record, apfsContainerType))
    }

    private static func isAPFSVolume(_ record: StorageMediaRecord) -> Bool {
        record.className == "AppleAPFSVolume" || (record.isLeaf && matchesType(record, apfsVolumeType) && record.className != "AppleAPFSSnapshot")
    }

    private static func matchesType(_ record: StorageMediaRecord, _ type: String) -> Bool {
        record.content?.caseInsensitiveCompare(type) == .orderedSame || record.contentHint?.caseInsensitiveCompare(type) == .orderedSame
    }

    private static func normalizedIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.uppercased()
    }

    private static func cleanDisplayName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.hasSuffix(" Media") ? String(trimmed.dropLast(6)) : trimmed
    }
}

private let unsupportedSMARTStatus = HardwareMetricStatus(
    availability: .unsupported,
    source: "Storage SMART API audit",
    detail: "SMART/wear is not exposed through a stable product-level public API"
)

private let unsupportedWearStatus = HardwareMetricStatus(
    availability: .unsupported,
    source: "Storage wear API audit",
    detail: "storage wear is not exposed through a stable product-level public API"
)

private func unavailableBatteryStatus(detail: String) -> HardwareMetricStatus {
    HardwareMetricStatus(availability: .unavailable, source: "IOKit IOPowerSources", detail: detail)
}

private func readSysctlString(_ name: String) -> String? {
    var size = 0
    guard name.withCString({ sysctlbyname($0, nil, &size, nil, 0) }) == 0, size > 1 else { return nil }
    var buffer = [CChar](repeating: 0, count: size)
    guard name.withCString({ sysctlbyname($0, &buffer, &size, nil, 0) }) == 0 else { return nil }
    return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
}

private func readSysctlInt(_ name: String) -> Int? {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size
    guard name.withCString({ sysctlbyname($0, &value, &size, nil, 0) }) == 0 else { return nil }
    return Int(value)
}

private func integerValue(_ value: Any?) -> Int? {
    guard let number = value as? NSNumber else { return nil }
    return number.intValue
}

private func doubleValue(_ value: Any?) -> Double? {
    guard let number = value as? NSNumber else { return nil }
    let result = number.doubleValue
    return result.isFinite ? result : nil
}

private func unsignedValue(_ value: Any?) -> UInt64? {
    guard let number = value as? NSNumber, number.int64Value >= 0 else { return nil }
    return UInt64(number.int64Value)
}

private func validatedChargePercent(current: Int?, maximum: Int?) -> Double? {
    guard let current, let maximum, maximum > 0, current >= 0, current <= maximum else { return nil }
    let percent = Double(current) / Double(maximum) * 100
    return percent.isFinite && percent >= 0 && percent <= 100 ? percent : nil
}

private func stringProperty(_ key: String, properties: [String: Any]) -> String? {
    guard let value = properties[key] as? String else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func storageRole(_ value: Any?) -> StorageVolumeRole? {
    let rawValue: String?
    if let value = value as? String {
        rawValue = value
    } else if let values = value as? [String] {
        rawValue = values.first
    } else if let values = value as? [Any] {
        rawValue = values.first as? String
    } else {
        rawValue = nil
    }

    switch rawValue?.lowercased() {
    case "system": return .system
    case "data": return .data
    case "preboot": return .preboot
    case "recovery": return .recovery
    case "vm": return .vm
    case "update": return .update
    case "xart": return .xART
    case "hardware": return .hardware
    case nil: return nil
    default: return .other
    }
}
