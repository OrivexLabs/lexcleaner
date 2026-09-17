import Foundation
import Darwin

public enum CleanerCategory: String, CaseIterable, Codable, Sendable, Hashable {
    case userCache
    case applicationCache
    case logs
    case temporaryFiles
    case unknown

    fileprivate init(scanCategory: ScanCategory) {
        switch scanCategory {
        case .userCache: self = .userCache
        case .applicationCache: self = .applicationCache
        case .logs: self = .logs
        case .temporaryFiles: self = .temporaryFiles
        }
    }
}

/// A rule scope is explicit because ordinary cleaner rules must never be able
/// to opt out of the normal protected-path checks. App Manager uses the two
/// narrow scopes below only for exact, user-selected paths that have already
/// been associated with an installed app.
public enum CleanerRuleScope: String, Codable, Sendable, Hashable {
    case standard
    case installedAppBundle
    case appResidual
}

public enum CleanupSafetyLevel: String, CaseIterable, Codable, Sendable, Hashable {
    case safe
    case reviewRequired
    case protected
    case unknown
}

public enum CleanupReason: String, CaseIterable, Codable, Sendable, Hashable {
    case regenerableCache
    case safeEvidenceInsufficient
    case applicationCacheNeedsReview
    case userDataProtected
    case credentialDataProtected
    case browserProfileProtected
    case gitRepositoryProtected
    case systemPathProtected
    case personalDataProtected
    case symlinkProtected
    case activeLogProtected
    case oldLogNeedsReview
    case crashDiagnosticLogNeedsReview
    case recentTemporaryFileProtected
    case oldTemporaryFileNeedsReview
    case specialTemporaryDirectoryProtected
    case directoryContainerProtected
    case agePolicyNotMet
    case sizePolicyNotMet
    case sourceChanged
    case ruleConflict
    case unknownPath
    case unknownDataDisposition
}

public enum CacheDataDisposition: String, Codable, Sendable, Hashable {
    case regenerableCache
    case applicationState
    case userDatabase
    case downloadedContent
    case session
    case credential
    case extensionData
    case unknown
}

public enum AgePolicy: Codable, Sendable, Hashable {
    case any
    case olderThan(TimeInterval)

    public func passes(modifiedAt: Date?, now: Date) -> Bool {
        switch self {
        case .any:
            return modifiedAt != nil
        case let .olderThan(seconds):
            guard let modifiedAt else { return false }
            return now.timeIntervalSince(modifiedAt) >= seconds
        }
    }
}

public struct SizePolicy: Codable, Sendable, Hashable {
    public let minimumBytes: UInt64?
    public let maximumBytes: UInt64?

    public init(minimumBytes: UInt64? = nil, maximumBytes: UInt64? = nil) {
        self.minimumBytes = minimumBytes
        self.maximumBytes = maximumBytes
    }

    public static let any = SizePolicy()

    public func passes(sizeBytes: UInt64) -> Bool {
        if let minimumBytes, sizeBytes < minimumBytes { return false }
        if let maximumBytes, sizeBytes > maximumBytes { return false }
        return true
    }
}

public struct ExclusionRule: Codable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let pathPrefixes: [URL]
    public let pathComponents: Set<String>
    public let fileNameTokens: Set<String>
    public let safetyLevel: CleanupSafetyLevel
    public let reason: CleanupReason

    public init(
        id: String,
        name: String,
        pathPrefixes: [URL] = [],
        pathComponents: Set<String> = [],
        fileNameTokens: Set<String> = [],
        safetyLevel: CleanupSafetyLevel = .protected,
        reason: CleanupReason = .unknownPath
    ) {
        self.id = id
        self.name = name
        self.pathPrefixes = pathPrefixes
        self.pathComponents = pathComponents
        self.fileNameTokens = fileNameTokens
        self.safetyLevel = safetyLevel
        self.reason = reason
    }
}

public enum SafeRuleConfidence: String, Codable, Sendable, Hashable {
    case high
    case medium
    case low
}

public struct SafeRuleEvidence: Codable, Sendable, Hashable {
    public let ruleID: String
    public let category: CleanerCategory
    public let pathPattern: String
    public let bundleIdentifier: String?
    public let dataDisposition: CacheDataDisposition
    public let dataUse: String
    public let regenerationBasis: String
    public let safetyEvidence: [String]
    public let exclusionConditions: [String]
    public let agePolicy: AgePolicy
    public let sizePolicy: SizePolicy
    public let ownershipRequirement: String
    public let confidence: SafeRuleConfidence
    public let testCoverage: [String]
    public let realValidation: String

    public init(
        ruleID: String,
        category: CleanerCategory,
        pathPattern: String,
        bundleIdentifier: String? = nil,
        dataDisposition: CacheDataDisposition,
        dataUse: String,
        regenerationBasis: String,
        safetyEvidence: [String],
        exclusionConditions: [String],
        agePolicy: AgePolicy,
        sizePolicy: SizePolicy,
        ownershipRequirement: String,
        confidence: SafeRuleConfidence,
        testCoverage: [String],
        realValidation: String
    ) {
        self.ruleID = ruleID
        self.category = category
        self.pathPattern = pathPattern
        self.bundleIdentifier = bundleIdentifier
        self.dataDisposition = dataDisposition
        self.dataUse = dataUse
        self.regenerationBasis = regenerationBasis
        self.safetyEvidence = safetyEvidence
        self.exclusionConditions = exclusionConditions
        self.agePolicy = agePolicy
        self.sizePolicy = sizePolicy
        self.ownershipRequirement = ownershipRequirement
        self.confidence = confidence
        self.testCoverage = testCoverage
        self.realValidation = realValidation
    }

    public func isComplete(for rule: CleanerRule) -> Bool {
        ruleID == rule.id &&
        category == rule.category &&
        dataDisposition == rule.dataDisposition &&
        agePolicy == rule.agePolicy &&
        sizePolicy == rule.sizePolicy &&
        !pathPattern.isEmpty &&
        !dataUse.isEmpty &&
        !regenerationBasis.isEmpty &&
        !safetyEvidence.isEmpty &&
        !exclusionConditions.isEmpty &&
        !ownershipRequirement.isEmpty &&
        confidence == .high &&
        !testCoverage.isEmpty &&
        !realValidation.isEmpty
    }
}

