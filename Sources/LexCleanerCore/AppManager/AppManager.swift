import Foundation
import Darwin
import Security

// App Manager is intentionally read-only. It discovers bundles and residual
// paths, but it never executes an app, removes a path, or changes system state.

public struct AppMetadata: Codable, Sendable, Hashable {
    public let bundleIdentifier: String?
    public let displayName: String?
    public let version: String?
    public let shortVersion: String?
    public let minimumOSVersion: String?
    public let executableName: String?

    public init(
        bundleIdentifier: String?,
        displayName: String?,
        version: String?,
        shortVersion: String?,
        minimumOSVersion: String?,
        executableName: String?
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.version = version
        self.shortVersion = shortVersion
        self.minimumOSVersion = minimumOSVersion
        self.executableName = executableName
    }
}

public struct InstalledApp: Codable, Sendable, Hashable {
    public let path: URL
    public let metadata: AppMetadata
    public let discoveredUnder: URL
    public let sizeBytes: UInt64?
    public let modifiedAt: Date?
    public let source: AppSource
    public let signature: AppSignatureStatus

    public init(
        path: URL,
        metadata: AppMetadata,
        discoveredUnder: URL,
        sizeBytes: UInt64? = nil,
        modifiedAt: Date? = nil,
        source: AppSource = .unknown,
        signature: AppSignatureStatus = .unavailable
    ) {
        self.path = path.standardizedFileURL
        self.metadata = metadata
        self.discoveredUnder = discoveredUnder.standardizedFileURL
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
        self.source = source
        self.signature = signature
    }

    public var bundleIdentifier: String? { metadata.bundleIdentifier }
    public var displayName: String { metadata.displayName ?? path.deletingPathExtension().lastPathComponent }

    /// The app bundle is always review-required and must be explicitly
    /// selected. It is intentionally separate from residual candidates so the
    /// UI cannot silently treat the app body as residual data.
    public var appBundleCleanupCandidate: CleanerCandidate {
        CleanerCandidate(
            path: path,
            category: .applicationCache,
            size: sizeBytes ?? 0,
            modifiedAt: modifiedAt,
            owningApp: bundleIdentifier,
            safetyLevel: .reviewRequired,
            cleanupReason: .applicationCacheNeedsReview,
            matchedRule: "installed-app-bundle",
            matchedRuleIDs: ["installed-app-bundle"],
            estimatedReclaimableBytes: sizeBytes ?? 0
        )
    }

    public var appBundleCleanupRule: CleanerRule {
        CleanerRule(
            id: "installed-app-bundle",
            name: "Installed App Bundle",
            category: .applicationCache,
            sourceCategories: [.applicationCache],
            allowedRoots: [path],
            defaultSafetyLevel: .reviewRequired,
            cleanupReason: .applicationCacheNeedsReview,
            dataDisposition: .applicationState,
            agePolicy: .any,
            sizePolicy: .any,
            scope: .installedAppBundle
        )
    }
}

public enum AppSource: String, Codable, Sendable, Hashable {
    case applications
    case userApplications
    case systemApplications
    case systemCoreServices
    case networkApplications
    case unknown
}

public enum AppSignatureStatus: String, Codable, Sendable, Hashable {
    case valid
    case invalid
    case unavailable
    case unknown
}

public enum InstalledAppIssueKind: String, Codable, Sendable, Hashable {
    case invalidRoot
    case enumerationFailed
    case invalidBundle
    case metadataUnavailable
    case missingBundleIdentifier
    case duplicateBundle
}

public struct InstalledAppIssue: Codable, Sendable, Hashable, Error {
    public let kind: InstalledAppIssueKind
    public let path: URL
    public let detail: String

    public init(kind: InstalledAppIssueKind, path: URL, detail: String) {
        self.kind = kind
        self.path = path
        self.detail = detail
    }
}

public struct InstalledAppInventory: Codable, Sendable, Hashable {
    public let generatedAt: Date
    public let roots: [URL]
    public let apps: [InstalledApp]
    public let issues: [InstalledAppIssue]

    public init(generatedAt: Date, roots: [URL], apps: [InstalledApp], issues: [InstalledAppIssue]) {
        self.generatedAt = generatedAt
        self.roots = roots
        self.apps = apps
        self.issues = issues
    }
}

