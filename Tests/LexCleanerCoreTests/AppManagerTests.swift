import Foundation
import Testing
@testable import LexCleanerCore

@Suite("AppManager")
struct AppManagerTests {
    @Test("enumerates a controlled app and reads bundle metadata")
    func enumeratesControlledApp() async throws {
        let root = try TestAppFixture.createRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try TestAppFixture.createApp(at: root, bundleIdentifier: "com.lexcleaner.fixture", name: "Fixture App")

        let inventory = await InstalledAppCatalog(applicationRoots: [root], maxSearchDepth: 1).enumerate()
        #expect(inventory.apps.count == 1)
        #expect(inventory.apps[0].path == app)
        #expect(inventory.apps[0].bundleIdentifier == "com.lexcleaner.fixture")
        #expect(inventory.apps[0].metadata.displayName == "Fixture App")
        #expect(inventory.apps[0].metadata.shortVersion == "1.2")
        #expect(inventory.apps[0].sizeBytes ?? 0 > 0)
        #expect(inventory.apps[0].modifiedAt != nil)
        #expect(inventory.apps[0].source == .unknown)
        #expect(inventory.apps[0].signature == .invalid || inventory.apps[0].signature == .unknown || inventory.apps[0].signature == .unavailable)
    }

    @Test("enumerates bundle identifiers without calculating bundle sizes")
    func enumeratesBundleIdentifiersLightweight() async throws {
        let root = try TestAppFixture.createRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try TestAppFixture.createApp(at: root, bundleIdentifier: "com.lexcleaner.lightweight", name: "Lightweight App")

        let identifiers = await InstalledAppCatalog(applicationRoots: [root], maxSearchDepth: 1).enumerateBundleIdentifiers()
        #expect(identifiers == ["com.lexcleaner.lightweight"])
    }