public struct CleanerRule: Codable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let category: CleanerCategory
    public let sourceCategories: Set<ScanCategory>
    public let allowedRoots: [URL]
    public let pathComponentHints: Set<String>
    public let defaultSafetyLevel: CleanupSafetyLevel
    public let cleanupReason: CleanupReason
    public let dataDisposition: CacheDataDisposition
    public let agePolicy: AgePolicy
    public let sizePolicy: SizePolicy
    public let exclusionRules: [ExclusionRule]
    public let safeEvidence: SafeRuleEvidence?
    public let scope: CleanerRuleScope

    public init(
        id: String,
        name: String,
        category: CleanerCategory,
        sourceCategories: Set<ScanCategory>,
        allowedRoots: [URL],
        pathComponentHints: Set<String> = [],
        defaultSafetyLevel: CleanupSafetyLevel,
        cleanupReason: CleanupReason,
        dataDisposition: CacheDataDisposition = .unknown,
        agePolicy: AgePolicy,
        sizePolicy: SizePolicy = .any,
        exclusionRules: [ExclusionRule] = [],
        safeEvidence: SafeRuleEvidence? = nil,
        scope: CleanerRuleScope = .standard
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.sourceCategories = sourceCategories
        self.allowedRoots = allowedRoots
        self.pathComponentHints = pathComponentHints
        self.defaultSafetyLevel = defaultSafetyLevel
        self.cleanupReason = cleanupReason
        self.dataDisposition = dataDisposition
        self.agePolicy = agePolicy
        self.sizePolicy = sizePolicy
        self.exclusionRules = exclusionRules
        self.safeEvidence = safeEvidence
        self.scope = scope
    }

    public static func builtInRules(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) -> [CleanerRule] {
        let home = homeDirectory.standardizedFileURL
        let userCacheRuleID = "calibrated-user-cache-fscached-data"
        let userCacheAgePolicy: AgePolicy = .olderThan(24 * 60 * 60)
        let userCacheSizePolicy = SizePolicy(minimumBytes: 1)
        let userCacheEvidence = SafeRuleEvidence(
            ruleID: userCacheRuleID,
            category: .userCache,
            pathPattern: "~/Library/Caches/<verified-installed-bundle-id>/fsCachedData/**",
            bundleIdentifier: "<verified-installed-bundle-id>",
            dataDisposition: .regenerableCache,
            dataUse: "Application-generated filesystem cache objects under the standard fsCachedData container",
            regenerationBasis: "The owning application can recreate these cache objects; the rule never matches the cache container itself.",
            safetyEvidence: [
                "The path has an exact installed application bundle identifier as its first cache component.",
                "The second component is the narrow fsCachedData cache container.",
                "Validated objects are regular files, not databases, credentials, sessions, or user documents."
            ],
            exclusionConditions: [
                "Unknown or uninstalled bundle identifier",
                "Any symlink component, canonical path escape, identity change, or protected path",
                "Directories, sensitive filename/path components, recent files, and zero-byte files"
            ],
            agePolicy: userCacheAgePolicy,
            sizePolicy: userCacheSizePolicy,
            ownershipRequirement: "Bundle identifier must resolve to an installed .app in /Applications or ~/Applications.",
            confidence: .high,
            testCoverage: [
                "exact fsCachedData path and installed ownership",
                "unowned bundle and non-fsCachedData path remain non-safe",
                "symlink, identity, sourceChanged, and protected-path rejection"
            ],
            realValidation: "Current-Mac read-only scan plus 100-candidate manual inspection and controlled Trash E2E."
        )
        return [
            CleanerRule(
                id: userCacheRuleID,
                name: "User Cache",
                category: .userCache,
                sourceCategories: [.userCache],
                allowedRoots: [home.appendingPathComponent("Library/Caches", isDirectory: true)],
                pathComponentHints: ["fsCachedData"],
                defaultSafetyLevel: .safe,
                cleanupReason: .regenerableCache,
                dataDisposition: .regenerableCache,
                agePolicy: userCacheAgePolicy,
                sizePolicy: userCacheSizePolicy,
                safeEvidence: userCacheEvidence
            ),
            CleanerRule(
                id: "classify-application-cache",
                name: "Application Cache",
                category: .applicationCache,
                sourceCategories: [.applicationCache],
                allowedRoots: [home.appendingPathComponent("Library/Application Support", isDirectory: true)],
                pathComponentHints: ["Cache", "Caches", "CacheStorage", "Code Cache", "GPUCache", "Service Worker", "WebKit"],
                defaultSafetyLevel: .reviewRequired,
                cleanupReason: .applicationCacheNeedsReview,
                dataDisposition: .regenerableCache,
                agePolicy: .olderThan(3 * 24 * 60 * 60),
                sizePolicy: SizePolicy(minimumBytes: 1)
            ),
            CleanerRule(
                id: "classify-logs",
                name: "Logs",
                category: .logs,
                sourceCategories: [.logs],
                allowedRoots: [home.appendingPathComponent("Library/Logs", isDirectory: true)],
                defaultSafetyLevel: .reviewRequired,
                cleanupReason: .oldLogNeedsReview,
                dataDisposition: .unknown,
                agePolicy: .olderThan(7 * 24 * 60 * 60),
                sizePolicy: SizePolicy(minimumBytes: 1)
            ),
            CleanerRule(
                id: "classify-temporary-files",
                name: "Temporary Files",
                category: .temporaryFiles,
                sourceCategories: [.temporaryFiles],
                allowedRoots: [temporaryDirectory.standardizedFileURL],
                defaultSafetyLevel: .reviewRequired,
                cleanupReason: .oldTemporaryFileNeedsReview,
                dataDisposition: .unknown,
                agePolicy: .olderThan(24 * 60 * 60),
                sizePolicy: SizePolicy(minimumBytes: 1)
            )
        ]
    }
}

