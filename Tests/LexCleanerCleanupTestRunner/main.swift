import Foundation
import Darwin
@_spi(Testing) import LexCleanerCore

@main
struct LexCleanerCleanupTestRunner {
    private static let testNow = Date().addingTimeInterval(-3 * 24 * 60 * 60)

    static func main() async {
        let tests: [(String, () async throws -> Void)] = [
            ("safe candidate enters plan", testSafeCandidate),
            ("review candidate without selection is rejected", testReviewWithoutSelection),
            ("review candidate with explicit selection enters plan", testReviewWithSelection),
            ("protected candidate is rejected", testProtectedCandidate),
            ("unknown candidate is rejected", testUnknownCandidate),
            ("malformed safe candidate fails closed", testMalformedSafeCandidate),
            ("source change before plan is rejected", testSourceChangedBeforePlan),
            ("inode replacement fails preflight", testInodeReplacement),
            ("symlink replacement fails preflight", testSymlinkReplacement),
            ("plan file change fails preflight", testPlanFileChange),
            ("dry run does not mutate", testDryRun),
            ("duplicate candidates are rejected independently", testDuplicateCandidate),
            ("partial failure is isolated", testPartialFailure),
            ("cancelled execution skips items", testCancellation),
            ("Trash failure is recorded", testTrashFailure),
            ("real scan classify plan preflight and Trash", testControlledRealPipeline)
        ]

        var passed = 0
        for (name, test) in tests {
            do {
                try await test()
                print("PASS  " + name)
                passed += 1
            } catch {
                print("FAIL  " + name + ": " + String(describing: error))
            }
        }
        print("RESULT  " + String(passed) + "/" + String(tests.count) + " passed")
        if passed != tests.count { exit(1) }
    }

    private static func testSafeCandidate() async throws {
        try await withFixture { fixture in
            let file = fixture.root.appendingPathComponent("safe.cache")
            try write("safe", to: file)
            let candidate = try makeCandidate(path: file, safety: .safe, reason: .regenerableCache)
            let plan = await fixture.planner.makePlan(candidates: [candidate], selection: CleanupSelection())
            try require(plan.eligibleCount == 1, "safe candidate was not eligible")
            try require(plan.items[0].explicitlySelected == false, "safe candidate was falsely marked explicitly selected")
        }
    }

    private static func testReviewWithoutSelection() async throws {
        try await withFixture { fixture in
            let file = fixture.root.appendingPathComponent("review.cache")
            try write("review", to: file)
            let candidate = try makeCandidate(path: file, safety: .reviewRequired, reason: .applicationCacheNeedsReview)
            let plan = await fixture.planner.makePlan(candidates: [candidate], selection: CleanupSelection())
            try require(plan.eligibleCount == 0, "unselected review item entered execution plan")
            try require(plan.items[0].rejectionReason == .notSelected, "wrong review rejection reason")
        }
    }

    private static func testReviewWithSelection() async throws {
        try await withFixture { fixture in
            let file = fixture.root.appendingPathComponent("review-selected.cache")
            try write("review", to: file)
            let candidate = try makeCandidate(path: file, safety: .reviewRequired, reason: .applicationCacheNeedsReview)
            let selection = CleanupSelection(selectedPaths: [file], userConfirmed: true)
            let plan = await fixture.planner.makePlan(candidates: [candidate], selection: selection)
            try require(plan.eligibleCount == 1, "explicitly selected review item was not eligible")
            try require(plan.items[0].explicitlySelected, "selection was not recorded")
        }
    }

    private static func testProtectedCandidate() async throws {
        try await withFixture { fixture in
            let file = fixture.root.appendingPathComponent("protected.cache")
            try write("protected", to: file)
            let candidate = try makeCandidate(path: file, safety: .protected, reason: .userDataProtected)
            let plan = await fixture.planner.makePlan(candidates: [candidate], selection: CleanupSelection(selectedPaths: [file], userConfirmed: true))
            try require(plan.eligibleCount == 0, "protected item entered execution plan")
            try require(plan.items[0].rejectionReason == .protected, "wrong protected rejection reason")
        }
    }

