import Foundation
import Darwin
import LexCleanerCore
import SwiftUI

enum DiskAnalyzerPhase: Equatable {
    case idle
    case scanning
    case enriching
    case completed
    case cancelled
    case failed

    var titleKey: LocalizedStringKey {
        switch self {
        case .idle: return "diskAnalyzer.phase.idle"
        case .scanning: return "diskAnalyzer.phase.scanning"
        case .enriching: return "diskAnalyzer.phase.enriching"
        case .completed: return "diskAnalyzer.phase.completed"
        case .cancelled: return "diskAnalyzer.phase.cancelled"
        case .failed: return "diskAnalyzer.phase.failed"
        }
    }
}

enum DiskLargeFileSort: String, CaseIterable, Identifiable {
    case size
    case modified
    case name

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .size: return "diskAnalyzer.sort.size"
        case .modified: return "diskAnalyzer.sort.modified"
        case .name: return "diskAnalyzer.sort.name"
        }
    }
}

enum DiskContentFilter: String, CaseIterable, Identifiable {
    case all
    case documents
    case images
    case videos
    case audio
    case archives
    case development
    case other

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .all: return "diskAnalyzer.filter.all"
        case .documents: return "diskAnalyzer.type.documents"
        case .images: return "diskAnalyzer.type.images"
        case .videos: return "diskAnalyzer.type.videos"
        case .audio: return "diskAnalyzer.type.audio"
        case .archives: return "diskAnalyzer.type.archives"
        case .development: return "diskAnalyzer.type.development"
        case .other: return "diskAnalyzer.type.other"
        }
    }

    var contentCategory: DiskContentCategory? {
        switch self {
        case .all: return nil
        case .documents: return .documents
        case .images: return .images
        case .videos: return .videos
        case .audio: return .audio
        case .archives: return .archives
        case .development: return .development
        case .other: return .other
        }
    }
}

struct DiskVolumeSummary: Sendable, Equatable {
    let totalBytes: UInt64
    let usedBytes: UInt64
    let availableBytes: UInt64
}

struct DiskScanProgress: Equatable {
    let visitedPathCount: UInt64
    let fileCount: UInt64
    let directoryCount: UInt64
    let totalBytes: UInt64
    let allocatedBytes: UInt64
}

/// The UI bridge deliberately keeps only the bounded projections needed by the
/// current screen. The Core snapshot remains a Core-owned value and is not
/// retained by SwiftUI state.
private struct DiskCompletedProjection {
    let cancelled: Bool
    let progress: DiskScanProgress
    let volumeCapacityBytes: UInt64?
    let allocationStatus: DiskAllocationStatus
    let rootTreemapNodes: [TreemapNode]
    let largeFiles: [LargeFileEntry]
    let contentStatistics: [DiskContentCategory: DiskContentStatistics]
    let issues: [DiskAnalysisIssue]
    let suppressedIssueCount: UInt64

    init(snapshot: DiskAnalysisSnapshot, rootPath: String) {
        cancelled = snapshot.cancelled
        progress = DiskScanProgress(
            visitedPathCount: snapshot.visitedPathCount,
            fileCount: snapshot.fileCount,
            directoryCount: snapshot.directoryCount,
            totalBytes: snapshot.totalBytes,
            allocatedBytes: snapshot.allocatedBytes
        )
        volumeCapacityBytes = snapshot.volumeCapacityBytes
        allocationStatus = snapshot.allocationStatus
        // `treemapNodes` is a bounded Core projection (root/directories + Top-N
        // files). Copy only the layer shown by the Home screen, then release the
        // Core snapshot when the scan task returns.
        rootTreemapNodes = snapshot.treemapNodes(forParentPath: URL(fileURLWithPath: rootPath))
            .sorted { $0.allocatedSizeBytes > $1.allocatedSizeBytes }
        largeFiles = snapshot.largeFiles
        contentStatistics = snapshot.contentStatistics
        issues = Array(snapshot.issues.prefix(256))
        suppressedIssueCount = snapshot.suppressedIssueCount
    }
}

