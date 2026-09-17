import Foundation
import Darwin

public enum ScanCategory: String, CaseIterable, Codable, Sendable, Hashable {
    case userCache
    case applicationCache
    case logs
    case temporaryFiles
}

public enum ScanRiskLevel: String, Codable, Sendable, Hashable {
    case low
    case review
    case protected
}

public typealias RiskLevel = ScanRiskLevel
public typealias Category = ScanCategory

public enum ScanFileType: String, Codable, Sendable, Hashable {
    case regularFile
    case directory
    case symbolicLink
    case other
}

public enum ScanPathMatcher: Codable, Sendable, Hashable {
    case all
    case directoryNames(names: Set<String>, maxDiscoveryDepth: Int)
}

public struct ScanRule: Codable, Sendable, Hashable {
    public let id: String
    public let category: ScanCategory
    public let riskLevel: ScanRiskLevel
    public let allowedRoots: [URL]
    public let excludedPaths: [URL]
    public let matcher: ScanPathMatcher

    public init(
        id: String,
        category: ScanCategory,
        riskLevel: ScanRiskLevel,
        allowedRoots: [URL],
        excludedPaths: [URL] = [],
        matcher: ScanPathMatcher = .all
    ) {
        self.id = id
        self.category = category
        self.riskLevel = riskLevel
        self.allowedRoots = allowedRoots
        self.excludedPaths = excludedPaths
        self.matcher = matcher
    }
}

public struct ScanTarget: Codable, Sendable, Hashable {
    public let url: URL
    public let ruleID: String

    public init(url: URL, ruleID: String) {
        self.url = url
        self.ruleID = ruleID
    }
}

public enum ScanIssueKind: String, Codable, Sendable, Hashable {
    case invalidTarget
    case notFound
    case notDirectory
    case permissionDenied
    case enumerationFailed
    case metadataUnavailable
    case symlinkSkipped
    case symlinkEscape
    case duplicatePath
    case excludedPath
    case protectedPath
    case missingRule
    case cancelled
}

public struct ScanIssue: Codable, Sendable, Hashable {
    public let kind: ScanIssueKind
    public let path: URL
    public let detail: String
    public let riskLevel: ScanRiskLevel

    public init(kind: ScanIssueKind, path: URL, detail: String, riskLevel: ScanRiskLevel) {
        self.kind = kind
        self.path = path
        self.detail = detail
        self.riskLevel = riskLevel
    }
}

public struct ScanItem: Codable, Sendable, Hashable {
    public let path: URL
    public let category: ScanCategory
    public let fileType: ScanFileType
    public let sizeBytes: UInt64
    public let lastModified: Date?
    public let riskLevel: ScanRiskLevel

    public init(
        path: URL,
        category: ScanCategory,
        fileType: ScanFileType,
        sizeBytes: UInt64,
        lastModified: Date?,
        riskLevel: ScanRiskLevel
    ) {
        self.path = path
        self.category = category
        self.fileType = fileType
        self.sizeBytes = sizeBytes
        self.lastModified = lastModified
        self.riskLevel = riskLevel
    }
}

public struct ScanProgress: Sendable {
    public let currentPath: URL?
    public let item: ScanItem?
    public let visitedPathCount: UInt64
    public let discoveredFileCount: UInt64
    public let discoveredDirectoryCount: UInt64
    public let discoveredBytes: UInt64
    public let elapsed: TimeInterval

    public init(
        currentPath: URL?,
        item: ScanItem? = nil,
        visitedPathCount: UInt64,
        discoveredFileCount: UInt64,
        discoveredDirectoryCount: UInt64,
        discoveredBytes: UInt64,
        elapsed: TimeInterval
    ) {
        self.currentPath = currentPath
        self.item = item
        self.visitedPathCount = visitedPathCount
        self.discoveredFileCount = discoveredFileCount
        self.discoveredDirectoryCount = discoveredDirectoryCount
        self.discoveredBytes = discoveredBytes
        self.elapsed = elapsed
    }
}

public struct ScanSummary: Codable, Sendable, Hashable {
    public let category: ScanCategory
    public let fileCount: UInt64
    public let directoryCount: UInt64
    public let totalBytes: UInt64
    public let directoryMetadataBytes: UInt64
    public let latestModification: Date?