public actor InstalledAppCatalog {
    public let applicationRoots: [URL]
    private let maxSearchDepth: Int

    public init(applicationRoots: [URL] = InstalledAppCatalog.defaultApplicationRoots(), maxSearchDepth: Int = 3) {
        self.applicationRoots = applicationRoots.map { $0.standardizedFileURL }
        self.maxSearchDepth = max(0, maxSearchDepth)
    }

    public static func defaultApplicationRoots(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        let home = homeDirectory.standardizedFileURL
        return [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Library/CoreServices", isDirectory: true),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Network/Applications", isDirectory: true)
        ]
    }

    public func enumerate() -> InstalledAppInventory {
        let fileManager = FileManager.default
        var apps: [InstalledApp] = []
        var issues: [InstalledAppIssue] = []
        var seenPaths: Set<URL> = []
        var seenBundleIDs: Set<String> = []

        for root in applicationRoots {
            let root = root.standardizedFileURL
            guard root.path.hasPrefix("/") else {
                issues.append(InstalledAppIssue(kind: .invalidRoot, path: root, detail: "Application root must be absolute."))
                continue
            }
            guard let rootMetadata = AppManagerFileMetadata.read(at: root), rootMetadata.fileType == .directory else {
                continue
            }
            guard let rootCanonical = AppManagerFileMetadata.canonicalURL(root) else {
                issues.append(InstalledAppIssue(kind: .invalidRoot, path: root, detail: "Application root could not be canonicalized."))
                continue
            }

            var pending: [(url: URL, depth: Int)] = [(root, 0)]
            var visitedDirectories: Set<URL> = [rootCanonical]
            while let current = pending.popLast() {
                let entries: [URL]
                do {
                    entries = try fileManager.contentsOfDirectory(at: current.url, includingPropertiesForKeys: nil, options: [])
                } catch {
                    issues.append(InstalledAppIssue(kind: .enumerationFailed, path: current.url, detail: error.localizedDescription))
                    continue
                }

                for entry in entries.sorted(by: { $0.path < $1.path }) {
                    let normalized = entry.standardizedFileURL
                    guard let metadata = AppManagerFileMetadata.read(at: normalized) else {
                        issues.append(InstalledAppIssue(kind: .metadataUnavailable, path: normalized, detail: "Could not read file metadata."))
                        continue
                    }
                    if normalized.pathExtension.lowercased() == "app" {
                        guard metadata.fileType == .directory else {
                            issues.append(InstalledAppIssue(kind: .invalidBundle, path: normalized, detail: "An .app entry is not a directory bundle."))
                            continue
                        }
                        guard let canonical = AppManagerFileMetadata.canonicalURL(normalized), seenPaths.insert(canonical).inserted else {
                            continue
                        }
                        switch Self.readInstalledApp(at: normalized, discoveredUnder: root) {
                        case let .success(app):
                            if let bundleIdentifier = app.bundleIdentifier {
                                if seenBundleIDs.insert(bundleIdentifier).inserted {
                                    apps.append(app)
                                } else {
                                    issues.append(InstalledAppIssue(kind: .duplicateBundle, path: normalized, detail: "Bundle identifier \(bundleIdentifier) was already discovered."))
                                }
                            } else {
                                issues.append(InstalledAppIssue(kind: .missingBundleIdentifier, path: normalized, detail: "CFBundleIdentifier is missing or invalid."))
                            }
                        case let .failure(issue):
                            issues.append(issue)
                        }
                        continue
                    }

                    guard current.depth < maxSearchDepth,
                          metadata.fileType == .directory,
                          let canonical = AppManagerFileMetadata.canonicalURL(normalized),
                          visitedDirectories.insert(canonical).inserted else {
                        continue
                    }
                    pending.append((normalized, current.depth + 1))
                }
            }
        }

        return InstalledAppInventory(
            generatedAt: Date(),
            roots: applicationRoots,
            apps: apps.sorted { $0.path.path < $1.path.path },
            issues: issues
        )
    }

    /// Returns installed bundle identifiers without calculating bundle sizes or
    /// signatures. This is intended for read-only overview consumers that need
    /// ownership evidence but must not rescan every App bundle payload.
    public func enumerateBundleIdentifiers() -> Set<String> {
        let fileManager = FileManager.default
        var identifiers: Set<String> = []

        for root in applicationRoots {
            guard let rootMetadata = AppManagerFileMetadata.read(at: root), rootMetadata.fileType == .directory,
                  let rootCanonical = AppManagerFileMetadata.canonicalURL(root) else { continue }

            var pending: [(url: URL, depth: Int)] = [(root.standardizedFileURL, 0)]
            var visitedDirectories: Set<URL> = [rootCanonical]
            while let current = pending.popLast() {
                guard let entries = try? fileManager.contentsOfDirectory(
                    at: current.url,
                    includingPropertiesForKeys: nil,
                    options: []
                ) else { continue }

                for entry in entries {
                    let normalized = entry.standardizedFileURL
                    guard let metadata = AppManagerFileMetadata.read(at: normalized) else { continue }
                    if normalized.pathExtension.lowercased() == "app" {
                        guard metadata.fileType == .directory else { continue }
                        guard let info = AppManagerFileMetadata.readPlist(
                            at: normalized.appendingPathComponent("Contents/Info.plist")
                        ), let identifier = info.string(forKey: "CFBundleIdentifier").flatMap(Self.validBundleIdentifier) else {
                            continue
                        }
                        identifiers.insert(identifier)
                        continue
                    }

                    guard current.depth < maxSearchDepth,
                          metadata.fileType == .directory,
                          let canonical = AppManagerFileMetadata.canonicalURL(normalized),
                          visitedDirectories.insert(canonical).inserted else { continue }
                    pending.append((normalized, current.depth + 1))
                }
            }
        }
        return identifiers
    }

    private static func readInstalledApp(at path: URL, discoveredUnder root: URL) -> Result<InstalledApp, InstalledAppIssue> {
        let infoURL = path.appendingPathComponent("Contents/Info.plist")
        guard let info = AppManagerFileMetadata.readPlist(at: infoURL) else {
            return .failure(InstalledAppIssue(kind: .metadataUnavailable, path: path, detail: "Contents/Info.plist could not be decoded."))
        }
        let bundleIdentifier = info.string(forKey: "CFBundleIdentifier").flatMap(Self.validBundleIdentifier)
        let metadata = AppMetadata(
            bundleIdentifier: bundleIdentifier,
            displayName: info.string(forKey: "CFBundleDisplayName") ?? info.string(forKey: "CFBundleName"),
            version: info.string(forKey: "CFBundleVersion"),
            shortVersion: info.string(forKey: "CFBundleShortVersionString"),
            minimumOSVersion: info.string(forKey: "LSMinimumSystemVersion"),
            executableName: info.string(forKey: "CFBundleExecutable")
        )
        return .success(InstalledApp(
            path: path,
            metadata: metadata,
            discoveredUnder: root,
            sizeBytes: AppManagerFileMetadata.directorySize(at: path),
            modifiedAt: AppManagerFileMetadata.read(at: path)?.modifiedAt,
            source: AppManagerFileMetadata.source(for: root),
            signature: AppManagerFileMetadata.signatureStatus(at: path)
        ))
    }

    private static func validBundleIdentifier(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/"), !trimmed.contains("\\"), !trimmed.contains("..") else { return nil }
        let components = trimmed.split(separator: ".")
        guard components.count >= 2, components.allSatisfy({ !$0.isEmpty }) else { return nil }
        return trimmed
    }
}