    private static func testUnknownCandidate() async throws {
        try await withFixture { fixture in
            let file = fixture.root.appendingPathComponent("unknown.cache")
            try write("unknown", to: file)
            let candidate = try makeCandidate(path: file, safety: .unknown, reason: .unknownPath)
            let plan = await fixture.planner.makePlan(candidates: [candidate], selection: CleanupSelection(selectedPaths: [file], userConfirmed: true))
            try require(plan.eligibleCount == 0, "unknown item entered execution plan")
            try require(plan.items[0].rejectionReason == .unknown, "wrong unknown rejection reason")
        }
    }

    private static func testMalformedSafeCandidate() async throws {
        try await withFixture { fixture in
            let file = fixture.root.appendingPathComponent("malformed.cache")
            try write("malformed", to: file)
            let base = try makeCandidate(path: file, safety: .safe, reason: .regenerableCache)
            let candidate = CleanerCandidate(path: base.path, category: .unknown, size: base.size, modifiedAt: base.modifiedAt, owningApp: nil, safetyLevel: .safe, cleanupReason: .regenerableCache, matchedRule: "fixture-rule", matchedRuleIDs: ["fixture-rule"], estimatedReclaimableBytes: base.size)
            let plan = await fixture.planner.makePlan(candidates: [candidate], selection: CleanupSelection())
            try require(plan.eligibleCount == 0, "malformed safe candidate entered execution plan")
            try require(plan.items[0].rejectionReason == .invalidCandidate, "wrong malformed candidate reason")
        }
    }

    private static func testSourceChangedBeforePlan() async throws {
        try await withFixture { fixture in
            let file = fixture.root.appendingPathComponent("changed-before-plan.cache")
            try write("before", to: file)
            let candidate = try makeCandidate(path: file, safety: .safe, reason: .regenerableCache)
            try write("after with different size", to: file)
            let plan = await fixture.planner.makePlan(candidates: [candidate], selection: CleanupSelection())
            try require(plan.eligibleCount == 0, "changed source entered plan")
            try require(plan.items[0].rejectionReason == .sourceChanged, "wrong source change reason")
        }
    }

    private static func testInodeReplacement() async throws {
        try await withFixture { fixture in
            let file = fixture.root.appendingPathComponent("inode.cache")
            try write("same-size", to: file)
            let candidate = try makeCandidate(path: file, safety: .safe, reason: .regenerableCache)
            let plan = await fixture.planner.makePlan(candidates: [candidate], selection: CleanupSelection())
            try FileManager.default.removeItem(at: file)
            try write("same-size", to: file)
            let preflight = await fixture.planner.preflight(plan: plan, checkedAt: testNow)
            try require(preflight.items[0].status == .rejected, "inode replacement passed preflight")
            try require(preflight.items[0].failureReason == .identityMismatch, "wrong inode replacement reason")
            try require(FileManager.default.fileExists(atPath: file.path), "replacement file disappeared")
        }
    }

