import Foundation
import Darwin
import Testing
@_spi(Testing) @testable import LexCleanerCore

@Suite("SafeDeleteEngine")
struct SafeDeleteEngineTests {
    @Test("dry run assesses and does not mutate")
    func dryRunAssessesAndDoesNotMutate() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let target = fixture.directory.appendingPathComponent("cache.txt")
        try Data("real test data".utf8).write(to: target)

        let result = try await fixture.engine.delete(path: target.path, mode: .dryRun)

        #expect(result.action == .wouldMoveToTrash)
        #expect(FileManager.default.fileExists(atPath: target.path))
        let entries = await fixture.logger.allEntries()
        #expect(entries.count == 1)
        #expect(entries.first?.outcome == .dryRun)
    }

    @Test("trash mode moves a real file to Trash")
    func trashModeMovesRealFileToTrash() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let target = fixture.directory.appendingPathComponent("trash-me.txt")
        try Data("trash me".utf8).write(to: target)

        let result = try await fixture.engine.delete(path: target.path, mode: .trash)

        #expect(result.action == .movedToTrash)
        #expect(!FileManager.default.fileExists(atPath: target.path))
        let entries = await fixture.logger.allEntries()
        #expect(entries.last?.outcome == .trashed)
    }

    @Test("empty path is rejected")
    func rejectsEmptyPath() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        await assertError(.emptyPath) { _ = try await fixture.engine.delete(path: "   ", mode: .dryRun) }
    }

    @Test("relative path is rejected")
    func rejectsRelativePath() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        await assertError(.relativePath) { _ = try await fixture.engine.delete(path: "Library/Caches", mode: .dryRun) }
    }

    @Test("filesystem root is rejected")
    func rejectsRoot() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        await assertError(.rootDeletionForbidden) { _ = try await fixture.engine.delete(path: "/", mode: .dryRun) }
    }

    @Test("home directory is rejected")
    func rejectsHomeDirectory() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let policy = SafeDeletePolicy(whitelistedRoots: [home], homeDirectory: home)
        let homeEngine = SafeDeleteEngine(policy: policy, logger: fixture.logger)
        await assertError(.homeDeletionForbidden) { _ = try await homeEngine.delete(path: home.path, mode: .dryRun) }
    }

    @Test("system critical directory is rejected even when whitelisted")
    func rejectsSystemCriticalDirectoryEvenWhenWhitelisted() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let policy = SafeDeletePolicy(whitelistedRoots: [URL(fileURLWithPath: "/")])
        let systemEngine = SafeDeleteEngine(policy: policy, logger: fixture.logger)
        await assertError(.protectedPath(URL(fileURLWithPath: "/System"))) { _ = try await systemEngine.delete(path: "/System", mode: .dryRun) }
    }

    @Test("path outside whitelist is rejected")
    func rejectsPathOutsideWhitelist() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("LexCleanerOutside-\(UUID().uuidString)")
        try Data("outside".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        await assertError(.notWhitelisted(outside.standardizedFileURL)) { _ = try await fixture.engine.delete(path: outside.path, mode: .dryRun) }
    }

    @Test("symlink escaping whitelist is rejected")
    func rejectsSymlinkEscapingWhitelist() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let outsideDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("LexCleanerSymlinkOutside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outsideDirectory) }
        let outsideFile = outsideDirectory.appendingPathComponent("secret.txt")
        try Data("secret".utf8).write(to: outsideFile)
        let link = fixture.directory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outsideFile)

        await assertError(.symlinkEscape(link.standardizedFileURL, canonicalURL(outsideFile))) { _ = try await fixture.engine.delete(path: link.path, mode: .dryRun) }
        #expect(FileManager.default.fileExists(atPath: outsideFile.path))
    }

    @Test("internal symlink is allowed with elevated risk")
    func allowsSymlinkWithinWhitelistAndMarksElevatedRisk() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let realFile = fixture.directory.appendingPathComponent("real.txt")
        try Data("real".utf8).write(to: realFile)
        let link = fixture.directory.appendingPathComponent("internal-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: realFile)

        let assessment = try await fixture.engine.assess(path: link.path)

        #expect(assessment.containsSymlink)
        #expect(assessment.riskLevel == .elevated)
        #expect(assessment.resolvedPath == canonicalURL(realFile))
    }

    @Test("missing path is rejected")
    func rejectsMissingPath() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let missing = fixture.directory.appendingPathComponent("missing")
        await assertError(.notFound) { _ = try await fixture.engine.delete(path: missing.path, mode: .dryRun) }
    }

    @Test("rejected operation is logged")
    func rejectedOperationIsLogged() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        await assertError(.rootDeletionForbidden) { _ = try await fixture.engine.delete(path: "/", mode: .dryRun) }
        let entries = await fixture.logger.allEntries()
        #expect(entries.last?.outcome == .rejected)
    }

    @Test("path replacement is rejected fail-closed")
    func pathReplacementIsRejected() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let target = fixture.directory.appendingPathComponent("replace-me.txt")
        try Data("original".utf8).write(to: target)
        let replacer = RealPathReplacer()
        let engine = SafeDeleteEngine(
            policy: SafeDeletePolicy(whitelistedRoots: [fixture.directory]),
            logger: fixture.logger,
            preExecutionObserver: { path in await replacer.replace(at: path) }
        )

        await assertError(.pathChanged) { _ = try await engine.delete(path: target.path, mode: .trash) }
        #expect(FileManager.default.fileExists(atPath: target.path))
        let replacementContents = String(data: try Data(contentsOf: target), encoding: .utf8)
        #expect(replacementContents == "replacement")
        let entries = await fixture.logger.allEntries()
        #expect(entries.last?.outcome == .rejected)
    }

    private struct Fixture {
        let directory: URL
        let logger: InMemorySafeDeleteLogger
        let engine: SafeDeleteEngine
    }

    private func makeFixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LexCleanerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let logger = InMemorySafeDeleteLogger()
        let engine = SafeDeleteEngine(policy: SafeDeletePolicy(whitelistedRoots: [directory]), logger: logger)
        return Fixture(directory: directory, logger: logger, engine: engine)
    }

    private func assertError(_ expected: SafeDeleteError, operation: @escaping () async throws -> Void) async {
        do {
            try await operation()
            Issue.record("Expected error \(expected), but operation succeeded")
        } catch let error as SafeDeleteError {
            #expect(error == expected)
        } catch {
            Issue.record("Expected SafeDeleteError, got \(error)")
        }
    }

    private func canonicalURL(_ url: URL) -> URL {
        guard let resolved = realpath(url.path, nil) else { return url.standardizedFileURL }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved))
    }
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
