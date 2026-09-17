import Foundation
import Darwin
import Testing
@testable import LexCleanerCore

@Suite("CleanupPlanner")
struct CleanupPlannerTests {
    @Test("creates a safe dry-run plan without mutating")
    func createsSafeDryRunPlan() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LexCleanerCleanupXCTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("cache.bin")
        try Data("cache".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3 * 24 * 60 * 60)], ofItemAtPath: file.path)
        var info = stat()
        guard lstat(file.path, &info) == 0 else { throw TestFailure() }
        let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000)
        let candidate = CleanerCandidate(path: file, category: .userCache, size: UInt64(info.st_size), modifiedAt: modified, owningApp: nil, safetyLevel: .safe, cleanupReason: .regenerableCache, matchedRule: "test-rule", matchedRuleIDs: ["test-rule"], estimatedReclaimableBytes: UInt64(info.st_size))
        let rule = CleanerRule(id: "test-rule", name: "Test", category: .userCache, sourceCategories: [.userCache], allowedRoots: [root], defaultSafetyLevel: .safe, cleanupReason: .regenerableCache, dataDisposition: .regenerableCache, agePolicy: .olderThan(24 * 60 * 60), sizePolicy: SizePolicy(minimumBytes: 1))
        let engine = SafeDeleteEngine(policy: SafeDeletePolicy(whitelistedRoots: [root]), logger: InMemorySafeDeleteLogger())
        let planner = CleanupPlanner(safeDeleteEngine: engine, classificationRules: [rule])
        let plan = await planner.makePlan(candidates: [candidate], selection: CleanupSelection())
        let dryRun = await planner.dryRun(plan: plan)
        #expect(dryRun.processCount == 1)
        #expect(dryRun.processBytes == UInt64(info.st_size))
        #expect(FileManager.default.fileExists(atPath: file.path))

        let explicitlyConfirmedButDeselected = await planner.makePlan(
            candidates: [candidate],
            selection: CleanupSelection(userConfirmed: true)
        )
        #expect(explicitlyConfirmedButDeselected.eligibleCount == 0)
        #expect(explicitlyConfirmedButDeselected.items[0].rejectionReason == .notSelected)
    }
}

private struct TestFailure: Error {}
