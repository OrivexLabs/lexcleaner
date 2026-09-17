import Foundation
import Darwin
import Testing
@testable import LexCleanerCore

@Suite("DiskAnalysisEngine")
struct DiskAnalysisTests {
    @Test("builds aggregate tree and bounded large-file projection")
    func buildsAggregateTreeAndLargeFiles() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let nested = fixture.directory.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let oldDate = Date(timeIntervalSinceNow: -3_600)
        let first = fixture.directory.appendingPathComponent("first.bin")
        let second = nested.appendingPathComponent("second.bin")
        let recent = nested.appendingPathComponent("recent.bin")
        try Data(repeating: 1, count: 16).write(to: first)
        try Data(repeating: 2, count: 12).write(to: second)
        try Data(repeating: 3, count: 64).write(to: recent)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: first.path)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: second.path)

        let updates = UpdateCollector()
        let configuration = DiskAnalysisConfiguration(
            allowedRoots: [fixture.directory],
            maxConcurrentDirectories: 2,
            largeFiles: LargeFileOptions(
                thresholdBytes: 8,
                topN: 2,
                minimumAge: 1_000,
                pathPrefix: fixture.directory
            ),
            memorySampleStride: 1
        )
        let snapshot = await DiskAnalysisEngine(maxConcurrentDirectories: 2).analyze(
            targets: [DiskAnalysisTarget(url: fixture.directory)],
            configuration: configuration
        ) { update in
            await updates.append(update)
        }

        #expect(!snapshot.cancelled)
        #expect(snapshot.fileCount == 3)
        #expect(snapshot.directoryCount == 2)
        #expect(snapshot.tree.nodes.count == 2)
        #expect(snapshot.tree.retainedFileNodeCount == 2)
        #expect(snapshot.largeFiles.map(\.path).contains(first))
        #expect(snapshot.largeFiles.map(\.path).contains(second))
        #expect(!snapshot.largeFiles.map(\.path).contains(recent))
        #expect(snapshot.treemapNodes.filter(\.isLargeFile).count == 2)
        #expect(!snapshot.treemapNodes.contains { $0.isOther && $0.path == nested })
        #expect(snapshot.contentStatistics[.other]?.fileCount == 3)
        #expect(snapshot.contentStatistics[.other]?.totalBytes == 92)
        #expect(await updates.kinds().contains(.directoryCompleted))
        #expect(await updates.kinds().contains(.completed))
        #expect(snapshot.performance.maxObservedConcurrentDirectories <= 2)
        #expect(snapshot.performance.maxDirectoryEntriesBuffered < 10)
        #expect(snapshot.performance.maxDirectoryEntriesBuffered > 0)
        #expect(snapshot.performance.maxDirectoryEntriesBuffered <= 4096)
    }

    @Test("records file type statistics without changing cleanup semantics")
    func contentStatistics() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try Data(repeating: 1, count: 5).write(to: fixture.directory.appendingPathComponent("photo.png"))
        try Data(repeating: 2, count: 7).write(to: fixture.directory.appendingPathComponent("archive.zip"))
        try Data(repeating: 3, count: 11).write(to: fixture.directory.appendingPathComponent("source.swift"))

        let snapshot = await DiskAnalysisEngine().analyze(
            targets: [DiskAnalysisTarget(url: fixture.directory)],
            configuration: DiskAnalysisConfiguration(allowedRoots: [fixture.directory])
        )

        #expect(snapshot.contentStatistics[.images]?.fileCount == 1)
        #expect(snapshot.contentStatistics[.images]?.totalBytes == 5)
        #expect(snapshot.contentStatistics[.archives]?.fileCount == 1)
        #expect(snapshot.contentStatistics[.archives]?.totalBytes == 7)
        #expect(snapshot.contentStatistics[.development]?.fileCount == 1)
        #expect(snapshot.contentStatistics[.development]?.totalBytes == 11)
    }

    @Test("deduplicates logical and allocated bytes for hard links")
    func hardLinkAccounting() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let first = fixture.directory.appendingPathComponent("first.bin")
        let second = fixture.directory.appendingPathComponent("second.bin")
        try Data(repeating: 7, count: 128).write(to: first)
        try FileManager.default.linkItem(at: first, to: second)

        let snapshot = await DiskAnalysisEngine().analyze(
            targets: [DiskAnalysisTarget(url: fixture.directory)],
            configuration: DiskAnalysisConfiguration(allowedRoots: [fixture.directory])
        )

        #expect(snapshot.fileCount == 2)
        #expect(snapshot.totalBytes == 128)
        #expect(snapshot.allocatedBytes > 0)
    }

    @Test("keeps sparse logical size separate from allocated size and bounds it to the volume")
    func sparseFileAccounting() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let sparse = fixture.directory.appendingPathComponent("sparse.bin")
        let descriptor = open(sparse.path, O_CREAT | O_RDWR, 0o600)
        #expect(descriptor >= 0)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        #expect(ftruncate(descriptor, 64 * 1024 * 1024) == 0)

        let snapshot = await DiskAnalysisEngine().analyze(
            targets: [DiskAnalysisTarget(url: fixture.directory)],
            configuration: DiskAnalysisConfiguration(allowedRoots: [fixture.directory])
        )

        #expect(snapshot.totalBytes >= 64 * 1024 * 1024)
        #expect(snapshot.allocatedBytes <= (snapshot.volumeCapacityBytes ?? UInt64.max))
        #expect(snapshot.allocatedBytes < snapshot.totalBytes)
        #expect(snapshot.treemapNodes.first?.allocatedSizeBytes ?? UInt64.max < snapshot.treemapNodes.first?.sizeBytes ?? 0)
    }

    @Test("treats symlink loops and escapes as leaves")
    func symlinkSafety() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let outside = fixture.directory.deletingLastPathComponent().appendingPathComponent("LexCleanerDiskOutside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: fixture.directory.appendingPathComponent("loop"), withDestinationURL: fixture.directory)
        try FileManager.default.createSymbolicLink(at: fixture.directory.appendingPathComponent("escape"), withDestinationURL: outside)

        let snapshot = await DiskAnalysisEngine().analyze(
            targets: [DiskAnalysisTarget(url: fixture.directory)],
            configuration: DiskAnalysisConfiguration(allowedRoots: [fixture.directory])
        )

        #expect(!snapshot.cancelled)
        #expect(snapshot.issues.contains { $0.kind == .symlinkSkipped })
        #expect(snapshot.issues.contains { $0.kind == .symlinkEscape })
        #expect(snapshot.directoryCount == 1)
    }

    @Test("watchdog skips a blocked directory and continues later work")
    func watchdogTimeoutSkipsBlockedDirectory() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let first = fixture.directory.appendingPathComponent("first", isDirectory: true)
        let second = fixture.directory.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try Data(repeating: 9, count: 32).write(to: first.appendingPathComponent("first.bin"))
        try Data(repeating: 7, count: 32).write(to: second.appendingPathComponent("second.bin"))
        let counter = DirectoryOpenInvocationCounter()

        let opener: DiskDirectoryOpenHandler = { path in
            if counter.next() == 2 {
                usleep(300_000)
                return DiskDirectoryOpenAttempt(fileDescriptor: -1, errorNumber: ETIMEDOUT)
            }
            let descriptor = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            return DiskDirectoryOpenAttempt(
                fileDescriptor: descriptor,
                errorNumber: descriptor >= 0 ? 0 : errno
            )
        }
        let configuration = DiskAnalysisConfiguration(
            allowedRoots: [fixture.directory],
            maxConcurrentDirectories: 1,
            memorySampleStride: 1,
            collectPerformanceBreakdown: true
        )
        let snapshot = await DiskAnalysisEngine(
            maxConcurrentDirectories: 1,
            directoryOpenHandler: opener
        ).analyze(
            targets: [DiskAnalysisTarget(url: fixture.directory)],
            configuration: configuration
        )

        #expect(!snapshot.cancelled)
        #expect(snapshot.fileCount == 1)
        #expect(snapshot.issues.contains {
            $0.kind == .enumerationFailed
                && $0.detail.contains("watchdog timeout")
        })
        #expect(snapshot.performance.breakdown?.watchdogTimeouts == 1)
    }

    @Test("cancellation remains bounded while a directory open is blocked")
    func cancellationDuringBlockedDirectoryOpen() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let opener: DiskDirectoryOpenHandler = { path in
            usleep(300_000)
            return DiskDirectoryOpenAttempt(fileDescriptor: -1, errorNumber: ETIMEDOUT)
        }
        let task = Task {
            await DiskAnalysisEngine(
                maxConcurrentDirectories: 1,
                directoryOpenHandler: opener
            ).analyze(
                targets: [DiskAnalysisTarget(url: fixture.directory)],
                configuration: DiskAnalysisConfiguration(
                    allowedRoots: [fixture.directory],
                    maxConcurrentDirectories: 1,
                    collectPerformanceBreakdown: true
                )
            )
        }
        try await Task.sleep(for: .milliseconds(20))
        task.cancel()
        let snapshot = await task.value

        #expect(snapshot.cancelled)
        #expect((snapshot.performance.cancellationLatency ?? .infinity) < 1.0)
    }

    @Test("cancellation produces a partial snapshot and bounded latency")
    func cancellation() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        for index in 0..<4_000 {
            try Data(repeating: UInt8(index % 255), count: 8).write(to: fixture.directory.appendingPathComponent("file-\(index).dat"))
        }

        let controller = CancellationController()
        let task = Task {
            await DiskAnalysisEngine(maxConcurrentDirectories: 2).analyze(
                targets: [DiskAnalysisTarget(url: fixture.directory)],
                configuration: DiskAnalysisConfiguration(allowedRoots: [fixture.directory], memorySampleStride: 1)
            ) { _ in
                await controller.requestCancellation()
                await Task.yield()
            }
        }
        await controller.set(task)
        let snapshot = await task.value
        #expect(snapshot.cancelled)
        #expect(snapshot.fileCount < 4_000)
        #expect(snapshot.issues.contains { $0.kind == .cancelled })
        #expect((snapshot.performance.cancellationLatency ?? .infinity) < 1.0)
    }

    private struct Fixture { let directory: URL }

    private func makeFixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LexCleanerDiskAnalysisXCTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return Fixture(directory: directory)
    }
}

private actor UpdateCollector {
    private var stored: [DiskAnalysisUpdateKind] = []
    func append(_ update: DiskAnalysisUpdate) { stored.append(update.kind) }
    func kinds() -> [DiskAnalysisUpdateKind] { stored }
}

private actor CancellationController {
    private var requested = false
    private var task: Task<DiskAnalysisSnapshot, Never>?

    func set(_ task: Task<DiskAnalysisSnapshot, Never>) {
        self.task = task
        if requested { task.cancel() }
    }

    func requestCancellation() {
        requested = true
        task?.cancel()
    }
}

private final class DirectoryOpenInvocationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}
