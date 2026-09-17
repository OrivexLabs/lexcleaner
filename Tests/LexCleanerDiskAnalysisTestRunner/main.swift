import Foundation
import Darwin
import LexCleanerCore

@main
struct LexCleanerDiskAnalysisTestRunner {
    static func main() async {
        do {
            try await run()
            if !CommandLine.arguments.contains("--benchmark-child") {
                print("DiskAnalysis real validation: PASS")
            }
        } catch {
            fputs("DiskAnalysis real validation: FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func run() async throws {
        if CommandLine.arguments.contains("--harness") {
            try await runBenchmarkHarness()
            return
        }
        if CommandLine.arguments.contains("--strict-30") {
            try await runStrictThirtyBenchmark()
            return
        }
        if CommandLine.arguments.contains("--benchmark-child") {
            try await runBenchmarkChild()
            return
        }
        if CommandLine.arguments.contains("--quality") {
            try await runQualityAcceptance()
            return
        }
        if CommandLine.arguments.contains("--home") {
            try await benchmarkHome(concurrency: requestedConcurrency(defaultValue: 3))
            return
        }
        if CommandLine.arguments.contains("--cache") {
            try await benchmarkMoleComparableCacheScope(concurrency: requestedConcurrency(defaultValue: 3))
            return
        }
        if CommandLine.arguments.contains("--cache-ttr") {
            try await benchmarkCacheTwoStage(concurrency: requestedConcurrency(defaultValue: 3))
            return
        }
        if let path = argumentValue(prefix: "--path=") {
            try await benchmarkPathScope(URL(fileURLWithPath: path), concurrency: requestedConcurrency(defaultValue: 4))
            return
        }
        let fixture = try makeFixture("LexCleanerDiskAnalysisRunner")
        defer { try? FileManager.default.removeItem(at: fixture) }
        let outside = fixture.deletingLastPathComponent().appendingPathComponent("LexCleanerDiskAnalysisOutside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }

        let fileCount = 50_000
        for bucketIndex in 0..<8 {
            try FileManager.default.createDirectory(
                at: fixture.appendingPathComponent("bucket-\(bucketIndex)", isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        for index in 0..<fileCount {
            let bucket = fixture.appendingPathComponent("bucket-\(index % 8)", isDirectory: true)
            try Data(repeating: UInt8(index % 251), count: index == 42 ? 2_000_000 : 32)
                .write(to: bucket.appendingPathComponent("file-\(index).dat"))
        }
        try FileManager.default.createSymbolicLink(at: fixture.appendingPathComponent("loop"), withDestinationURL: fixture)
        try FileManager.default.createSymbolicLink(at: fixture.appendingPathComponent("escape"), withDestinationURL: outside)
        let denied = fixture.appendingPathComponent("permission-denied", isDirectory: true)
        try FileManager.default.createDirectory(at: denied, withIntermediateDirectories: true)
        try Data("private".utf8).write(to: denied.appendingPathComponent("hidden.dat"))
        guard chmod(denied.path, 0) == 0 else { throw RunnerError("Could not make permission fixture inaccessible.") }
        defer { _ = chmod(denied.path, 0o700) }

        let configuration = DiskAnalysisConfiguration(
            allowedRoots: [fixture],
            maxConcurrentDirectories: 3,
            largeFiles: LargeFileOptions(thresholdBytes: 1_000_000, topN: 10),
            memorySampleStride: 1_024
        )
        let updates = UpdateCounter()
        let started = Date()
        let snapshot = await DiskAnalysisEngine(maxConcurrentDirectories: 3).analyze(
            targets: [DiskAnalysisTarget(url: fixture), DiskAnalysisTarget(url: fixture)],
            configuration: configuration
        ) { update in
            await updates.record(update)
        }
        let wallDuration = Date().timeIntervalSince(started)
        guard snapshot.fileCount >= UInt64(fileCount) else { throw RunnerError("Expected at least \(fileCount) files, got \(snapshot.fileCount).") }
        guard snapshot.tree.retainedFileNodeCount <= 10 else { throw RunnerError("Large-file result exceeded Top N.") }
        guard snapshot.tree.nodes.count < fileCount else { throw RunnerError("DiskTree retained a full file tree.") }
        guard snapshot.performance.maxObservedConcurrentDirectories <= 3 else { throw RunnerError("Concurrency limit exceeded.") }
        guard snapshot.issues.contains(where: { $0.kind == .canonicalDuplicate }) else { throw RunnerError("Canonical duplicate was not recorded.") }
        guard snapshot.issues.contains(where: { $0.kind == .symlinkSkipped }) else { throw RunnerError("Symlink loop was not recorded.") }
        guard snapshot.issues.contains(where: { $0.kind == .symlinkEscape }) else { throw RunnerError("Symlink escape was not recorded.") }
        let permissionRecorded = snapshot.issues.contains(where: { $0.kind == .permissionDenied })
        print("50k fixture: files=\(snapshot.fileCount) directories=\(snapshot.directoryCount) bytes=\(snapshot.totalBytes)")
        print("metrics: wall=\(format(wallDuration)) duration=\(format(snapshot.performance.duration)) cpu=\(format(snapshot.performance.cpuTimeSeconds))s avgCPU=\(format(snapshot.performance.averageCPUPercent))% peakRSS=\(snapshot.performance.peakResidentMemoryBytes) throughput=\(format(snapshot.performance.throughputFilesPerSecond))/s maxConcurrency=\(snapshot.performance.maxObservedConcurrentDirectories) maxBuffered=\(snapshot.performance.maxDirectoryEntriesBuffered) treeNodes=\(snapshot.tree.nodes.count) updates=\(await updates.count())")
        print("issues: permissionDenied=\(permissionRecorded) symlinkLoop=\(snapshot.issues.contains { $0.kind == .symlinkSkipped }) symlinkEscape=\(snapshot.issues.contains { $0.kind == .symlinkEscape }) canonicalDuplicate=\(snapshot.issues.contains { $0.kind == .canonicalDuplicate })")
        if getuid() != 0 && !permissionRecorded { throw RunnerError("Expected a permissionDenied issue for a mode-000 directory.") }

        try await validateCancellation(fileCount: 10_000)
        try await validateHomeAllowedArea()
        try await benchmarkMoleComparableCacheScope()
    }

    private static func validateCancellation(fileCount: Int) async throws {
        let fixture = try makeFixture("LexCleanerDiskAnalysisCancel")
        defer { try? FileManager.default.removeItem(at: fixture) }
        for index in 0..<fileCount {
            try Data(repeating: 7, count: 16).write(to: fixture.appendingPathComponent("file-\(index)"))
        }
        let controller = CancellationController()
        let task = Task {
            await DiskAnalysisEngine(maxConcurrentDirectories: 2).analyze(
                targets: [DiskAnalysisTarget(url: fixture)],
                configuration: DiskAnalysisConfiguration(allowedRoots: [fixture], memorySampleStride: 1)
            ) { _ in
                await controller.requestCancellation()
                await Task.yield()
            }
        }
        await controller.set(task)
        let snapshot = await task.value
        guard snapshot.cancelled, snapshot.fileCount < UInt64(fileCount) else { throw RunnerError("Cancellation did not stop partial work.") }
        print("cancellation: filesBeforeStop=\(snapshot.fileCount)/\(fileCount) latency=\(format(snapshot.performance.cancellationLatency ?? -1))s")
    }

    private static func validateHomeAllowedArea() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let allowed = home.appendingPathComponent("Library/Caches", isDirectory: true)
        guard FileManager.default.fileExists(atPath: allowed.path) else {
            print("home allowed area: SKIPPED (\(allowed.path) does not exist)")
            return
        }
        let snapshot = await DiskAnalysisEngine(maxConcurrentDirectories: 2).analyze(
            targets: [DiskAnalysisTarget(url: allowed)],
            configuration: DiskAnalysisConfiguration(
                allowedRoots: [allowed],
                maxConcurrentDirectories: 3,
                largeFiles: LargeFileOptions(thresholdBytes: UInt64.max, topN: 0),
                memorySampleStride: 512
            )
        )
        guard !snapshot.issues.contains(where: { $0.kind == .protectedPath && $0.path == allowed }) else {
            throw RunnerError("Home allowed area was rejected.")
        }
        print("home allowed area: path=\(allowed.path) files=\(snapshot.fileCount) directories=\(snapshot.directoryCount) issues=\(snapshot.issues.count)")
    }

    private static func benchmarkMoleComparableCacheScope(concurrency: Int = 3) async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let allowed = home.appendingPathComponent("Library/Caches", isDirectory: true)
        guard FileManager.default.fileExists(atPath: allowed.path) else { return }
        let started = Date()
        let boundedConcurrency = max(1, min(concurrency, 6))
        let snapshot = await DiskAnalysisEngine(maxConcurrentDirectories: boundedConcurrency).analyze(
            targets: [DiskAnalysisTarget(url: allowed)],
            configuration: DiskAnalysisConfiguration(
                allowedRoots: [allowed],
                maxConcurrentDirectories: boundedConcurrency,
                largeFiles: LargeFileOptions(thresholdBytes: 50 * 1024 * 1024, topN: 100),
                memorySampleStride: 512,
                initialDirectoryIdentityCapacity: 1 << 14,
                collectPerformanceBreakdown: CommandLine.arguments.contains("--breakdown")
            )
        )
        let wall = Date().timeIntervalSince(started)
        print("mole comparable cache scope: concurrency=\(boundedConcurrency) wall=\(format(wall)) duration=\(format(snapshot.performance.duration)) cpu=\(format(snapshot.performance.cpuTimeSeconds))s peakRSS=\(snapshot.performance.peakResidentMemoryBytes) files=\(snapshot.fileCount) directories=\(snapshot.directoryCount) logicalBytes=\(snapshot.totalBytes) allocatedBytes=\(snapshot.allocatedBytes) volumeCapacity=\(snapshot.volumeCapacityBytes ?? 0) allocationStatus=\(snapshot.allocationStatus.rawValue) largeFiles=\(snapshot.largeFiles.count) issues=\(snapshot.issues.count)")
        printBreakdown(snapshot.performance.breakdown)
    }

    /// Measures the product pipeline's first bounded inventory projection and
    /// the authoritative result from the same scan. The callback is the same
    /// compact update bridge used by the SwiftUI model; it does not create a
    /// second traversal or alter the scan configuration.
    private static func benchmarkCacheTwoStage(concurrency: Int = 3) async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let allowed = home.appendingPathComponent("Library/Caches", isDirectory: true)
        guard FileManager.default.fileExists(atPath: allowed.path) else { return }
        let boundedConcurrency = max(1, min(concurrency, 6))
        let started = Date()
        let recorder = StageTimingRecorder(startedAt: started, rootPath: allowed.path)
        let snapshot = await DiskAnalysisEngine(maxConcurrentDirectories: boundedConcurrency).analyze(
            targets: [DiskAnalysisTarget(url: allowed)],
            configuration: DiskAnalysisConfiguration(
                allowedRoots: [allowed],
                maxConcurrentDirectories: boundedConcurrency,
                largeFiles: LargeFileOptions(thresholdBytes: 50 * 1024 * 1024, topN: 100),
                memorySampleStride: 512,
                initialDirectoryIdentityCapacity: 1 << 14
            )
        ) { update in
            recorder.record(update)
        }
        let firstUsable = recorder.value()
        let fullWall = Date().timeIntervalSince(started)
        print("two-stage cache scope: concurrency=\(boundedConcurrency) usable=\(format(firstUsable ?? -1))s full=\(format(fullWall))s duration=\(format(snapshot.performance.duration)) cpu=\(format(snapshot.performance.cpuTimeSeconds))s peakRSS=\(snapshot.performance.peakResidentMemoryBytes) files=\(snapshot.fileCount) directories=\(snapshot.directoryCount) logicalBytes=\(snapshot.totalBytes) allocatedBytes=\(snapshot.allocatedBytes) issues=\(snapshot.issues.count) cancelled=\(snapshot.cancelled)")
    }

    private static func requestedConcurrency(defaultValue: Int) -> Int {
        guard let marker = CommandLine.arguments.first(where: { $0.hasPrefix("--concurrency=") }),
              let value = Int(marker.split(separator: "=", maxSplits: 1).last ?? "") else {
            return defaultValue
        }
        return value
    }

    private static func argumentValue(prefix: String) -> String? {
        CommandLine.arguments.first(where: { $0.hasPrefix(prefix) }).map { String($0.dropFirst(prefix.count)) }
    }

    private static func benchmarkPathScope(_ path: URL, concurrency: Int) async throws {
        let normalized = path.standardizedFileURL
        guard FileManager.default.fileExists(atPath: normalized.path) else {
            throw RunnerError("Benchmark path does not exist: \(normalized.path)")
        }
        let metadata = try FileManager.default.attributesOfItem(atPath: normalized.path)
        guard (metadata[.type] as? FileAttributeType) == .typeDirectory else {
            throw RunnerError("Benchmark path is not a directory: \(normalized.path)")
        }
        let boundedConcurrency = max(1, min(concurrency, 6))
        let started = Date()
        let snapshot = await DiskAnalysisEngine(maxConcurrentDirectories: boundedConcurrency).analyze(
            targets: [DiskAnalysisTarget(url: normalized)],
            configuration: DiskAnalysisConfiguration(
                allowedRoots: [normalized],
                maxConcurrentDirectories: boundedConcurrency,
                largeFiles: LargeFileOptions(thresholdBytes: 0, topN: 20),
                memorySampleStride: 512,
                excludedDirectoryNames: [".git"],
                includeSymbolicLinks: false,
                collectPerformanceBreakdown: CommandLine.arguments.contains("--breakdown")
            )
        )
        let wall = Date().timeIntervalSince(started)
        print("equal-scope path=\(normalized.path) concurrency=\(boundedConcurrency) wall=\(format(wall)) duration=\(format(snapshot.performance.duration)) cpu=\(format(snapshot.performance.cpuTimeSeconds))s peakRSS=\(snapshot.performance.peakResidentMemoryBytes) files=\(snapshot.fileCount) directories=\(snapshot.directoryCount) logicalBytes=\(snapshot.totalBytes) allocatedBytes=\(snapshot.allocatedBytes) largeFiles=\(snapshot.largeFiles.count) issues=\(snapshot.issues.count)")
        printBreakdown(snapshot.performance.breakdown)
    }

    private static func benchmarkHome(concurrency: Int = 3) async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let started = Date()
        let boundedConcurrency = max(1, min(concurrency, 6))
        let snapshot = await DiskAnalysisEngine(maxConcurrentDirectories: boundedConcurrency).analyze(
            targets: [DiskAnalysisTarget(url: home)],
            configuration: DiskAnalysisConfiguration(
                allowedRoots: [home],
                maxConcurrentDirectories: boundedConcurrency,
                largeFiles: LargeFileOptions(thresholdBytes: 50 * 1024 * 1024, topN: 100),
                memorySampleStride: 2_048,
                initialDirectoryIdentityCapacity: 1 << 18
            )
        )
        let wall = Date().timeIntervalSince(started)
        print("home scope: concurrency=\(boundedConcurrency) wall=\(format(wall)) duration=\(format(snapshot.performance.duration)) cpu=\(format(snapshot.performance.cpuTimeSeconds))s peakRSS=\(snapshot.performance.peakResidentMemoryBytes) files=\(snapshot.fileCount) directories=\(snapshot.directoryCount) logicalBytes=\(snapshot.totalBytes) allocatedBytes=\(snapshot.allocatedBytes) volumeCapacity=\(snapshot.volumeCapacityBytes ?? 0) allocationStatus=\(snapshot.allocationStatus.rawValue) treeNodes=\(snapshot.tree.nodes.count) largeFiles=\(snapshot.largeFiles.count) issues=\(snapshot.issues.count) cancelled=\(snapshot.cancelled)")
    }

    // MARK: - Fixed, read-only benchmark harness

    // MARK: - Disk Analyzer quality acceptance

    /// Runs only controlled, read-only quality checks. The million-entry
    /// fixture is intentionally created outside the repository and removed in
    /// a defer block. A sparse APFS disk image is used as a second volume so
    /// the boundary check is real, repeatable, and does not require sudo or a
    /// physical external disk.
    private static func runQualityAcceptance() async throws {
        var failures: [String] = []

        do {
            if try await validateSecondVolume() {
                print("QUALITY volume-boundary: PASS")
            } else {
                failures.append("volume-boundary")
                print("QUALITY volume-boundary: FAIL")
            }
        } catch {
            failures.append("volume-boundary")
            print("QUALITY volume-boundary: ERROR \(error.localizedDescription)")
        }

        do {
            let watchdog = try await validateWatchdogSlowDirectory()
            if watchdog {
                print("QUALITY watchdog: PASS")
            } else {
                failures.append("watchdog")
                print("QUALITY watchdog: FAIL (a real timeout was not observed)")
            }
        } catch {
            failures.append("watchdog")
            print("QUALITY watchdog: ERROR \(error.localizedDescription)")
        }

        do {
            if try await validateMillionFileFixture() {
                print("QUALITY million-file: PASS")
            } else {
                failures.append("million-file")
                print("QUALITY million-file: FAIL")
            }
        } catch {
            failures.append("million-file")
            print("QUALITY million-file: ERROR \(error.localizedDescription)")
        }

        print("QUALITY watchdog-note: only a real slow directory is used; no injected/mock timeout is counted as success.")
        guard failures.isEmpty else {
            throw RunnerError("Quality acceptance failed: \(failures.joined(separator: ", ")).")
        }
    }

    private static func validateSecondVolume() async throws -> Bool {
        let mounted = try makeQualityVolume()
        defer {
            _ = runTool(path: "/usr/bin/hdiutil", arguments: ["detach", mounted.deviceEntry])
            try? FileManager.default.removeItem(at: mounted.image)
        }

        let externalRoot = mounted.mountPoint.appendingPathComponent("controlled-root", isDirectory: true)
        try FileManager.default.createDirectory(at: externalRoot, withIntermediateDirectories: true)
        let externalFile = externalRoot.appendingPathComponent("external-sentinel.bin")
        try Data(repeating: 9, count: 8 * 1024 * 1024).write(to: externalFile)

        let hostRoot = try makeFixture("LexCleanerVolumeBoundary")
        defer { try? FileManager.default.removeItem(at: hostRoot) }
        let hostFile = hostRoot.appendingPathComponent("host-sentinel.bin")
        try Data(repeating: 3, count: 128 * 1024).write(to: hostFile)
        let escapeLink = hostRoot.appendingPathComponent("external-link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: escapeLink, withDestinationURL: externalRoot)

        let combined = await DiskAnalysisEngine(maxConcurrentDirectories: 2).analyze(
            targets: [DiskAnalysisTarget(url: hostRoot), DiskAnalysisTarget(url: externalRoot)],
            configuration: DiskAnalysisConfiguration(
                allowedRoots: [hostRoot, externalRoot],
                maxConcurrentDirectories: 2,
                largeFiles: LargeFileOptions(thresholdBytes: 0, topN: 20),
                memorySampleStride: 1,
                includeSymbolicLinks: true,
                collectPerformanceBreakdown: true
            )
        )
        let externalOnly = await DiskAnalysisEngine(maxConcurrentDirectories: 1).analyze(
            targets: [DiskAnalysisTarget(url: externalRoot)],
            configuration: DiskAnalysisConfiguration(
                allowedRoots: [externalRoot],
                maxConcurrentDirectories: 1,
                largeFiles: LargeFileOptions(thresholdBytes: 0, topN: 20),
                memorySampleStride: 1,
                includeSymbolicLinks: false
            )
        )
        let duExternal = try allocatedBytesFromDU(at: externalRoot)
        let externalCapacity = externalOnly.volumeCapacityBytes ?? 0
        let escapedPathWasNotScanned = !combined.treemapNodes.contains {
            $0.path.standardizedFileURL.path == externalFile.standardizedFileURL.path
        }
        let hostSymlinkIssue = combined.issues.contains { issue in
            issue.kind == .symlinkEscape || issue.kind == .symlinkSkipped
        }
        let boundaryRecorded = combined.issues.contains { $0.kind == .volumeBoundary }
        let allocatedMatchesDU = absoluteDifference(externalOnly.allocatedBytes, duExternal) <= 4 * 1024 * 1024
        let withinCapacity = externalCapacity == 0 || externalOnly.allocatedBytes <= externalCapacity
        let countsExternalExactly = externalOnly.fileCount == 1
        let passed = boundaryRecorded && escapedPathWasNotScanned && hostSymlinkIssue
            && countsExternalExactly && allocatedMatchesDU && withinCapacity
        print("QUALITY volume-details: mount=\(mounted.mountPoint.path) device=\(mounted.deviceEntry) hostFiles=\(combined.fileCount) externalFiles=\(externalOnly.fileCount) externalAllocated=\(externalOnly.allocatedBytes) duAllocated=\(duExternal) diff=\(signedDifference(externalOnly.allocatedBytes, duExternal)) capacity=\(externalCapacity) boundary=\(boundaryRecorded) symlinkSafe=\(hostSymlinkIssue) escapedContentExcluded=\(escapedPathWasNotScanned)")
        printBreakdown(combined.performance.breakdown)
        return passed
    }

    /// A large, real directory enumeration is used here. It must complete
    /// without hanging; the result is PASS only if the production watchdog
    /// actually reports a timeout and safely skips a directory. Normal local
    /// APFS directories do not reliably block open(2), so a completed scan is
    /// reported separately rather than being mislabelled as a timeout pass.
    private static func validateWatchdogSlowDirectory() async throws -> Bool {
        let root = try makeFixture("LexCleanerWatchdogSlow")
        defer { try? FileManager.default.removeItem(at: root) }
        let filesPerDirectory = 4_000
        for directoryIndex in 0..<8 {
            let directory = root.appendingPathComponent("slow-\(directoryIndex)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for fileIndex in 0..<filesPerDirectory {
                guard FileManager.default.createFile(
                    atPath: directory.appendingPathComponent("entry-\(fileIndex)").path,
                    contents: Data([7])
                ) else {
                    throw RunnerError("Could not create watchdog fixture entry.")
                }
            }
        }
        let started = Date()
        let snapshot = await DiskAnalysisEngine(maxConcurrentDirectories: 2).analyze(
            targets: [DiskAnalysisTarget(url: root)],
            configuration: DiskAnalysisConfiguration(
                allowedRoots: [root],
                maxConcurrentDirectories: 2,
                largeFiles: LargeFileOptions(thresholdBytes: UInt64.max, topN: 0),
                memorySampleStride: 1_024,
                collectPerformanceBreakdown: true
            )
        )
        let wall = Date().timeIntervalSince(started)
        let timeoutCount = snapshot.performance.breakdown?.watchdogTimeouts ?? 0
        let completedWithoutHang = !snapshot.cancelled && snapshot.fileCount == UInt64(filesPerDirectory * 8)
        print("QUALITY watchdog-details: wall=\(format(wall)) files=\(snapshot.fileCount) directories=\(snapshot.directoryCount) completedWithoutHang=\(completedWithoutHang) timeouts=\(timeoutCount) issues=\(snapshot.issues.count)")
        printBreakdown(snapshot.performance.breakdown)
        return timeoutCount > 0
    }

    private static func validateMillionFileFixture() async throws -> Bool {
        let root = try makeFixture("LexCleanerMillionFiles")
        defer { try? FileManager.default.removeItem(at: root) }
        let bucketCount = 1_024
        let filesPerBucket = 1_024
        let expectedFiles = UInt64(bucketCount * filesPerBucket)
        let payload = Data([7])
        let createStarted = Date()
        for bucketIndex in 0..<bucketCount {
            let bucket = root.appendingPathComponent("bucket-\(bucketIndex)", isDirectory: true)
            try FileManager.default.createDirectory(at: bucket, withIntermediateDirectories: true)
            for fileIndex in 0..<filesPerBucket {
                guard FileManager.default.createFile(
                    atPath: bucket.appendingPathComponent("file-\(fileIndex)").path,
                    contents: payload
                ) else {
                    throw RunnerError("Could not create million-file fixture entry.")
                }
            }
        }
        let creationWall = Date().timeIntervalSince(createStarted)

        let scanStarted = Date()
        let snapshot = await DiskAnalysisEngine(maxConcurrentDirectories: 4).analyze(
            targets: [DiskAnalysisTarget(url: root)],
            configuration: DiskAnalysisConfiguration(
                allowedRoots: [root],
                maxConcurrentDirectories: 4,
                largeFiles: LargeFileOptions(thresholdBytes: UInt64.max, topN: 0),
                memorySampleStride: 16_384,
                initialDirectoryIdentityCapacity: 2_048,
                collectPerformanceBreakdown: true
            )
        )
        let scanWall = Date().timeIntervalSince(scanStarted)
        let duAllocated = try allocatedBytesFromDU(at: root)
        let directoryOverheadAllowance = max(4 * 1024 * 1024, snapshot.directoryCount * 8 * 1024)
        let allocatedMatchesDU = absoluteDifference(snapshot.allocatedBytes, duAllocated) <= directoryOverheadAllowance
        let countAccurate = snapshot.fileCount == expectedFiles && snapshot.directoryCount == UInt64(bucketCount + 1)
        let complete = !snapshot.cancelled && snapshot.tree.isComplete
        let capacitySafe = snapshot.volumeCapacityBytes.map { snapshot.allocatedBytes <= $0 } ?? true
        print("QUALITY million-details: create=\(format(creationWall)) scan=\(format(scanWall)) files=\(snapshot.fileCount)/\(expectedFiles) directories=\(snapshot.directoryCount)/\(bucketCount + 1) allocated=\(snapshot.allocatedBytes) du=\(duAllocated) diff=\(signedDifference(snapshot.allocatedBytes, duAllocated)) allowance=\(directoryOverheadAllowance) peakRSS=\(snapshot.performance.peakResidentMemoryBytes) throughput=\(format(snapshot.performance.throughputFilesPerSecond))/s complete=\(complete) capacitySafe=\(capacitySafe)")
        printBreakdown(snapshot.performance.breakdown)

        let controller = CancellationController()
        let cancellationStarted = Date()
        let task = Task {
            await DiskAnalysisEngine(maxConcurrentDirectories: 4).analyze(
                targets: [DiskAnalysisTarget(url: root)],
                configuration: DiskAnalysisConfiguration(
                    allowedRoots: [root],
                    maxConcurrentDirectories: 4,
                    largeFiles: LargeFileOptions(thresholdBytes: UInt64.max, topN: 0),
                    memorySampleStride: 2_048
                )
            ) { update in
                if update.visitedPathCount >= 16_384 {
                    await controller.requestCancellation()
                }
            }
        }
        await controller.set(task)
        let cancelledSnapshot = await task.value
        let cancellationLatency = Date().timeIntervalSince(cancellationStarted)
        let cancellationPassed = cancelledSnapshot.cancelled && cancelledSnapshot.fileCount < expectedFiles && cancellationLatency < 5
        print("QUALITY million-cancellation: cancelled=\(cancelledSnapshot.cancelled) filesBeforeStop=\(cancelledSnapshot.fileCount)/\(expectedFiles) latency=\(format(cancellationLatency)) passed=\(cancellationPassed)")
        return countAccurate && allocatedMatchesDU && complete && capacitySafe && cancellationPassed
    }

    private static func makeQualityVolume() throws -> QualityMountedVolume {
        let image = FileManager.default.temporaryDirectory.appendingPathComponent("LexCleanerQualityVolume-\(UUID().uuidString).sparseimage")
        let create = runTool(path: "/usr/bin/hdiutil", arguments: ["create", "-size", "256m", "-fs", "APFS", "-volname", "LexCleanerQuality", "-type", "SPARSE", "-ov", image.path])
        guard create.status == 0 else {
            throw RunnerError("hdiutil create failed: \(String(data: create.stderr, encoding: .utf8) ?? "unknown error")")
        }
        let attach = runTool(path: "/usr/bin/hdiutil", arguments: ["attach", "-nobrowse", "-plist", image.path])
        guard attach.status == 0 else {
            try? FileManager.default.removeItem(at: image)
            throw RunnerError("hdiutil attach failed: \(String(data: attach.stderr, encoding: .utf8) ?? "unknown error")")
        }
        do {
            guard let plist = try PropertyListSerialization.propertyList(from: attach.stdout, options: [], format: nil) as? [String: Any],
                  let entities = plist["system-entities"] as? [[String: Any]],
                  let mountPoint = entities.compactMap({ $0["mount-point"] as? String }).first,
                  let deviceEntry = entities.compactMap({ $0["dev-entry"] as? String }).first else {
                throw RunnerError("hdiutil attach returned no mount point/device.")
            }
            return QualityMountedVolume(image: image, mountPoint: URL(fileURLWithPath: mountPoint), deviceEntry: deviceEntry)
        } catch {
            _ = runTool(path: "/usr/bin/hdiutil", arguments: ["detach", "-force", image.path])
            try? FileManager.default.removeItem(at: image)
            throw error
        }
    }

    private static func runTool(path: String, arguments: [String]) -> ToolResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
            process.waitUntilExit()
            return ToolResult(status: process.terminationStatus, stdout: stdout.fileHandleForReading.readDataToEndOfFile(), stderr: stderr.fileHandleForReading.readDataToEndOfFile())
        } catch {
            return ToolResult(status: -1, stdout: Data(), stderr: Data(error.localizedDescription.utf8))
        }
    }

    private static func absoluteDifference(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        lhs >= rhs ? lhs - rhs : rhs - lhs
    }

    /// Strict external A/B protocol for a real macOS directory. Each arm is
    /// an independent process under `/usr/bin/time -l`; the parent applies a
    /// per-process timeout and never turns a timeout into a latency sample.
    /// The cold and warm cohorts are reported separately. The macOS page cache
    /// is not flushed because doing so requires privileged/destructive system
    /// operations; "warm" therefore means a later independent process in the
    /// same cohort, not a claim of a fully cold disk.
    private static func runStrictThirtyBenchmark() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaultRoot = home.appendingPathComponent("Library/Caches", isDirectory: true)
        let root = URL(fileURLWithPath: argumentValue(prefix: "--path=") ?? defaultRoot.path).standardizedFileURL
        guard root.path.hasPrefix("/"), FileManager.default.fileExists(atPath: root.path) else {
            throw RunnerError("Strict benchmark root does not exist or is not absolute: \(root.path)")
        }
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw RunnerError("Strict benchmark root is not a directory: \(root.path)")
        }
        guard let moleExecutable = ["/opt/homebrew/bin/mole", "/usr/local/bin/mole"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw RunnerError("Mole executable was not found; no external baseline will be fabricated.")
        }