public struct CleanerCandidate: Codable, Sendable, Hashable {
    public let path: URL
    public let category: CleanerCategory
    public let size: UInt64
    public let modifiedAt: Date?
    public let owningApp: String?
    public let safetyLevel: CleanupSafetyLevel
    public let cleanupReason: CleanupReason
    public let matchedRule: String
    public let matchedRuleIDs: [String]
    public let estimatedReclaimableBytes: UInt64

    public init(
        path: URL,
        category: CleanerCategory,
        size: UInt64,
        modifiedAt: Date?,
        owningApp: String?,
        safetyLevel: CleanupSafetyLevel,
        cleanupReason: CleanupReason,
        matchedRule: String,
        matchedRuleIDs: [String],
        estimatedReclaimableBytes: UInt64
    ) {
        self.path = path
        self.category = category
        self.size = size
        self.modifiedAt = modifiedAt
        self.owningApp = owningApp
        self.safetyLevel = safetyLevel
        self.cleanupReason = cleanupReason
        self.matchedRule = matchedRule
        self.matchedRuleIDs = matchedRuleIDs
        self.estimatedReclaimableBytes = estimatedReclaimableBytes
    }
}

/// Stable, locale-independent identity for the group shown by the Cleaner UI.
/// The display labels remain an App concern; this key is deliberately based on
/// the classification output so a rescan does not reorder or merge unrelated
/// groups because of localized text.
public struct CleanerGroupKey: Codable, Sendable, Hashable, Comparable {
    public let owningApp: String?
    public let category: CleanerCategory
    public let rule: String

    public init(owningApp: String?, category: CleanerCategory, rule: String) {
        let normalizedApp = owningApp?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.owningApp = normalizedApp?.isEmpty == true ? nil : normalizedApp
        self.category = category
        self.rule = rule
    }

    public init(candidate: CleanerCandidate) {
        self.init(owningApp: candidate.owningApp, category: candidate.category, rule: candidate.matchedRule)
    }

    /// Length-prefixing prevents delimiter collisions while keeping the key
    /// readable in diagnostics and UI accessibility identifiers.
    public var stableID: String {
        [owningApp ?? "<unknown-app>", category.rawValue, rule]
            .map { "\($0.utf8.count):\($0)" }
            .joined(separator: "|")
    }

    public static func < (lhs: CleanerGroupKey, rhs: CleanerGroupKey) -> Bool {
        lhs.stableID < rhs.stableID
    }
}

public enum CleanerGroupSelectionState: String, Codable, Sendable, Hashable {
    case allSelected
    case partiallySelected
    case noneSelected
    case disabled
}

/// A presentation-ready group. It is still a Core value type so selection
/// semantics can be tested without constructing SwiftUI views or fake files.
public struct CleanerCandidateGroup: Identifiable, Codable, Sendable, Hashable {
    public let key: CleanerGroupKey
    public let safetyLevel: CleanupSafetyLevel
    public let candidates: [CleanerCandidate]

    public init(key: CleanerGroupKey, safetyLevel: CleanupSafetyLevel, candidates: [CleanerCandidate]) {
        self.key = key
        self.safetyLevel = safetyLevel
        self.candidates = candidates.sorted { $0.path.standardizedFileURL.path < $1.path.standardizedFileURL.path }
    }

    public var id: String { "\(safetyLevel.rawValue)|\(key.stableID)" }
    public var selectableCandidates: [CleanerCandidate] {
        candidates.filter { $0.safetyLevel == .safe || $0.safetyLevel == .reviewRequired }
    }
    public var totalBytes: UInt64 { candidates.reduce(0) { $0 + $1.size } }

    public static func grouped(_ candidates: [CleanerCandidate]) -> [CleanerCandidateGroup] {
        let grouped = Dictionary(grouping: candidates) { candidate in
            CompositeGroupKey(key: CleanerGroupKey(candidate: candidate), safetyLevel: candidate.safetyLevel)
        }
        return grouped.map { composite, candidates in
            CleanerCandidateGroup(key: composite.key, safetyLevel: composite.safetyLevel, candidates: candidates)
        }.sorted { $0.id < $1.id }
    }
}

public struct CleanerSelectionState: Sendable, Equatable {
    public private(set) var selectedPaths: Set<URL>

    public init(candidates: [CleanerCandidate] = []) {
        selectedPaths = Set(candidates.filter { $0.safetyLevel == .safe }.map { $0.path.standardizedFileURL })
    }

    public init(selectedPaths: Set<URL>) {
        self.selectedPaths = Set(selectedPaths.map { $0.standardizedFileURL })
    }

    public func isSelected(_ candidate: CleanerCandidate) -> Bool {
        selectedPaths.contains(candidate.path.standardizedFileURL)
    }

    public func canSelect(_ candidate: CleanerCandidate) -> Bool {
        candidate.safetyLevel == .safe || candidate.safetyLevel == .reviewRequired
    }

    public func state(for group: CleanerCandidateGroup) -> CleanerGroupSelectionState {
        let selectable = group.selectableCandidates
        guard !selectable.isEmpty else { return .disabled }
        let selectedCount = selectable.filter(isSelected).count
        if selectedCount == 0 { return .noneSelected }
        if selectedCount == selectable.count { return .allSelected }
        return .partiallySelected
    }

    public mutating func setSelected(_ selected: Bool, for candidate: CleanerCandidate) {
        guard canSelect(candidate) else { return }
        let path = candidate.path.standardizedFileURL
        if selected {
            selectedPaths.insert(path)
        } else {
            selectedPaths.remove(path)
        }
    }

    public mutating func setSelected(_ selected: Bool, for group: CleanerCandidateGroup) {
        for candidate in group.selectableCandidates {
            setSelected(selected, for: candidate)
        }
    }
}

private struct CompositeGroupKey: Hashable {
    let key: CleanerGroupKey
    let safetyLevel: CleanupSafetyLevel
}