public enum ResidualKind: String, Codable, CaseIterable, Sendable, Hashable {
    case applicationSupport
    case cache
    case preferences
    case savedApplicationState
    case logs
    case webKit
    case httpStorage
    case container
    case launchAgent
    case unknown
}

public enum ResidualDataDisposition: String, Codable, CaseIterable, Sendable, Hashable {
    case applicationState
    case regenerableCache
    case userPreferences
    case savedState
    case logs
    case webData
    case containerData
    case launchItem
    case sharedData
    case unknown
}

public enum ResidualConfidence: String, Codable, CaseIterable, Sendable, Hashable {
    case high
    case medium
    case low
    case unknown
}

public struct AppResidualCandidate: Codable, Sendable, Hashable {
    public let id: UUID
    public let path: URL
    public let bundleIdentifier: String
    public let owningAppPath: URL
    public let kind: ResidualKind
    public let dataDisposition: ResidualDataDisposition
    public let sizeBytes: UInt64
    public let modifiedAt: Date?
    public let confidence: ResidualConfidence
    public let isSharedData: Bool
    public let isUnknownData: Bool
    public let reason: String

    public init(
        id: UUID = UUID(),
        path: URL,
        bundleIdentifier: String,
        owningAppPath: URL,
        kind: ResidualKind,
        dataDisposition: ResidualDataDisposition,
        sizeBytes: UInt64,
        modifiedAt: Date?,
        confidence: ResidualConfidence,
        isSharedData: Bool = false,
        isUnknownData: Bool = false,
        reason: String
    ) {
        self.id = id
        self.path = path.standardizedFileURL
        self.bundleIdentifier = bundleIdentifier
        self.owningAppPath = owningAppPath.standardizedFileURL
        self.kind = kind
        self.dataDisposition = dataDisposition
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
        self.confidence = confidence
        self.isSharedData = isSharedData
        self.isUnknownData = isUnknownData
        self.reason = reason
    }

