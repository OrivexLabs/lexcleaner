import Foundation
import Darwin
import LexCleanerCore

@main
struct LexCleanerHardwareTestRunner {
    static func main() async {
        if CommandLine.arguments.contains("--long") {
            await runLongStabilityTest()
            return
        }
        let tests: [(String, () async throws -> Void)] = [
            ("real M4 hardware snapshot", testRealSnapshot),
            ("unsupported metrics do not fabricate values", testUnsupportedMetrics),
            ("hardware stream cancellation", testCancellation),
            ("hardware samples remain valid", testRepeatedSamples)
        ]
        var passed = 0
        for (name, test) in tests {
            do {
                try await test()
                print("PASS  \(name)")
                passed += 1
            } catch {
                print("FAIL  \(name): \(error)")
            }
        }
        print("RESULT  \(passed)/\(tests.count) passed")
        if passed != tests.count { exit(1) }
    }

    private static func testRealSnapshot() async throws {
        let sampler = HardwareSampler()
        let snapshot = try await sampler.sample()
        guard snapshot.hardware.status.availability == .available else { throw TestFailure("hardware information unavailable") }
        guard snapshot.hardware.modelIdentifier?.isEmpty == false else { throw TestFailure("model identifier missing") }
        guard snapshot.hardware.physicalMemoryBytes ?? 0 > 0 else { throw TestFailure("physical memory missing") }
        guard snapshot.thermal.state != nil else { throw TestFailure("thermal state missing") }
        guard snapshot.storage.status.availability == .available, !snapshot.storage.physicalDisks.isEmpty else { throw TestFailure("storage metadata missing") }
        print("REAL_HARDWARE model=\(snapshot.hardware.modelIdentifier ?? "unknown") arm64=\(snapshot.hardware.isAppleSilicon ?? false) physicalCores=\(snapshot.hardware.physicalCoreCount ?? 0) logicalCores=\(snapshot.hardware.logicalCoreCount ?? 0) pCores=\(snapshot.hardware.performanceCoreCount ?? 0) eCores=\(snapshot.hardware.efficiencyCoreCount ?? 0) thermal=\(snapshot.thermal.state?.rawValue ?? "unavailable") battery=\(snapshot.battery.status.availability.rawValue) physicalDisks=\(snapshot.storage.physicalDisks.count) containers=\(snapshot.storage.physicalDisks.flatMap(\.containers).count) volumes=\(snapshot.storage.physicalDisks.flatMap(\.containers).flatMap(\.volumes).count) smart=\(snapshot.storage.smartStatus.availability.rawValue) wear=\(snapshot.storage.wearStatus.availability.rawValue) sensors=\(snapshot.sensors.status.availability.rawValue) fans=\(snapshot.fans.status.availability.rawValue) power=\(snapshot.power.status.availability.rawValue)")
        for disk in snapshot.storage.physicalDisks {
            let containers = disk.containers.map { container in
                let roles = container.volumes.map { "\($0.displayName):\($0.role.rawValue)" }.joined(separator: ",")
                return "\(container.displayName)=\(container.capacityBytes ?? 0)B[\(roles)]"
            }.joined(separator: "|")
            print("STORAGE_TOPOLOGY disk=\(disk.displayName) kind=\(disk.kind.rawValue) capacity=\(disk.capacityBytes ?? 0) containers=\(containers)")
        }
    }

    private static func testUnsupportedMetrics() async throws {
        let snapshot = try await HardwareSampler().sample()
        guard snapshot.sensors.status.availability == .unsupported, snapshot.sensors.valuesCelsius.isEmpty else { throw TestFailure("sensor data was fabricated") }
        guard snapshot.fans.status.availability == .unsupported, snapshot.fans.fanRPM.isEmpty else { throw TestFailure("fan data was fabricated") }
        guard snapshot.power.status.availability == .unsupported, snapshot.power.totalWatts == nil else { throw TestFailure("power data was fabricated") }
    }