private final class DiskUpdateCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let rootPath: String
    private let startedAt: Date
    private var directoryNodes: [String: DiskNode] = [:]
    private var largeFiles: [String: LargeFileEntry] = [:]
    private var issues: [DiskAnalysisIssue] = []
    private var visitedPathCount: UInt64 = 0
    private var fileCount: UInt64 = 0
    private var directoryCount: UInt64 = 0
    private var totalBytes: UInt64 = 0
    private var allocatedBytes: UInt64 = 0
    private var firstUsableResultDuration: TimeInterval?

    init(rootPath: String, startedAt: Date = Date()) {
        self.rootPath = rootPath
        self.startedAt = startedAt
        firstUsableResultDuration = nil
    }

    func record(_ update: DiskAnalysisUpdate) {
        lock.lock()
        defer { lock.unlock() }
        visitedPathCount = update.visitedPathCount
        fileCount = update.fileCount
        directoryCount = update.directoryCount
        totalBytes = update.totalBytes
        allocatedBytes = update.allocatedBytes
        if let node = update.node {
            let isRootLevel = node.parentCanonicalPath?.path == rootPath || node.parentCanonicalPath == nil
            // During an in-flight Home scan retain only the visible root-level
            // aggregate. The completed snapshot owns the full tree; keeping
            // thousands of transient nodes here only makes SwiftUI rebuild a
            // large graph repeatedly without improving the live view.
            if isRootLevel {
                directoryNodes[node.canonicalPath.path] = node
                if firstUsableResultDuration == nil {
                    firstUsableResultDuration = Date().timeIntervalSince(startedAt)
                }
            }
        }
        if let largeFile = update.largeFile { largeFiles[largeFile.canonicalPath.path] = largeFile }
        if let issue = update.issue, issues.count < 256 { issues.append(issue) }
    }

    func values() -> (nodes: [String: DiskNode], largeFiles: [String: LargeFileEntry], issues: [DiskAnalysisIssue], visited: UInt64, files: UInt64, directories: UInt64, bytes: UInt64, allocated: UInt64, firstUsableResultDuration: TimeInterval?) {
        lock.lock()
        defer { lock.unlock() }
        // Return copy-on-write containers directly. Rebuilding arrays and dictionaries
        // every 150 ms caused avoidable allocation spikes on large home scans.
        return (directoryNodes, largeFiles, issues, visitedPathCount, fileCount, directoryCount, totalBytes, allocatedBytes, firstUsableResultDuration)
    }
}

@MainActor
final class DiskAnalyzerViewModel: ObservableObject {
    @Published private(set) var phase: DiskAnalyzerPhase = .idle
    /// True once the first bounded root-level inventory can render a Treemap.
    /// The final snapshot remains authoritative for all quality-sensitive data.
    @Published private(set) var fastInventoryReady = false
    @Published private(set) var fastInventoryTime: TimeInterval?
    @Published private(set) var volume: DiskVolumeSummary?
    private var liveDirectoryNodes: [String: DiskNode] = [:]
    private var liveLargeFiles: [String: LargeFileEntry] = [:]
    @Published private(set) var liveIssues: [DiskAnalysisIssue] = []
    @Published private(set) var progress = DiskScanProgress(visitedPathCount: 0, fileCount: 0, directoryCount: 0, totalBytes: 0, allocatedBytes: 0)
    @Published private(set) var treemapNodes: [TreemapNode] = []
    @Published private(set) var filteredLargeFileEntries: [LargeFileEntry] = []
    @Published private(set) var isLoadingTreemap = false
    @Published private(set) var lastError: String?
    @Published var searchText = "" { didSet { rebuildLargeFileProjection() } }
    @Published var sortOrder: DiskLargeFileSort = .size { didSet { rebuildLargeFileProjection() } }
    @Published var contentFilter: DiskContentFilter = .all { didSet { rebuildLargeFileProjection() } }
    @Published private(set) var currentDirectory: URL?