    public var cleanupSafetyLevel: CleanupSafetyLevel {
        if isSharedData || isUnknownData || confidence == .unknown { return .unknown }
        if confidence == .low { return .protected }
        switch kind {
        case .cache, .webKit, .httpStorage:
            return .reviewRequired
        case .applicationSupport, .preferences, .savedApplicationState, .logs, .container, .launchAgent, .unknown:
            return .protected
        }
    }

    public var cleanupReason: CleanupReason {
        if isSharedData || isUnknownData || confidence == .unknown { return .unknownDataDisposition }
        if confidence == .low { return .userDataProtected }
        switch kind {
        case .cache, .webKit, .httpStorage: return .applicationCacheNeedsReview
        case .logs: return .oldLogNeedsReview
        case .applicationSupport, .preferences, .savedApplicationState, .container, .launchAgent, .unknown:
            return .userDataProtected
        }
    }

    public var cleanerCategory: CleanerCategory {
        kind == .logs ? .logs : .applicationCache
    }

    public func asCleanerCandidate() -> CleanerCandidate {
        let level = cleanupSafetyLevel
        return CleanerCandidate(
            path: path,
            category: cleanerCategory,
            size: sizeBytes,
            modifiedAt: modifiedAt,
            owningApp: bundleIdentifier,
            safetyLevel: level,
            cleanupReason: cleanupReason,
            matchedRule: "app-residual-\(kind.rawValue)",
            matchedRuleIDs: ["app-residual-\(kind.rawValue)"],
            estimatedReclaimableBytes: level == .reviewRequired ? sizeBytes : 0
        )
    }

    public var cleanupRule: CleanerRule {
        CleanerRule(
            id: "app-residual-\(kind.rawValue)",
            name: "App Residual",
            category: cleanerCategory,
            sourceCategories: [kind == .logs ? .logs : .applicationCache],
            allowedRoots: [path],
            defaultSafetyLevel: cleanupSafetyLevel,
            cleanupReason: cleanupReason,
            dataDisposition: .unknown,
            agePolicy: .any,
            sizePolicy: .any,
            scope: .appResidual
        )
    }
}

public enum SentinelFeasibilityStatus: String, Codable, Sendable, Hashable {
    case feasibleReadOnly
    case unavailable
    case unsupported
}

public struct SentinelFeasibility: Codable, Sendable, Hashable {
    public let status: SentinelFeasibilityStatus
    public let detail: String
    public let requiresWrite: Bool
    public let requiresPrivilege: Bool

    public init(status: SentinelFeasibilityStatus, detail: String, requiresWrite: Bool = false, requiresPrivilege: Bool = false) {
        self.status = status
        self.detail = detail
        self.requiresWrite = requiresWrite
        self.requiresPrivilege = requiresPrivilege
    }
}

public struct AppResidualAnalysis: Codable, Sendable, Hashable {
    public let analyzedAt: Date
    public let app: InstalledApp
    public let candidates: [AppResidualCandidate]
    public let issues: [String]
    public let sentinel: SentinelFeasibility

    public init(analyzedAt: Date, app: InstalledApp, candidates: [AppResidualCandidate], issues: [String], sentinel: SentinelFeasibility) {
        self.analyzedAt = analyzedAt
        self.app = app
        self.candidates = candidates
        self.issues = issues
        self.sentinel = sentinel
    }
}