        let iterations = max(1, min(30, Int(argumentValue(prefix: "--iterations=") ?? "30") ?? 30))
        let timeoutSeconds = max(0.25, min(300, Double(argumentValue(prefix: "--timeout-seconds=") ?? "2") ?? 2))
        let seed = UInt64(argumentValue(prefix: "--seed=") ?? "20260823") ?? 20260823
        let duObservation = bestEffortAllocatedBytesFromDU(at: root)
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path

        print("BENCHMARK_PROTOCOL version=2 root=\(root.path) iterationsPerState=\(iterations) timeoutSeconds=\(format(timeoutSeconds)) seed=\(seed)")
        print("BENCHMARK_PROTOCOL arms=LexCleaner,Mole order=randomized-per-round independent-process=true time=/usr/bin/time -l")
        print("BENCHMARK_PROTOCOL cacheStates=cold,warm; cold=unique-HOME process launch; warm=primed-HOME independent process; macOS-page-cache=not-flushed")
        print("BENCHMARK_PROTOCOL scope=both arms receive identical root and analyze command; Mole JSON has no allocated-size field; Lex symlink leaves are retained")
        print("BENCHMARK_GROUND_TRUTH duAllocatedBytes=\(duObservation.bytes.map(String.init) ?? "unavailable") duExit=\(duObservation.exitCode) duComplete=\(duObservation.complete)")
        print("BENCHMARK_MOLE version=\(moleVersion(executable: moleExecutable)) path=\(moleExecutable)")

