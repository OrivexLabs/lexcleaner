import Foundation
import Darwin
@_spi(Testing) import LexCleanerCore

@main
struct LexCleanerCoreTestRunner {
    private struct Fixture {
        let directory: URL
        let logger: InMemorySafeDeleteLogger
        let engine: SafeDeleteEngine
    }

    static func main() async {
        let tests: [(String, () async throws -> Void)] = [
            ("dry run assesses and does not mutate", testDryRun),
            ("trash mode moves a real file to Trash", testTrashMode),
            ("empty path is rejected", testEmptyPath),
            ("relative path is rejected", testRelativePath),
            ("filesystem root is rejected", testRoot),
            ("home directory is rejected", testHome),
            ("system critical directory is rejected", testSystemCritical),
            ("path outside whitelist is rejected", testOutsideWhitelist),
            ("escaping symlink is rejected", testEscapingSymlink),
            ("internal symlink is elevated", testInternalSymlink),
            ("missing path is rejected", testMissingPath),
            ("rejected operation is logged", testRejectedOperationIsLogged),
            ("path replacement is rejected fail-closed", testPathReplacementIsRejected)
        ]
        var passed = 0
        for (name, test) in tests {
            do { try await test(); print("PASS  \(name)"); passed += 1 }
            catch { print("FAIL  \(name): \(error)") }
        }
        print("RESULT  \(passed)/\(tests.count) passed")
        if passed != tests.count { exit(1) }
    }