    public init(
        category: ScanCategory,
        fileCount: UInt64,
        directoryCount: UInt64,
        totalBytes: UInt64,
        directoryMetadataBytes: UInt64,
        latestModification: Date?
    ) {
        self.category = category
        self.fileCount = fileCount
        self.directoryCount = directoryCount
        self.totalBytes = totalBytes
        self.directoryMetadataBytes = directoryMetadataBytes
        self.latestModification = latestModification
    }
}

public struct ScanMemorySample: Codable, Sendable, Hashable {
    public let elapsed: TimeInterval
    public let residentMemoryBytes: UInt64

    public init(elapsed: TimeInterval, residentMemoryBytes: UInt64) {
        self.elapsed = elapsed
        self.residentMemoryBytes = residentMemoryBytes
    }
}

public struct ScanPerformanceMetrics: Codable, Sendable, Hashable {
    public let duration: TimeInterval
    public let peakResidentMemoryBytes: UInt64
    public let memorySamples: [ScanMemorySample]
    public let maxObservedConcurrentDirectories: Int

    public init(
        duration: TimeInterval,
        peakResidentMemoryBytes: UInt64,
        memorySamples: [ScanMemorySample],
        maxObservedConcurrentDirectories: Int
    ) {
        self.duration = duration
        self.peakResidentMemoryBytes = peakResidentMemoryBytes
        self.memorySamples = memorySamples
        self.maxObservedConcurrentDirectories = maxObservedConcurrentDirectories
    }
}

public struct ScanResult: Codable, Sendable {
    public let startedAt: Date
    public let finishedAt: Date
    public let cancelled: Bool
    public let visitedPathCount: UInt64
    public let fileCount: UInt64
    public let directoryCount: UInt64
    public let totalBytes: UInt64
    public let summaries: [ScanSummary]
    public let issues: [ScanIssue]
    public let performance: ScanPerformanceMetrics

    public init(
        startedAt: Date,
        finishedAt: Date,
        cancelled: Bool,
        visitedPathCount: UInt64,
        fileCount: UInt64,
        directoryCount: UInt64,
        totalBytes: UInt64,
        summaries: [ScanSummary],
        issues: [ScanIssue],
        performance: ScanPerformanceMetrics
    ) {
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.cancelled = cancelled
        self.visitedPathCount = visitedPathCount
        self.fileCount = fileCount
        self.directoryCount = directoryCount
        self.totalBytes = totalBytes
        self.summaries = summaries
        self.issues = issues
        self.performance = performance
    }
}

