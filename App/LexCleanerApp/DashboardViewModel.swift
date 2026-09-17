import Foundation
import LexCleanerCore
import SwiftUI

final class DashboardScanCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [ScanItem] = []

    func append(_ item: ScanItem) {
        lock.lock()
        defer { lock.unlock() }
        items.append(item)
    }

    func makeItems() -> [ScanItem] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var monitoringSnapshot: MonitoringSnapshot?
    @Published private(set) var hardwareSnapshot: HardwareSnapshot?
    @Published private(set) var safeReclaimableBytes: UInt64?
    @Published private(set) var safeCandidateCount: UInt64?
    @Published private(set) var reviewCandidateCount: UInt64?
    @Published private(set) var installedAppCount: Int?
    @Published private(set) var scanIssueCount: Int?
    @Published private(set) var isLoadingOverview = true
    @Published private(set) var isSampling = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastErrorKey: String?

    private let monitoringSampler = MonitoringSampler(configuration: .standard)
    private let hardwareSampler = HardwareSampler(configuration: .standard)
    private var monitoringTask: Task<Void, Never>?
    private var hardwareTask: Task<Void, Never>?
    private var overviewTask: Task<Void, Never>?

    func start() {
        startSamplingIfNeeded()
        guard overviewTask == nil else { return }
        isLoadingOverview = true
        overviewTask = Task { [weak self] in
            await self?.loadOverview()
        }
    }

    func stop() {
        monitoringTask?.cancel()
        hardwareTask?.cancel()
        overviewTask?.cancel()
        monitoringTask = nil
        hardwareTask = nil
        overviewTask = nil
        isSampling = false
    }

    private func startSamplingIfNeeded() {
        guard monitoringTask == nil, hardwareTask == nil else { return }
        isSampling = true

        monitoringTask = Task { [weak self, monitoringSampler] in
            do {
                for try await snapshot in monitoringSampler.snapshots() {
                    guard !Task.isCancelled else { return }
                    self?.monitoringSnapshot = snapshot
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.lastErrorKey = "monitoring.unavailable"
                self?.lastError = error.localizedDescription
                DiagnosticsStore.shared.record(.error, message: "Monitoring sampling failed")
            }
        }

        hardwareTask = Task { [weak self, hardwareSampler] in
            do {
                for try await snapshot in hardwareSampler.snapshots() {
                    guard !Task.isCancelled else { return }
                    self?.hardwareSnapshot = snapshot
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.lastErrorKey = "hardware.unavailable"
                self?.lastError = error.localizedDescription
                DiagnosticsStore.shared.record(.error, message: "Hardware sampling failed")
            }
        }
    }

    private func loadOverview() async {
        let collector = DashboardScanCollector()
        let scanEngine = ScanEngine(maxConcurrentDirectories: 4)
        let classificationEngine = ClassificationEngine()
        let appCatalog = InstalledAppCatalog()
        let safeOwnershipCatalog = InstalledAppCatalog(
            applicationRoots: ClassificationEngine.defaultApplicationRoots()
        )

        async let bundleIdentifiersTask = appCatalog.enumerateBundleIdentifiers()
        let safeBundleIdentifiers = await safeOwnershipCatalog.enumerateBundleIdentifiers()
        // Dashboard's reclaimable number is intentionally limited to the currently
        // calibrated safe rule. Review-only categories remain owned by Cleaner.
        let cacheRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches", isDirectory: true)
        let fileManager = FileManager.default
        let dashboardTargets = safeBundleIdentifiers.sorted().compactMap { identifier -> ScanTarget? in
            let cachePath = cacheRoot
                .appendingPathComponent(identifier, isDirectory: true)
                .appendingPathComponent("fsCachedData", isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: cachePath.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return nil
            }
            return ScanTarget(url: cachePath, ruleID: "user-cache")
        }
        let scanResult = await scanEngine.scan(
            targets: dashboardTargets,
            rules: ScanEngine.builtInRules()
        ) { progress in
            if let item = progress.item {
                collector.append(item)
            }
        }

        guard !Task.isCancelled else { return }
        let classification = await classificationEngine.classify(
            items: collector.makeItems(),
            rules: ClassificationEngine.builtInRules()
        )

        guard !Task.isCancelled else { return }
        safeReclaimableBytes = classification.statistics.safeBytes
        safeCandidateCount = classification.statistics.safeCount
        reviewCandidateCount = classification.statistics.reviewRequiredCount
        installedAppCount = (await bundleIdentifiersTask).count
        scanIssueCount = scanResult.issues.count
        isLoadingOverview = false
    }

    deinit {
        monitoringTask?.cancel()
        hardwareTask?.cancel()
        overviewTask?.cancel()
    }
}

enum DashboardFormat {
    static func bytes(_ value: UInt64?) -> String {
        guard let value else { return L10n.string("common.collecting") }
        return ByteUnitFormatter.string(bytes: value)
    }

    static func rate(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return L10n.string("common.notAvailable") }
        return "\(ByteUnitFormatter.string(bytes: value)) /s"
    }

    static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(value.formatted(.number.precision(.fractionLength(1))))%"
    }

    static func date(_ value: Date?) -> String {
        guard let value else { return L10n.string("common.waitingForSample") }
        return value.formatted(date: .omitted, time: .shortened)
    }
}