public struct AppResidualAnalyzer: Sendable {
    public let homeDirectory: URL

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    public func analyze(app: InstalledApp) -> AppResidualAnalysis {
        guard let bundleIdentifier = app.bundleIdentifier else {
            return AppResidualAnalysis(
                analyzedAt: Date(), app: app, candidates: [],
                issues: ["App has no valid bundle identifier; residual analysis is fail-closed."],
                sentinel: SentinelFeasibility(status: .unsupported, detail: "A valid bundle identifier is required.")
            )
        }

        let library = homeDirectory.appendingPathComponent("Library", isDirectory: true)
        let exactLocations: [(ResidualKind, ResidualDataDisposition, URL, ResidualConfidence, String)] = [
            (.applicationSupport, .applicationState, library.appendingPathComponent("Application Support/\(bundleIdentifier)"), .high, "Exact bundle identifier application state path."),
            (.cache, .regenerableCache, library.appendingPathComponent("Caches/\(bundleIdentifier)"), .high, "Exact bundle identifier cache path; user review remains required."),
            (.savedApplicationState, .savedState, library.appendingPathComponent("Saved Application State/\(bundleIdentifier).savedState"), .high, "Exact bundle identifier saved state path."),
            (.logs, .logs, library.appendingPathComponent("Logs/\(bundleIdentifier)"), .high, "Exact bundle identifier log path."),
            (.webKit, .webData, library.appendingPathComponent("WebKit/\(bundleIdentifier)"), .high, "Exact bundle identifier WebKit path; user review remains required."),
            (.httpStorage, .webData, library.appendingPathComponent("HTTPStorages/\(bundleIdentifier)"), .high, "Exact bundle identifier HTTP storage path; user review remains required."),
            (.container, .containerData, library.appendingPathComponent("Containers/\(bundleIdentifier)"), .high, "Exact bundle identifier container path; container data is protected."),
            (.launchAgent, .launchItem, library.appendingPathComponent("LaunchAgents/\(bundleIdentifier).plist"), .medium, "Exact bundle identifier launch item; no launchd mutation is offered.")
        ]

        var candidates: [AppResidualCandidate] = []
        var issues: [String] = []
        var seen: Set<URL> = []

        for (kind, disposition, path, confidence, reason) in exactLocations {
            if let candidate = makeCandidateIfPresent(
                path: path,
                bundleIdentifier: bundleIdentifier,
                app: app,
                kind: kind,
                disposition: disposition,
                confidence: confidence,
                reason: reason,
                seen: &seen
            ) {
                candidates.append(candidate)
            }
        }

        let preferencesRoot = library.appendingPathComponent("Preferences", isDirectory: true)
        if let entries = try? FileManager.default.contentsOfDirectory(at: preferencesRoot, includingPropertiesForKeys: nil, options: []) {
            for entry in entries where Self.isBundlePreference(entry.lastPathComponent, bundleIdentifier: bundleIdentifier) {
                if let candidate = makeCandidateIfPresent(
                    path: entry,
                    bundleIdentifier: bundleIdentifier,
                    app: app,
                    kind: .preferences,
                    disposition: .userPreferences,
                    confidence: entry.lastPathComponent == "\(bundleIdentifier).plist" ? .high : .medium,
                    reason: "Preference filename is exactly associated with the bundle identifier; preferences are protected.",
                    seen: &seen
                ) {
                    candidates.append(candidate)
                }
            }
        }

        let groupContainers = library.appendingPathComponent("Group Containers", isDirectory: true)
        if FileManager.default.fileExists(atPath: groupContainers.path) {
            issues.append("Group Containers were not associated automatically because they may be shared; shared data is fail-closed.")
        }

        return AppResidualAnalysis(
            analyzedAt: Date(),
            app: app,
            candidates: candidates.sorted { $0.path.path < $1.path.path },
            issues: issues,
            sentinel: SentinelFeasibility(status: .feasibleReadOnly, detail: "Only deterministic bundle metadata and residual path checks are available; no Sentinel write/helper operation is attempted.")
        )
    }

    public func sentinelFeasibility(for app: InstalledApp) -> SentinelFeasibility {
        guard app.bundleIdentifier != nil else {
            return SentinelFeasibility(status: .unsupported, detail: "A valid bundle identifier is required.")
        }
        return SentinelFeasibility(status: .feasibleReadOnly, detail: "Read-only feasibility check only; no helper, launch item, command, or file mutation is permitted.")
    }