    let scanRoot: URL
    private let engine = DiskAnalysisEngine(maxConcurrentDirectories: 4)
    private var scanTask: Task<Void, Never>?
    private var liveUpdateTask: Task<Void, Never>?
    private var treemapTask: Task<Void, Never>?
    private var volumeTask: Task<Void, Never>?
    private var hasStarted = false
    private var lastLiveProjectionUpdate = Date.distantPast

    init(scanRoot: URL? = nil) {
        self.scanRoot = (scanRoot ?? FileManager.default.homeDirectoryForCurrentUser).standardizedFileURL
    }

    var isScanning: Bool { phase == .scanning || phase == .enriching }
    private var completedProjection: DiskCompletedProjection?

    var issues: [DiskAnalysisIssue] { completedProjection?.issues ?? liveIssues }
    var issueCount: UInt64 { UInt64(issues.count) + (completedProjection?.suppressedIssueCount ?? 0) }
    var isComplete: Bool { completedProjection != nil && phase == .completed }
    var visitedPathCount: UInt64 { progress.visitedPathCount }
    var scannedFileCount: UInt64 { progress.fileCount }
    var scannedDirectoryCount: UInt64 { progress.directoryCount }
    var scannedBytes: UInt64 { progress.totalBytes }
    var scannedLogicalBytes: UInt64 { progress.totalBytes }
    var scannedAllocatedBytes: UInt64 { completedProjection?.progress.allocatedBytes ?? progress.allocatedBytes }
    var volumeCapacityBytes: UInt64? { completedProjection?.volumeCapacityBytes }
    var allocationStatus: DiskAllocationStatus { completedProjection?.allocationStatus ?? .unavailable }

    var directoryNodes: [DiskNode] {
        return Array(liveDirectoryNodes.values)
    }

    var largeFiles: [LargeFileEntry] {
        if let completedProjection { return completedProjection.largeFiles }
        return Array(liveLargeFiles.values)
    }

    private var currentLargeFiles: [LargeFileEntry] {
        if let completedProjection { return completedProjection.largeFiles }
        return Array(liveLargeFiles.values)
    }