    private static func testSymlinkReplacement() async throws {
        try await withFixture { fixture in
            let file = fixture.root.appendingPathComponent("symlink-replace.cache")
            let outside = FileManager.default.temporaryDirectory.appendingPathComponent("LexCleanerCleanupOutside-\(UUID().uuidString)")
            try write("original", to: file)
            try write("outside", to: outside)
            defer { try? FileManager.default.removeItem(at: outside) }
            let candidate = try makeCandidate(path: file, safety: .safe, reason: .regenerableCache)
            let plan = await fixture.planner.makePlan(candidates: [candidate], selection: CleanupSelection())
            try FileManager.default.removeItem(at: file)
            try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)
            let preflight = await fixture.planner.preflight(plan: plan, checkedAt: testNow)
            try require(preflight.items[0].status == .rejected, "symlink replacement passed preflight")
            try require(preflight.items[0].failureReason == .identityMismatch || preflight.items[0].failureReason == .symlinkRejected, "wrong symlink replacement reason")
            try require(FileManager.default.fileExists(atPath: outside.path), "symlink target changed")
        }
    }

    private static func testPlanFileChange() async throws {
        try await withFixture { fixture in
            let file = fixture.root.appendingPathComponent("plan-change.cache")
            try write("before", to: file)
            let candidate = try makeCandidate(path: file, safety: .safe, reason: .regenerableCache)
            let plan = await fixture.planner.makePlan(candidates: [candidate], selection: CleanupSelection())
            try write("changed after plan", to: file)
            let preflight = await fixture.planner.preflight(plan: plan, checkedAt: testNow)
            try require(preflight.items[0].status == .rejected, "changed plan source passed preflight")
            try require(preflight.items[0].failureReason == .sourceChanged, "wrong plan source change reason")
        }
    }

    private static func testDryRun() async throws {
        try await withFixture { fixture in
            let file = fixture.root.appendingPathComponent("dry-run.cache")
            try write("dry-run", to: file)
            let candidate = try makeCandidate(path: file, safety: .safe, reason: .regenerableCache)
            let plan = await fixture.planner.makePlan(candidates: [candidate], selection: CleanupSelection())
            let dryRun = await fixture.planner.dryRun(plan: plan)
            try require(dryRun.processCount == 1, "dry run process count mismatch")
            try require(dryRun.processBytes == candidate.size, "dry run size mismatch")
            try require(dryRun.items[0].wouldProcess, "dry run item was not processable")
            try require(FileManager.default.fileExists(atPath: file.path), "dry run mutated file")
        }
    }

    private static func testDuplicateCandidate() async throws {
        try await withFixture { fixture in
            let file = fixture.root.appendingPathComponent("duplicate.cache")
            try write("duplicate", to: file)
            let candidate = try makeCandidate(path: file, safety: .safe, reason: .regenerableCache)
            let plan = await fixture.planner.makePlan(candidates: [candidate, candidate], selection: CleanupSelection())
            try require(plan.items.count == 2, "duplicate was silently dropped")
            try require(plan.items[0].isEligible, "first duplicate was not eligible")
            try require(plan.items[1].rejectionReason == .duplicateCandidate, "duplicate reason missing")
        }
    }

    private static func testPartialFailure() async throws {
        try await withFixture { fixture in
            let first = fixture.root.appendingPathComponent("partial-first.cache")
            let second = fixture.root.appendingPathComponent("partial-second.cache")
            try write("first", to: first)
            try write("second", to: second)
            let candidates = try [makeCandidate(path: first, safety: .safe, reason: .regenerableCache), makeCandidate(path: second, safety: .safe, reason: .regenerableCache)]
            let plan = await fixture.planner.makePlan(candidates: candidates, selection: CleanupSelection())
            let preflight = await fixture.planner.preflight(plan: plan, checkedAt: testNow)
            try write("second changed after preflight", to: second)
            let execution = await fixture.planner.execute(plan: plan, preflight: preflight)
            let executionDetails = execution.items.map { "\($0.status.rawValue)/\(String(describing: $0.failureReason))" }
            try require(execution.items.filter { $0.status == .success }.count == 1, "partial success count mismatch: \(executionDetails)")
            try require(execution.items.filter { $0.status == .rejected }.count == 1, "partial rejection count mismatch")
            try require(FileManager.default.fileExists(atPath: second.path), "failed item disappeared")
        }
    }

    private static func testCancellation() async throws {
        try await withFixture { fixture in
            let file = fixture.root.appendingPathComponent("cancel.cache")
            try write("cancel", to: file)
            let candidate = try makeCandidate(path: file, safety: .safe, reason: .regenerableCache)
            let plan = await fixture.planner.makePlan(candidates: [candidate], selection: CleanupSelection())
            let preflight = await fixture.planner.preflight(plan: plan, checkedAt: testNow)
            let task = Task { await fixture.planner.execute(plan: plan, preflight: preflight) }
            task.cancel()
            let execution = await task.value
            try require(execution.items[0].status == .skipped || execution.items[0].status == .rejected, "cancelled execution proceeded")
            try require(FileManager.default.fileExists(atPath: file.path), "cancelled execution mutated file")
        }
    }

    private static func testTrashFailure() async throws {
        try await withFixture(fileManagerBox: FileManagerBox(FailingFileManager())) { fixture in
            let file = fixture.root.appendingPathComponent("trash-failure.cache")
            try write("failure", to: file)
            let candidate = try makeCandidate(path: file, safety: .safe, reason: .regenerableCache)
            let plan = await fixture.planner.makePlan(candidates: [candidate], selection: CleanupSelection())
            let preflight = await fixture.planner.preflight(plan: plan, checkedAt: testNow)
            try require(preflight.items[0].status == .passed, "failing Trash fixture did not pass preflight: \(preflight.items[0].failureReason as Any)")
            let execution = await fixture.planner.execute(plan: plan, preflight: preflight)
            try require(execution.items[0].status == .failed, "Trash failure was not failed")
            try require(execution.items[0].failureReason == .safeDeleteFailed, "wrong Trash failure reason")
            try require(FileManager.default.fileExists(atPath: file.path), "failed Trash removed file")
        }
    }

    private static func testControlledRealPipeline() async throws {
        try await withFixture { fixture in
            let first = fixture.root.appendingPathComponent("pipeline-first.cache")
            let second = fixture.root.appendingPathComponent("pipeline-second.cache")
            try write("first", to: first)
            try write("second", to: second)

            let collector = ItemCollector()
            let scanRule = ScanRule(id: "pipeline-scan", category: .userCache, riskLevel: .low, allowedRoots: [fixture.root])
            _ = await ScanEngine(maxConcurrentDirectories: 2).scan(targets: [ScanTarget(url: fixture.root, ruleID: scanRule.id)], rules: [scanRule]) { progress in
                if let item = progress.item { await collector.append(item) }
            }
            let scanItems = await collector.items().filter { $0.fileType == .regularFile }
            let candidates = await ClassificationEngine(applicationRoots: [fixture.applicationsRoot]).classify(items: scanItems, rules: [fixture.rule], now: testNow).candidates.sorted { $0.path.path < $1.path.path }
            let candidateDetails = candidates.map { "\($0.path.lastPathComponent)/\($0.safetyLevel.rawValue)/\($0.cleanupReason.rawValue)" }
            try require(candidates.count == 2 && candidates.allSatisfy { $0.safetyLevel == .safe }, "controlled scan/classification did not produce two safe files: \(candidateDetails)")

            let plan = await fixture.planner.makePlan(candidates: candidates, selection: CleanupSelection())
            let dryRun = await fixture.planner.dryRun(plan: plan)
            try require(dryRun.processCount == 2, "controlled dry run count mismatch")
            try require(FileManager.default.fileExists(atPath: first.path) && FileManager.default.fileExists(atPath: second.path), "dry run changed controlled files")

            try write("second changed after dry run", to: second)
            let preflight = await fixture.planner.preflight(plan: plan, checkedAt: testNow)
            try require(preflight.items.filter { $0.status == .passed }.count == 1, "controlled preflight did not preserve one unchanged file")
            try require(preflight.items.filter { $0.status == .rejected }.count == 1, "controlled preflight did not reject changed file")
            let execution = await fixture.planner.execute(plan: plan, preflight: preflight)
            try require(execution.items.filter { $0.status == .success }.count == 1, "controlled Trash success missing")
            try require(execution.items.filter { $0.status == .rejected }.count == 1, "controlled changed item was not rejected")
            try require(!FileManager.default.fileExists(atPath: first.path), "unchanged allowed file was not moved to Trash")
            try require(FileManager.default.fileExists(atPath: second.path), "changed file was moved to Trash")
            try require(!execution.audit.isEmpty, "audit was empty")
        }
    }

    private struct Fixture {
        let root: URL
        let applicationsRoot: URL
        let rule: CleanerRule
        let planner: CleanupPlanner
    }

    private static func withFixture(
        fileManagerBox: FileManagerBox = FileManagerBox(.default),
        _ operation: (Fixture) async throws -> Void
    ) async throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("LexCleanerCleanup-\(UUID().uuidString)", isDirectory: true)
        let applicationsRoot = workspace.appendingPathComponent("Applications", isDirectory: true)
        let home = workspace.appendingPathComponent("Home", isDirectory: true)
        let cacheRoot = home.appendingPathComponent("Library/Caches", isDirectory: true)
        let root = cacheRoot.appendingPathComponent("com.lexcleaner.fixture/fsCachedData", isDirectory: true)
        let app = applicationsRoot.appendingPathComponent("Fixture.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents", isDirectory: true), withIntermediateDirectories: true)
        let info = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>com.lexcleaner.fixture</string></dict></plist>"
        try Data(info.utf8).write(to: app.appendingPathComponent("Contents/Info.plist"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let rule = CleanerRule.builtInRules(homeDirectory: home, temporaryDirectory: workspace.appendingPathComponent("tmp"))[0]
        let logger = InMemoryCleanupAuditLogger()
        let deleteEngine = SafeDeleteEngine(policy: SafeDeletePolicy(whitelistedRoots: [root]), fileManager: fileManagerBox.value, logger: InMemorySafeDeleteLogger())
        let planner = CleanupPlanner(safeDeleteEngine: deleteEngine, classificationRules: [rule], classificationEngine: ClassificationEngine(applicationRoots: [applicationsRoot]), auditLogger: logger)
        try await operation(Fixture(root: root, applicationsRoot: applicationsRoot, rule: rule, planner: planner))
    }

    private static func makeCandidate(path: URL, safety: CleanupSafetyLevel, reason: CleanupReason) throws -> CleanerCandidate {
        var info = stat()
        guard lstat(path.path, &info) == 0 else { throw TestFailure("candidate metadata unavailable") }
        let size = info.st_size > 0 ? UInt64(info.st_size) : 0
        let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000)
        let ruleID = "calibrated-user-cache-fscached-data"
        return CleanerCandidate(path: path.standardizedFileURL, category: .userCache, size: size, modifiedAt: modified, owningApp: nil, safetyLevel: safety, cleanupReason: reason, matchedRule: ruleID, matchedRuleIDs: [ruleID], estimatedReclaimableBytes: safety == .safe || safety == .reviewRequired ? size : 0)
    }

    private static func write(_ contents: String, to path: URL) throws {
        try Data(contents.utf8).write(to: path)
        try FileManager.default.setAttributes([.modificationDate: testNow.addingTimeInterval(-3 * 24 * 60 * 60)], ofItemAtPath: path.path)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw TestFailure(message) }
    }
}

private actor ItemCollector {
    private var stored: [ScanItem] = []
    func append(_ item: ScanItem) { stored.append(item) }
    func items() -> [ScanItem] { stored }
}

private final class FailingFileManager: FileManager {
    override func trashItem(at url: URL, resultingItemURL: AutoreleasingUnsafeMutablePointer<NSURL?>?) throws {
        throw NSError(domain: "LexCleanerCleanupTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "controlled Trash failure"])
    }
}

private final class FileManagerBox: @unchecked Sendable {
    let value: FileManager

    init(_ value: FileManager) { self.value = value }
}

private struct TestFailure: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}