    private func makeCandidateIfPresent(
        path: URL,
        bundleIdentifier: String,
        app: InstalledApp,
        kind: ResidualKind,
        disposition: ResidualDataDisposition,
        confidence: ResidualConfidence,
        reason: String,
        seen: inout Set<URL>
    ) -> AppResidualCandidate? {
        let normalized = path.standardizedFileURL
        guard let metadata = AppManagerFileMetadata.read(at: normalized),
              let canonical = AppManagerFileMetadata.canonicalURL(normalized),
              seen.insert(canonical).inserted else { return nil }
        let shared = normalized.pathComponents.contains("Group Containers") || normalized.pathComponents.contains("Shared")
        let unknown = !normalized.path.hasPrefix(homeDirectory.appendingPathComponent("Library").path + "/")
        return AppResidualCandidate(
            path: normalized,
            bundleIdentifier: bundleIdentifier,
            owningAppPath: app.path,
            kind: kind,
            dataDisposition: shared ? .sharedData : (unknown ? .unknown : disposition),
            sizeBytes: metadata.fileType == .directory
                ? (AppManagerFileMetadata.directorySize(at: normalized) ?? 0)
                : AppManagerFileMetadata.size(metadata: metadata),
            modifiedAt: metadata.modifiedAt,
            confidence: shared || unknown ? .unknown : confidence,
            isSharedData: shared,
            isUnknownData: unknown,
            reason: shared ? "Shared container path; automatic association is forbidden." : (unknown ? "Residual path is outside the approved user Library boundary." : reason)
        )
    }

    private static func isBundlePreference(_ name: String, bundleIdentifier: String) -> Bool {
        name == "\(bundleIdentifier).plist" || name.hasPrefix("\(bundleIdentifier).")
    }
}

public enum UninstallPlanDecision: String, Codable, Sendable, Hashable {
    case eligibleForCleanupReview
    case rejectedFailClosed
}

public struct UninstallPlanItem: Codable, Sendable, Hashable {
    public let candidate: AppResidualCandidate
    public let cleanupCandidate: CleanerCandidate
    public let explicitlySelected: Bool
    public let decision: UninstallPlanDecision
    public let rejectionReason: String?

    public init(candidate: AppResidualCandidate, explicitlySelected: Bool = false) {
        self.candidate = candidate
        self.cleanupCandidate = candidate.asCleanerCandidate()
        self.explicitlySelected = explicitlySelected
        if candidate.cleanupSafetyLevel == .reviewRequired && explicitlySelected {
            self.decision = .eligibleForCleanupReview
            self.rejectionReason = nil
        } else {
            self.decision = .rejectedFailClosed
            self.rejectionReason = candidate.isSharedData || candidate.isUnknownData || candidate.confidence == .unknown
                ? "Unknown or shared residual data is fail-closed."
                : "Residual requires explicit user selection and confirmation in CleanupPlanner."
        }
    }

    public var isEligibleForCleanupReview: Bool { decision == .eligibleForCleanupReview }
}

public struct UninstallPlan: Codable, Sendable, Hashable {
    public let planID: UUID
    public let createdAt: Date
    public let app: InstalledApp
    public let appBundleCandidate: CleanerCandidate
    public let appBundleSelected: Bool
    public let items: [UninstallPlanItem]
    public let sentinel: SentinelFeasibility

    public init(planID: UUID = UUID(), createdAt: Date, app: InstalledApp, appBundleSelected: Bool = false, items: [UninstallPlanItem], sentinel: SentinelFeasibility) {
        self.planID = planID
        self.createdAt = createdAt
        self.app = app
        self.appBundleCandidate = app.appBundleCleanupCandidate
        self.appBundleSelected = appBundleSelected
        self.items = items
        self.sentinel = sentinel
    }

    public var eligibleItems: [UninstallPlanItem] { items.filter(\.isEligibleForCleanupReview) }
    public var cleanupCandidates: [CleanerCandidate] { [appBundleCandidate] + items.map(\.cleanupCandidate) }
    public var eligibleCleanupCandidates: [CleanerCandidate] { (appBundleSelected ? [appBundleCandidate] : []) + eligibleItems.map(\.cleanupCandidate) }
    public var appBundleRemovalIsSupported: Bool { true }
}

public struct UninstallSelection: Sendable, Hashable {
    public let selectedPaths: Set<URL>
    public let userConfirmed: Bool

    public init(selectedPaths: Set<URL> = [], userConfirmed: Bool = false) {
        self.selectedPaths = Set(selectedPaths.map { $0.standardizedFileURL })
        self.userConfirmed = userConfirmed
    }