        var benchmarkFailed = false
        for state in [BenchmarkCacheState.cold, .warm] {
            var rng = SplitMix64(seed: seed ^ (state == .cold ? 0xC01D : 0xA2A))
            var records: [BenchmarkRunRecord] = []
            records.reserveCapacity(iterations * 2)
            var warmHomes: [BenchmarkArm: URL] = [:]
            defer {
                for home in warmHomes.values { try? FileManager.default.removeItem(at: home) }
            }

            if state == .warm {
                for arm in [BenchmarkArm.lexCleaner, .mole] {
                    let warmHome = try makeBenchmarkHome(label: "warm-\(arm.rawValue)")
                    warmHomes[arm] = warmHome
                    let warmup = try runBenchmarkArm(
                        arm: arm,
                        root: root,
                        executable: executable,
                        moleExecutable: moleExecutable,
                        home: warmHome,
                        timeoutSeconds: timeoutSeconds
                    )
                    printBenchmarkWarmup(state: state, arm: arm, result: warmup)
                }
            }

            var moleTimeoutStreak = 0
            for iteration in 1...iterations {
                let order: [BenchmarkArm] = rng.nextBool()
                    ? [.lexCleaner, .mole]
                    : [.mole, .lexCleaner]
                for arm in order {
                    let runHome: URL
                    let removeHomeAfterRun: Bool
                    if state == .cold {
                        runHome = try makeBenchmarkHome(label: "cold-\(arm.rawValue)-\(iteration)")
                        removeHomeAfterRun = true
                    } else {
                        guard let warmHome = warmHomes[arm] else { throw RunnerError("Missing warm HOME for \(arm.rawValue).") }
                        runHome = warmHome
                        removeHomeAfterRun = false
                    }
                    let result = try runBenchmarkArm(
                        arm: arm,
                        root: root,
                        executable: executable,
                        moleExecutable: moleExecutable,
                        home: runHome,
                        timeoutSeconds: timeoutSeconds
                    )
                    if removeHomeAfterRun { try? FileManager.default.removeItem(at: runHome) }
                    let record = normalizeBenchmarkResult(state: state, iteration: iteration, arm: arm, result: result)
                    records.append(record)
                    printBenchmarkRun(record)
                    if arm == .mole {
                        if record.status == .timeout {
                            moleTimeoutStreak += 1
                            if moleTimeoutStreak == 3 {
                                print("BENCHMARK_STABILITY_FAIL state=\(state.rawValue) arm=Mole reason=three-consecutive-timeouts iteration=\(iteration) timeoutSeconds=\(format(timeoutSeconds))")
                            }
                        } else if record.status == .success {
                            moleTimeoutStreak = 0
                        }
                    }
                }
            }

            for arm in [BenchmarkArm.lexCleaner, .mole] {
                let summary = summarizeBenchmark(records: records.filter { $0.arm == arm }, planned: iterations)
                printBenchmarkSummary(state: state, arm: arm, summary: summary, duBytes: duObservation.bytes)
                if summary.successes != iterations || summary.timeouts > 0 || summary.failures > 0 {
                    benchmarkFailed = true
                }
            }
        }