    private static func makeFixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LexCleanerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let logger = InMemorySafeDeleteLogger()
        return Fixture(directory: directory, logger: logger, engine: SafeDeleteEngine(policy: SafeDeletePolicy(whitelistedRoots: [directory]), logger: logger))
    }

    private static func withFixture(_ operation: (Fixture) async throws -> Void) async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try await operation(fixture)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw TestFailure(message) }
    }

    private static func requireError(_ expected: SafeDeleteError, operation: () async throws -> Void) async throws {
        do {
            try await operation()
            throw TestFailure("expected \(expected), operation succeeded")
        } catch let error as SafeDeleteError {
            try require(error == expected, "expected \(expected), got \(error)")
        }
    }

    private static func testDryRun() async throws {
        try await withFixture { fixture in
            let target = fixture.directory.appendingPathComponent("cache.txt")
            try Data("real test data".utf8).write(to: target)
            let result = try await fixture.engine.delete(path: target.path, mode: .dryRun)
            try require(result.action == .wouldMoveToTrash, "wrong dry-run action")
            try require(FileManager.default.fileExists(atPath: target.path), "dry run mutated the file")
            let entries = await fixture.logger.allEntries()
            try require(entries.count == 1 && entries.first?.outcome == .dryRun, "dry-run log missing")
        }
    }

    private static func testTrashMode() async throws {
        try await withFixture { fixture in
            let target = fixture.directory.appendingPathComponent("trash-me.txt")
            try Data("trash me".utf8).write(to: target)
            let result = try await fixture.engine.delete(path: target.path, mode: .trash)
            try require(result.action == .movedToTrash, "wrong trash action")
            try require(!FileManager.default.fileExists(atPath: target.path), "file remained at original path")
            let entries = await fixture.logger.allEntries()
            try require(entries.last?.outcome == .trashed, "trash log missing")
        }
    }

    private static func testEmptyPath() async throws { try await withFixture { f in try await requireError(.emptyPath) { _ = try await f.engine.delete(path: "   ") } } }
    private static func testRelativePath() async throws { try await withFixture { f in try await requireError(.relativePath) { _ = try await f.engine.delete(path: "Library/Caches") } } }
    private static func testRoot() async throws { try await withFixture { f in try await requireError(.rootDeletionForbidden) { _ = try await f.engine.delete(path: "/") } } }

    private static func testHome() async throws {
        try await withFixture { fixture in
            let home = FileManager.default.homeDirectoryForCurrentUser
            let engine = SafeDeleteEngine(policy: SafeDeletePolicy(whitelistedRoots: [home], homeDirectory: home), logger: fixture.logger)
            try await requireError(.homeDeletionForbidden) { _ = try await engine.delete(path: home.path) }
        }
    }

    private static func testSystemCritical() async throws {
        try await withFixture { fixture in
            let engine = SafeDeleteEngine(policy: SafeDeletePolicy(whitelistedRoots: [URL(fileURLWithPath: "/")]), logger: fixture.logger)
            try await requireError(.protectedPath(URL(fileURLWithPath: "/System"))) { _ = try await engine.delete(path: "/System") }
        }
    }

    private static func testOutsideWhitelist() async throws {
        try await withFixture { fixture in
            let outside = FileManager.default.temporaryDirectory.appendingPathComponent("LexCleanerOutside-\(UUID().uuidString)")
            try Data("outside".utf8).write(to: outside)
            defer { try? FileManager.default.removeItem(at: outside) }
            try await requireError(.notWhitelisted(outside.standardizedFileURL)) { _ = try await fixture.engine.delete(path: outside.path) }
        }
    }

    private static func testEscapingSymlink() async throws {
        try await withFixture { fixture in
            let outsideDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("LexCleanerSymlinkOutside-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: outsideDirectory) }
            let outsideFile = outsideDirectory.appendingPathComponent("secret.txt")
            try Data("secret".utf8).write(to: outsideFile)
            let link = fixture.directory.appendingPathComponent("link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outsideFile)
            try await requireError(.symlinkEscape(link.standardizedFileURL, canonicalURL(outsideFile))) { _ = try await fixture.engine.delete(path: link.path) }
            try require(FileManager.default.fileExists(atPath: outsideFile.path), "outside target was changed")
        }
    }

    private static func testInternalSymlink() async throws {
        try await withFixture { fixture in
            let realFile = fixture.directory.appendingPathComponent("real.txt")
            try Data("real".utf8).write(to: realFile)
            let link = fixture.directory.appendingPathComponent("internal-link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: realFile)
            let assessment = try await fixture.engine.assess(path: link.path)
            try require(assessment.containsSymlink && assessment.riskLevel == .elevated, "internal symlink risk was not elevated")
            try require(assessment.resolvedPath == canonicalURL(realFile), "symlink was not resolved")
        }
    }

    private static func testMissingPath() async throws { try await withFixture { fixture in let missing = fixture.directory.appendingPathComponent("missing"); try await requireError(.notFound) { _ = try await fixture.engine.delete(path: missing.path) } } }

    private static func testRejectedOperationIsLogged() async throws {
        try await withFixture { fixture in
            try await requireError(.rootDeletionForbidden) { _ = try await fixture.engine.delete(path: "/") }
            let entries = await fixture.logger.allEntries()
            try require(entries.last?.outcome == .rejected, "rejection was not logged")
        }
    }

    private static func testPathReplacementIsRejected() async throws {
        try await withFixture { fixture in
            let target = fixture.directory.appendingPathComponent("replace-me.txt")
            try Data("original".utf8).write(to: target)
            let replacer = RealPathReplacer()
            let engine = SafeDeleteEngine(
                policy: SafeDeletePolicy(whitelistedRoots: [fixture.directory]),
                logger: fixture.logger,
                preExecutionObserver: { path in await replacer.replace(at: path) }
            )

            try await requireError(.pathChanged) { _ = try await engine.delete(path: target.path, mode: .trash) }
            try require(FileManager.default.fileExists(atPath: target.path), "replacement was moved to Trash")
            let replacementContents = String(data: try Data(contentsOf: target), encoding: .utf8)
            try require(replacementContents == "replacement", "replacement contents changed")
            let entries = await fixture.logger.allEntries()
            try require(entries.last?.outcome == .rejected, "path change was not logged as a rejection")
        }
    }

    private static func canonicalURL(_ url: URL) -> URL {
        guard let resolved = realpath(url.path, nil) else { return url.standardizedFileURL }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved))
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

private actor RealPathReplacer {
    private var didReplace = false

    func replace(at path: URL) {
        guard !didReplace else { return }
        didReplace = true
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: path)
        try? Data("replacement".utf8).write(to: path)
    }
}