public actor ScanEngine {
    private let maxConcurrentDirectories: Int

    public init(maxConcurrentDirectories: Int = 4) {
        self.maxConcurrentDirectories = max(1, maxConcurrentDirectories)
    }

    public static func builtInRules(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) -> [ScanRule] {
        let home = homeDirectory.standardizedFileURL
        return [
            ScanRule(
                id: "user-cache",
                category: .userCache,
                riskLevel: .low,
                allowedRoots: [home.appendingPathComponent("Library/Caches", isDirectory: true)]
            ),
            ScanRule(
                id: "application-cache",
                category: .applicationCache,
                riskLevel: .review,
                allowedRoots: [home.appendingPathComponent("Library/Application Support", isDirectory: true)],
                matcher: .directoryNames(
                    names: ["Cache", "Caches", "CacheStorage", "Code Cache", "GPUCache", "Service Worker", "WebKit"],
                    maxDiscoveryDepth: 2
                )
            ),
            ScanRule(
                id: "logs",
                category: .logs,
                riskLevel: .review,
                allowedRoots: [home.appendingPathComponent("Library/Logs", isDirectory: true)]
            ),
            ScanRule(
                id: "temporary-files",
                category: .temporaryFiles,
                riskLevel: .low,
                allowedRoots: [temporaryDirectory.standardizedFileURL]
            )
        ]
    }

    public static func builtInTargets(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) -> [ScanTarget] {
        builtInRules(homeDirectory: homeDirectory, temporaryDirectory: temporaryDirectory).compactMap { rule in
            guard let root = rule.allowedRoots.first else { return nil }
            return ScanTarget(url: root, ruleID: rule.id)
        }
    }

    public func scan(
        targets: [ScanTarget],
        rules: [ScanRule],
        progress: (@Sendable (ScanProgress) async -> Void)? = nil
    ) async -> ScanResult {
        let startedAt = Date()
        let accumulator = ScanAccumulator(startedAt: startedAt)
        let queue = DirectoryWorkQueue()
        let rulesByID = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0) })
        var initialItems: [ScanWorkItem] = []
        var initialPaths: Set<String> = []

        for target in targets {
            guard let rule = rulesByID[target.ruleID] else {
                await accumulator.recordIssue(ScanIssue(
                    kind: .missingRule,
                    path: target.url.standardizedFileURL,
                    detail: "No ScanRule exists for ruleID \(target.ruleID).",
                    riskLevel: .protected
                ))
                continue
            }

            guard let item = await Self.makeInitialWorkItem(target: target, rule: rule, accumulator: accumulator) else {
                continue
            }
            if initialPaths.insert(item.url.path).inserted {
                initialItems.append(item)
            } else {
                await accumulator.recordIssue(ScanIssue(
                    kind: .duplicatePath,
                    path: item.url,
                    detail: "Duplicate scan target was skipped.",
                    riskLevel: rule.riskLevel
                ))
            }
        }

        let initialDuplicates = await queue.enqueue(initialItems)
        for duplicate in initialDuplicates {
            await accumulator.recordIssue(ScanIssue(
                kind: .duplicatePath,
                path: duplicate,
                detail: "Canonical directory was already queued or scanned.",
                riskLevel: .review
            ))
        }

        if !initialItems.isEmpty {
            await withTaskGroup(of: Void.self) { group in
                let workerCount = maxConcurrentDirectories
                for _ in 0..<workerCount {
                    group.addTask {
                        await Self.worker(
                            queue: queue,
                            accumulator: accumulator,
                            rulesByID: rulesByID,
                            progress: progress
                        )
                    }
                }
            }
        }

        let wasCancelled = Task.isCancelled
        if wasCancelled {
            await accumulator.recordIssue(ScanIssue(
                kind: .cancelled,
                path: URL(fileURLWithPath: "/"),
                detail: "Scan cancelled before completion.",
                riskLevel: .low
            ))
        }
        let finishedAt = Date()
        let result = await accumulator.makeResult(
            finishedAt: finishedAt,
            cancelled: wasCancelled,
            maxObservedConcurrentDirectories: await queue.maxObservedConcurrency()
        )
        if let progress {
            await progress(ScanProgress(
                currentPath: nil,
                visitedPathCount: result.visitedPathCount,
                discoveredFileCount: result.fileCount,
                discoveredDirectoryCount: result.directoryCount,
                discoveredBytes: result.totalBytes,
                elapsed: result.performance.duration
            ))
        }
        return result
    }

    private static func makeInitialWorkItem(
        target: ScanTarget,
        rule: ScanRule,
        accumulator: ScanAccumulator
    ) async -> ScanWorkItem? {
        let normalized = target.url.standardizedFileURL
        guard normalized.path.hasPrefix("/") else {
            await accumulator.recordIssue(ScanIssue(kind: .invalidTarget, path: normalized, detail: "Only absolute scan paths are accepted.", riskLevel: .protected))
            return nil
        }
        guard let metadata = nodeMetadata(at: normalized) else {
            await accumulator.recordIssue(ScanIssue(kind: .notFound, path: normalized, detail: "Target does not exist or cannot be inspected.", riskLevel: .review))
            return nil
        }
        if metadata.fileType == .symbolicLink {
            await accumulator.recordIssue(ScanIssue(kind: .symlinkSkipped, path: normalized, detail: "Symlink targets are not recursively scanned.", riskLevel: .review))
            return nil
        }
        guard metadata.fileType == .directory else {
            await accumulator.recordIssue(ScanIssue(kind: .notDirectory, path: normalized, detail: "Scan targets must be directories.", riskLevel: .review))
            return nil
        }
        guard let resolved = canonicalURL(normalized) else {
            await accumulator.recordIssue(ScanIssue(kind: .metadataUnavailable, path: normalized, detail: "Target canonicalization failed.", riskLevel: .protected))
            return nil
        }
        guard isWithinAnyRoot(normalized, roots: rule.allowedRoots) || isWithinAnyRoot(resolved, roots: rule.allowedRoots) else {
            await accumulator.recordIssue(ScanIssue(kind: .protectedPath, path: normalized, detail: "Target is outside its ScanRule allowlist.", riskLevel: .protected))
            return nil
        }
        if isHardExcluded(resolved, homeDirectory: FileManager.default.homeDirectoryForCurrentUser) || isRuleExcluded(resolved, rule: rule) {
            await accumulator.recordIssue(ScanIssue(kind: .excludedPath, path: normalized, detail: "Target is excluded by scan safety policy.", riskLevel: .protected))
            return nil
        }
        let matchedScope: Bool
        switch rule.matcher {
        case .all:
            matchedScope = true
        case .directoryNames:
            matchedScope = false
        }
        return ScanWorkItem(url: normalized, canonicalURL: resolved, ruleID: rule.id, depth: 0, inMatchedScope: matchedScope)
    }

    private static func worker(
        queue: DirectoryWorkQueue,
        accumulator: ScanAccumulator,
        rulesByID: [String: ScanRule],
        progress: (@Sendable (ScanProgress) async -> Void)?
    ) async {
        while !Task.isCancelled {
            guard let work = await queue.next() else { return }
            guard let rule = rulesByID[work.ruleID] else {
                await accumulator.recordIssue(ScanIssue(kind: .missingRule, path: work.url, detail: "ScanRule disappeared during scan.", riskLevel: .protected))
                await queue.complete()
                continue
            }

            _ = await accumulator.recordVisit(path: work.url)
            if work.inMatchedScope, let metadata = nodeMetadata(at: work.url) {
                await recordItem(entryURL: work.url, metadata: metadata, rule: rule, accumulator: accumulator, progress: progress)
            }
            let children = await scanDirectory(work: work, rule: rule, accumulator: accumulator, progress: progress)
            let duplicates = await queue.enqueue(children)
            for duplicate in duplicates {
                await accumulator.recordIssue(ScanIssue(kind: .duplicatePath, path: duplicate, detail: "Canonical directory was already queued or scanned.", riskLevel: rule.riskLevel))
            }
            await queue.complete()
        }
        await queue.cancel()
    }

    private static func scanDirectory(
        work: ScanWorkItem,
        rule: ScanRule,
        accumulator: ScanAccumulator,
        progress: (@Sendable (ScanProgress) async -> Void)?
    ) async -> [ScanWorkItem] {
        guard !Task.isCancelled else { return [] }
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: work.url,
                includingPropertiesForKeys: nil,
                options: []
            )
        } catch {
            let issueKind: ScanIssueKind = isPermissionError(error) ? .permissionDenied : .enumerationFailed
            await accumulator.recordIssue(ScanIssue(kind: issueKind, path: work.url, detail: error.localizedDescription, riskLevel: rule.riskLevel))
            return []
        }

        var children: [ScanWorkItem] = []
        children.reserveCapacity(entries.count)
        for entryURL in entries {
            if Task.isCancelled { break }
            guard let metadata = nodeMetadata(at: entryURL) else {
                await accumulator.recordIssue(ScanIssue(kind: .metadataUnavailable, path: entryURL.standardizedFileURL, detail: "lstat failed; entry skipped.", riskLevel: rule.riskLevel))
                continue
            }
            if let snapshot = await accumulator.recordVisit(path: entryURL.standardizedFileURL), let callback = progress {
                await callback(snapshot)
            }

            if metadata.fileType == .symbolicLink {
                let normalized = entryURL.standardizedFileURL
                if let resolved = canonicalURL(normalized), !isWithinAnyRoot(resolved, roots: rule.allowedRoots) {
                    await accumulator.recordIssue(ScanIssue(kind: .symlinkEscape, path: normalized, detail: "Symlink target is outside the ScanRule allowlist; recursion refused.", riskLevel: .protected))
                } else {
                    await accumulator.recordIssue(ScanIssue(kind: .symlinkSkipped, path: normalized, detail: "Symlink was treated as a leaf; recursion refused.", riskLevel: .review))
                }
                if work.inMatchedScope {
                    await recordItem(entryURL: normalized, metadata: metadata, rule: rule, accumulator: accumulator, progress: progress)
                }
                continue
            }

            guard let canonical = canonicalURL(entryURL) else {
                await accumulator.recordIssue(ScanIssue(kind: .metadataUnavailable, path: entryURL.standardizedFileURL, detail: "Canonicalization failed; entry skipped.", riskLevel: .protected))
                continue
            }
            if isHardExcluded(canonical, homeDirectory: FileManager.default.homeDirectoryForCurrentUser) || isRuleExcluded(canonical, rule: rule) {
                await accumulator.recordIssue(ScanIssue(kind: .excludedPath, path: entryURL.standardizedFileURL, detail: "Entry is excluded by scan safety policy.", riskLevel: .protected))
                continue
            }
            guard isWithinAnyRoot(canonical, roots: rule.allowedRoots) else {
                await accumulator.recordIssue(ScanIssue(kind: .protectedPath, path: entryURL.standardizedFileURL, detail: "Resolved entry escaped the ScanRule allowlist.", riskLevel: .protected))
                continue
            }

            if metadata.fileType == .directory {
                let childDepth = work.depth + 1
                let (shouldDescend, childMatchedScope) = descentDecision(
                    rule.matcher,
                    name: entryURL.lastPathComponent,
                    childDepth: childDepth,
                    inheritedMatchedScope: work.inMatchedScope
                )
                if shouldDescend {
                    children.append(ScanWorkItem(
                        url: entryURL.standardizedFileURL,
                        canonicalURL: canonical,
                        ruleID: rule.id,
                        depth: childDepth,
                        inMatchedScope: childMatchedScope
                    ))
                }
            } else if work.inMatchedScope {
                await recordItem(entryURL: entryURL.standardizedFileURL, metadata: metadata, rule: rule, accumulator: accumulator, progress: progress)
            }
        }
        return children
    }

    private static func recordItem(
        entryURL: URL,
        metadata: ScanNodeMetadata,
        rule: ScanRule,
        accumulator: ScanAccumulator,
        progress: (@Sendable (ScanProgress) async -> Void)?
    ) async {
        let item = ScanItem(
            path: entryURL,
            category: rule.category,
            fileType: metadata.fileType,
            sizeBytes: metadata.sizeBytes,
            lastModified: metadata.lastModified,
            riskLevel: rule.riskLevel
        )
        if let snapshot = await accumulator.recordItem(item), let callback = progress {
            await callback(snapshot)
        }
    }

    private static func descentDecision(
        _ matcher: ScanPathMatcher,
        name: String,
        childDepth: Int,
        inheritedMatchedScope: Bool
    ) -> (Bool, Bool) {
        if inheritedMatchedScope { return (true, true) }
        switch matcher {
        case .all:
            return (true, true)
        case let .directoryNames(names, maxDiscoveryDepth):
            if names.contains(name) { return (true, true) }
            return (childDepth < max(1, maxDiscoveryDepth), false)
        }
    }
}

