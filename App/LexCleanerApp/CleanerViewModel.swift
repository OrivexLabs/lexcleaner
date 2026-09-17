import Foundation
import LexCleanerCore
import SwiftUI

struct CleanerScanScope: Sendable {
    let targets: [ScanTarget]
    let scanRules: [ScanRule]
    let classificationRules: [CleanerRule]
    let applicationRoots: [URL]
    let deletionRoots: [URL]
    let isControlledFixture: Bool

    static func live() -> CleanerScanScope {
        let targets = ScanEngine.builtInTargets()
        return CleanerScanScope(
            targets: targets,
            scanRules: ScanEngine.builtInRules(),
            classificationRules: ClassificationEngine.builtInRules(),
            applicationRoots: ClassificationEngine.defaultApplicationRoots(),
            deletionRoots: targets.map(\.url),
            isControlledFixture: false
        )
    }

    static func fromProcessArguments() -> CleanerScanScope {
        guard ProcessInfo.processInfo.arguments.contains("--lexcleaner-controlled-fixture") else {
            return .live()
        }

        // This fixture is opt-in and is only used for a real UI E2E. It is never
        // selected by a production scan and contains no user data.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LexCleaner-CleanerUI-E2E-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("Home", isDirectory: true)
        let applications = home.appendingPathComponent("Applications", isDirectory: true)
        let cacheRoot = home.appendingPathComponent("Library/Caches", isDirectory: true)
        let applicationSupportRoot = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let bundleID = "com.lexcleaner.controlled-ui-fixture"
        let app = applications.appendingPathComponent("ControlledFixture.app", isDirectory: true)
        let cache = cacheRoot
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("fsCachedData", isDirectory: true)
        let file = cache.appendingPathComponent("ui-e2e-safe-cache.bin")
        let unknownFile = cache.appendingPathComponent("ui-e2e-source-changed.bin")
        let reviewCache = applicationSupportRoot
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Cache", isDirectory: true)
        let reviewFile = reviewCache.appendingPathComponent("ui-e2e-review-cache.bin")
        let reviewFileTwo = reviewCache.appendingPathComponent("ui-e2e-review-cache-2.bin")

        do {
            try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents", isDirectory: true), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: reviewCache, withIntermediateDirectories: true)
            let info: [String: Any] = [
                "CFBundleIdentifier": bundleID,
                "CFBundlePackageType": "APPL",
                "CFBundleName": "ControlledFixture",
                "CFBundleVersion": "1"
            ]
            let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            try plist.write(to: app.appendingPathComponent("Contents/Info.plist"))
            try Data("LexCleaner controlled UI fixture".utf8).write(to: file, options: .atomic)
            try Data("LexCleaner controlled source snapshot".utf8).write(to: unknownFile, options: .atomic)
            try Data("LexCleaner controlled review fixture".utf8).write(to: reviewFile, options: .atomic)
            try Data("LexCleaner controlled second review fixture".utf8).write(to: reviewFileTwo, options: .atomic)
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(-3 * 24 * 60 * 60)],
                ofItemAtPath: file.path
            )
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(-5 * 24 * 60 * 60)],
                ofItemAtPath: reviewFile.path
            )
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(-5 * 24 * 60 * 60)],
                ofItemAtPath: reviewFileTwo.path
            )
        } catch {
            // An unavailable fixture must surface as an empty/error scan, never
            // as invented candidates.
            return CleanerScanScope(
                targets: [],
                scanRules: [],
                classificationRules: [],
                applicationRoots: [applications],
                deletionRoots: [cacheRoot],
                isControlledFixture: true
            )
        }

        let scanRules = ScanEngine.builtInRules(homeDirectory: home, temporaryDirectory: root.appendingPathComponent("tmp"))
        let targets = ScanEngine.builtInTargets(homeDirectory: home, temporaryDirectory: root.appendingPathComponent("tmp"))
        return CleanerScanScope(
            targets: targets,
            scanRules: scanRules,
            classificationRules: CleanerRule.builtInRules(homeDirectory: home, temporaryDirectory: root.appendingPathComponent("tmp")),
            applicationRoots: [applications],
            deletionRoots: targets.map(\.url),
            isControlledFixture: true
        )
    }
}

enum CleanerPhase: Equatable {
    case idle
    case scanning
    case ready
    case planning
    case dryRun
    case preflighting
    case executing
    case completed
    case cancelled
    case failed

    var title: LocalizedStringKey {
        switch self {
        case .idle: return "cleaner.phase.idle"
        case .scanning: return "cleaner.phase.scanning"
        case .ready: return "cleaner.phase.ready"
        case .planning: return "cleaner.phase.planning"
        case .dryRun: return "cleaner.phase.dryRun"
        case .preflighting: return "cleaner.phase.preflight"
        case .executing: return "cleaner.phase.executing"
        case .completed: return "cleaner.phase.completed"
        case .cancelled: return "cleaner.phase.cancelled"
        case .failed: return "cleaner.phase.failed"
        }
    }
}