public struct ClassificationStatistics: Codable, Sendable, Hashable {
    public let safeCount: UInt64
    public let safeBytes: UInt64
    public let reviewRequiredCount: UInt64
    public let reviewRequiredBytes: UInt64
    public let protectedCount: UInt64
    public let protectedBytes: UInt64
    public let unknownCount: UInt64
    public let unknownBytes: UInt64

    public init(
        safeCount: UInt64,
        safeBytes: UInt64,
        reviewRequiredCount: UInt64,
        reviewRequiredBytes: UInt64,
        protectedCount: UInt64,
        protectedBytes: UInt64,
        unknownCount: UInt64,
        unknownBytes: UInt64
    ) {
        self.safeCount = safeCount
        self.safeBytes = safeBytes
        self.reviewRequiredCount = reviewRequiredCount
        self.reviewRequiredBytes = reviewRequiredBytes
        self.protectedCount = protectedCount
        self.protectedBytes = protectedBytes
        self.unknownCount = unknownCount
        self.unknownBytes = unknownBytes
    }
}

public struct CleanerClassificationResult: Codable, Sendable {
    public let candidates: [CleanerCandidate]
    public let statistics: ClassificationStatistics
    public let rulesEvaluated: Int
    public let classifiedAt: Date
    public let cancelled: Bool

    public init(
        candidates: [CleanerCandidate],
        statistics: ClassificationStatistics,
        rulesEvaluated: Int,
        classifiedAt: Date,
        cancelled: Bool = false
    ) {
        self.candidates = candidates
        self.statistics = statistics
        self.rulesEvaluated = rulesEvaluated
        self.classifiedAt = classifiedAt
        self.cancelled = cancelled
    }
}

public typealias ClassificationResult = CleanerClassificationResult

private struct PreparedRoot {
    let url: URL
    let canonicalURL: URL?
    let path: String
    let canonicalPath: String?

    init(url: URL, canonicalURL: URL?) {
        self.url = url
        self.canonicalURL = canonicalURL
        self.path = url.path
        self.canonicalPath = canonicalURL?.path
    }
}

private struct PreparedRule {
    let rule: CleanerRule
    let allowedRoots: [PreparedRoot]
    let id: String
    let sourceCategories: Set<ScanCategory>
    let pathComponentHints: Set<String>

    init(rule: CleanerRule, allowedRoots: [PreparedRoot]) {
        self.rule = rule
        self.allowedRoots = allowedRoots
        self.id = rule.id
        self.sourceCategories = rule.sourceCategories
        self.pathComponentHints = rule.pathComponentHints
    }
}

private struct ClassificationContext {
    let rules: [PreparedRule]
    let allAllowedRoots: [PreparedRoot]
    let protectedRoots: [PreparedRoot]
    let homePath: String
    let installedBundleIdentifiers: Set<String>

    init(rules: [CleanerRule], installedBundleIdentifiers: Set<String>) {
        self.rules = rules.map { rule in
            PreparedRule(
                rule: rule,
                allowedRoots: rule.allowedRoots.map { root in
                    PreparedRoot(url: root.standardizedFileURL, canonicalURL: canonicalURL(root))
                }
            )
        }

        var rootsByPath: [String: PreparedRoot] = [:]
        for root in self.rules.flatMap(\.allowedRoots) {
            rootsByPath[root.path] = root
        }
        self.allAllowedRoots = Array(rootsByPath.values)

        let canonicalHome = canonicalURL(FileManager.default.homeDirectoryForCurrentUser) ?? FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        self.homePath = canonicalHome.path
        let protectedURLs = [
            URL(fileURLWithPath: "/System"), URL(fileURLWithPath: "/Library"), URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/usr"), URL(fileURLWithPath: "/bin"), URL(fileURLWithPath: "/sbin"),
            URL(fileURLWithPath: "/etc"), URL(fileURLWithPath: "/dev"), URL(fileURLWithPath: "/Volumes"), URL(fileURLWithPath: "/private/etc"),
            canonicalHome.appendingPathComponent("Documents"), canonicalHome.appendingPathComponent("Desktop"), canonicalHome.appendingPathComponent("Downloads"),
            canonicalHome.appendingPathComponent("Projects"), canonicalHome.appendingPathComponent(".ssh"), canonicalHome.appendingPathComponent(".gnupg"),
            canonicalHome.appendingPathComponent("Library/Keychains"), canonicalHome.appendingPathComponent("Library/Mail"), canonicalHome.appendingPathComponent("Library/Messages"),
            canonicalHome.appendingPathComponent("Library/Music"), canonicalHome.appendingPathComponent("Music"), canonicalHome.appendingPathComponent("Library/Mobile Documents"),
            canonicalHome.appendingPathComponent("iCloud Drive")
        ]
        var protectedByPath: [String: PreparedRoot] = [:]
        for root in protectedURLs {
            let standardized = root.standardizedFileURL
            protectedByPath[standardized.path] = PreparedRoot(url: standardized, canonicalURL: canonicalURL(standardized))
        }
        self.protectedRoots = Array(protectedByPath.values)
        self.installedBundleIdentifiers = installedBundleIdentifiers
    }
}

private struct PathFacts {
    let path: String
    let components: [String]
    let lowerPath: String
    let lowerComponents: [String]
    let lastComponent: String
    let lowerLastComponent: String

    init(path url: URL) {
        let path = url.path
        let components = url.pathComponents
        self.path = path
        self.components = components
        self.lowerPath = path.lowercased()
        self.lowerComponents = components.map { $0.lowercased() }
        self.lastComponent = url.lastPathComponent
        self.lowerLastComponent = url.lastPathComponent.lowercased()
    }
}

