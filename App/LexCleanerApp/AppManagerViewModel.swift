import Foundation
import LexCleanerCore
import SwiftUI

enum AppManagerSortOrder: String, CaseIterable, Identifiable {
    case name
    case size
    case modified

    var id: String { rawValue }
    var titleKey: LocalizedStringKey {
        switch self {
        case .name: return "appManager.sort.name"
        case .size: return "appManager.sort.size"
        case .modified: return "appManager.sort.modified"
        }
    }
}

enum AppManagerPhase: Equatable {
    case idle
    case loading
    case analyzing
    case ready
    case dryRun
    case preflighting
    case executing
    case completed
    case cancelled
    case failed

    var titleKey: LocalizedStringKey {
        switch self {
        case .idle: return "appManager.phase.idle"
        case .loading: return "appManager.phase.loading"
        case .analyzing: return "appManager.phase.analyzing"
        case .ready: return "appManager.phase.ready"
        case .dryRun: return "appManager.phase.dryRun"
        case .preflighting: return "appManager.phase.preflight"
        case .executing: return "appManager.phase.executing"
        case .completed: return "appManager.phase.completed"
        case .cancelled: return "appManager.phase.cancelled"
        case .failed: return "appManager.phase.failed"
        }
    }
}

private struct AppManagerFixture {
    let root: URL
    let appsRoot: URL
    let home: URL
    let app: URL

    static func make() -> AppManagerFixture? {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LexCleaner-AppManagerUI-E2E-\(UUID().uuidString)", isDirectory: true)
        let appsRoot = root.appendingPathComponent("Applications", isDirectory: true)
        let home = root.appendingPathComponent("Home", isDirectory: true)
        let app = appsRoot.appendingPathComponent("Controlled App.app", isDirectory: true)
        let cache = home.appendingPathComponent("Library/Caches/com.lexcleaner.appmanager-ui", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: appsRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents", isDirectory: true), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            let plist: [String: Any] = [
                "CFBundleIdentifier": "com.lexcleaner.appmanager-ui",
                "CFBundleDisplayName": "Controlled App",
                "CFBundleName": "Controlled App",
                "CFBundleVersion": "1",
                "CFBundleShortVersionString": "1.0",
                "CFBundlePackageType": "APPL"
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: app.appendingPathComponent("Contents/Info.plist"), options: .atomic)
            try Data("controlled residual cache".utf8).write(to: cache.appendingPathComponent("old-cache.bin"), options: .atomic)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-10 * 24 * 60 * 60)], ofItemAtPath: cache.appendingPathComponent("old-cache.bin").path)
            return AppManagerFixture(root: root, appsRoot: appsRoot, home: home, app: app)
        } catch {
            try? FileManager.default.removeItem(at: root)
            return nil
        }
    }
}

@MainActor
final class AppManagerViewModel: ObservableObject {
    @Published private(set) var phase: AppManagerPhase = .idle
    @Published private(set) var inventory: InstalledAppInventory?
    @Published private(set) var selectedApp: InstalledApp?
    @Published private(set) var analysis: AppResidualAnalysis?
    @Published private(set) var uninstallPlan: UninstallPlan?
    @Published private(set) var dryRun: CleanupDryRunResult?
    @Published private(set) var preflight: CleanupPreflightResult?
    @Published private(set) var execution: CleanupExecutionResult?
    @Published private(set) var errorMessage: String?
    @Published private(set) var selectedResidualPaths: Set<URL> = []
    @Published private(set) var appBundleSelected = false
    @Published var searchText = ""
    @Published var sortOrder: AppManagerSortOrder = .name
    @Published var isConfirmationPresented = false

    private let manager: AppManager
    private let fixture: AppManagerFixture?
    private var task: Task<Void, Never>?
    private var hasLoaded = false

    init() {
        if ProcessInfo.processInfo.arguments.contains("--lexcleaner-app-manager-fixture"), let fixture = AppManagerFixture.make() {
            self.fixture = fixture
            self.manager = AppManager(
                catalog: InstalledAppCatalog(applicationRoots: [fixture.appsRoot], maxSearchDepth: 1),
                residualAnalyzer: AppResidualAnalyzer(homeDirectory: fixture.home)
            )
        } else {
            self.fixture = nil
            self.manager = AppManager()
        }
    }

    var isControlledFixture: Bool { fixture != nil }
    var apps: [InstalledApp] {
        guard let inventory else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = query.isEmpty ? inventory.apps : inventory.apps.filter { app in
            [app.displayName, app.bundleIdentifier ?? "", app.path.path]
                .joined(separator: " ").lowercased().contains(query)
        }
        return filtered.sorted { lhs, rhs in
            switch sortOrder {
            case .name: return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            case .size: return (lhs.sizeBytes ?? 0) > (rhs.sizeBytes ?? 0)
            case .modified: return (lhs.modifiedAt ?? .distantPast) > (rhs.modifiedAt ?? .distantPast)
            }
        }
    }

    var selectableCount: Int {
        selectedResidualPaths.count + (appBundleSelected ? 1 : 0)
    }

    var selectedBytes: UInt64 {
        let residualBytes = analysis?.candidates.filter { selectedResidualPaths.contains($0.path.standardizedFileURL) }.reduce(0) { $0 + $1.sizeBytes } ?? 0
        return residualBytes + (appBundleSelected ? selectedApp?.sizeBytes ?? 0 : 0)
    }