    private func rebuildLargeFileProjection() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        filteredLargeFileEntries = currentLargeFiles.filter { entry in
            let matchesFilter = contentFilter.contentCategory.map { DiskContentCategory.classify(path: entry.path) == $0 } ?? true
            let matchesSearch = query.isEmpty || entry.path.path.lowercased().contains(query)
            return matchesFilter && matchesSearch
        }.sorted { lhs, rhs in
            switch sortOrder {
            case .size:
                return lhs.allocatedSizeBytes == rhs.allocatedSizeBytes ? lhs.path.path < rhs.path.path : lhs.allocatedSizeBytes > rhs.allocatedSizeBytes
            case .modified:
                return lhs.lastModified == rhs.lastModified ? lhs.path.path < rhs.path.path : (lhs.lastModified ?? .distantPast) > (rhs.lastModified ?? .distantPast)
            case .name:
                return lhs.path.lastPathComponent.localizedStandardCompare(rhs.path.lastPathComponent) == .orderedAscending
            }
        }
    }

    var currentDirectoryName: String { currentDirectory?.lastPathComponent ?? scanRoot.lastPathComponent }

    var contentStatistics: [DiskContentCategory: DiskContentStatistics] {
        completedProjection?.contentStatistics ?? [:]
    }

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        loadVolume()
        scan()
    }

    func scan() {
        scanTask?.cancel()
        completedProjection = nil
        liveDirectoryNodes = [:]
        liveLargeFiles = [:]
        liveIssues = []
        treemapNodes = []
        treemapCache.removeAll(keepingCapacity: false)
        filteredLargeFileEntries = []
        fastInventoryReady = false
        fastInventoryTime = nil
        lastLiveProjectionUpdate = .distantPast
        progress = DiskScanProgress(visitedPathCount: 0, fileCount: 0, directoryCount: 0, totalBytes: 0, allocatedBytes: 0)
        lastError = nil
        currentDirectory = scanRoot
        phase = .scanning

        let root = scanRoot
        let identityCapacity = root.path.hasSuffix("/Library/Caches") ? (1 << 14) : (1 << 18)
        let collector = DiskUpdateCollector(rootPath: root.path, startedAt: Date())
        let engine = self.engine
        liveUpdateTask?.cancel()
        treemapTask?.cancel()
        isLoadingTreemap = false
        liveUpdateTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let values = collector.values()
                self?.apply(values)
                // Poll more frequently only until the first bounded inventory
                // projection is available; the enrichment phase is throttled
                // back to avoid turning progress into UI work.
                let interval: Duration = self?.fastInventoryReady == true ? .milliseconds(150) : .milliseconds(10)
                try? await Task.sleep(for: interval)
            }
        }
        scanTask = Task { [weak self] in
            let projection: DiskCompletedProjection
            do {
                let configuration = DiskAnalysisConfiguration(
                    allowedRoots: [root],
                    maxConcurrentDirectories: 4,
                    largeFiles: LargeFileOptions(thresholdBytes: 50 * 1024 * 1024, topN: 100),
                    memorySampleStride: 512,
                    initialDirectoryIdentityCapacity: identityCapacity,
                    adaptiveConcurrency: true
                )
                let result = await engine.analyze(
                    targets: [DiskAnalysisTarget(url: root)],
                    configuration: configuration
                ) { update in
                    collector.record(update)
                }
                guard !Task.isCancelled else { return }
                // Keep the Core snapshot inside this scope. The bridge receives
                // only the bounded current-layer/top-N projection, then the
                // full snapshot is released before the main-actor transition.
                projection = DiskCompletedProjection(snapshot: result, rootPath: root.path)
            }
            // Release only allocator pages that are no longer in use. This is
            // deliberately off the main actor and does not discard any Core
            // projection or alter scan results.
            _ = malloc_zone_pressure_relief(malloc_default_zone(), 0)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.completedProjection = projection
                // The completed Core snapshot is intentionally not stored in the
                // ViewModel. SwiftUI receives only the bounded screen projection.
                self.liveDirectoryNodes.removeAll(keepingCapacity: false)
                self.liveLargeFiles.removeAll(keepingCapacity: false)
                self.liveIssues = projection.issues
                self.progress = projection.progress
                self.currentDirectory = self.currentDirectory ?? root
                self.treemapNodes = projection.rootTreemapNodes
                self.rebuildLargeFileProjection()
                self.phase = projection.cancelled ? .cancelled : .completed
                self.scanTask = nil
                self.liveUpdateTask?.cancel()
                self.liveUpdateTask = nil
            }
        }
    }

    func cancel() {
        guard isScanning else { return }
        scanTask?.cancel()
        liveUpdateTask?.cancel()
        treemapTask?.cancel()
        isLoadingTreemap = false
        // A cancelled scan is not a result that can be drilled into safely. Drop
        // the live projection so a large partial home scan is promptly reclaimable.
        liveDirectoryNodes.removeAll(keepingCapacity: false)
        liveLargeFiles.removeAll(keepingCapacity: false)
        liveIssues.removeAll(keepingCapacity: false)
        treemapNodes = []
        filteredLargeFileEntries = []
        phase = .cancelled
    }

    /// Releases every screen-owned scan projection when this page is no longer
    /// visible. A later visit starts a fresh scan rather than retaining a
    /// Home-sized result graph in the app process.
    func deactivate() {
        scanTask?.cancel()
        liveUpdateTask?.cancel()
        treemapTask?.cancel()
        volumeTask?.cancel()
        scanTask = nil
        liveUpdateTask = nil
        treemapTask = nil
        volumeTask = nil
        completedProjection = nil
        liveDirectoryNodes.removeAll(keepingCapacity: false)
        liveLargeFiles.removeAll(keepingCapacity: false)
        liveIssues.removeAll(keepingCapacity: false)
        treemapNodes.removeAll(keepingCapacity: false)
        treemapCache.removeAll(keepingCapacity: false)
        filteredLargeFileEntries.removeAll(keepingCapacity: false)
        progress = DiskScanProgress(visitedPathCount: 0, fileCount: 0, directoryCount: 0, totalBytes: 0, allocatedBytes: 0)
        currentDirectory = nil
        fastInventoryReady = false
        fastInventoryTime = nil
        isLoadingTreemap = false
        lastError = nil
        phase = .idle
        hasStarted = false
        // The completed Home scan can leave empty allocator pages behind even
        // after all SwiftUI projections have been dropped. Reclaim only pages
        // that no longer contain live allocations, off the main actor.
        Task.detached(priority: .utility) {
            _ = malloc_zone_pressure_relief(malloc_default_zone(), 0)
        }
    }

    func enter(_ node: TreemapNode) {
        guard node.category == .directory, !node.isOther else { return }
        currentDirectory = node.path
        let path = node.path.standardizedFileURL.path
        if let cached = treemapCache[path] {
            treemapNodes = cached
        } else {
            loadTreemapChildren(for: node.path)
        }
    }

    func goToRoot() {
        currentDirectory = scanRoot
        if let cached = treemapCache[scanRoot.path] {
            treemapNodes = cached
        } else {
            rebuildTreemapNodes()
        }
    }

    func goToParent() {
        guard let currentDirectory, currentDirectory.standardizedFileURL.path != scanRoot.path else { return }
        self.currentDirectory = currentDirectory.deletingLastPathComponent()
        let parent = self.currentDirectory?.standardizedFileURL.path ?? scanRoot.path
        if let cached = treemapCache[parent] {
            treemapNodes = cached
        } else {
            loadTreemapChildren(for: self.currentDirectory ?? scanRoot)
        }
    }

    func clearSearch() { searchText = "" }

    private func apply(_ values: (nodes: [String: DiskNode], largeFiles: [String: LargeFileEntry], issues: [DiskAnalysisIssue], visited: UInt64, files: UInt64, directories: UInt64, bytes: UInt64, allocated: UInt64, firstUsableResultDuration: TimeInterval?)) {
        guard phase == .scanning || phase == .enriching else { return }
        let now = Date()
        if !fastInventoryReady, let firstUsableResultDuration = values.firstUsableResultDuration {
            liveDirectoryNodes = values.nodes
            liveLargeFiles = values.largeFiles
            liveIssues = Array(values.issues.prefix(256))
            progress = DiskScanProgress(visitedPathCount: values.visited, fileCount: values.files, directoryCount: values.directories, totalBytes: values.bytes, allocatedBytes: values.allocated)
            rebuildTreemapNodes()
            fastInventoryReady = true
            fastInventoryTime = firstUsableResultDuration
            phase = .enriching
            lastLiveProjectionUpdate = now
            return
        }
        if now.timeIntervalSince(lastLiveProjectionUpdate) >= 0.75 {
            liveDirectoryNodes = values.nodes
            liveLargeFiles = values.largeFiles
            liveIssues = Array(values.issues.prefix(256))
            rebuildTreemapNodes()
            rebuildLargeFileProjection()
            progress = DiskScanProgress(visitedPathCount: values.visited, fileCount: values.files, directoryCount: values.directories, totalBytes: values.bytes, allocatedBytes: values.allocated)
            lastLiveProjectionUpdate = now
        }
    }

    private func rebuildTreemapNodes() {
        let currentPath = (currentDirectory ?? scanRoot).standardizedFileURL.path
        let directories: [DiskNode]
        let largeFiles: [LargeFileEntry]
        if let completedProjection {
            if currentPath == scanRoot.standardizedFileURL.path {
                treemapNodes = completedProjection.rootTreemapNodes
            }
            return
        } else {
            directories = Array(liveDirectoryNodes.values)
            largeFiles = Array(liveLargeFiles.values)
        }
        let currentID = currentPath
        let directoryProjection = directories.lazy.filter { $0.parentCanonicalPath?.path == currentID }.map { node in
            TreemapNode(id: node.canonicalPath.path, path: node.path, parentID: node.parentCanonicalPath?.path, name: node.name, category: .directory, sizeBytes: node.sizeBytes, allocatedSizeBytes: node.allocatedSizeBytes, fileCount: node.fileCount, directoryCount: node.directoryCount, isLargeFile: false)
        }
        let fileProjection = largeFiles.lazy.filter { $0.canonicalPath.deletingLastPathComponent().standardizedFileURL.path == currentID }.map { entry in
            TreemapNode(id: "file:\(entry.canonicalPath.path)", path: entry.path, parentID: entry.canonicalPath.deletingLastPathComponent().standardizedFileURL.path, name: entry.path.lastPathComponent, category: entry.fileType, sizeBytes: entry.sizeBytes, allocatedSizeBytes: entry.allocatedSizeBytes, fileCount: 1, directoryCount: 0, isLargeFile: true)
        }
        treemapNodes = (Array(directoryProjection) + Array(fileProjection)).sorted { $0.allocatedSizeBytes > $1.allocatedSizeBytes }
    }

    // A small navigation cache avoids retaining a history of every drilled
    // directory. The current visible layer remains the only unbounded UI input.
    private var treemapCache: [String: [TreemapNode]] = [:]

    private func cacheTreemap(_ nodes: [TreemapNode], for path: String) {
        if treemapCache.count >= 4, treemapCache[path] == nil {
            if let oldestKey = treemapCache.keys.first {
                treemapCache.removeValue(forKey: oldestKey)
            }
        }
        treemapCache[path] = nodes
    }

    private func loadTreemapChildren(for directory: URL) {
        treemapTask?.cancel()
        isLoadingTreemap = true
        let target = directory.standardizedFileURL
        let root = scanRoot
        let engine = self.engine
        treemapTask = Task { [weak self] in
            let configuration = DiskAnalysisConfiguration(
                allowedRoots: [root],
                maxConcurrentDirectories: 2,
                largeFiles: LargeFileOptions(thresholdBytes: 50 * 1024 * 1024, topN: 100),
                memorySampleStride: 512
            )
            let snapshot = await engine.analyze(
                targets: [DiskAnalysisTarget(url: target)],
                configuration: configuration
            )
            guard !Task.isCancelled else { return }
            // The subtree scan treats `target` as its new root. Depending on
            // whether a node came from the aggregate projection or the
            // bounded large-file projection, its parentID can be nil or a
            // canonical path from the original scan. Use the resolved direct
            // parent as the UI boundary so a drill never leaves the previous
            // layer visible when the async subtree result arrives.
            let nodes = snapshot.treemapNodes(forParentPath: target)
                .sorted { $0.allocatedSizeBytes > $1.allocatedSizeBytes }
            await MainActor.run { [weak self] in
                guard let self, self.currentDirectory?.standardizedFileURL.path == target.path else { return }
                self.cacheTreemap(nodes, for: target.path)
                self.treemapNodes = nodes
                self.isLoadingTreemap = false
                self.treemapTask = nil
            }
        }
    }

    private func loadVolume() {
        volumeTask?.cancel()
        volumeTask = Task { [weak self] in
            let value = await Task.detached(priority: .utility) {
                Self.readVolume(at: URL(fileURLWithPath: "/"))
            }.value
            guard !Task.isCancelled else { return }
            self?.volume = value
            self?.volumeTask = nil
        }
    }

    private nonisolated static func readVolume(at url: URL) -> DiskVolumeSummary? {
        guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else { return nil }
        let totalBytes = UInt64(max(0, total))
        let availableBytes = UInt64(max(0, available))
        return DiskVolumeSummary(totalBytes: totalBytes, usedBytes: totalBytes >= availableBytes ? totalBytes - availableBytes : 0, availableBytes: availableBytes)
    }

    private nonisolated func canonicalPath(_ url: URL) -> URL { url.standardizedFileURL }

    deinit {
        scanTask?.cancel()
        liveUpdateTask?.cancel()
        treemapTask?.cancel()
        volumeTask?.cancel()
    }
}