private final class CleanerScanCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [ScanItem] = []

    func append(_ item: ScanItem) {
        lock.lock()
        items.append(item)
        lock.unlock()
    }

    func makeItems() -> [ScanItem] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }
}

private final class ControlledFixtureMutationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didMutate = false

    func claim(path: URL) -> Bool {
        guard path.lastPathComponent == "ui-e2e-source-changed.bin" else { return false }
        lock.lock()
        defer { lock.unlock() }
        guard !didMutate else { return false }
        didMutate = true
        return true
    }
}

@MainActor
final class CleanerViewModel: ObservableObject {
    let scope: CleanerScanScope

    @Published private(set) var phase: CleanerPhase = .idle
    @Published private(set) var candidates: [CleanerCandidate] = []
    @Published private(set) var statistics: ClassificationStatistics?
    @Published private(set) var scanProgress: ScanProgress?
    @Published private(set) var scanResult: ScanResult?
    @Published private(set) var plan: CleanupPlan?
    @Published private(set) var dryRun: CleanupDryRunResult?
    @Published private(set) var preflight: CleanupPreflightResult?
    @Published private(set) var execution: CleanupExecutionResult?
    @Published private(set) var errorMessage: String?
    @Published private(set) var selectedPaths: Set<URL> = []
    @Published var isConfirmationPresented = false
    @Published var isHighRiskConfirmationPresented = false

    private var pipelineTask: Task<Void, Never>?
    private var planner: CleanupPlanner?
    private var lastProgressUpdate = Date.distantPast

    init(scope: CleanerScanScope = .fromProcessArguments()) {
        self.scope = scope
    }

    var canStartScan: Bool { pipelineTask == nil && phase != .scanning }
    var selectableSelectedCount: Int { selectedPaths.count }
    var highRiskSelectedCount: Int {
        dryRun?.items.filter { $0.wouldProcess && $0.safetyLevel == .reviewRequired }.count ?? 0
    }
    var highRiskSelectedBytes: UInt64 {
        dryRun?.items.filter { $0.wouldProcess && $0.safetyLevel == .reviewRequired }
            .reduce(0) { $0 + $1.size } ?? 0
    }

    func groups(for safetyLevel: CleanupSafetyLevel) -> [CleanerCandidateGroup] {
        CleanerCandidateGroup.grouped(candidates).filter { $0.safetyLevel == safetyLevel }
    }

    func selectionState(for group: CleanerCandidateGroup) -> CleanerGroupSelectionState {
        CleanerSelectionState(selectedPaths: selectedPaths).state(for: group)
    }

    func toggleGroup(_ group: CleanerCandidateGroup) {
        let state = selectionState(for: group)
        guard state != .disabled else { return }
        let shouldSelect = state != .allSelected
        var selection = CleanerSelectionState(selectedPaths: selectedPaths)
        selection.setSelected(shouldSelect, for: group)
        selectedPaths = selection.selectedPaths
        invalidateExecutionState()
    }