public actor ClassificationEngine {
    private let installedBundleIdentifiers: Set<String>

    public init(applicationRoots: [URL] = ClassificationEngine.defaultApplicationRoots()) {
        self.installedBundleIdentifiers = Self.discoverBundleIdentifiers(in: applicationRoots)
    }

    public static func defaultApplicationRoots(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        ]
    }

    public static func builtInRules(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) -> [CleanerRule] {
        CleanerRule.builtInRules(homeDirectory: homeDirectory, temporaryDirectory: temporaryDirectory)
    }

    public func classify(
        items: [ScanItem],
        rules: [CleanerRule] = CleanerRule.builtInRules(),
        now: Date = Date()
    ) async -> CleanerClassificationResult {
        let context = ClassificationContext(
            rules: rules,
            installedBundleIdentifiers: installedBundleIdentifiers
        )
        var candidates: [CleanerCandidate] = []
        candidates.reserveCapacity(items.count)
        var stats = MutableClassificationStatistics()
        var cancelled = false

        for (index, item) in items.enumerated() {
            if index % 256 == 0 {
                if Task.isCancelled {
                    cancelled = true
                    break
                }
                await Task.yield()
            }
            let candidate = autoreleasepool {
                Self.classify(
                    item: item,
                    now: now,
                    context: context
                )
            }
            candidates.append(candidate)
            stats.add(candidate)
        }
        cancelled = cancelled || Task.isCancelled

        return CleanerClassificationResult(
            candidates: candidates,
            statistics: stats.result,
            rulesEvaluated: rules.count,
            classifiedAt: now,
            cancelled: cancelled
        )
    }

    private static func classify(
        item: ScanItem,
        now: Date,
        context: ClassificationContext
    ) -> CleanerCandidate {
        let category = CleanerCategory(scanCategory: item.category)
        let pathFacts = PathFacts(path: item.path)
        let current = currentMetadata(at: item.path)
        let owningApp = inferOwningApp(for: pathFacts, category: category)
        let matchedRules = context.rules.filter { rule in ruleMatches(rule: rule, item: item, current: current, pathFacts: pathFacts) }
        let matchedIDs = matchedRules.map(\.id).sorted()
        let primaryRule = matchedRules.first

        if let current, current.fileType == .symbolicLink || item.fileType == .symbolicLink {
            return candidate(item: item, category: category, owningApp: owningApp, safety: .protected, reason: .symlinkProtected, matchedIDs: matchedIDs, estimatedBytes: 0)
        }
        if current == nil {
            return candidate(item: item, category: category, owningApp: owningApp, safety: .unknown, reason: .sourceChanged, matchedIDs: matchedIDs, estimatedBytes: 0)
        }
        if current?.fileType != item.fileType || current?.sizeBytes != item.sizeBytes || current?.lastModified != item.lastModified {
            return candidate(item: item, category: category, owningApp: owningApp, safety: .unknown, reason: .sourceChanged, matchedIDs: matchedIDs, estimatedBytes: 0)
        }
        if !context.rules.isEmpty && hasSymlinkComponent(item.path, roots: context.allAllowedRoots) {
            return candidate(item: item, category: category, owningApp: owningApp, safety: .protected, reason: .symlinkProtected, matchedIDs: matchedIDs, estimatedBytes: 0)
        }
        let protection = protectedPathEvaluation(for: pathFacts, context: context)
        let explicitAppBundle = primaryRule?.rule.scope == .installedAppBundle &&
            matchedRules.count == 1 &&
            item.fileType == .directory &&
            item.path.pathExtension.lowercased() == "app" &&
            primaryRule?.allowedRoots.contains(where: { $0.url.standardizedFileURL == item.path.standardizedFileURL }) == true
        if protection.isProtected && !explicitAppBundle {
            return candidate(item: item, category: category, owningApp: owningApp, safety: .protected, reason: protectionReason(for: pathFacts, isGitRepository: protection.isGitRepository), matchedIDs: matchedIDs, estimatedBytes: 0)
        }
        if let primaryRule,
           matchedRules.count == 1,
           primaryRule.rule.scope == .installedAppBundle,
           explicitAppBundle {
            guard Bundle(url: item.path)?.bundleIdentifier != nil else {
                return candidate(item: item, category: category, owningApp: owningApp, safety: .unknown, reason: .unknownPath, matchedIDs: matchedIDs, estimatedBytes: 0)
            }
            return candidate(item: item, category: category, owningApp: Bundle(url: item.path)?.bundleIdentifier, safety: .reviewRequired, reason: .applicationCacheNeedsReview, matchedIDs: matchedIDs, estimatedBytes: item.sizeBytes)
        }
        if let primaryRule,
           matchedRules.count == 1,
           primaryRule.rule.scope == .appResidual,
           primaryRule.allowedRoots.contains(where: { $0.url.standardizedFileURL == item.path.standardizedFileURL }),
           item.fileType == .regularFile || item.fileType == .directory {
            // Sensitive data protections remain authoritative even for an
            // exact app-residual rule. A bundle-id match must never turn
            // cookies, sessions, credentials, or user databases into a
            // cleanup candidate.
            if isSensitiveDataPath(pathFacts) {
                return candidate(item: item, category: category, owningApp: owningApp, safety: .protected, reason: protectionReason(for: pathFacts, isGitRepository: protection.isGitRepository), matchedIDs: matchedIDs, estimatedBytes: 0)
            }
            return candidate(item: item, category: category, owningApp: owningApp, safety: primaryRule.rule.defaultSafetyLevel, reason: primaryRule.rule.cleanupReason, matchedIDs: matchedIDs, estimatedBytes: reclaimableBytes(item.sizeBytes, level: primaryRule.rule.defaultSafetyLevel))
        }
        // Keep the calibrated fsCachedData rule's unmatched paths unknown so
        // its narrow evidence boundary remains fail-closed. All ordinary
        // cache/log/temp rules still protect sensitive data before age/size
        // evaluation.
        let isCalibratedSafeRule = context.rules.contains { rule in
            rule.rule.safeEvidence != nil &&
            rule.rule.defaultSafetyLevel == .safe &&
            rule.sourceCategories.contains(item.category) &&
            isWithinAnyRoot(item.path, roots: rule.allowedRoots)
        }
        if isSensitiveDataPath(pathFacts) && !isCalibratedSafeRule {
            return candidate(item: item, category: category, owningApp: owningApp, safety: .protected, reason: protectionReason(for: pathFacts, isGitRepository: protection.isGitRepository), matchedIDs: matchedIDs, estimatedBytes: 0)
        }
        if item.fileType == .directory {
            return candidate(item: item, category: category, owningApp: owningApp, safety: .protected, reason: .directoryContainerProtected, matchedIDs: matchedIDs, estimatedBytes: 0)
        }
        guard let primaryRule else {
            return candidate(item: item, category: category, owningApp: owningApp, safety: .unknown, reason: .unknownPath, matchedIDs: [], estimatedBytes: 0)
        }
        if matchedRules.count > 1 {
            return candidate(item: item, category: category, owningApp: owningApp, safety: .unknown, reason: .ruleConflict, matchedIDs: matchedIDs, estimatedBytes: 0)
        }
        if let exclusion = matchingExclusion(for: item.path, category: category, rules: primaryRule.rule.exclusionRules) {
            return candidate(item: item, category: category, owningApp: owningApp, safety: exclusion.safetyLevel, reason: exclusion.reason, matchedIDs: matchedIDs, estimatedBytes: reclaimableBytes(item.sizeBytes, level: exclusion.safetyLevel))
        }
        if !primaryRule.rule.agePolicy.passes(modifiedAt: item.lastModified, now: now) {
            let reason: CleanupReason
            let safety: CleanupSafetyLevel
            switch item.category {
            case .logs:
                let active = isActiveLog(item.lastModified, now: now)
                reason = active ? .activeLogProtected : .agePolicyNotMet
                safety = active ? .protected : .reviewRequired
            case .temporaryFiles:
                reason = .recentTemporaryFileProtected
                safety = .protected
            case .userCache, .applicationCache:
                reason = .agePolicyNotMet
                safety = .reviewRequired
            }
            return candidate(item: item, category: category, owningApp: owningApp, safety: safety, reason: reason, matchedIDs: matchedIDs, estimatedBytes: reclaimableBytes(item.sizeBytes, level: safety))
        }
        if !primaryRule.rule.sizePolicy.passes(sizeBytes: item.sizeBytes) {
            return candidate(item: item, category: category, owningApp: owningApp, safety: .reviewRequired, reason: .sizePolicyNotMet, matchedIDs: matchedIDs, estimatedBytes: 0)
        }

        switch item.category {
        case .userCache:
            if primaryRule.rule.dataDisposition == CacheDataDisposition.regenerableCache {
                let hasEvidence = primaryRule.rule.defaultSafetyLevel == .safe &&
                    primaryRule.rule.safeEvidence?.isComplete(for: primaryRule.rule) == true &&
                    isVerifiedRegenerableUserCachePath(
                        item.path,
                        item: item,
                        roots: primaryRule.allowedRoots,
                        installedBundleIdentifiers: context.installedBundleIdentifiers
                    )
                return candidate(
                    item: item,
                    category: category,
                    owningApp: owningApp,
                    safety: hasEvidence ? .safe : .reviewRequired,
                    reason: hasEvidence ? .regenerableCache : .safeEvidenceInsufficient,
                    matchedIDs: matchedIDs,
                    estimatedBytes: item.sizeBytes
                )
            }
        case .applicationCache:
            if primaryRule.rule.dataDisposition == CacheDataDisposition.regenerableCache,
               owningApp != nil,
               hasCachePathHint(pathFacts.components, hints: primaryRule.pathComponentHints) {
                return candidate(item: item, category: category, owningApp: owningApp, safety: .reviewRequired, reason: .applicationCacheNeedsReview, matchedIDs: matchedIDs, estimatedBytes: item.sizeBytes)
            }
            return candidate(item: item, category: category, owningApp: owningApp, safety: .unknown, reason: .unknownDataDisposition, matchedIDs: matchedIDs, estimatedBytes: 0)
        case .logs:
            let crash = isCrashOrDiagnosticLog(pathFacts.lowerPath)
            return candidate(item: item, category: category, owningApp: owningApp, safety: .reviewRequired, reason: crash ? .crashDiagnosticLogNeedsReview : .oldLogNeedsReview, matchedIDs: matchedIDs, estimatedBytes: item.sizeBytes)
        case .temporaryFiles:
            return candidate(item: item, category: category, owningApp: owningApp, safety: .reviewRequired, reason: .oldTemporaryFileNeedsReview, matchedIDs: matchedIDs, estimatedBytes: item.sizeBytes)
        }
        return candidate(item: item, category: category, owningApp: owningApp, safety: .unknown, reason: .unknownDataDisposition, matchedIDs: matchedIDs, estimatedBytes: 0)
    }

    private static func ruleMatches(rule: PreparedRule, item: ScanItem, current: CurrentMetadata?, pathFacts: PathFacts) -> Bool {
        guard rule.sourceCategories.contains(item.category) else { return false }
        guard current != nil else { return false }
        guard isWithinAnyRoot(item.path, roots: rule.allowedRoots) else { return false }
        if !rule.pathComponentHints.isEmpty && item.fileType != .directory && !hasCachePathHint(pathFacts.components, hints: rule.pathComponentHints) {
            return false
        }
        return true
    }

    private static func matchingExclusion(for path: URL, category: CleanerCategory, rules: [ExclusionRule]) -> ExclusionRule? {
        rules.first { rule in
            let componentMatch = rule.pathComponents.isEmpty || rule.pathComponents.contains(where: { path.pathComponents.contains($0) })
            let tokenMatch = rule.fileNameTokens.isEmpty || rule.fileNameTokens.contains(where: { path.lastPathComponent.localizedCaseInsensitiveContains($0) })
            let prefixMatch = rule.pathPrefixes.isEmpty || isWithinAnyRoot(path, roots: rule.pathPrefixes)
            return componentMatch && tokenMatch && prefixMatch
        }
    }

    private static func discoverBundleIdentifiers(in roots: [URL]) -> Set<String> {
        var identifiers = Set<String>()
        let fileManager = FileManager.default
        for root in roots {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for entry in entries where entry.pathExtension.lowercased() == "app" {
                guard let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                      values.isDirectory == true,
                      values.isSymbolicLink != true,
                      let bundleIdentifier = Bundle(url: entry)?.bundleIdentifier,
                      isValidBundleIdentifier(bundleIdentifier) else { continue }
                identifiers.insert(bundleIdentifier)
            }
        }
        return identifiers
    }

    private static func candidate(
        item: ScanItem,
        category: CleanerCategory,
        owningApp: String?,
        safety: CleanupSafetyLevel,
        reason: CleanupReason,
        matchedIDs: [String],
        estimatedBytes: UInt64
    ) -> CleanerCandidate {
        CleanerCandidate(
            path: item.path,
            category: category,
            size: item.sizeBytes,
            modifiedAt: item.lastModified,
            owningApp: owningApp,
            safetyLevel: safety,
            cleanupReason: reason,
            matchedRule: matchedIDs.first ?? "none",
            matchedRuleIDs: matchedIDs,
            estimatedReclaimableBytes: estimatedBytes
        )
    }
}