    @Test("associates exact residual paths and protects state and preferences")
    func analyzesResidualsFailClosed() async throws {
        let home = try TestAppFixture.createRoot()
        defer { try? FileManager.default.removeItem(at: home) }
        let appRoot = home.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: appRoot, withIntermediateDirectories: true)
        let appPath = try TestAppFixture.createApp(at: appRoot, bundleIdentifier: "com.lexcleaner.fixture", name: "Fixture App")
        let cache = home.appendingPathComponent("Library/Caches/com.lexcleaner.fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("cache".utf8).write(to: cache.appendingPathComponent("old.bin"))
        let preferences = home.appendingPathComponent("Library/Preferences/com.lexcleaner.fixture.plist")
        try FileManager.default.createDirectory(at: preferences.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("preferences".utf8).write(to: preferences)

        let app = InstalledApp(
            path: appPath,
            metadata: AppMetadata(bundleIdentifier: "com.lexcleaner.fixture", displayName: "Fixture App", version: "1", shortVersion: "1.2", minimumOSVersion: nil, executableName: nil),
            discoveredUnder: appRoot
        )
        let analysis = AppResidualAnalyzer(homeDirectory: home).analyze(app: app)
        let cacheCandidate = try #require(analysis.candidates.first { $0.kind == .cache })
        let preferenceCandidate = try #require(analysis.candidates.first { $0.kind == .preferences })
        #expect(cacheCandidate.confidence == .high)
        #expect(cacheCandidate.cleanupSafetyLevel == .reviewRequired)
        #expect(preferenceCandidate.cleanupSafetyLevel == .protected)
        #expect(analysis.sentinel.status == .feasibleReadOnly)
        #expect(analysis.sentinel.requiresWrite == false)
        #expect(analysis.sentinel.requiresPrivilege == false)
    }

    @Test("unknown and shared candidates are never eligible")
    func unknownAndSharedAreFailClosed() {
        let app = InstalledApp(
            path: URL(fileURLWithPath: "/tmp/Fixture.app"),
            metadata: AppMetadata(bundleIdentifier: "com.lexcleaner.fixture", displayName: "Fixture", version: nil, shortVersion: nil, minimumOSVersion: nil, executableName: nil),
            discoveredUnder: URL(fileURLWithPath: "/tmp")
        )
        let shared = AppResidualCandidate(path: URL(fileURLWithPath: "/tmp/shared"), bundleIdentifier: "com.lexcleaner.fixture", owningAppPath: app.path, kind: .unknown, dataDisposition: .sharedData, sizeBytes: 4, modifiedAt: nil, confidence: .high, isSharedData: true, reason: "shared")
        let unknown = AppResidualCandidate(path: URL(fileURLWithPath: "/tmp/unknown"), bundleIdentifier: "com.lexcleaner.fixture", owningAppPath: app.path, kind: .unknown, dataDisposition: .unknown, sizeBytes: 4, modifiedAt: nil, confidence: .unknown, isUnknownData: true, reason: "unknown")
        #expect(shared.asCleanerCandidate().safetyLevel == .unknown)
        #expect(unknown.asCleanerCandidate().safetyLevel == .unknown)
        #expect(UninstallPlanItem(candidate: shared, explicitlySelected: true).isEligibleForCleanupReview == false)
        #expect(UninstallPlanItem(candidate: unknown, explicitlySelected: true).isEligibleForCleanupReview == false)
    }

    @Test("uninstall plan adapts to CleanupPlanner dry run without filesystem mutation")
    func cleanupPlannerDryRunIsReadOnly() async throws {
        let home = try TestAppFixture.createRoot()
        defer { try? FileManager.default.removeItem(at: home) }
        let appRoot = home.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: appRoot, withIntermediateDirectories: true)
        let appPath = try TestAppFixture.createApp(at: appRoot, bundleIdentifier: "com.lexcleaner.fixture", name: "Fixture App")
        let cache = home.appendingPathComponent("Library/Caches/com.lexcleaner.fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("cache".utf8).write(to: cache.appendingPathComponent("old.bin"))
        let app = InstalledApp(path: appPath, metadata: AppMetadata(bundleIdentifier: "com.lexcleaner.fixture", displayName: "Fixture", version: nil, shortVersion: nil, minimumOSVersion: nil, executableName: nil), discoveredUnder: appRoot)
        let manager = AppManager(catalog: InstalledAppCatalog(applicationRoots: [home]), residualAnalyzer: AppResidualAnalyzer(homeDirectory: home))
        let analysis = await manager.analyzeResiduals(for: app)
        let cacheCandidate = try #require(analysis.candidates.first { $0.kind == .cache })
        let uninstallPlan = await manager.makeUninstallPlan(for: app, selection: UninstallSelection(selectedPaths: [cacheCandidate.path], userConfirmed: true))
        let planItem = try #require(uninstallPlan.items.first { $0.candidate.path == cacheCandidate.path })
        #expect(planItem.isEligibleForCleanupReview)

        let rule = CleanerRule(id: "app-residual-cache", name: "App residual cache", category: .applicationCache, sourceCategories: [.applicationCache], allowedRoots: [cache.deletingLastPathComponent()], pathComponentHints: ["com.lexcleaner.fixture"], defaultSafetyLevel: .reviewRequired, cleanupReason: .applicationCacheNeedsReview, dataDisposition: .regenerableCache, agePolicy: .any, sizePolicy: .any)
        let logger = InMemorySafeDeleteLogger()
        let deleteEngine = SafeDeleteEngine(policy: SafeDeletePolicy(whitelistedRoots: [cache]), logger: logger)
        let planner = CleanupPlanner(safeDeleteEngine: deleteEngine, classificationRules: [rule])
        let cleanupPlan = await planner.makePlan(candidates: [planItem.cleanupCandidate], selection: CleanupSelection(selectedPaths: [cache], userConfirmed: true))
        let dryRun = await planner.dryRun(plan: cleanupPlan)
        #expect(dryRun.processCount == 1)
        #expect(FileManager.default.fileExists(atPath: cache.path))
        let preflight = await planner.preflight(plan: cleanupPlan)
        #expect(preflight.items[0].status == .rejected)
        #expect(FileManager.default.fileExists(atPath: cache.path))
    }

    @Test("moves only explicitly selected app bundle and residual to Trash through the full pipeline")
    func fullUninstallPipelineUsesTrashOnly() async throws {
        let home = try TestAppFixture.createRoot()
        defer { try? FileManager.default.removeItem(at: home) }
        let appRoot = home.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: appRoot, withIntermediateDirectories: true)
        let appPath = try TestAppFixture.createApp(at: appRoot, bundleIdentifier: "com.lexcleaner.full-ui", name: "Full UI Fixture")
        let cache = home.appendingPathComponent("Library/Caches/com.lexcleaner.full-ui", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("rebuildable".utf8).write(to: cache.appendingPathComponent("cache.bin"))

        let app = try #require((await InstalledAppCatalog(applicationRoots: [appRoot], maxSearchDepth: 1).enumerate()).apps.first)
        let analysis = AppResidualAnalyzer(homeDirectory: home).analyze(app: app)
        let cacheCandidate = try #require(analysis.candidates.first { $0.kind == .cache })
        let logger = InMemoryCleanupAuditLogger()
        let planner = CleanupPlanner(
            whitelistedRoots: [appPath, cacheCandidate.path],
            classificationRules: [app.appBundleCleanupRule, cacheCandidate.cleanupRule],
            applicationRoots: [appRoot],
            explicitlyAllowedApplicationBundles: [appPath],
            auditLogger: logger
        )
        let selected = CleanupSelection(selectedPaths: [appPath, cacheCandidate.path], userConfirmed: true)
        let plan = await planner.makePlan(candidates: [app.appBundleCleanupCandidate, cacheCandidate.asCleanerCandidate()], selection: selected)
        #expect(plan.eligibleCount == 2)
        let dryRun = await planner.dryRun(plan: plan)
        #expect(dryRun.processCount == 2)
        #expect(FileManager.default.fileExists(atPath: appPath.path))
        #expect(FileManager.default.fileExists(atPath: cacheCandidate.path.path))
        let preflight = await planner.preflight(plan: plan)
        #expect(preflight.items.allSatisfy { $0.status == .passed })
        let execution = await planner.execute(plan: plan, preflight: preflight)
        #expect(execution.items.filter { $0.status == .success }.count == 2)
        #expect(execution.reclaimedBytes > 0)
        #expect(!FileManager.default.fileExists(atPath: appPath.path))
        #expect(!FileManager.default.fileExists(atPath: cacheCandidate.path.path))
        let auditEntries = await logger.allEntries()
        #expect(auditEntries.contains { $0.phase == .execution && $0.executionStatus == .success })
    }
}

private enum TestAppFixture {
    static func createRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LexCleanerAppManagerXCTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func createApp(at root: URL, bundleIdentifier: String, name: String) throws -> URL {
        let app = root.appendingPathComponent("\(name).app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleDisplayName": name,
            "CFBundleName": name,
            "CFBundleVersion": "42",
            "CFBundleShortVersionString": "1.2",
            "CFBundlePackageType": "APPL"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }
}