        if benchmarkFailed {
            throw RunnerError("Strict 30-run A/B is FAIL/INCOMPLETE: at least one cohort did not produce 30 successful observations per arm; timeout samples were excluded from latency percentiles.")
        }
        print("BENCHMARK_STATUS=COMPLETE (all cold/warm cohorts completed with 30 successful observations per arm; this is not a product-performance PASS)")
        print("BENCHMARK_COMPARISON=INCONCLUSIVE reason=Mole-does-not-report-allocated-size-and-file/symlink-scope-is-not-identical")
    }

    private static func runBenchmarkChild() async throws {
        guard let rootPath = argumentValue(prefix: "--root=") else { throw RunnerError("Benchmark child requires --root=.") }
        let root = URL(fileURLWithPath: rootPath).standardizedFileURL
        let snapshot = await DiskAnalysisEngine(maxConcurrentDirectories: 4).analyze(
            targets: [DiskAnalysisTarget(url: root)],
            configuration: DiskAnalysisConfiguration(
                allowedRoots: [root],
                maxConcurrentDirectories: 4,
                largeFiles: LargeFileOptions(thresholdBytes: 50 * 1024 * 1024, topN: 20),
                memorySampleStride: 512,
                includeSymbolicLinks: true,
                adaptiveConcurrency: false
            )
        )
        let output = BenchmarkLexChildOutput(
            completed: !snapshot.cancelled,
            fileCount: snapshot.fileCount,
            directoryCount: snapshot.directoryCount,
            logicalBytes: snapshot.totalBytes,
            allocatedBytes: snapshot.allocatedBytes,
            volumeCapacityBytes: snapshot.volumeCapacityBytes,
            internalCPUSeconds: snapshot.performance.cpuTimeSeconds,
            internalPeakRSSBytes: snapshot.performance.peakResidentMemoryBytes
        )
        let data = try JSONEncoder().encode(output)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
        guard output.completed else { throw RunnerError("Benchmark child was cancelled unexpectedly.") }
    }

    private static func runBenchmarkArm(
        arm: BenchmarkArm,
        root: URL,
        executable: String,
        moleExecutable: String,
        home: URL,
        timeoutSeconds: Double
    ) throws -> TimedBenchmarkProcess {
        switch arm {
        case .lexCleaner:
            return try runTimedBenchmarkProcess(
                executable: executable,
                arguments: ["--benchmark-child", "--root=\(root.path)"],
                home: home,
                timeoutSeconds: timeoutSeconds
            )
        case .mole:
            return try runTimedBenchmarkProcess(
                executable: moleExecutable,
                arguments: ["analyze", "-json", root.path],
                home: home,
                timeoutSeconds: timeoutSeconds
            )
        }
    }

    private static func normalizeBenchmarkResult(state: BenchmarkCacheState, iteration: Int, arm: BenchmarkArm, result: TimedBenchmarkProcess) -> BenchmarkRunRecord {
        if result.timedOut {
            return BenchmarkRunRecord(state: state, iteration: iteration, arm: arm, status: .timeout, wall: result.wall, userCPU: result.userCPU, systemCPU: result.systemCPU, peakRSSBytes: result.peakRSSBytes, fileCount: nil, directoryCount: nil, logicalBytes: nil, allocatedBytes: nil, allocatedReported: arm == .lexCleaner, exitCode: result.exitCode, diagnostic: "process timeout; stderr=\(compact(result.stderr))")
        }
        guard result.exitCode == 0 else {
            return BenchmarkRunRecord(state: state, iteration: iteration, arm: arm, status: .failure, wall: result.wall, userCPU: result.userCPU, systemCPU: result.systemCPU, peakRSSBytes: result.peakRSSBytes, fileCount: nil, directoryCount: nil, logicalBytes: nil, allocatedBytes: nil, allocatedReported: arm == .lexCleaner, exitCode: result.exitCode, diagnostic: compact(result.stderr))
        }
        do {
            let output = try JSONSerialization.jsonObject(with: result.stdout) as? [String: Any] ?? [:]
            let fileCount: UInt64?
            let directoryCount: UInt64?
            let logicalBytes: UInt64?
            let allocatedBytes: UInt64?
            if arm == .lexCleaner {
                fileCount = (output["fileCount"] as? NSNumber)?.uint64Value
                directoryCount = (output["directoryCount"] as? NSNumber)?.uint64Value
                logicalBytes = (output["logicalBytes"] as? NSNumber)?.uint64Value
                allocatedBytes = (output["allocatedBytes"] as? NSNumber)?.uint64Value
            } else {
                fileCount = (output["total_files"] as? NSNumber)?.uint64Value
                let entries = output["entries"] as? [[String: Any]] ?? []
                directoryCount = UInt64(entries.filter { ($0["is_dir"] as? Bool) == true }.count)
                logicalBytes = (output["total_size"] as? NSNumber)?.uint64Value
                allocatedBytes = nil
            }
            guard let fileCount, let logicalBytes else {
                return BenchmarkRunRecord(state: state, iteration: iteration, arm: arm, status: .failure, wall: result.wall, userCPU: result.userCPU, systemCPU: result.systemCPU, peakRSSBytes: result.peakRSSBytes, fileCount: nil, directoryCount: nil, logicalBytes: nil, allocatedBytes: nil, allocatedReported: arm == .lexCleaner, exitCode: result.exitCode, diagnostic: "successful process without required JSON summary")
            }
            return BenchmarkRunRecord(state: state, iteration: iteration, arm: arm, status: .success, wall: result.wall, userCPU: result.userCPU, systemCPU: result.systemCPU, peakRSSBytes: result.peakRSSBytes, fileCount: fileCount, directoryCount: directoryCount, logicalBytes: logicalBytes, allocatedBytes: allocatedBytes, allocatedReported: arm == .lexCleaner, exitCode: result.exitCode, diagnostic: "")
        } catch {
            return BenchmarkRunRecord(state: state, iteration: iteration, arm: arm, status: .failure, wall: result.wall, userCPU: result.userCPU, systemCPU: result.systemCPU, peakRSSBytes: result.peakRSSBytes, fileCount: nil, directoryCount: nil, logicalBytes: nil, allocatedBytes: nil, allocatedReported: arm == .lexCleaner, exitCode: result.exitCode, diagnostic: "invalid JSON: \(error.localizedDescription)")
        }
    }

    private static func runTimedBenchmarkProcess(executable: String, arguments: [String], home: URL, timeoutSeconds: Double) throws -> TimedBenchmarkProcess {
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/time")
        process.arguments = ["-l", executable] + arguments
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = home.path
        environment["LC_ALL"] = "C"
        process.environment = environment
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let waitState = ProcessWaitState()
        process.terminationHandler = { _ in waitState.signal() }
        let started = DispatchTime.now().uptimeNanoseconds
        try process.run()
        let processID = process.processIdentifier
        _ = setpgid(processID, processID)
        var timedOut = false
        if waitState.wait(timeoutSeconds: timeoutSeconds) == .timedOut {
            if process.isRunning {
                timedOut = true
                _ = kill(-processID, SIGTERM)
                if waitState.wait(timeoutSeconds: 0.25) == .timedOut {
                    _ = kill(-processID, SIGKILL)
                    _ = waitState.wait(timeoutSeconds: 1)
                }
            } else {
                _ = waitState.wait(timeoutSeconds: 0.25)
            }
        }
        if process.isRunning { process.waitUntilExit() }
        let finished = DispatchTime.now().uptimeNanoseconds
        let stdout = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let metrics = parseTimeMetrics(stderr)
        return TimedBenchmarkProcess(
            timedOut: timedOut,
            wall: Double(finished - started) / 1_000_000_000,
            userCPU: metrics.user,
            systemCPU: metrics.system,
            peakRSSBytes: metrics.peakRSSBytes,
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr
        )
    }

    private static func makeBenchmarkHome(label: String) throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("LexCleanerBenchmark-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private static func printBenchmarkWarmup(state: BenchmarkCacheState, arm: BenchmarkArm, result: TimedBenchmarkProcess) {
        let status = result.timedOut ? "timeout" : (result.exitCode == 0 ? "success" : "failure")
        print("BENCHMARK_WARMUP state=\(state.rawValue) arm=\(arm.rawValue) status=\(status) wall=\(format(result.wall)) userCPU=\(format(result.userCPU)) systemCPU=\(format(result.systemCPU)) peakRSSBytes=\(result.peakRSSBytes) exit=\(result.exitCode) diagnostic=\(compact(result.stderr))")
    }

    private static func printBenchmarkRun(_ record: BenchmarkRunRecord) {
        print("BENCHMARK_RUN state=\(record.state.rawValue) iteration=\(record.iteration) arm=\(record.arm.rawValue) status=\(record.status.rawValue) wall=\(format(record.wall)) userCPU=\(format(record.userCPU)) systemCPU=\(format(record.systemCPU)) cpu=\(format(record.userCPU + record.systemCPU)) peakRSSBytes=\(record.peakRSSBytes) files=\(record.fileCount.map(String.init) ?? "NA") directories=\(record.directoryCount.map(String.init) ?? "NA") logicalBytes=\(record.logicalBytes.map(String.init) ?? "NA") allocatedBytes=\(record.allocatedBytes.map(String.init) ?? "NA") allocatedReported=\(record.allocatedReported) exit=\(record.exitCode) diagnostic=\(record.diagnostic)")
    }

    private static func printBenchmarkSummary(state: BenchmarkCacheState, arm: BenchmarkArm, summary: BenchmarkSummary, duBytes: UInt64?) {
        print("BENCHMARK_SUMMARY state=\(state.rawValue) arm=\(arm.rawValue) planned=\(summary.planned) successes=\(summary.successes) timeouts=\(summary.timeouts) failures=\(summary.failures) wallMedian=\(summary.wallMedian.map(format) ?? "NA") wallP95=\(summary.wallP95.map(format) ?? "NA") wallP99=\(summary.wallP99.map(format) ?? "NA") cpuMedian=\(summary.cpuMedian.map(format) ?? "NA") peakRSSMedianBytes=\(summary.rssMedian.map(String.init) ?? "NA") filesRange=\(summary.filesRange) allocatedRange=\(summary.allocatedRange) allocatedReported=\(summary.allocatedReported) duObservedBytes=\(duBytes.map(String.init) ?? "NA")")
    }

    private static func summarizeBenchmark(records: [BenchmarkRunRecord], planned: Int) -> BenchmarkSummary {
        let successful = records.filter { $0.status == .success }
        let walls = successful.map(\.wall)
        let cpu = successful.map { $0.userCPU + $0.systemCPU }
        let rss = successful.map(\.peakRSSBytes)
        let files = successful.compactMap(\.fileCount)
        let allocated = successful.compactMap(\.allocatedBytes)
        return BenchmarkSummary(
            planned: planned,
            successes: successful.count,
            timeouts: records.filter { $0.status == .timeout }.count,
            failures: records.filter { $0.status == .failure }.count,
            wallMedian: percentile(walls, 0.50),
            wallP95: percentile(walls, 0.95),
            wallP99: percentile(walls, 0.99),
            cpuMedian: percentile(cpu, 0.50),
            rssMedian: percentile(rss, 0.50),
            filesRange: rangeDescription(files),
            allocatedRange: rangeDescription(allocated),
            allocatedReported: successful.allSatisfy(\.allocatedReported)
        )
    }

    private static func percentile<T: Comparable>(_ values: [T], _ probability: Double) -> T? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let rank = max(1, Int(ceil(probability * Double(sorted.count))))
        return sorted[min(sorted.count, rank) - 1]
    }

    private static func rangeDescription(_ values: [UInt64]) -> String {
        guard let minValue = values.min(), let maxValue = values.max() else { return "NA" }
        return minValue == maxValue ? String(minValue) : "\(minValue)-\(maxValue)"
    }

    private static func parseTimeMetrics(_ data: Data) -> TimeMetrics {
        let output = String(data: data, encoding: .utf8) ?? ""
        var user = 0.0
        var system = 0.0
        var rss: UInt64 = 0
        for line in output.split(separator: "\n") {
            let text = String(line)
            let tokens = text.split(whereSeparator: { $0 == " " || $0 == "\t" })
            for (index, token) in tokens.enumerated() where index > 0 {
                if token == "user", let value = Double(tokens[index - 1]) { user = value }
                if token == "sys", let value = Double(tokens[index - 1]) { system = value }
            }
            if text.contains("maximum resident set size"), let value = tokens.first.flatMap({ UInt64($0) }) { rss = value }
        }
        return TimeMetrics(user: user, system: system, peakRSSBytes: rss)
    }

    private static func moleVersion(executable: String) -> String {
        let result = runTool(path: executable, arguments: ["--version"])
        return compact(result.stdout.isEmpty ? result.stderr : result.stdout)
    }

    private static func compact(_ data: Data) -> String {
        let value = String(data: data, encoding: .utf8) ?? ""
        return value.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines).prefix(240).description
    }

    private static func bestEffortAllocatedBytesFromDU(at root: URL) -> DUObservation {
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-skPx", root.path]
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return DUObservation(bytes: nil, exitCode: -1, complete: false)
        }
        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let kilobytes = stdout.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).first.flatMap { UInt64($0) }
        return DUObservation(bytes: kilobytes.map { $0 * 1024 }, exitCode: process.terminationStatus, complete: process.terminationStatus == 0)
    }

    /// Runs a reproducible fixture through LexCleaner and Mole. The harness
    /// deliberately distinguishes analyzer-cache state from the macOS file
    /// cache: flushing the latter is privileged and is not attempted.
    private static func runBenchmarkHarness() async throws {
        let fixture = try makeHarnessFixture()
        defer {
            _ = chmod(fixture.denied.path, 0o700)
            try? FileManager.default.removeItem(at: fixture.root)
            try? FileManager.default.removeItem(at: fixture.outside)
        }

        let duAllocatedBytes = try allocatedBytesFromDU(at: fixture.root)
        guard chmod(fixture.denied.path, 0) == 0 else {
            throw RunnerError("Could not apply the permission-denied fixture mode.")
        }
        print("HARNESS version=1 dataset=controlled-fixed fixture=\(fixture.root.path) expectedFiles=\(fixture.expectedFileCount) topN=20 concurrency=4")
        print("HARNESS rules symlink=Lex profile-fixed (equal=false/full=true), volume=stay-on-root-volume, permission=record-and-skip, output=normalized-summary+Top20")
        print("HARNESS cache-state Lex=analyzer-cache-disabled; Mole=cold empty HOME then warm same HOME; macOS page cache=not flushed")
        print("HARNESS ground-truth duAllocatedBytes=\(duAllocatedBytes)")

        for profile in HarnessProfile.allCases {
            let moleHome = FileManager.default.temporaryDirectory
                .appendingPathComponent("LexCleanerMoleHarnessHome-\(profile.rawValue)-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: moleHome, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: moleHome) }

            let moleCold = try runMole(profile: profile, root: fixture.root, home: moleHome)
            let moleWarm = try runMole(profile: profile, root: fixture.root, home: moleHome)
            let lexCold = await runLex(profile: profile, root: fixture.root)
            let lexWarm = await runLex(profile: profile, root: fixture.root)

            printHarnessResult("LexCleaner", profile: profile, cache: "cold", result: lexCold, duAllocatedBytes: duAllocatedBytes)
            printHarnessResult("LexCleaner", profile: profile, cache: "warm", result: lexWarm, duAllocatedBytes: duAllocatedBytes)
            print("HARNESS Mole profile=\(profile.rawValue) cache=cold wall=\(format(moleCold.wall)) rss=\(moleCold.peakRSSMiB)MiB totalSizeLogical=\(moleCold.totalSize) totalFiles=\(moleCold.totalFiles) entries=\(moleCold.entryCount) largeFiles=\(moleCold.largeFileCount) normalizedBytes=\(moleCold.normalizedOutputBytes) exit=\(moleCold.exitCode)")
            print("HARNESS Mole profile=\(profile.rawValue) cache=warm wall=\(format(moleWarm.wall)) rss=\(moleWarm.peakRSSMiB)MiB totalSizeLogical=\(moleWarm.totalSize) totalFiles=\(moleWarm.totalFiles) entries=\(moleWarm.entryCount) largeFiles=\(moleWarm.largeFileCount) normalizedBytes=\(moleWarm.normalizedOutputBytes) exit=\(moleWarm.exitCode)")

            guard lexCold.snapshot.fileCount == lexWarm.snapshot.fileCount,
                  lexCold.snapshot.totalBytes == lexWarm.snapshot.totalBytes,
                  lexCold.snapshot.allocatedBytes == lexWarm.snapshot.allocatedBytes else {
                throw RunnerError("Lex cold/warm result changed on unchanged fixture for profile \(profile.rawValue).")
            }
            guard lexCold.snapshot.allocatedBytes <= (lexCold.snapshot.volumeCapacityBytes ?? UInt64.max) else {
                throw RunnerError("Allocated bytes exceeded the volume capacity in profile \(profile.rawValue).")
            }
        }
        print("HARNESS quality-note million-file fixture is not generated by this short harness; the separate large-scale validation remains required.")
        print("HARNESS quality-note no incremental disk-analysis cache is implemented; Lex warm means a second scan with cache disabled.")
    }

    private static func runLex(profile: HarnessProfile, root: URL) async -> HarnessLexResult {
        let started = Date()
        let snapshot = await DiskAnalysisEngine(maxConcurrentDirectories: 4).analyze(
            targets: [DiskAnalysisTarget(url: root)],
            configuration: DiskAnalysisConfiguration(
                allowedRoots: [root],
                maxConcurrentDirectories: 4,
                largeFiles: LargeFileOptions(thresholdBytes: 1 << 20, topN: 20),
                memorySampleStride: 512,
                includeSymbolicLinks: profile.includeSymbolicLinks,
                adaptiveConcurrency: false
            )
        )
        let wall = Date().timeIntervalSince(started)
        let output = HarnessNormalizedOutput(
            fileCount: snapshot.fileCount,
            directoryCount: snapshot.directoryCount,
            logicalBytes: snapshot.totalBytes,
            allocatedBytes: snapshot.allocatedBytes,
            topLargeFilePaths: snapshot.largeFiles.prefix(20).map { $0.path.path },
            issueKinds: snapshot.issues.map { $0.kind.rawValue }.sorted()
        )
        let outputBytes = (try? JSONEncoder().encode(output).count) ?? 0
        return HarnessLexResult(snapshot: snapshot, wall: wall, normalizedOutputBytes: outputBytes)
    }

    private static func runMole(profile: HarnessProfile, root: URL, home: URL) throws -> HarnessMoleResult {
        guard let executable = ["/opt/homebrew/bin/mole", "/usr/local/bin/mole"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw RunnerError("Mole 1.52.0 executable was not found; the external A/B leg cannot be run honestly.")
        }
        let started = Date()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/time")
        process.arguments = ["-l", executable, "analyze", "-json", root.path]
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = home.path
        process.environment = environment
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let wall = Date().timeIntervalSince(started)
        let stdout = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = errorPipe.fileHandleForReading.readDataToEndOfFile()
        guard let object = try JSONSerialization.jsonObject(with: stdout) as? [String: Any], process.terminationStatus == 0 else {
            let error = String(data: stderr, encoding: .utf8) ?? "unknown Mole failure"
            throw RunnerError("Mole \(profile.rawValue) run failed: \(error.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        let entries = object["entries"] as? [[String: Any]] ?? []
        let largeFiles = object["large_files"] as? [[String: Any]] ?? []
        let totalSize = (object["total_size"] as? NSNumber)?.uint64Value ?? 0
        let totalFiles = (object["total_files"] as? NSNumber)?.uint64Value ?? 0
        let normalized = HarnessNormalizedOutput(
            fileCount: totalFiles,
            directoryCount: UInt64(entries.filter { ($0["is_dir"] as? Bool) == true }.count),
            logicalBytes: totalSize,
            allocatedBytes: 0,
            topLargeFilePaths: largeFiles.prefix(20).compactMap { $0["path"] as? String },
            issueKinds: []
        )
        let rssBytes = parsePeakRSSBytes(stderr)
        return HarnessMoleResult(
            wall: wall,
            peakRSSMiB: String(format: "%.2f", Double(rssBytes) / 1_048_576),
            totalSize: totalSize,
            totalFiles: totalFiles,
            entryCount: entries.count,
            largeFileCount: largeFiles.count,
            normalizedOutputBytes: (try? JSONEncoder().encode(normalized).count) ?? 0,
            exitCode: process.terminationStatus
        )
    }

    private static func printHarnessResult(_ name: String, profile: HarnessProfile, cache: String, result: HarnessLexResult, duAllocatedBytes: UInt64) {
        let snapshot = result.snapshot
        print("HARNESS \(name) profile=\(profile.rawValue) cache=\(cache) wall=\(format(result.wall)) duration=\(format(snapshot.performance.duration)) rss=\(String(format: "%.2f", Double(snapshot.performance.peakResidentMemoryBytes) / 1_048_576))MiB files=\(snapshot.fileCount) directories=\(snapshot.directoryCount) logicalBytes=\(snapshot.totalBytes) allocatedBytes=\(snapshot.allocatedBytes) duDiff=\(signedDifference(snapshot.allocatedBytes, duAllocatedBytes)) normalizedBytes=\(result.normalizedOutputBytes) issues=\(snapshot.issues.count)")
    }

    private static func makeHarnessFixture() throws -> HarnessFixture {
        let root = try makeFixture("LexCleanerBenchmarkHarness")
        let outside = root.deletingLastPathComponent().appendingPathComponent("LexCleanerBenchmarkOutside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let denied = root.appendingPathComponent("permission-denied", isDirectory: true)
        let bucketCount = 32
        let fileCount = 20_000
        for bucket in 0..<bucketCount {
            for shard in 0..<8 {
                try FileManager.default.createDirectory(at: root.appendingPathComponent("bucket-\(bucket)/shard-\(shard)", isDirectory: true), withIntermediateDirectories: true)
            }
        }
        let payload = Data(repeating: 7, count: 64)
        for index in 0..<fileCount {
            let directory = root.appendingPathComponent("bucket-\(index % bucketCount)/shard-\((index / bucketCount) % 8)", isDirectory: true)
            let contents = index == 17 ? Data(repeating: 3, count: 2 * 1024 * 1024) : payload
            guard FileManager.default.createFile(atPath: directory.appendingPathComponent("file-\(index).dat").path, contents: contents) else {
                throw RunnerError("Could not create benchmark fixture file \(index).")
            }
        }
        let hardLinkSource = root.appendingPathComponent("bucket-0/shard-0/file-0.dat")
        try FileManager.default.linkItem(at: hardLinkSource, to: root.appendingPathComponent("hardlink.dat"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("loop"), withDestinationURL: root)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: outside)
        try FileManager.default.createDirectory(at: denied, withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: denied.appendingPathComponent("hidden.dat").path, contents: Data("private".utf8)) else {
            throw RunnerError("Could not create permission fixture file.")
        }
        return HarnessFixture(root: root, outside: outside, denied: denied, expectedFileCount: UInt64(fileCount + 1))
    }

    private static func allocatedBytesFromDU(at root: URL) throws -> UInt64 {
        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-skPx", root.path]
        process.standardOutput = outputPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8),
              let kilobytes = UInt64(output.split(whereSeparator: { $0 == " " || $0 == "\t" }).first ?? "") else {
            throw RunnerError("du -skPx did not return a usable allocated-size result.")
        }
        return kilobytes * 1024
    }

    private static func parsePeakRSSBytes(_ data: Data) -> UInt64 {
        let output = String(data: data, encoding: .utf8) ?? ""
        for line in output.split(separator: "\n") where line.contains("peak memory footprint") {
            if let value = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).first,
               let bytes = UInt64(value) { return bytes }
        }
        return 0
    }

    private static func signedDifference(_ lhs: UInt64, _ rhs: UInt64) -> String {
        if lhs >= rhs { return "+\(lhs - rhs)" }
        return "-\(rhs - lhs)"
    }

    private static func makeFixture(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func format(_ value: Double) -> String { String(format: "%.3f", value) }

    private static func printBreakdown(_ breakdown: DiskAnalysisBreakdown?) {
        guard let breakdown else { return }
        print("breakdown: metadata calls=\(breakdown.metadataCalls) entries=\(breakdown.metadataEntries) time=\(formatNanoseconds(breakdown.metadataNanoseconds)); symlink entries=\(breakdown.symlinkEntries) time=\(formatNanoseconds(breakdown.symlinkNanoseconds)); volume checks=\(breakdown.volumeChecks) boundary=\(breakdown.volumeBoundaryEntries) time=\(formatNanoseconds(breakdown.volumeNanoseconds)); permission checks=\(breakdown.permissionChecks) failures=\(breakdown.permissionFailures); identity checks=\(breakdown.identityChecks) time=\(formatNanoseconds(breakdown.identityNanoseconds)); hardlinks candidates=\(breakdown.hardLinkCandidates) duplicates=\(breakdown.hardLinkDuplicates) time=\(formatNanoseconds(breakdown.hardLinkNanoseconds)); watchdog opens=\(breakdown.watchdogOpens) time=\(formatNanoseconds(breakdown.watchdogNanoseconds)) timeouts=\(breakdown.watchdogTimeouts); aggregation records=\(breakdown.aggregationRecords) time=\(formatNanoseconds(breakdown.aggregationNanoseconds)); largeFiles candidates=\(breakdown.largeFileCandidates) materialized=\(breakdown.largeFileEntriesMaterialized) rejectedBeforeMaterialization=\(breakdown.largeFileCandidatesRejectedBeforeMaterialization)")
    }

    private static func formatNanoseconds(_ value: UInt64) -> String {
        String(format: "%.6fs", Double(value) / 1_000_000_000)
    }
}

private struct RunnerError: Error, LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private enum HarnessProfile: String, CaseIterable {
    case equalScope = "equal-scope"
    case fullQuality = "full-quality"

    var includeSymbolicLinks: Bool { self == .fullQuality }
}

private struct HarnessFixture {
    let root: URL
    let outside: URL
    let denied: URL
    let expectedFileCount: UInt64
}

private struct HarnessNormalizedOutput: Codable {
    let fileCount: UInt64
    let directoryCount: UInt64
    let logicalBytes: UInt64
    let allocatedBytes: UInt64
    let topLargeFilePaths: [String]
    let issueKinds: [String]
}

private struct HarnessLexResult {
    let snapshot: DiskAnalysisSnapshot
    let wall: TimeInterval
    let normalizedOutputBytes: Int
}

private enum BenchmarkCacheState: String {
    case cold
    case warm
}

private enum BenchmarkArm: String {
    case lexCleaner = "LexCleaner"
    case mole = "Mole"
}

private enum BenchmarkRunStatus: String {
    case success
    case timeout
    case failure
}

private struct BenchmarkLexChildOutput: Codable {
    let completed: Bool
    let fileCount: UInt64
    let directoryCount: UInt64
    let logicalBytes: UInt64
    let allocatedBytes: UInt64
    let volumeCapacityBytes: UInt64?
    let internalCPUSeconds: Double
    let internalPeakRSSBytes: UInt64
}

private struct TimedBenchmarkProcess {
    let timedOut: Bool
    let wall: Double
    let userCPU: Double
    let systemCPU: Double
    let peakRSSBytes: UInt64
    let exitCode: Int32
    let stdout: Data
    let stderr: Data
}

private struct TimeMetrics {
    let user: Double
    let system: Double
    let peakRSSBytes: UInt64
}

private struct BenchmarkRunRecord {
    let state: BenchmarkCacheState
    let iteration: Int
    let arm: BenchmarkArm
    let status: BenchmarkRunStatus
    let wall: Double
    let userCPU: Double
    let systemCPU: Double
    let peakRSSBytes: UInt64
    let fileCount: UInt64?
    let directoryCount: UInt64?
    let logicalBytes: UInt64?
    let allocatedBytes: UInt64?
    let allocatedReported: Bool
    let exitCode: Int32
    let diagnostic: String
}

private struct BenchmarkSummary {
    let planned: Int
    let successes: Int
    let timeouts: Int
    let failures: Int
    let wallMedian: Double?
    let wallP95: Double?
    let wallP99: Double?
    let cpuMedian: Double?
    let rssMedian: UInt64?
    let filesRange: String
    let allocatedRange: String
    let allocatedReported: Bool
}

private struct DUObservation {
    let bytes: UInt64?
    let exitCode: Int32
    let complete: Bool
}

private final class ProcessWaitState: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)

    func signal() { semaphore.signal() }

    func wait(timeoutSeconds: Double) -> DispatchTimeoutResult {
        semaphore.wait(timeout: .now() + timeoutSeconds)
    }
}

