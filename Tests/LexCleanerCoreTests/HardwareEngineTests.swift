import Foundation
import Testing
@testable import LexCleanerCore

@Suite("HardwareObservabilityFoundation")
struct HardwareEngineTests {
    @Test("rejects an unsafe hardware sampling interval")
    func rejectsUnsafeSamplingInterval() {
        #expect(throws: HardwareSamplingError.invalidSamplingInterval) {
            _ = try HardwareSamplingConfiguration(interval: 0.01)
        }
    }

    @Test("reports real Apple Silicon hardware information when available")
    func reportsHardwareInformation() async throws {
        let snapshot = try await HardwareSampler().sample()
        #expect(snapshot.hardware.status.availability == .available)
        #expect(snapshot.hardware.modelIdentifier?.isEmpty == false)
        #expect(snapshot.hardware.physicalMemoryBytes ?? 0 > 0)
        #expect(snapshot.hardware.logicalCoreCount ?? 0 >= snapshot.hardware.physicalCoreCount ?? 0)
    }

    @Test("reports the public thermal state without temperature guessing")
    func reportsThermalState() async throws {
        let snapshot = try await HardwareSampler().sample()
        #expect(snapshot.thermal.status.availability == .available)
        #expect(snapshot.thermal.state != nil)
        #expect(snapshot.sensors.valuesCelsius.isEmpty)
    }

    @Test("reports battery unavailable on hardware without a battery")
    func reportsBatteryAvailability() async throws {
        let snapshot = try await HardwareSampler().sample()
        if snapshot.battery.status.availability == .available {
            #expect(snapshot.battery.isPresent == true)
            if let charge = snapshot.battery.chargePercent { #expect((0...100).contains(charge)) }
            if let cycleCount = snapshot.battery.cycleCount { #expect(cycleCount >= 0) }
        } else {
            #expect(snapshot.battery.status.availability == .unavailable)
            #expect(snapshot.battery.capacityStatus.availability == .unavailable)
            #expect(snapshot.battery.cycleCountStatus.availability == .unavailable)
            #expect(snapshot.battery.healthStatus.availability == .unavailable)
            #expect(snapshot.battery.chargePercent == nil)
            #expect(snapshot.battery.cycleCount == nil)
        }
    }

    @Test("reports storage metadata with valid ranges")
    func reportsStorage() async throws {
        let snapshot = try await HardwareSampler().sample()
        #expect(snapshot.storage.status.availability == .available)
        #expect(!snapshot.storage.physicalDisks.isEmpty)
        #expect(snapshot.storage.physicalDisks.allSatisfy { ($0.capacityBytes ?? 0) > 0 })
        #expect(snapshot.storage.physicalDisks.flatMap(\.containers).allSatisfy { ($0.capacityBytes ?? 0) > 0 })
        #expect(snapshot.storage.physicalDisks.flatMap(\.containers).flatMap(\.volumes).allSatisfy { $0.capacityScope == .sharedContainer })
        #expect(snapshot.storage.smartStatus.availability == .unsupported)
        #expect(snapshot.storage.wearStatus.availability == .unsupported)
    }

    @Test("deduplicates physical media and does not count APFS System/Data twice")
    func buildsPhysicalDiskTopology() {
        let records = [
            media(1, className: "IOMedia", name: "APPLE SSD Media", bsd: "disk0", size: 500_000_000_000, whole: true, removable: false),
            media(2, parents: [1], className: "IOMedia", bsd: "disk0s2", content: "7C3457EF-0000-11AA-AA11-00306543ECAC", size: 494_000_000_000),
            media(3, parents: [2, 1], className: "AppleAPFSMedia", bsd: "disk3", uuid: "container-1", content: "EF57347C-0000-11AA-AA11-00306543ECAC", size: 494_000_000_000, whole: true),
            media(4, parents: [3, 2, 1], className: "AppleAPFSVolume", name: "Macintosh HD", bsd: "disk3s1", uuid: "system-1", content: "41504653-0000-11AA-AA11-00306543ECAC", role: .system, volumeGroupUUID: "group-1", size: 494_000_000_000, leaf: true),
            media(5, parents: [3, 2, 1], className: "AppleAPFSVolume", name: "Data", bsd: "disk3s5", uuid: "data-1", content: "41504653-0000-11AA-AA11-00306543ECAC", role: .data, volumeGroupUUID: "group-1", size: 494_000_000_000, leaf: true),
            media(6, parents: [3, 2, 1], className: "AppleAPFSSnapshot", name: "com.apple.os.update", bsd: "disk3s1s1", uuid: "snapshot-1", content: "41504653-0000-11AA-AA11-00306543ECAC", size: 494_000_000_000, leaf: true),
            media(7, parents: [2, 1], className: "AppleAPFSMedia", bsd: "disk9", uuid: "container-1", content: "EF57347C-0000-11AA-AA11-00306543ECAC", size: 494_000_000_000, whole: true),
            media(8, className: "IOMedia", name: "External SSD Media", bsd: "disk4", size: 1_000_000_000_000, whole: true, removable: true),
            media(9, parents: [8], className: "AppleAPFSMedia", bsd: "disk5", uuid: "container-2", content: "EF57347C-0000-11AA-AA11-00306543ECAC", size: 1_000_000_000_000, whole: true),
            media(10, parents: [9, 8], className: "AppleAPFSVolume", name: "External Data", bsd: "disk5s1", uuid: "external-volume", content: "41504653-0000-11AA-AA11-00306543ECAC", role: .data, size: 1_000_000_000_000, leaf: true)
        ]

        let disks = StorageTopologyBuilder.build(records: records)
        #expect(disks.count == 2)
        #expect(disks.map { $0.bsdName ?? "" } == ["disk0", "disk4"])
        #expect(disks[0].containers.count == 1)
        #expect(disks[0].containers[0].volumes.map { $0.role } == [StorageVolumeRole.system, StorageVolumeRole.data])
        #expect(disks[0].containers[0].physicalStoreBSDNames == ["disk0s2"])
        #expect(disks[0].containers[0].volumes.allSatisfy { $0.capacityScope == .sharedContainer })

        let withoutExternal = StorageTopologyBuilder.build(records: records.filter { $0.registryID < 8 })
        #expect(withoutExternal.count == 1)
        #expect(withoutExternal[0].containers.count == 1)
    }

    @Test("unsupported metrics never contain fabricated values")
    func unsupportedMetricsContainNoValues() async throws {
        let snapshot = try await HardwareSampler().sample()
        #expect(snapshot.sensors.status.availability == .unsupported)
        #expect(snapshot.sensors.valuesCelsius.isEmpty)
        #expect(snapshot.fans.status.availability == .unsupported)
        #expect(snapshot.fans.fanRPM.isEmpty)
        #expect(snapshot.power.status.availability == .unsupported)
        #expect(snapshot.power.totalWatts == nil)
        #expect(snapshot.power.cpuWatts == nil)
        #expect(snapshot.power.gpuWatts == nil)
        #expect(snapshot.power.aneWatts == nil)
    }

    @Test("emits hardware snapshots and supports cancellation")
    func emitsAndCancels() async throws {
        let configuration = try HardwareSamplingConfiguration(interval: 0.1)
        let sampler = HardwareSampler(configuration: configuration)
        let stream = sampler.snapshots()
        let consumer = Task { () -> Int in
            var count = 0
            do {
                for try await _ in stream {
                    count += 1
                    if count >= 2 { break }
                }
            } catch {
                return count
            }
            return count
        }
        let count = await consumer.value
        #expect(count >= 2)
        consumer.cancel()
    }

    private func media(
        _ registryID: UInt64,
        parents: [UInt64] = [],
        className: String,
        name: String? = nil,
        bsd: String? = nil,
        uuid: String? = nil,
        content: String? = nil,
        role: StorageVolumeRole? = nil,
        volumeGroupUUID: String? = nil,
        size: UInt64? = nil,
        whole: Bool = false,
        leaf: Bool = false,
        removable: Bool? = nil
    ) -> StorageMediaRecord {
        StorageMediaRecord(
            registryID: registryID,
            parentMediaIDs: parents,
            className: className,
            registryName: name,
            fullName: name,
            bsdName: bsd,
            uuid: uuid,
            content: content,
            contentHint: nil,
            role: role,
            volumeGroupUUID: volumeGroupUUID,
            sizeBytes: size,
            isWhole: whole,
            isLeaf: leaf,
            isRemovable: removable,
            isEjectable: nil,
            isWritable: true,
            model: name,
            vendor: nil,
            revision: nil
        )
    }

    @Test("continuous samples retain stable timestamp ordering")
    func continuousSamples() async throws {
        let configuration = try HardwareSamplingConfiguration(interval: 0.1)
        let sampler = HardwareSampler(configuration: configuration)
        var iterator = sampler.snapshots().makeAsyncIterator()
        let first = try #require(try await iterator.next())
        let second = try #require(try await iterator.next())
        #expect(second.timestamp >= first.timestamp)
        #expect(second.hardware.status.availability != .unsupported)
    }
}
