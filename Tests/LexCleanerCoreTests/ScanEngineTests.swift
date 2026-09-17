import Foundation
import Testing
@_spi(Testing) @testable import LexCleanerCore

@Suite("ScanEngine")
struct ScanEngineTests {
    @Test("scans files, directories, metadata and progress")
    func scansMetadata() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let nested = fixture.directory.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("content".utf8).write(to: nested.appendingPathComponent("item.txt"))
        let rule = ScanRule(id: "test", category: .userCache, riskLevel: .low, allowedRoots: [fixture.directory])
        let collector = ItemCollector()
        let result = await ScanEngine(maxConcurrentDirectories: 2).scan(
            targets: [ScanTarget(url: fixture.directory, ruleID: rule.id)],
            rules: [rule]
        ) { progress in
            if let item = progress.item { await collector.append(item) }
        }
        let items = await collector.items()
        #expect(result.fileCount == 1)
        #expect(result.directoryCount == 2)
        #expect(items.contains { $0.fileType == .regularFile && $0.lastModified != nil })
        #expect(result.performance.memorySamples.count > 0)
    }

    @Test("does not recurse through symlink loops")
    func skipsSymlinkLoop() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try FileManager.default.createSymbolicLink(
            at: fixture.directory.appendingPathComponent("loop"),
            withDestinationURL: fixture.directory
        )
        let rule = ScanRule(id: "test", category: .temporaryFiles, riskLevel: .low, allowedRoots: [fixture.directory])
        let result = await ScanEngine().scan(
            targets: [ScanTarget(url: fixture.directory, ruleID: rule.id)],
            rules: [rule]
        )
        #expect(!result.cancelled)
        #expect(result.issues.contains { $0.kind == .symlinkSkipped })
    }

    @Test("deduplicates targets and protects personal directories")
    func deduplicatesAndProtects() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let rule = ScanRule(id: "test", category: .userCache, riskLevel: .low, allowedRoots: [fixture.directory])
        let duplicateResult = await ScanEngine().scan(
            targets: [ScanTarget(url: fixture.directory, ruleID: rule.id), ScanTarget(url: fixture.directory, ruleID: rule.id)],
            rules: [rule]
        )
        #expect(duplicateResult.issues.contains { $0.kind == .duplicatePath })

        let documents = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
        let personalRule = ScanRule(id: "personal", category: .userCache, riskLevel: .protected, allowedRoots: [FileManager.default.homeDirectoryForCurrentUser])
        let personalResult = await ScanEngine().scan(
            targets: [ScanTarget(url: documents, ruleID: personalRule.id)],
            rules: [personalRule]
        )
        #expect(personalResult.visitedPathCount == 0)
        #expect(personalResult.issues.contains { $0.kind == .excludedPath || $0.kind == .protectedPath })
    }

    private struct Fixture {
        let directory: URL
    }

    private func makeFixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LexCleanerScanXCTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return Fixture(directory: directory)
    }
}

private actor ItemCollector {
    private var stored: [ScanItem] = []
    func append(_ item: ScanItem) { stored.append(item) }
    func items() -> [ScanItem] { stored }
}