private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func nextBool() -> Bool {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return ((value ^ (value >> 31)) & 1) == 1
    }
}

private struct HarnessMoleResult {
    let wall: TimeInterval
    let peakRSSMiB: String
    let totalSize: UInt64
    let totalFiles: UInt64
    let entryCount: Int
    let largeFileCount: Int
    let normalizedOutputBytes: Int
    let exitCode: Int32
}

private struct QualityMountedVolume {
    let image: URL
    let mountPoint: URL
    let deviceEntry: String
}

private struct ToolResult {
    let status: Int32
    let stdout: Data
    let stderr: Data
}

private actor UpdateCounter {
    private var value = 0
    func record(_ update: DiskAnalysisUpdate) { value += 1; _ = update }
    func count() -> Int { value }
}

private final class StageTimingRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let startedAt: Date
    private let rootPath: String
    private var firstUsable: TimeInterval?

    init(startedAt: Date, rootPath: String) {
        self.startedAt = startedAt
        self.rootPath = rootPath
    }

    func record(_ update: DiskAnalysisUpdate) {
        guard update.stage == .fastInventory, let node = update.node else { return }
        let isRootLevel = node.parentCanonicalPath?.path == rootPath || node.parentCanonicalPath == nil
        guard isRootLevel else { return }
        lock.lock()
        if firstUsable == nil {
            firstUsable = Date().timeIntervalSince(startedAt)
        }
        lock.unlock()
    }

    func value() -> TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        return firstUsable
    }
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