    func startScan() {
        stop()
        clearResults()
        phase = .scanning
        let scope = self.scope
        pipelineTask = Task { [weak self] in
            let collector = CleanerScanCollector()
            let controlledFixtureMutationGate = ControlledFixtureMutationGate()
            let scanEngine = ScanEngine(maxConcurrentDirectories: 4)
            let scan = await scanEngine.scan(targets: scope.targets, rules: scope.scanRules) { progress in
                if let item = progress.item {
                    collector.append(item)
                    // Controlled-only source replacement proves the real
                    // Classification fail-closed path without inventing a
                    // candidate or touching user data.
                    if scope.isControlledFixture,
                       controlledFixtureMutationGate.claim(path: item.path) {
                        try? Data("LexCleaner controlled changed source".utf8).write(to: item.path, options: .atomic)
                    }
                    if scope.isControlledFixture {
                        // Keep the real controlled-fixture scan observable long
                        // enough to verify the user-facing cancellation path.
                        try? await Task.sleep(nanoseconds: 250_000_000)
                    }
                }
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, Date().timeIntervalSince(self.lastProgressUpdate) >= 0.08 else { return }
                    self.lastProgressUpdate = Date()
                    self.scanProgress = progress
                }
            }

            guard !Task.isCancelled else {
                await MainActor.run {
                    self?.phase = .cancelled
                    self?.scanProgress = nil
                    self?.pipelineTask = nil
                }
                return
            }

            let classificationEngine = ClassificationEngine(applicationRoots: scope.applicationRoots)
            let classification = await classificationEngine.classify(
                items: collector.makeItems(),
                rules: scope.classificationRules
            )
            guard !Task.isCancelled else {
                await MainActor.run {
                    self?.phase = .cancelled
                    self?.scanProgress = nil
                    self?.pipelineTask = nil
                }
                return
            }

            await MainActor.run {
                guard let self else { return }
                self.scanResult = scan
                self.scanProgress = nil
                self.candidates = classification.candidates
                self.statistics = classification.statistics
                self.errorMessage = scope.targets.isEmpty ? "cleaner.noTargets" : nil
                self.selectedPaths = CleanerSelectionState(candidates: classification.candidates).selectedPaths
                self.phase = classification.cancelled || scan.cancelled ? .cancelled : .ready
                self.pipelineTask = nil
            }
        }
    }

    func cancel() {
        guard pipelineTask != nil else { return }
        pipelineTask?.cancel()
        pipelineTask = nil
        phase = .cancelled
    }

    func stop() {
        pipelineTask?.cancel()
        pipelineTask = nil
        if phase == .scanning || phase == .planning || phase == .preflighting || phase == .executing {
            phase = .cancelled
        }
    }

    func isSelected(_ candidate: CleanerCandidate) -> Bool {
        selectedPaths.contains(candidate.path.standardizedFileURL)
    }

    func canSelect(_ candidate: CleanerCandidate) -> Bool {
        candidate.safetyLevel == .safe || candidate.safetyLevel == .reviewRequired
    }

    func setSelected(_ selected: Bool, for candidate: CleanerCandidate) {
        var selection = CleanerSelectionState(selectedPaths: selectedPaths)
        selection.setSelected(selected, for: candidate)
        guard selection.selectedPaths != selectedPaths else { return }
        selectedPaths = selection.selectedPaths
        invalidateExecutionState()
    }

    func createDryRun() {
        guard phase == .ready, !selectedPaths.isEmpty else { return }
        phase = .planning
        errorMessage = nil
        let scope = self.scope
        let selected = selectedPaths
        pipelineTask = Task { [weak self] in
            let planner = self?.makePlanner(scope: scope)
            guard let planner else { return }
            let plan = await planner.makePlan(
                candidates: self?.candidates ?? [],
                selection: CleanupSelection(selectedPaths: selected, userConfirmed: true)
            )
            let dryRun = await planner.dryRun(plan: plan)
            guard !Task.isCancelled else {
                await MainActor.run { self?.phase = .cancelled; self?.pipelineTask = nil }
                return
            }
            await MainActor.run {
                guard let self else { return }
                self.planner = planner
                self.plan = plan
                self.dryRun = dryRun
                self.phase = .dryRun
                self.pipelineTask = nil
            }
        }
    }

    func confirmAndExecute() {
        guard phase == .dryRun, dryRun?.processCount ?? 0 > 0 else { return }
        if highRiskSelectedCount > 0 {
            isHighRiskConfirmationPresented = true
        } else {
            isConfirmationPresented = true
        }
    }

    func continueAfterHighRiskConfirmation() {
        isHighRiskConfirmationPresented = false
        isConfirmationPresented = true
    }

    func executeAfterConfirmation() {
        isConfirmationPresented = false
        guard let planner, let plan else { return }
        phase = .preflighting
        errorMessage = nil
        pipelineTask = Task { [weak self] in
            let preflight = await planner.preflight(plan: plan)
            guard !Task.isCancelled else {
                await MainActor.run { self?.phase = .cancelled; self?.pipelineTask = nil }
                return
            }
            await MainActor.run { self?.preflight = preflight; self?.phase = .executing }
            let execution = await planner.execute(plan: plan, preflight: preflight)
            guard !Task.isCancelled else {
                await MainActor.run { self?.phase = .cancelled; self?.pipelineTask = nil }
                return
            }
            await MainActor.run {
                guard let self else { return }
                self.execution = execution
                let failures = execution.items.filter { $0.status == .failed || $0.status == .rejected }
                if failures.count == execution.items.count {
                    self.phase = .failed
                    self.errorMessage = "cleaner.executionFailed"
                } else {
                    self.phase = .completed
                    self.errorMessage = failures.isEmpty ? nil : "cleaner.partialFailure"
                }
                self.pipelineTask = nil
            }
        }
    }

    private func makePlanner(scope: CleanerScanScope) -> CleanupPlanner {
        return CleanupPlanner(
            whitelistedRoots: scope.deletionRoots,
            classificationRules: scope.classificationRules,
            applicationRoots: scope.applicationRoots
        )
    }

    private func clearResults() {
        candidates = []
        statistics = nil
        scanProgress = nil
        scanResult = nil
        plan = nil
        dryRun = nil
        preflight = nil
        execution = nil
        errorMessage = nil
        selectedPaths = []
        planner = nil
        isConfirmationPresented = false
        isHighRiskConfirmationPresented = false
    }

    private func invalidateExecutionState() {
        plan = nil
        dryRun = nil
        preflight = nil
        execution = nil
        if phase == .dryRun || phase == .completed || phase == .failed {
            phase = .ready
        }
    }

    deinit {
        pipelineTask?.cancel()
    }
}
