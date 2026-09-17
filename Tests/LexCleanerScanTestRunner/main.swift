import Foundation
@_spi(Testing) import LexCleanerCore

@main
struct LexCleanerScanTestRunner {
    private struct Fixture {
        let directory: URL
        let rule: ScanRule
        let target: ScanTarget
    }

    static func main() async {
        let tests: [(String, () async throws -> Void)] = [
            ("ordinary directory and metadata", testOrdinaryDirectory),
            ("empty directory", testEmptyDirectory),
            ("large directory", testLargeDirectory),
            ("symlink is a leaf", testSymlink),
            ("symlink loop is bounded", testSymlinkLoop),
            ("permission error is recorded", testPermissionError),
            ("duplicate paths are skipped", testDuplicatePaths),
            ("cancellation is reported", testCancellation),
            ("missing path is recorded", testMissingPath),
            ("system path is protected", testSystemPath),
            ("personal data path is protected", testPersonalDataPath),
            ("application cache matcher is restrictive", testApplicationCacheMatcher)
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

    private static func makeFixture(
        matcher: ScanPathMatcher = .all,
        category: ScanCategory = .userCache,
        riskLevel: ScanRiskLevel = .low
    ) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LexCleanerScan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let rule = ScanRule(id: "test-rule", category: category, riskLevel: riskLevel, allowedRoots: [directory], matcher: matcher)
        return Fixture(directory: directory, rule: rule, target: ScanTarget(url: directory, ruleID: rule.id))
    }

    private static func withFixture(_ operation: (Fixture) async throws -> Void) async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try await operation(fixture)
    }

