import Foundation
import LexCleanerCore

@main
struct LexCleanerAppManagerTestRunner {
    static func main() async {
        do {
            try await runRealInventory()
            try await runControlledPlanAndDryRun()
            print("APP_MANAGER_RESULT PASS")
        } catch {
            fputs("APP_MANAGER_RESULT FAIL: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func runRealInventory() async throws {
        let manager = AppManager()
        let inventory = await manager.enumerateInstalledApps()
        print("REAL_APP_INVENTORY count=\(inventory.apps.count) issues=\(inventory.issues.count) roots=\(inventory.roots.count)")
        for app in inventory.apps.prefix(20) {
            let analysis = await manager.analyzeResiduals(for: app)
            let summary = analysis.candidates.map { "\($0.kind.rawValue):\($0.confidence.rawValue):\($0.cleanupSafetyLevel.rawValue)" }.joined(separator: ",")
            print("APP path=\(app.path.path) name=\(app.displayName) bundle=\(app.bundleIdentifier ?? "<missing>") version=\(app.metadata.shortVersion ?? app.metadata.version ?? "<unknown>") residuals=\(analysis.candidates.count) [\(summary)]")
        }
        guard inventory.apps.count >= 20 else {
            throw RunnerError("Real Mac inventory returned fewer than 20 apps; manual sample requirement was not met.")
        }
    }

    private static func runControlledPlanAndDryRun() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LexCleanerAppManagerRunner-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let appRoot = root.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: appRoot, withIntermediateDirectories: true)
        let appPath = appRoot.appendingPathComponent("Controlled Test.app", isDirectory: true)
        let contents = appPath.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.lexcleaner.controlled-test",
            "CFBundleDisplayName": "Controlled Test",
            "CFBundleVersion": "1",
            "CFBundleShortVersionString": "1.0",
            "CFBundlePackageType": "APPL"
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: contents.appendingPathComponent("Info.plist"))
        let cache = root.appendingPathComponent("Library/Caches/com.lexcleaner.controlled-test", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("controlled cache".utf8).write(to: cache.appendingPathComponent("old.cache"))

        let app = InstalledApp(path: appPath, metadata: AppMetadata(bundleIdentifier: "com.lexcleaner.controlled-test", displayName: "Controlled Test", version: "1", shortVersion: "1.0", minimumOSVersion: nil, executableName: nil), discoveredUnder: appRoot)
        let manager = AppManager(catalog: InstalledAppCatalog(applicationRoots: [appRoot]), residualAnalyzer: AppResidualAnalyzer(homeDirectory: root))
        let analysis = await manager.analyzeResiduals(for: app)
        guard let cacheCandidate = analysis.candidates.first(where: { $0.kind == .cache }) else { throw RunnerError("controlled cache was not discovered") }
        let uninstallPlan = await manager.makeUninstallPlan(for: app, selection: UninstallSelection(selectedPaths: [cacheCandidate.path], userConfirmed: true))
        guard uninstallPlan.eligibleItems.count == 1 else { throw RunnerError("controlled residual did not enter explicit review plan") }

        let rule = CleanerRule(id: "app-residual-cache", name: "App residual cache", category: .applicationCache, sourceCategories: [.applicationCache], allowedRoots: [cache.deletingLastPathComponent()], pathComponentHints: ["com.lexcleaner.controlled-test"], defaultSafetyLevel: .reviewRequired, cleanupReason: .applicationCacheNeedsReview, dataDisposition: .regenerableCache, agePolicy: .any, sizePolicy: .any)
        let engine = SafeDeleteEngine(policy: SafeDeletePolicy(whitelistedRoots: [cache]), logger: InMemorySafeDeleteLogger())
        let planner = CleanupPlanner(safeDeleteEngine: engine, classificationRules: [rule])
        let cleanupPlan = await planner.makePlan(candidates: uninstallPlan.eligibleCleanupCandidates, selection: CleanupSelection(selectedPaths: [cache], userConfirmed: true))
        let before = try FileManager.default.attributesOfItem(atPath: cache.path)[.modificationDate] as? Date
        let dryRun = await planner.dryRun(plan: cleanupPlan)
        guard dryRun.processCount == 1, FileManager.default.fileExists(atPath: cache.path) else { throw RunnerError("controlled dry run mutated or rejected the selected residual") }
        let after = try FileManager.default.attributesOfItem(atPath: cache.path)[.modificationDate] as? Date
        guard before == after else { throw RunnerError("controlled dry run changed residual metadata") }
        let preflight = await planner.preflight(plan: cleanupPlan)
        guard preflight.items.allSatisfy({ $0.status == .rejected }), FileManager.default.fileExists(atPath: cache.path) else { throw RunnerError("controlled preflight did not remain fail-closed for a directory container") }
        print("CONTROLLED_APP_PLAN candidates=\(analysis.candidates.count) eligible=\(uninstallPlan.eligibleItems.count) dryRun=\(dryRun.processCount) preflightRejected=\(preflight.items.filter { $0.status == .rejected }.count) filesystemUnchanged=true")
    }
}

private struct RunnerError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