    public func contains(_ path: URL) -> Bool { selectedPaths.contains(path.standardizedFileURL) }
}

public struct AppManager: Sendable {
    public let catalog: InstalledAppCatalog
    public let residualAnalyzer: AppResidualAnalyzer

    public init(
        catalog: InstalledAppCatalog = InstalledAppCatalog(),
        residualAnalyzer: AppResidualAnalyzer = AppResidualAnalyzer()
    ) {
        self.catalog = catalog
        self.residualAnalyzer = residualAnalyzer
    }

    public func enumerateInstalledApps() async -> InstalledAppInventory {
        await catalog.enumerate()
    }

    public func analyzeResiduals(for app: InstalledApp) async -> AppResidualAnalysis {
        residualAnalyzer.analyze(app: app)
    }

    public func makeUninstallPlan(for app: InstalledApp, selection: UninstallSelection = UninstallSelection()) async -> UninstallPlan {
        let analysis = residualAnalyzer.analyze(app: app)
        let items = analysis.candidates.map { candidate in
            UninstallPlanItem(candidate: candidate, explicitlySelected: selection.userConfirmed && selection.contains(candidate.path))
        }
        return UninstallPlan(createdAt: Date(), app: app, appBundleSelected: selection.userConfirmed && selection.contains(app.path), items: items, sentinel: analysis.sentinel)
    }
}

private struct AppManagerPlist {
    let values: [String: Any]

    func string(forKey key: String) -> String? { values[key] as? String }
}

private enum AppManagerFileType {
    case regular
    case directory
    case symbolicLink
    case other
}

private struct AppManagerFileMetadata {
    let fileType: AppManagerFileType
    let sizeBytes: UInt64
    let modifiedAt: Date?

    static func read(at url: URL) -> AppManagerFileMetadata? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        let type = info.st_mode & S_IFMT
        let fileType: AppManagerFileType
        switch type {
        case S_IFREG: fileType = .regular
        case S_IFDIR: fileType = .directory
        case S_IFLNK: fileType = .symbolicLink
        default: fileType = .other
        }
        let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000)
        return AppManagerFileMetadata(fileType: fileType, sizeBytes: info.st_size > 0 ? UInt64(info.st_size) : 0, modifiedAt: modified)
    }

    static func canonicalURL(_ url: URL) -> URL? {
        guard let pointer = realpath(url.path, nil) else { return nil }
        defer { free(pointer) }
        return URL(fileURLWithPath: String(cString: pointer))
    }

    static func readPlist(at url: URL) -> AppManagerPlist? {
        guard let data = try? Data(contentsOf: url),
              let property = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let values = property as? [String: Any] else { return nil }
        return AppManagerPlist(values: values)
    }

    static func size(metadata: AppManagerFileMetadata) -> UInt64 {
        // Keep the lstat size identical to CleanupPlanner's source snapshot.
        // Recursive directory usage would make a plan look source-changed even
        // when the directory itself had not changed.
        return metadata.sizeBytes
    }

    static func directorySize(at root: URL) -> UInt64? {
        guard read(at: root)?.fileType == .directory,
            let enumerator = FileManager.default.enumerator(
                  at: root,
                  includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                  options: []
              ) else { return nil }
        var total: UInt64 = 0
        while let item = enumerator.nextObject() as? URL {
            guard let metadata = read(at: item) else { continue }
            if metadata.fileType == .symbolicLink {
                enumerator.skipDescendants()
            } else if metadata.fileType == .regular {
                let sum = total.addingReportingOverflow(metadata.sizeBytes)
                total = sum.overflow ? UInt64.max : sum.partialValue
            }
        }
        return total
    }

    static func source(for root: URL) -> AppSource {
        switch root.standardizedFileURL.path {
        case "/Applications": return .applications
        case "/System/Applications": return .systemApplications
        case "/System/Library/CoreServices", "/System/Library/CoreServices/Applications": return .systemCoreServices
        case "/Network/Applications": return .networkApplications
        default:
            let homeApplications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").standardizedFileURL.path
            return root.standardizedFileURL.path == homeApplications ? .userApplications : .unknown
        }
    }

    static func signatureStatus(at path: URL) -> AppSignatureStatus {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(path as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return .unavailable }
        let result = SecStaticCodeCheckValidity(staticCode, [], nil)
        if result == errSecSuccess { return .valid }
        if result == errSecCSUnsigned { return .invalid }
        return .unknown
    }
}
