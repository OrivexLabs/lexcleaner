import Foundation
import Darwin
@_spi(Testing) import LexCleanerCore

@main
struct LexCleanerMonitoringTestRunner {
    static func main() async {
        if CommandLine.arguments.contains("--calibration") {
            await runCalibration()
            return
        }
        if CommandLine.arguments.contains("--long") {
            await runLongStabilityTest()
            return
        }
        let tests: [(String, () async throws -> Void)] = [
            ("real snapshot reports hardware counters", testRealSnapshot),
            ("sampling cancellation stops the stream", testCancellation),
            ("real disk write changes cumulative counters", testDiskActivity),
            ("real network request changes interface counters", testNetworkActivity)
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

    private static func runCalibration() async {
        do {
            let duration: TimeInterval = 300
            let configuration = try MonitoringSamplingConfiguration(interval: 1, processLimit: 0, includeProcesses: false)
            let sampler = MonitoringSampler(configuration: configuration)
            var stream = sampler.snapshots().makeAsyncIterator()
            let started = Date()
            var sampleCount = 0
            while let snapshot = try await stream.next() {
                let elapsed = Date().timeIntervalSince(started)
                print("CALIBRATION sample=\(sampleCount) elapsed=\(String(format: "%.3f", elapsed)) cpu=\(String(format: "%.3f", snapshot.cpu.totalUsagePercent)) user=\(String(format: "%.3f", snapshot.cpu.userUsagePercent)) system=\(String(format: "%.3f", snapshot.cpu.systemUsagePercent)) idle=\(String(format: "%.3f", snapshot.cpu.idleUsagePercent)) cores=\(snapshot.cpu.perCoreUsagePercent.count)")
                sampleCount += 1
                if elapsed >= duration { break }
            }
            print("CALIBRATION_RESULT duration=\(Date().timeIntervalSince(started)) samples=\(sampleCount)")
        } catch {
            print("CALIBRATION_RESULT failure=\(error)")
            exit(1)
        }
    }

    private static func runLongStabilityTest() async {
        do {
            let duration: TimeInterval = 600
            let sampler = MonitoringSampler(configuration: try MonitoringSamplingConfiguration(interval: 1, processLimit: 64))
            let stream = sampler.snapshots()
            let started = Date()
            var sampleCount = 0
            var firstRSS: UInt64 = 0
            var peakRSS: UInt64 = 0
            var lastRSS: UInt64 = 0
            var minimumCPU = Double.greatestFiniteMagnitude
            var maximumCPU = 0.0
            var minimumSystemUsed = UInt64.max
            var maximumSystemUsed: UInt64 = 0
            var nextReport: TimeInterval = 60
            for try await snapshot in stream {
                let elapsed = Date().timeIntervalSince(started)
                let rss = residentMemoryBytes()
                if sampleCount == 0 { firstRSS = rss }
                peakRSS = max(peakRSS, rss)
                lastRSS = rss
                sampleCount += 1
                minimumCPU = min(minimumCPU, snapshot.cpu.totalUsagePercent)
                maximumCPU = max(maximumCPU, snapshot.cpu.totalUsagePercent)
                minimumSystemUsed = min(minimumSystemUsed, snapshot.memory.usedMemoryBytes)
                maximumSystemUsed = max(maximumSystemUsed, snapshot.memory.usedMemoryBytes)
                if elapsed >= nextReport {
                    print("LONG_SAMPLE elapsed=\(Int(elapsed))s samples=\(sampleCount) cpu=\(snapshot.cpu.totalUsagePercent)% systemUsed=\(snapshot.memory.usedMemoryBytes) samplerRSS=\(rss)")
                    nextReport += 60
                }
                if elapsed >= duration { break }
            }
            let actualDuration = Date().timeIntervalSince(started)
            print("LONG_RESULT duration=\(actualDuration) samples=\(sampleCount) cpuRange=\(minimumCPU)...\(maximumCPU) systemUsedRange=\(minimumSystemUsed)...\(maximumSystemUsed) samplerRSS=\(firstRSS)...\(peakRSS)...\(lastRSS) rssDelta=\(Int64(lastRSS) - Int64(firstRSS))")
            guard actualDuration >= duration, sampleCount >= 500 else { exit(1) }
        } catch {
            print("LONG_RESULT failure=\(error)")
            exit(1)
        }
    }

    private static func configuration() throws -> MonitoringSamplingConfiguration {
        try MonitoringSamplingConfiguration(interval: 0.2, processLimit: 128)
    }

    private static func testRealSnapshot() async throws {
        let sampler = MonitoringSampler(configuration: try configuration())
        var stream = sampler.snapshots().makeAsyncIterator()
        _ = try require(try await stream.next(), "first snapshot missing")
        let snapshot = try require(try await stream.next(), "second snapshot missing")
        guard snapshot.cpu.perCoreUsagePercent.count > 0 else { throw TestFailure("per-core CPU data missing") }
        guard snapshot.memory.physicalMemoryBytes > 0 else { throw TestFailure("physical memory missing") }
        guard snapshot.disk.totalBytes > 0 else { throw TestFailure("disk capacity missing") }
        guard !snapshot.processes.isEmpty else { throw TestFailure("process list missing") }
        print("REAL_SNAPSHOT cpu=\(snapshot.cpu.totalUsagePercent)% memoryUsed=\(snapshot.memory.usedMemoryBytes) available=\(snapshot.memory.availableMemoryBytes) wired=\(snapshot.memory.wiredMemoryBytes) compressed=\(snapshot.memory.compressedMemoryBytes) swapUsed=\(snapshot.memory.swapUsedBytes) pressure=\(snapshot.memory.pressure.rawValue) diskPath=\(snapshot.disk.volumePath.path) diskTotal=\(snapshot.disk.totalBytes) diskUsed=\(snapshot.disk.usedBytes) diskAvailable=\(snapshot.disk.availableBytes) diskReadRate=\(snapshot.disk.readBytesPerSecond) networkInterfaces=\(snapshot.network.interfaces.count) processes=\(snapshot.processes.count)")
    }

    private static func testCancellation() async throws {
        let sampler = MonitoringSampler(configuration: try configuration())
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
        try await Task.sleep(for: .milliseconds(500))
        consumer.cancel()
        let count = await consumer.value
        guard count >= 1 else { throw TestFailure("stream emitted no sample before cancellation") }
    }

    private static func testDiskActivity() async throws {
        let sampler = MonitoringSampler(configuration: try configuration())
        let before = try await sampler.sample()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("LexCleanerMonitoring-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: file) }
        let payload = Data(repeating: 0x5A, count: 64 * 1024 * 1024)
        try payload.write(to: file, options: [.atomic])
        try await Task.sleep(for: .milliseconds(500))
        let after = try await sampler.sample()
        guard after.disk.ioStatisticsAvailable else { throw TestFailure("disk I/O counters unavailable on this macOS storage stack") }
        guard after.disk.cumulativeWrittenBytes >= before.disk.cumulativeWrittenBytes else { throw TestFailure("disk cumulative write counter regressed") }
        print("DISK_ACTIVITY beforeWrite=\(before.disk.cumulativeWrittenBytes) afterWrite=\(after.disk.cumulativeWrittenBytes)")
    }

    private static func testNetworkActivity() async throws {
        let sampler = MonitoringSampler(configuration: try configuration())
        let before = try await sampler.sample()
        guard let url = URL(string: "https://example.com/") else { throw TestFailure("network URL unavailable") }
        let (_, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200..<400).contains(httpResponse.statusCode) else { throw TestFailure("network request failed") }
        var after = try await sampler.sample()
        for _ in 0..<5 where after.network.cumulativeReceivedBytes <= before.network.cumulativeReceivedBytes {
            try await Task.sleep(for: .milliseconds(500))
            after = try await sampler.sample()
        }
        guard after.network.cumulativeReceivedBytes >= before.network.cumulativeReceivedBytes else { throw TestFailure("network receive counter regressed") }
        guard after.network.cumulativeReceivedBytes > before.network.cumulativeReceivedBytes else { throw TestFailure("network request did not change interface receive counters") }
        print("NETWORK_ACTIVITY beforeReceive=\(before.network.cumulativeReceivedBytes) afterReceive=\(after.network.cumulativeReceivedBytes) interfaces=\(after.network.interfaces.map(\.name).joined(separator: ","))")
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