private struct MutableClassificationStatistics {
    var safeCount: UInt64 = 0
    var safeBytes: UInt64 = 0
    var reviewRequiredCount: UInt64 = 0
    var reviewRequiredBytes: UInt64 = 0
    var protectedCount: UInt64 = 0
    var protectedBytes: UInt64 = 0
    var unknownCount: UInt64 = 0
    var unknownBytes: UInt64 = 0

    mutating func add(_ candidate: CleanerCandidate) {
        switch candidate.safetyLevel {
        case .safe:
            safeCount += 1; safeBytes += candidate.size
        case .reviewRequired:
            reviewRequiredCount += 1; reviewRequiredBytes += candidate.size
        case .protected:
            protectedCount += 1; protectedBytes += candidate.size
        case .unknown:
            unknownCount += 1; unknownBytes += candidate.size
        }
    }

    var result: ClassificationStatistics {
        ClassificationStatistics(
            safeCount: safeCount,
            safeBytes: safeBytes,
            reviewRequiredCount: reviewRequiredCount,
            reviewRequiredBytes: reviewRequiredBytes,
            protectedCount: protectedCount,
            protectedBytes: protectedBytes,
            unknownCount: unknownCount,
            unknownBytes: unknownBytes
        )
    }
}

private struct CurrentMetadata: Sendable {
    let fileType: ScanFileType
    let sizeBytes: UInt64
    let lastModified: Date?
}