    private static func testCancellation() async throws {
        let sampler = HardwareSampler(configuration: try HardwareSamplingConfiguration(interval: 0.1))
        let stream = sampler.snapshots()
        let consumer = Task { () -> Int in
            var count = 0
            do {
                for try await _ in stream {
                    count += 1
                    if Task.isCancelled { break }
                }
            } catch {
                return count
            }
            return count
        }
        try await Task.sleep(for: .milliseconds(250))
        consumer.cancel()
        guard await consumer.value >= 1 else { throw TestFailure("no sample before cancellation") }
    }

    private static func testRepeatedSamples() async throws {
        let sampler = HardwareSampler(configuration: try HardwareSamplingConfiguration(interval: 0.1))
        var iterator = sampler.snapshots().makeAsyncIterator()
        var previous: HardwareSnapshot?
        for _ in 0..<4 {
            let snapshot = try require(try await iterator.next(), "missing repeated sample")
            if let previous, snapshot.timestamp < previous.timestamp { throw TestFailure("timestamp regressed") }
            guard snapshot.hardware.physicalMemoryBytes ?? 0 > 0 else { throw TestFailure("hardware sample lost physical memory") }
            previous = snapshot
        }
    }

    private static func runLongStabilityTest() async {
        do {
            let duration: TimeInterval = 600
            let sampler = HardwareSampler(configuration: try HardwareSamplingConfiguration(interval: 1))
            let started = Date()
            var sampleCount = 0
            var firstRSS: UInt64 = 0
            var peakRSS: UInt64 = 0
            var lastRSS: UInt64 = 0
            let firstCPU = processCPUSeconds()
            var firstTimestamp: Date?
            var lastTimestamp: Date?
            var thermalStates: Set<String> = []
            var batteryAvailability: Set<String> = []
            var storageDeviceCounts: Set<Int> = []
            for try await snapshot in sampler.snapshots() {
                let rss = residentMemoryBytes()
                if sampleCount == 0 { firstRSS = rss; firstTimestamp = snapshot.timestamp }
                peakRSS = max(peakRSS, rss)
                lastRSS = rss
                lastTimestamp = snapshot.timestamp
                thermalStates.insert(snapshot.thermal.state?.rawValue ?? "unavailable")
                batteryAvailability.insert(snapshot.battery.status.availability.rawValue)
                storageDeviceCounts.insert(snapshot.storage.physicalDisks.count)
                sampleCount += 1
                if sampleCount % 60 == 0 {
                    print("LONG_SAMPLE elapsed=\(Int(Date().timeIntervalSince(started)))s samples=\(sampleCount) thermal=\(snapshot.thermal.state?.rawValue ?? "unavailable") battery=\(snapshot.battery.status.availability.rawValue) physicalDisks=\(snapshot.storage.physicalDisks.count) rss=\(rss)")
                }
                if Date().timeIntervalSince(started) >= duration { break }
            }
            let actualDuration = Date().timeIntervalSince(started)
            let timestampSpan = (lastTimestamp ?? Date()).timeIntervalSince(firstTimestamp ?? Date())
            let cpuSeconds = max(0, processCPUSeconds() - firstCPU)
            let cpuPercent = actualDuration > 0 ? cpuSeconds / actualDuration * 100 : 0
            print("LONG_RESULT duration=\(actualDuration) samples=\(sampleCount) timestampSpan=\(timestampSpan) thermalStates=\(thermalStates.sorted().joined(separator: ",")) batteryAvailability=\(batteryAvailability.sorted().joined(separator: ",")) storageDeviceCounts=\(storageDeviceCounts.sorted().map(String.init).joined(separator: ",")) samplerRSS=\(firstRSS)...\(peakRSS)...\(lastRSS) rssDelta=\(Int64(lastRSS) - Int64(firstRSS)) cpuSeconds=\(cpuSeconds) cpuPercent=\(cpuPercent)")
            guard actualDuration >= duration, sampleCount >= 500, timestampSpan >= 590, cpuSeconds.isFinite else { exit(1) }
        } catch {
            print("LONG_RESULT failure=\(error)")
            exit(1)
        }
    }

    private static func residentMemoryBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }

    private static func processCPUSeconds() -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
        return user + system
    }

    private static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw TestFailure(message) }
        return value
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}