    var canCreateDryRun: Bool {
        phase == .ready && selectableCount > 0 && selectedApp != nil
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        refresh()
    }

    func refresh() {
        task?.cancel()
        hasLoaded = true
        phase = .loading
        clearSelectionAndPipeline()
        let manager = self.manager
        task = Task { [weak self] in
            let result = await manager.enumerateInstalledApps()
            guard !Task.isCancelled else {
                self?.phase = .cancelled
                self?.task = nil
                return
            }
            self?.inventory = result
            self?.phase = .ready
            self?.task = nil
        }
    }

    func select(_ app: InstalledApp) {
        task?.cancel()
        selectedApp = app
        analysis = nil
        clearSelectionAndPipeline(keepApp: true)
        phase = .analyzing
        let manager = self.manager
        task = Task { [weak self] in
            let result = await manager.analyzeResiduals(for: app)
            guard !Task.isCancelled else {
                self?.phase = .cancelled
                self?.task = nil
                return
            }
            self?.analysis = result
            self?.phase = .ready
            self?.task = nil
        }
    }

    func isSelected(_ candidate: AppResidualCandidate) -> Bool {
        selectedResidualPaths.contains(candidate.path.standardizedFileURL)
    }

    func canSelect(_ candidate: AppResidualCandidate) -> Bool {
        candidate.cleanupSafetyLevel == .reviewRequired && !candidate.isSharedData && !candidate.isUnknownData
    }

    func setSelected(_ selected: Bool, for candidate: AppResidualCandidate) {
        guard canSelect(candidate) else { return }
        let path = candidate.path.standardizedFileURL
        if selected { selectedResidualPaths.insert(path) } else { selectedResidualPaths.remove(path) }
        resetPipelineOnly()
    }

    func setAppBundleSelected(_ selected: Bool) {
        guard selectedApp != nil else { return }
        appBundleSelected = selected
        resetPipelineOnly()
    }

    func createDryRun() {
        guard canCreateDryRun, let app = selectedApp, let analysis else { return }
        phase = .dryRun
        errorMessage = nil
        let selectedPaths = selectedResidualPaths.union(appBundleSelected ? [app.path] : [])
        let residualRules = analysis.candidates.map(\.cleanupRule)
        let rules = [app.appBundleCleanupRule] + residualRules.reduce(into: [CleanerRule]()) { result, rule in
            if !result.contains(where: { $0.id == rule.id && $0.allowedRoots == rule.allowedRoots }) { result.append(rule) }
        }
        let candidates = [app.appBundleCleanupCandidate] + analysis.candidates.map { $0.asCleanerCandidate() }
        let planner = CleanupPlanner(
            whitelistedRoots: candidates.map { $0.path },
            classificationRules: rules,
            applicationRoots: [app.path.deletingLastPathComponent()],
            explicitlyAllowedApplicationBundles: [app.path]
        )
        let manager = self.manager
        task = Task { [weak self] in
            let uninstallPlan = await manager.makeUninstallPlan(
                for: app,
                selection: UninstallSelection(selectedPaths: selectedPaths, userConfirmed: true)
            )
            let plan = await planner.makePlan(
                candidates: candidates,
                selection: CleanupSelection(selectedPaths: selectedPaths, userConfirmed: true)
            )
            let dryRun = await planner.dryRun(plan: plan)
            guard !Task.isCancelled else {
                self?.phase = .cancelled
                self?.task = nil
                return
            }
            self?.uninstallPlan = uninstallPlan
            self?.planner = planner
            self?.plan = plan
            self?.dryRun = dryRun
            self?.phase = .dryRun
            self?.task = nil
        }
    }

    func confirmAndExecute() {
        guard phase == .dryRun, dryRun?.processCount ?? 0 > 0 else { return }
        isConfirmationPresented = true
    }

    func executeAfterConfirmation() {
        isConfirmationPresented = false
        guard let planner, let plan else { return }
        phase = .preflighting
        task = Task { [weak self] in
            let preflight = await planner.preflight(plan: plan)
            guard !Task.isCancelled else {
                self?.phase = .cancelled
                self?.task = nil
                return
            }
            self?.preflight = preflight
            self?.phase = .executing
            let execution = await planner.execute(plan: plan, preflight: preflight)
            guard !Task.isCancelled else {
                self?.phase = .cancelled
                self?.task = nil
                return
            }
            self?.execution = execution
            self?.phase = .completed
            self?.task = nil
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        phase = .cancelled
    }

    private var planner: CleanupPlanner?
    private var plan: CleanupPlan?

    private func resetPipelineOnly() {
        uninstallPlan = nil
        plan = nil
        planner = nil
        dryRun = nil
        preflight = nil
        execution = nil
        if phase == .dryRun || phase == .completed { phase = .ready }
    }

    private func clearSelectionAndPipeline(keepApp: Bool = false) {
        if !keepApp { selectedApp = nil }
        selectedResidualPaths = []
        appBundleSelected = false
        analysis = keepApp ? analysis : nil
        resetPipelineOnly()
    }

    deinit {
        task?.cancel()
        if let fixture { try? FileManager.default.removeItem(at: fixture.root) }
    }
}