private func currentMetadata(at url: URL) -> CurrentMetadata? {
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
    return CurrentMetadata(
        fileType: fileType,
        sizeBytes: info.st_size > 0 ? UInt64(info.st_size) : 0,
        lastModified: Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000)
    )
}

private func reclaimableBytes(_ size: UInt64, level: CleanupSafetyLevel) -> UInt64 {
    switch level {
    case .safe, .reviewRequired: return size
    case .protected, .unknown: return 0
    }
}

private func inferOwningApp(for path: PathFacts, category: CleanerCategory) -> String? {
    let components = path.components
    let marker: String
    switch category {
    case .applicationCache: marker = "Application Support"
    case .userCache: marker = "Caches"
    case .logs: marker = "Logs"
    case .temporaryFiles, .unknown: return nil
    }
    guard let index = components.firstIndex(of: marker), components.index(after: index) < components.endIndex else { return nil }
    let candidate = components[components.index(after: index)]
    return candidate == "/" ? nil : candidate
}

private func hasCachePathHint(_ components: [String], hints: Set<String>) -> Bool {
    components.dropFirst().contains { component in hints.contains(component) }
}

private func isVerifiedRegenerableUserCachePath(
    _ path: URL,
    item: ScanItem,
    roots: [PreparedRoot],
    installedBundleIdentifiers: Set<String>
) -> Bool {
    guard item.fileType == .regularFile else { return false }
    guard let canonicalPath = canonicalURL(path) else { return false }
    guard !hasSymlinkComponent(path, roots: roots) else { return false }
    guard let canonicalRoot = roots.compactMap(\.canonicalURL).first(where: { isSameOrDescendant(canonicalPath, of: $0) }) else { return false }

    let rootComponents = canonicalRoot.pathComponents
    let pathComponents = canonicalPath.pathComponents
    guard pathComponents.count >= rootComponents.count + 3,
          pathComponents.starts(with: rootComponents) else { return false }

    let relative = Array(pathComponents.dropFirst(rootComponents.count))
    let bundleIdentifier = relative[0]
    guard isValidBundleIdentifier(bundleIdentifier),
          installedBundleIdentifiers.contains(bundleIdentifier),
          relative[1] == "fsCachedData",
          relative.count >= 3 else { return false }
    guard !isSensitiveDataPath(PathFacts(path: path)) else { return false }
    return true
}

private func isValidBundleIdentifier(_ value: String) -> Bool {
    let components = value.split(separator: ".")
    guard components.count >= 2 else { return false }
    return components.allSatisfy { component in
        !component.isEmpty && component.allSatisfy { character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
        }
    }
}

private func isActiveLog(_ modifiedAt: Date?, now: Date) -> Bool {
    guard let modifiedAt else { return true }
    return now.timeIntervalSince(modifiedAt) < 24 * 60 * 60
}

private func isCrashOrDiagnosticLog(_ lowerPath: String) -> Bool {
    lowerPath.contains("crash") || lowerPath.contains("diagnostic") || lowerPath.hasSuffix(".ips") || lowerPath.contains("panic")
}

private let sensitivePathComponents: Set<String> = [
    ".ssh", ".gnupg", "keychains", "mail", "messages", "photos library.photoslibrary", "music",
    "mobile documents", "com~apple~clouddocs", "cookies", "web data", "login data", "credentials",
    "session", "sessions", "extension data", "download", "downloads", "saved application state"
]

private let protectedFilenameSuffixes = [".sqlite", ".sqlite3", ".db", ".realm", ".keychain-db", ".p12", ".pem"]
private let protectedFilenames: Set<String> = ["cookies", "web data", "login data", "history", "bookmarks", "preferences"]

