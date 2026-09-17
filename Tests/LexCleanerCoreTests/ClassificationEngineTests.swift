import Foundation
import Darwin
import Testing
@testable import LexCleanerCore

@Suite("ClassificationEngine")
struct ClassificationEngineTests {
    @Test("protects a real system path")
    func protectsSystemPath() async throws {
        let path = URL(fileURLWithPath: "/System")
        var info = stat()
        guard lstat(path.path, &info) == 0 else { throw TestFailure("/System metadata unavailable") }
        let item = ScanItem(path: path, category: .userCache, fileType: .directory, sizeBytes: info.st_size > 0 ? UInt64(info.st_size) : 0, lastModified: Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)), riskLevel: .protected)
        let rule = CleanerRule(id: "system", name: "System", category: .userCache, sourceCategories: [.userCache], allowedRoots: [URL(fileURLWithPath: "/")], defaultSafetyLevel: .safe, cleanupReason: .regenerableCache, dataDisposition: .regenerableCache, agePolicy: .any)
        let candidate = await ClassificationEngine().classify(items: [item], rules: [rule]).candidates[0]
        #expect(candidate.safetyLevel == .protected)
    }

    @Test("unknown paths fail closed")
    func unknownPathsFailClosed() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LexCleanerClassificationXCTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("data".utf8).write(to: root)
        var info = stat()
        guard lstat(root.path, &info) == 0 else { throw TestFailure("fixture metadata unavailable") }
        let item = ScanItem(path: root, category: .temporaryFiles, fileType: .regularFile, sizeBytes: UInt64(info.st_size), lastModified: Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)), riskLevel: .low)
        let candidate = await ClassificationEngine().classify(items: [item], rules: []).candidates[0]
        #expect(candidate.safetyLevel == .unknown)
        #expect(candidate.estimatedReclaimableBytes == 0)
    }

    @Test("calibrated cache requires exact path and installed ownership")
    func calibratedCacheRequiresEvidence() async throws {
        let fixture = try makeCalibrationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let file = fixture.cacheRoot.appendingPathComponent("com.lexcleaner.fixture/fsCachedData/cache.bin")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("cache".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3 * 24 * 60 * 60)], ofItemAtPath: file.path)
        let candidate = await ClassificationEngine(applicationRoots: [fixture.applicationsRoot]).classify(items: [try makeItem(at: file)], rules: [fixture.rule]).candidates[0]
        #expect(candidate.safetyLevel == .safe)
        #expect(candidate.matchedRule == "calibrated-user-cache-fscached-data")
    }

    @Test("unowned cache remains review required")
    func unownedCacheRemainsReviewRequired() async throws {
        let fixture = try makeCalibrationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let file = fixture.cacheRoot.appendingPathComponent("com.unknown.app/fsCachedData/cache.bin")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("cache".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3 * 24 * 60 * 60)], ofItemAtPath: file.path)
        let candidate = await ClassificationEngine(applicationRoots: [fixture.applicationsRoot]).classify(items: [try makeItem(at: file)], rules: [fixture.rule]).candidates[0]
        #expect(candidate.safetyLevel == .reviewRequired)
        #expect(candidate.cleanupReason == .safeEvidenceInsufficient)
    }

    @Test("calibrated rule records complete evidence")
    func calibratedRuleRecordsEvidence() throws {
        let rule = try #require(CleanerRule.builtInRules().first(where: { $0.id == "calibrated-user-cache-fscached-data" }))
        let evidence = try #require(rule.safeEvidence)
        #expect(evidence.isComplete(for: rule))
        #expect(evidence.pathPattern.contains("fsCachedData"))
        #expect(evidence.confidence == .high)
    }

    @Test("non fsCachedData cache path is unknown")
    func nonFsCachedDataPathFailsClosed() async throws {
        let fixture = try makeCalibrationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let file = fixture.cacheRoot.appendingPathComponent("com.lexcleaner.fixture/Cache.db")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("database".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3 * 24 * 60 * 60)], ofItemAtPath: file.path)
        let candidate = await ClassificationEngine(applicationRoots: [fixture.applicationsRoot]).classify(items: [try makeItem(at: file)], rules: [fixture.rule]).candidates[0]
        #expect(candidate.safetyLevel == .unknown)
        #expect(candidate.cleanupReason == .unknownPath)
    }

    @Test("classification cancellation is observable and fail-safe")
    func classificationCancellationIsObservable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LexCleanerClassificationCancellation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("data".utf8).write(to: root)
        let item = try makeItem(at: root)
        let task = Task {
            await ClassificationEngine().classify(
                items: Array(repeating: item, count: 2_048),
                rules: []
            )
        }
        task.cancel()
        let result = await task.value
        #expect(result.cancelled)
        #expect(result.candidates.isEmpty)
        #expect(result.statistics.safeCount == 0)
    }

    @Test("Cleaner grouping and selection are stable and fail closed")
    func cleanerGroupingAndSelection() {
        let safeA = makeCandidate(path: "/tmp/a-cache", app: "com.example.app", category: .userCache, rule: "cache-rule", safety: .safe)
        let safeB = makeCandidate(path: "/tmp/b-cache", app: "com.example.app", category: .userCache, rule: "cache-rule", safety: .safe)
        let review = makeCandidate(path: "/tmp/review", app: "com.example.app", category: .userCache, rule: "cache-rule", safety: .reviewRequired)
        let protected = makeCandidate(path: "/tmp/protected", app: "com.example.app", category: .userCache, rule: "cache-rule", safety: .protected)
        let unknown = makeCandidate(path: "/tmp/unknown", app: nil, category: .unknown, rule: "none", safety: .unknown)
        let candidates = [unknown, protected, review, safeB, safeA]

        let groups = CleanerCandidateGroup.grouped(candidates)
        #expect(groups.map(\.id) == groups.sorted { $0.id < $1.id }.map(\.id))
        #expect(Set(groups.map(\.key.stableID)).count == 2)
        #expect(groups.contains { $0.safetyLevel == .reviewRequired && $0.candidates.count == 1 })
        #expect(CleanerGroupKey(candidate: safeA).stableID == CleanerGroupKey(candidate: safeA).stableID)

        var selection = CleanerSelectionState(candidates: candidates)
        #expect(selection.isSelected(safeA))
        #expect(selection.isSelected(safeB))
        #expect(!selection.isSelected(review))
        #expect(selection.state(for: try! #require(groups.first { $0.safetyLevel == .reviewRequired })) == .noneSelected)

        let safeGroup = try! #require(groups.first { $0.safetyLevel == .safe })
        selection.setSelected(false, for: safeGroup)
        #expect(selection.state(for: safeGroup) == .noneSelected)
        selection.setSelected(true, for: safeGroup)
        #expect(selection.state(for: safeGroup) == .allSelected)
        selection.setSelected(true, for: review)
        #expect(selection.state(for: try! #require(groups.first { $0.safetyLevel == .reviewRequired })) == .allSelected)

        let protectedGroup = try! #require(groups.first { $0.safetyLevel == .protected })
        let unknownGroup = try! #require(groups.first { $0.safetyLevel == .unknown })
        #expect(selection.state(for: protectedGroup) == .disabled)
        #expect(selection.state(for: unknownGroup) == .disabled)
        selection.setSelected(true, for: protected)
        selection.setSelected(true, for: unknown)
        #expect(!selection.isSelected(protected))
        #expect(!selection.isSelected(unknown))
    }

    private func makeCandidate(
        path: String,
        app: String?,
        category: CleanerCategory,
        rule: String,
        safety: CleanupSafetyLevel
    ) -> CleanerCandidate {
        CleanerCandidate(
            path: URL(fileURLWithPath: path),
            category: category,
            size: 1,
            modifiedAt: Date(timeIntervalSince1970: 1),
            owningApp: app,
            safetyLevel: safety,
            cleanupReason: safety == .safe ? .regenerableCache : .unknownDataDisposition,
            matchedRule: rule,
            matchedRuleIDs: [rule],
            estimatedReclaimableBytes: safety == .safe ? 1 : 0
        )
    }

    private struct CalibrationFixture {
        let root: URL
        let applicationsRoot: URL
        let cacheRoot: URL
        let rule: CleanerRule
    }

    private func makeCalibrationFixture() throws -> CalibrationFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LexCleanerClassificationXCTest-\(UUID().uuidString)", isDirectory: true)
        let applicationsRoot = root.appendingPathComponent("Applications", isDirectory: true)
        let home = root.appendingPathComponent("Home", isDirectory: true)
        let cacheRoot = home.appendingPathComponent("Library/Caches", isDirectory: true)
        let app = applicationsRoot.appendingPathComponent("Fixture.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents", isDirectory: true), withIntermediateDirectories: true)
        let info = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>com.lexcleaner.fixture</string></dict></plist>"
        try Data(info.utf8).write(to: app.appendingPathComponent("Contents/Info.plist"))
        return CalibrationFixture(root: root, applicationsRoot: applicationsRoot, cacheRoot: cacheRoot, rule: CleanerRule.builtInRules(homeDirectory: home, temporaryDirectory: root.appendingPathComponent("tmp"))[0])
    }

    private func makeItem(at path: URL) throws -> ScanItem {
        var info = stat()
        guard lstat(path.path, &info) == 0 else { throw TestFailure("fixture metadata unavailable") }
        let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000)
        return ScanItem(path: path, category: .userCache, fileType: .regularFile, sizeBytes: UInt64(info.st_size), lastModified: modified, riskLevel: .low)
    }
}

private struct TestFailure: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}