    private static func scan(
        _ fixture: Fixture,
        engine: ScanEngine = ScanEngine(maxConcurrentDirectories: 2),
        progress: (@Sendable (ScanProgress) async -> Void)? = nil
    ) async -> ScanResult {
        await engine.scan(targets: [fixture.target], rules: [fixture.rule], progress: progress)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw TestFailure(message) }
    }

    private static func testOrdinaryDirectory() async throws {
        try await withFixture { fixture in
            let nested = fixture.directory.appendingPathComponent("nested", isDirectory: true)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            let first = fixture.directory.appendingPathComponent("first.txt")
            let second = nested.appendingPathComponent("second.log")
            try Data("one".utf8).write(to: first)
            try Data("two-two".utf8).write(to: second)
            let collector = ItemCollector()
            let result = await scan(fixture) { progress in if let item = progress.item { await collector.append(item) } }
            let items = await collector.items()
            try require(result.fileCount == 2, "file count mismatch")
            try require(result.directoryCount == 2, "directory count mismatch")
            try require(result.issues.isEmpty, "ordinary scan reported issues")
            try require(items.contains(where: { $0.fileType == .regularFile && $0.path.lastPathComponent == "first.txt" }), "file metadata missing")
            try require(items.contains(where: { $0.fileType == .directory && $0.path.lastPathComponent == "nested" }), "directory metadata missing")
            try require(items.contains(where: { $0.lastModified != nil }), "modification time missing")
        }
    }

    private static func testEmptyDirectory() async throws {
        try await withFixture { fixture in
            let result = await scan(fixture)
            try require(result.fileCount == 0, "empty directory has files")
            try require(result.directoryCount == 1, "root directory was not measured")
            try require(result.issues.isEmpty, "empty directory reported issues")
        }
    }

    private static func testLargeDirectory() async throws {
        try await withFixture { fixture in
            let fileCount = 5_000
            let payload = Data(repeating: 65, count: 64)
            for directoryIndex in 0..<8 {
                let directory = fixture.directory.appendingPathComponent("bucket-\(directoryIndex)", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                for fileIndex in 0..<625 {
                    try payload.write(to: directory.appendingPathComponent("item-\(fileIndex).dat"))
                }
            }
            let started = Date()
            let result = await scan(fixture)
            let wallDuration = Date().timeIntervalSince(started)
            print("LARGE_RESULT files=\(result.fileCount) visited=\(result.visitedPathCount) duration=\(result.performance.duration) wall=\(wallDuration) peakRSS=\(result.performance.peakResidentMemoryBytes) samples=\(result.performance.memorySamples.count)")
            try require(result.fileCount == UInt64(fileCount), "large file count mismatch")
            try require(result.performance.memorySamples.count > 0, "memory trend was not recorded")
            try require(result.performance.maxObservedConcurrentDirectories <= 2, "concurrency limit exceeded")
            try require(result.performance.maxObservedConcurrentDirectories == 2, "concurrency limit was not exercised")
        }
    }

    private static func testSymlink() async throws {
        try await withFixture { fixture in
            let real = fixture.directory.appendingPathComponent("real.txt")
            let outside = FileManager.default.temporaryDirectory.appendingPathComponent("LexCleanerScanOutside-\(UUID().uuidString)")
            try Data("real".utf8).write(to: real)
            try Data("outside".utf8).write(to: outside)
            defer { try? FileManager.default.removeItem(at: outside) }
            try FileManager.default.createSymbolicLink(at: fixture.directory.appendingPathComponent("internal-link"), withDestinationURL: real)
            try FileManager.default.createSymbolicLink(at: fixture.directory.appendingPathComponent("outside-link"), withDestinationURL: outside)
            let result = await scan(fixture)
            try require(result.fileCount == 3, "symlink leaves were not counted")
            try require(result.issues.contains(where: { $0.kind == .symlinkSkipped }), "internal symlink was not recorded")
            try require(result.issues.contains(where: { $0.kind == .symlinkEscape }), "escaping symlink was not recorded")
        }
    }

    private static func testSymlinkLoop() async throws {
        try await withFixture { fixture in
            let loop = fixture.directory.appendingPathComponent("loop")
            try FileManager.default.createSymbolicLink(at: loop, withDestinationURL: fixture.directory)
            let result = await scan(fixture)
            try require(!result.cancelled, "symlink loop cancelled the scan")
            try require(result.issues.contains(where: { $0.kind == .symlinkSkipped }), "symlink loop was not skipped")
        }
    }

    private static func testPermissionError() async throws {
        try await withFixture { fixture in
            let restricted = fixture.directory.appendingPathComponent("restricted", isDirectory: true)
            try FileManager.default.createDirectory(at: restricted, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: restricted.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: restricted.path) }
            let result = await scan(fixture)
            try require(result.issues.contains(where: { $0.path == restricted.standardizedFileURL && ($0.kind == .permissionDenied || $0.kind == .enumerationFailed) }), "permission issue was not recorded")
        }
    }

    private static func testDuplicatePaths() async throws {
        try await withFixture { fixture in
            let engine = ScanEngine(maxConcurrentDirectories: 2)
            let result = await engine.scan(
                targets: [fixture.target, fixture.target],
                rules: [fixture.rule]
            )
            try require(result.issues.contains(where: { $0.kind == .duplicatePath }), "duplicate path was not recorded")
        }
    }

    private static func testCancellation() async throws {
        try await withFixture { fixture in
            for directoryIndex in 0..<600 {
                let directory = fixture.directory.appendingPathComponent("dir-\(directoryIndex)", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                for fileIndex in 0..<20 {
                    try Data(repeating: 66, count: 32).write(to: directory.appendingPathComponent("file-\(fileIndex)"))
                }
            }
            let gate = CancellationGate()
            let task = Task {
                await ScanEngine(maxConcurrentDirectories: 2).scan(targets: [fixture.target], rules: [fixture.rule]) { _ in
                    await gate.signal()
                    await gate.waitForRelease()
                }
            }
            await gate.waitForSignal()
            task.cancel()
            await gate.release()
            let result = await task.value
            try require(result.cancelled, "cancelled scan did not report cancellation")
            try require(result.issues.contains(where: { $0.kind == .cancelled }), "cancellation issue was not recorded")
        }
    }

    private static func testMissingPath() async throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("LexCleanerScanMissing-\(UUID().uuidString)")
        let rule = ScanRule(id: "missing", category: .temporaryFiles, riskLevel: .low, allowedRoots: [FileManager.default.temporaryDirectory])
        let result = await ScanEngine().scan(targets: [ScanTarget(url: missing, ruleID: rule.id)], rules: [rule])
        try require(result.issues.contains(where: { $0.kind == .notFound }), "missing path was not recorded")
    }

    private static func testSystemPath() async throws {
        let rule = ScanRule(id: "system", category: .temporaryFiles, riskLevel: .protected, allowedRoots: [URL(fileURLWithPath: "/")])
        let result = await ScanEngine().scan(targets: [ScanTarget(url: URL(fileURLWithPath: "/System"), ruleID: rule.id)], rules: [rule])
        try require(result.issues.contains(where: { $0.kind == .excludedPath || $0.kind == .protectedPath }), "system path was not protected")
        try require(result.visitedPathCount == 0, "system path was scanned")
    }

    private static func testPersonalDataPath() async throws {
        let documents = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
        let rule = ScanRule(id: "personal", category: .userCache, riskLevel: .protected, allowedRoots: [FileManager.default.homeDirectoryForCurrentUser])
        let result = await ScanEngine().scan(targets: [ScanTarget(url: documents, ruleID: rule.id)], rules: [rule])
        try require(result.issues.contains(where: { $0.kind == .excludedPath || $0.kind == .protectedPath }), "Documents was not protected")
        try require(result.visitedPathCount == 0, "personal data path was scanned")
    }

    private static func testApplicationCacheMatcher() async throws {
        let fixture = try makeFixture(matcher: .directoryNames(names: ["Cache"], maxDiscoveryDepth: 2), category: .applicationCache, riskLevel: .review)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let app = fixture.directory.appendingPathComponent("ExampleApp", isDirectory: true)
        let cache = app.appendingPathComponent("Cache", isDirectory: true)
        let personal = app.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: personal, withIntermediateDirectories: true)
        try Data("cache".utf8).write(to: cache.appendingPathComponent("cache.db"))
        try Data("personal".utf8).write(to: personal.appendingPathComponent("data.db"))
        let result = await scan(fixture)
        try require(result.fileCount == 1, "application cache matcher scanned personal app data")
        try require(result.issues.isEmpty, "application cache matcher reported issues")
    }
}

private actor ItemCollector {
    private var stored: [ScanItem] = []
    func append(_ item: ScanItem) { stored.append(item) }
    func items() -> [ScanItem] { stored }
}

private actor CancellationGate {
    private var didSignal = false
    private var didRelease = false

    func signal() { didSignal = true }
    func release() { didRelease = true }

    func waitForSignal() async {
        while !didSignal {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    func waitForRelease() async {
        while !didRelease {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}