private func isSensitiveDataPath(_ path: PathFacts) -> Bool {
    if path.lowerComponents.contains(where: { sensitivePathComponents.contains($0) }) { return true }
    if path.lowerPath.contains("google/chrome") || path.lowerPath.contains("mozilla/firefox") || path.lowerPath.contains("bravesoftware") || path.lowerPath.contains("microsoft edge") || path.lowerPath.contains("safari") {
        return true
    }
    return protectedFilenameSuffixes.contains(where: { path.lowerLastComponent.hasSuffix($0) }) || protectedFilenames.contains(path.lowerLastComponent)
}

private struct ProtectedPathEvaluation {
    let isProtected: Bool
    let isGitRepository: Bool?
}

private let specialTemporaryComponents: Set<String> = [".trash", "temporaryitems", ".documentrevisions-v100"]

private func protectedPathEvaluation(for path: PathFacts, context: ClassificationContext) -> ProtectedPathEvaluation {
    let isProtectedRoot = path.path == "/" || path.path == context.homePath || context.protectedRoots.contains { root in
        isSameOrDescendant(path.path, of: root.path) ||
            (root.canonicalPath.map { isSameOrDescendant(path.path, of: $0) } ?? false)
    }
    if isProtectedRoot {
        return ProtectedPathEvaluation(isProtected: true, isGitRepository: nil)
    }
    let isGit = isGitRepositoryPath(path.path)
    return ProtectedPathEvaluation(
        isProtected: isProtectedRoot || isGit || path.lowerComponents.contains(where: { specialTemporaryComponents.contains($0) }),
        isGitRepository: isGit
    )
}

private func protectionReason(for path: PathFacts, isGitRepository: Bool?) -> CleanupReason {
    if path.lowerComponents.contains(where: { specialTemporaryComponents.contains($0) }) {
        return .specialTemporaryDirectoryProtected
    }
    if path.lowerPath.contains(".ssh") || path.lowerPath.contains(".gnupg") || path.lowerPath.contains("keychain") || path.lowerPath.contains("credentials") || path.lowerPath.hasSuffix(".p12") || path.lowerPath.hasSuffix(".pem") {
        return .credentialDataProtected
    }
    if path.lowerPath.contains("google/chrome") || path.lowerPath.contains("mozilla/firefox") || path.lowerPath.contains("safari") || path.lowerPath.contains("bravesoftware") || path.lowerPath.contains("microsoft edge") {
        return .browserProfileProtected
    }
    if isGitRepository ?? isGitRepositoryPath(path.path) { return .gitRepositoryProtected }
    if path.lowerPath.contains("/documents") || path.lowerPath.contains("/desktop") || path.lowerPath.contains("/downloads") || path.lowerPath.contains("/projects") || path.lowerPath.contains("/mail") || path.lowerPath.contains("/messages") || path.lowerPath.contains("/music") || path.lowerPath.contains("/photos") || path.lowerPath.contains("mobile documents") {
        return .personalDataProtected
    }
    if path.lowerPath.hasPrefix("/system") || path.lowerPath.hasPrefix("/library") || path.lowerPath.hasPrefix("/applications") || path.lowerPath == "/" {
        return .systemPathProtected
    }
    if path.lowerPath.contains(".git") { return .gitRepositoryProtected }
    return .userDataProtected
}

private func isGitRepositoryPath(_ path: String) -> Bool {
    var cursor = (path as NSString).deletingLastPathComponent
    for _ in 0..<64 {
        let git = cursor == "/" ? "/.git" : cursor + "/.git"
        var info = stat()
        if lstat(git, &info) == 0 { return true }
        let parent = (cursor as NSString).deletingLastPathComponent
        if parent == cursor { break }
        cursor = parent
    }
    return false
}

private func hasSymlinkComponent(_ path: URL, roots: [PreparedRoot]) -> Bool {
    for root in roots {
        var rootInfo = stat()
        if lstat(root.path, &rootInfo) == 0, (rootInfo.st_mode & S_IFMT) == S_IFLNK {
            return true
        }
    }
    guard let canonicalPath = canonicalURL(path) else { return true }
    guard let canonicalRoot = roots.compactMap(\.canonicalURL).first(where: { isSameOrDescendant(canonicalPath, of: $0) }) else { return true }

    let rootComponents = canonicalRoot.pathComponents
    let pathComponents = canonicalPath.pathComponents
    guard pathComponents.starts(with: rootComponents) else { return true }
    var cursor = canonicalRoot
    for component in pathComponents.dropFirst(rootComponents.count) {
        cursor.appendPathComponent(component)
        var info = stat()
        guard lstat(cursor.path, &info) == 0 else { return true }
        if (info.st_mode & S_IFMT) == S_IFLNK { return true }
    }
    return false
}

private func canonicalURL(_ url: URL) -> URL? {
    guard let resolved = realpath(url.path, nil) else { return nil }
    defer { free(resolved) }
    return URL(fileURLWithPath: String(cString: resolved))
}

private func isWithinAnyRoot(_ path: URL, roots: [URL]) -> Bool {
    roots.contains { isSameOrDescendant(path, of: $0) || (canonicalURL($0).map { isSameOrDescendant(path, of: $0) } ?? false) }
}

private func isWithinAnyRoot(_ path: URL, roots: [PreparedRoot]) -> Bool {
    roots.contains { root in
        isSameOrDescendant(path.path, of: root.path) || (root.canonicalPath.map { isSameOrDescendant(path.path, of: $0) } ?? false)
    }
}

private func isSameOrDescendant(_ path: URL, of root: URL) -> Bool {
    isSameOrDescendant(path.path, of: root.path)
}

private func isSameOrDescendant(_ path: String, of root: String) -> Bool {
    let rootString = root == "/" ? "/" : root.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    if rootString == "/" { return path.hasPrefix("/") }
    return path == "/\(rootString)" || path.hasPrefix("/\(rootString)/")
}