private struct ScanWorkItem: Sendable {
    let url: URL
    let canonicalURL: URL
    let ruleID: String
    let depth: Int
    let inMatchedScope: Bool
}

private struct ScanNodeMetadata: Sendable {
    let fileType: ScanFileType
    let sizeBytes: UInt64
    let lastModified: Date?
}

private actor DirectoryWorkQueue {
    private var pending: [ScanWorkItem] = []
    private var seenCanonicalPaths: Set<String> = []
    private var inFlight = 0
    private var maxInFlight = 0
    private var cancelled = false
    private var waiters: [CheckedContinuation<ScanWorkItem?, Never>] = []

    func enqueue(_ items: [ScanWorkItem]) -> [URL] {
        var duplicates: [URL] = []
        for item in items {
            guard seenCanonicalPaths.insert(item.canonicalURL.path).inserted else {
                duplicates.append(item.url)
                continue
            }
            if let waiter = waiters.popLast() {
                inFlight += 1
                maxInFlight = max(maxInFlight, inFlight)
                waiter.resume(returning: item)
            } else {
                pending.append(item)
            }
        }
        return duplicates
    }

    func next() async -> ScanWorkItem? {
        guard !cancelled else { return nil }
        if let item = pending.popLast() {
            inFlight += 1
            maxInFlight = max(maxInFlight, inFlight)
            return item
        }
        if inFlight == 0 { return nil }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func complete() {
        inFlight = max(0, inFlight - 1)
        if inFlight == 0 && pending.isEmpty {
            let currentWaiters = waiters
            waiters.removeAll()
            for waiter in currentWaiters { waiter.resume(returning: nil) }
        }
    }

    func cancel() {
        cancelled = true
        pending.removeAll()
        let currentWaiters = waiters
        waiters.removeAll()
        for waiter in currentWaiters { waiter.resume(returning: nil) }
    }

    func maxObservedConcurrency() -> Int { maxInFlight }
}

private actor ScanAccumulator {
    private struct MutableSummary {
        var fileCount: UInt64 = 0
        var directoryCount: UInt64 = 0
        var totalBytes: UInt64 = 0
        var directoryMetadataBytes: UInt64 = 0
        var latestModification: Date?
    }

    private let startedAt: Date
    private var visitedPathCount: UInt64 = 0
    private var fileCount: UInt64 = 0
    private var directoryCount: UInt64 = 0
    private var totalBytes: UInt64 = 0
    private var summaries: [ScanCategory: MutableSummary] = [:]
    private var issues: [ScanIssue] = []
    private var memorySamples: [ScanMemorySample] = []
    private var lastMemorySampleAt: UInt64 = 0

    init(startedAt: Date) { self.startedAt = startedAt }

    func recordVisit(path: URL) -> ScanProgress? {
        visitedPathCount += 1
        sampleMemoryIfNeeded(path: path)
        return progressIfNeeded(path: path)
    }

    func recordItem(_ item: ScanItem) -> ScanProgress? {
        let category = item.category
        var summary = summaries[category, default: MutableSummary()]
        switch item.fileType {
        case .directory:
            directoryCount += 1
            summary.directoryCount += 1
            summary.directoryMetadataBytes += item.sizeBytes
        case .regularFile, .symbolicLink, .other:
            fileCount += 1
            summary.fileCount += 1
            summary.totalBytes += item.sizeBytes
        }
        totalBytes += item.sizeBytes
        if let lastModified = item.lastModified, summary.latestModification.map({ $0 < lastModified }) ?? true {
            summary.latestModification = lastModified
        }
        summaries[category] = summary
        return makeProgress(path: item.path, item: item)
    }

    func recordIssue(_ issue: ScanIssue) { issues.append(issue) }

    func makeResult(
        finishedAt: Date,
        cancelled: Bool,
        maxObservedConcurrentDirectories: Int
    ) -> ScanResult {
        sampleMemoryIfNeeded(path: nil, force: true)
        let performance = ScanPerformanceMetrics(
            duration: finishedAt.timeIntervalSince(startedAt),
            peakResidentMemoryBytes: memorySamples.map(\.residentMemoryBytes).max() ?? 0,
            memorySamples: memorySamples,
            maxObservedConcurrentDirectories: maxObservedConcurrentDirectories
        )
        let orderedSummaries = summaries.keys.sorted { $0.rawValue < $1.rawValue }.map { category in
            let summary = summaries[category] ?? MutableSummary()
            return ScanSummary(
                category: category,
                fileCount: summary.fileCount,
                directoryCount: summary.directoryCount,
                totalBytes: summary.totalBytes,
                directoryMetadataBytes: summary.directoryMetadataBytes,
                latestModification: summary.latestModification
            )
        }
        return ScanResult(
            startedAt: startedAt,
            finishedAt: finishedAt,
            cancelled: cancelled,
            visitedPathCount: visitedPathCount,
            fileCount: fileCount,
            directoryCount: directoryCount,
            totalBytes: totalBytes,
            summaries: orderedSummaries,
            issues: issues,
            performance: performance
        )
    }

    private func progressIfNeeded(path: URL?, item: ScanItem? = nil) -> ScanProgress? {
        guard visitedPathCount == 1 || visitedPathCount % 32 == 0 else { return nil }
        return makeProgress(path: path, item: item)
    }

    private func makeProgress(path: URL?, item: ScanItem? = nil) -> ScanProgress {
        ScanProgress(
            currentPath: path,
            item: item,
            visitedPathCount: visitedPathCount,
            discoveredFileCount: fileCount,
            discoveredDirectoryCount: directoryCount,
            discoveredBytes: totalBytes,
            elapsed: Date().timeIntervalSince(startedAt)
        )
    }

    private func sampleMemoryIfNeeded(path: URL?, force: Bool = false) {
        if !force && visitedPathCount < lastMemorySampleAt + 64 { return }
        lastMemorySampleAt = visitedPathCount
        let bytes = currentResidentMemoryBytes()
        memorySamples.append(ScanMemorySample(elapsed: Date().timeIntervalSince(startedAt), residentMemoryBytes: bytes))
        if memorySamples.count > 256 { memorySamples.removeFirst(128) }
    }
}

private func nodeMetadata(at url: URL) -> ScanNodeMetadata? {
    var info = stat()
    guard lstat(url.path, &info) == 0 else { return nil }
    let type = info.st_mode & S_IFMT
    let fileType: ScanFileType
    switch type {
    case S_IFREG: fileType = .regularFile
    case S_IFDIR: fileType = .directory
    case S_IFLNK: fileType = .symbolicLink
    default: fileType = .other
    }
    let seconds = TimeInterval(info.st_mtimespec.tv_sec)
    let nanoseconds = TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000
    return ScanNodeMetadata(
        fileType: fileType,
        sizeBytes: info.st_size > 0 ? UInt64(info.st_size) : 0,
        lastModified: Date(timeIntervalSince1970: seconds + nanoseconds)
    )
}

private func canonicalURL(_ url: URL) -> URL? {
    guard let resolved = realpath(url.path, nil) else { return nil }
    defer { free(resolved) }
    return URL(fileURLWithPath: String(cString: resolved))
}

private func isWithinAnyRoot(_ path: URL, roots: [URL]) -> Bool {
    roots.contains { isSameOrDescendant(path, of: $0) || (canonicalURL($0).map { isSameOrDescendant(path, of: $0) } ?? false) }
}

private func isRuleExcluded(_ path: URL, rule: ScanRule) -> Bool {
    rule.excludedPaths.contains {
        isSameOrDescendant(path, of: $0)
            || (canonicalURL($0).map { isSameOrDescendant(path, of: $0) } ?? false)
    }
}

private func isSameOrDescendant(_ path: URL, of root: URL) -> Bool {
    let pathString = path.path
    let rootString = root.path == "/" ? "/" : root.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    if rootString == "/" { return pathString.hasPrefix("/") }
    return pathString == "/\(rootString)" || pathString.hasPrefix("/\(rootString)/")
}

private func isHardExcluded(_ path: URL, homeDirectory: URL) -> Bool {
    let home = canonicalURL(homeDirectory) ?? homeDirectory.standardizedFileURL
    let protected: [URL] = [
        URL(fileURLWithPath: "/"),
        home,
        URL(fileURLWithPath: "/System"),
        URL(fileURLWithPath: "/Library"),
        URL(fileURLWithPath: "/Applications"),
        URL(fileURLWithPath: "/Users"),
        URL(fileURLWithPath: "/bin"),
        URL(fileURLWithPath: "/sbin"),
        URL(fileURLWithPath: "/usr"),
        URL(fileURLWithPath: "/etc"),
        URL(fileURLWithPath: "/dev"),
        URL(fileURLWithPath: "/Volumes"),
        URL(fileURLWithPath: "/private/etc"),
        URL(fileURLWithPath: "/private/var/db"),
        URL(fileURLWithPath: "/private/var/root"),
        home.appendingPathComponent("Documents", isDirectory: true),
        home.appendingPathComponent("Desktop", isDirectory: true),
        home.appendingPathComponent("Projects", isDirectory: true)
    ]
    for item in protected {
        // /Users itself is protected, but making it a recursive exclusion would
        // also exclude the current user's approved Library cache/log roots.
        // Personal data is protected separately below and by the caller's rule.
        if item.path == "/" || item.path == home.path || item.path == "/Users" {
            if path.path == item.path { return true }
        } else if isSameOrDescendant(path, of: item) {
            return true
        }
    }
    if path.path == "/private/var" || path.path == "/var" { return true }
    return false
}

private func isPermissionError(_ error: Error) -> Bool {
    let code = (error as NSError).code
    return code == NSFileReadNoPermissionError || code == NSFileWriteNoPermissionError || code == Int(EACCES) || code == Int(EPERM)
}

private func currentResidentMemoryBytes() -> UInt64 {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
    return usage.ru_maxrss > 0 ? UInt64(usage.ru_maxrss) : 0
}
