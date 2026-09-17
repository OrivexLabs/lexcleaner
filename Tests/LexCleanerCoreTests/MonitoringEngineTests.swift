import Foundation
import Darwin
import Testing
@testable import LexCleanerCore

@Suite("MonitoringFoundation")
struct MonitoringEngineTests {
    @Test("rejects an unsafe sampling interval")
    func rejectsUnsafeSamplingInterval() {
        #expect(throws: MonitoringError.invalidSamplingInterval) {
            _ = try MonitoringSamplingConfiguration(interval: 0.01)
        }
    }

    @Test("can disable process collection for a low overhead consumer")
    func disablesProcessCollection() async throws {
        let configuration = try MonitoringSamplingConfiguration(interval: 0.1, processLimit: 0, includeProcesses: false)
        let snapshot = try await MonitoringSampler(configuration: configuration).sample()
        #expect(snapshot.processes.isEmpty)
        #expect(snapshot.cpu.perCoreUsagePercent.isEmpty == false)
    }

    @Test("reports real CPU counters and per-core values")
    func reportsCPU() async throws {
        let configuration = try MonitoringSamplingConfiguration(interval: 0.1, processLimit: 32)
        let sampler = MonitoringSampler(configuration: configuration)
        var stream = sampler.snapshots().makeAsyncIterator()
        _ = try await stream.next()
        let snapshot = try #require(try await stream.next())
        #expect(!snapshot.cpu.perCoreUsagePercent.isEmpty)
        #expect(snapshot.cpu.totalUsagePercent >= 0 && snapshot.cpu.totalUsagePercent <= 100)
        #expect(snapshot.cpu.userUsagePercent >= 0 && snapshot.cpu.userUsagePercent <= 100)
        #expect(snapshot.cpu.systemUsagePercent >= 0 && snapshot.cpu.systemUsagePercent <= 100)
        #expect(snapshot.cpu.idleUsagePercent >= 0 && snapshot.cpu.idleUsagePercent <= 100)
        #expect(abs(snapshot.cpu.userUsagePercent + snapshot.cpu.systemUsagePercent + snapshot.cpu.idleUsagePercent - 100) < 0.01)
        #expect(snapshot.cpu.perCoreUsagePercent.allSatisfy { $0 >= 0 && $0 <= 100 })
    }

    @Test("reports real memory counters")
    func reportsMemory() async throws {
        let sampler = MonitoringSampler()
        let snapshot = try await sampler.sample()
        #expect(snapshot.memory.physicalMemoryBytes > 0)
        #expect(snapshot.memory.usedMemoryBytes <= snapshot.memory.physicalMemoryBytes)
        #expect(snapshot.memory.availableMemoryBytes <= snapshot.memory.physicalMemoryBytes)
        #expect(snapshot.memory.wiredMemoryBytes > 0)
        #expect(snapshot.memory.pressureSource == .derivedFromPublicVMStatistics)
    }

    @Test("reports real startup volume capacity")
    func reportsDisk() async throws {
        let sampler = MonitoringSampler()
        let snapshot = try await sampler.sample()
        #expect(snapshot.disk.volumePath.path == "/")
        #expect(snapshot.disk.totalBytes > 0)
        #expect(snapshot.disk.availableBytes <= snapshot.disk.totalBytes)
        #expect(snapshot.disk.usedBytes + snapshot.disk.availableBytes <= snapshot.disk.totalBytes)
    }

    @Test("reports real network interfaces")
    func reportsNetwork() async throws {
        let sampler = MonitoringSampler()
        let snapshot = try await sampler.sample()
        #expect(snapshot.network.cumulativeReceivedBytes >= 0)
        #expect(snapshot.network.cumulativeSentBytes >= 0)
        #expect(snapshot.network.interfaces.allSatisfy { !$0.name.isEmpty })
    }

    @Test("reports the current process in the read-only process list")
    func reportsCurrentProcess() async throws {
        let configuration = try MonitoringSamplingConfiguration(interval: 0.1, processLimit: 512)
        let sampler = MonitoringSampler(configuration: configuration)
        var stream = sampler.snapshots().makeAsyncIterator()
        _ = try await stream.next()
        let snapshot = try #require(try await stream.next())
        #expect(snapshot.processes.contains { $0.pid == getpid() })
        #expect(snapshot.processes.allSatisfy { $0.cpuUsagePercent >= 0 && $0.residentMemoryBytes > 0 })
    }

    @Test("emits snapshots at a configurable interval")
    func emitsSnapshots() async throws {
        let configuration = try MonitoringSamplingConfiguration(interval: 0.1, processLimit: 16)
        let sampler = MonitoringSampler(configuration: configuration)
        var stream = sampler.snapshots().makeAsyncIterator()
        let first = try #require(try await stream.next())
        let second = try #require(try await stream.next())
        #expect(second.timestamp >= first.timestamp)
    }

    @Test("consumer cancellation stops a monitoring stream")
    func cancellationStopsStream() async throws {
        let configuration = try MonitoringSamplingConfiguration(interval: 0.1, processLimit: 16)
        let sampler = MonitoringSampler(configuration: configuration)
        let stream = sampler.snapshots()
        let firstSample = SampleGate()
        let consumer = Task { () -> Int in
            var count = 0
            do {
                for try await _ in stream {
                    count += 1
                    await firstSample.mark()
                    if Task.isCancelled { break }
                }
            } catch {
                return count
            }
            return count
        }
        await firstSample.wait()
        consumer.cancel()
        let count = await consumer.value
        #expect(count >= 1)
    }
}

private actor SampleGate {
    private var didReceiveSample = false

    func mark() { didReceiveSample = true }

    func wait() async {
        while !didReceiveSample {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}
