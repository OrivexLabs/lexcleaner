import Foundation
import Darwin
import os

public enum CleanupFailureReason: String, Sendable, Equatable {
    case notSelected
    case protected
    case unknown
    case sourceChanged
    case identityMismatch
    case canonicalPathChanged
    case fileTypeChanged
    case symlinkRejected
    case ruleConflict
    case classificationChanged
    case invalidCandidate
    case duplicateCandidate
    case notFound
    case preflightRequired
    case preflightFailed
    case cancelled
    case safeDeleteRejected
    case safeDeleteFailed
}

public enum CleanupDeletionMethod: String, Sendable, Equatable {
    case trash
}

public struct CleanupSelection: Sendable, Equatable {
    public let selectedPaths: Set<URL>
    public let userConfirmed: Bool

    public init(selectedPaths: Set<URL> = [], userConfirmed: Bool = false) {
        self.selectedPaths = Set(selectedPaths.map { $0.standardizedFileURL })
        self.userConfirmed = userConfirmed
    }

    public func contains(path: URL) -> Bool {
        selectedPaths.contains(path.standardizedFileURL)
    }
}

public enum CleanupPlanDecision: String, Sendable, Equatable {
    case eligible
    case rejected
}

public struct CleanupPlanItem: Sendable, Equatable {
    public let candidateIdentity: UUID
    public let originalPath: URL
    public let canonicalPath: URL?
    public let identity: SafeDeleteFileIdentity?
    public let size: UInt64
    public let modifiedAt: Date?
    public let category: CleanerCategory
    public let safetyLevel: CleanupSafetyLevel
    public let matchedRule: String
    public let cleanupReason: CleanupReason
    public let createdAt: Date
    public let reclaimableBytes: UInt64
    public let explicitlySelected: Bool
    public let deletionMethod: CleanupDeletionMethod
    public let decision: CleanupPlanDecision
    public let rejectionReason: CleanupFailureReason?

    public init(
        candidateIdentity: UUID,
        originalPath: URL,
        canonicalPath: URL?,
        identity: SafeDeleteFileIdentity?,
        size: UInt64,
        modifiedAt: Date?,
        category: CleanerCategory,
        safetyLevel: CleanupSafetyLevel,
        matchedRule: String,
        cleanupReason: CleanupReason,
        createdAt: Date,
        reclaimableBytes: UInt64,
        explicitlySelected: Bool,
        deletionMethod: CleanupDeletionMethod,
        decision: CleanupPlanDecision,
        rejectionReason: CleanupFailureReason?
    ) {
        self.candidateIdentity = candidateIdentity
        self.originalPath = originalPath
        self.canonicalPath = canonicalPath
        self.identity = identity
        self.size = size
        self.modifiedAt = modifiedAt
        self.category = category
        self.safetyLevel = safetyLevel
        self.matchedRule = matchedRule
        self.cleanupReason = cleanupReason
        self.createdAt = createdAt
        self.reclaimableBytes = reclaimableBytes
        self.explicitlySelected = explicitlySelected
        self.deletionMethod = deletionMethod
        self.decision = decision
        self.rejectionReason = rejectionReason
    }

    public var isEligible: Bool { decision == .eligible }
}

public struct CleanupPlan: Sendable, Equatable {
    public let planID: UUID
    public let createdAt: Date
    public let items: [CleanupPlanItem]

    public init(planID: UUID = UUID(), createdAt: Date, items: [CleanupPlanItem]) {
        self.planID = planID
        self.createdAt = createdAt
        self.items = items
    }

    public var eligibleItems: [CleanupPlanItem] { items.filter(\.isEligible) }
    public var eligibleCount: Int { eligibleItems.count }
    public var eligibleBytes: UInt64 { eligibleItems.reduce(0) { $0 + $1.reclaimableBytes } }
}

public struct CleanupDryRunItem: Sendable, Equatable {
    public let candidateIdentity: UUID
    public let path: URL
    public let category: CleanerCategory
    public let safetyLevel: CleanupSafetyLevel
    public let size: UInt64
    public let deletionMethod: CleanupDeletionMethod
    public let wouldProcess: Bool
    public let rejectionReason: CleanupFailureReason?

    public init(
        candidateIdentity: UUID,
        path: URL,
        category: CleanerCategory,
        safetyLevel: CleanupSafetyLevel,
        size: UInt64,
        deletionMethod: CleanupDeletionMethod,
        wouldProcess: Bool,
        rejectionReason: CleanupFailureReason?
    ) {
        self.candidateIdentity = candidateIdentity
        self.path = path
        self.category = category
        self.safetyLevel = safetyLevel
        self.size = size
        self.deletionMethod = deletionMethod
        self.wouldProcess = wouldProcess
        self.rejectionReason = rejectionReason
    }
}

public struct CleanupDryRunResult: Sendable, Equatable {
    public let planID: UUID
    public let generatedAt: Date
    public let processCount: Int
    public let processBytes: UInt64
    public let rejectedCount: Int
    public let items: [CleanupDryRunItem]

    public init(
        planID: UUID,
        generatedAt: Date,
        processCount: Int,
        processBytes: UInt64,
        rejectedCount: Int,
        items: [CleanupDryRunItem]
    ) {
        self.planID = planID
        self.generatedAt = generatedAt
        self.processCount = processCount
        self.processBytes = processBytes
        self.rejectedCount = rejectedCount
        self.items = items
    }
}

public enum CleanupPreflightStatus: String, Sendable, Equatable {
    case passed
    case rejected
}

public struct CleanupPreflightItem: Sendable, Equatable {
    public let candidateIdentity: UUID
    public let status: CleanupPreflightStatus
    public let checkedAt: Date
    public let currentCanonicalPath: URL?
    public let currentIdentity: SafeDeleteFileIdentity?
    public let currentSafetyLevel: CleanupSafetyLevel?
    public let currentCleanupReason: CleanupReason?
    public let failureReason: CleanupFailureReason?

    public init(
        candidateIdentity: UUID,
        status: CleanupPreflightStatus,
        checkedAt: Date,
        currentCanonicalPath: URL?,
        currentIdentity: SafeDeleteFileIdentity?,
        currentSafetyLevel: CleanupSafetyLevel?,
        currentCleanupReason: CleanupReason?,
        failureReason: CleanupFailureReason?
    ) {
        self.candidateIdentity = candidateIdentity
        self.status = status
        self.checkedAt = checkedAt
        self.currentCanonicalPath = currentCanonicalPath
        self.currentIdentity = currentIdentity
        self.currentSafetyLevel = currentSafetyLevel
        self.currentCleanupReason = currentCleanupReason
        self.failureReason = failureReason
    }
}

public struct CleanupPreflightResult: Sendable, Equatable {
    public let planID: UUID
    public let checkedAt: Date
    public let items: [CleanupPreflightItem]

    public init(planID: UUID, checkedAt: Date, items: [CleanupPreflightItem]) {
        self.planID = planID
        self.checkedAt = checkedAt
        self.items = items
    }

    public var passed: Bool { items.filter { $0.status == .passed }.count == items.count }
}

public enum CleanupExecutionStatus: String, Sendable, Equatable {
    case success
    case skipped
    case rejected
    case failed
}

public struct CleanupExecutionItem: Sendable, Equatable {
    public let candidateIdentity: UUID
    public let path: URL
    public let status: CleanupExecutionStatus
    public let reclaimedBytes: UInt64
    public let operationID: UUID?
    public let failureReason: CleanupFailureReason?

    public init(
        candidateIdentity: UUID,
        path: URL,
        status: CleanupExecutionStatus,
        reclaimedBytes: UInt64,
        operationID: UUID?,
        failureReason: CleanupFailureReason?
    ) {
        self.candidateIdentity = candidateIdentity
        self.path = path
        self.status = status
        self.reclaimedBytes = reclaimedBytes
        self.operationID = operationID
        self.failureReason = failureReason
    }
}

public enum CleanupAuditPhase: String, Sendable, Equatable {
    case planCreated
    case dryRun
    case preflight
    case execution
}

public struct CleanupAuditEntry: Sendable, Equatable {
    public let timestamp: Date
    public let phase: CleanupAuditPhase
    public let planID: UUID
    public let candidateIdentity: UUID
    public let path: URL
    public let explicitlySelected: Bool
    public let preflightStatus: CleanupPreflightStatus?
    public let executionStatus: CleanupExecutionStatus?
    public let reclaimedBytes: UInt64
    public let failureReason: CleanupFailureReason?

    public init(
        timestamp: Date,
        phase: CleanupAuditPhase,
        planID: UUID,
        candidateIdentity: UUID,
        path: URL,
        explicitlySelected: Bool,
        preflightStatus: CleanupPreflightStatus?,
        executionStatus: CleanupExecutionStatus?,
        reclaimedBytes: UInt64,
        failureReason: CleanupFailureReason?
    ) {
        self.timestamp = timestamp
        self.phase = phase
        self.planID = planID
        self.candidateIdentity = candidateIdentity
        self.path = path
        self.explicitlySelected = explicitlySelected
        self.preflightStatus = preflightStatus
        self.executionStatus = executionStatus
        self.reclaimedBytes = reclaimedBytes
        self.failureReason = failureReason
    }
}

public protocol CleanupAuditLogging: Sendable {
    func record(_ entry: CleanupAuditEntry) async
}

public actor InMemoryCleanupAuditLogger: CleanupAuditLogging {
    private var entries: [CleanupAuditEntry] = []

    public init() {}

    public func record(_ entry: CleanupAuditEntry) {
        entries.append(entry)
    }

    public func allEntries() -> [CleanupAuditEntry] { entries }
}

public struct OSLogCleanupAuditLogger: CleanupAuditLogging {
    private let logger = Logger(subsystem: "com.lexcleaner.app", category: "CleanupAudit")

    public init() {}

    public func record(_ entry: CleanupAuditEntry) {
        logger.log(level: entry.phase == .execution && entry.executionStatus != .success ? .error : .info,
                   "phase=\(entry.phase.rawValue, privacy: .public) plan=\(entry.planID.uuidString, privacy: .public) candidate=\(entry.candidateIdentity.uuidString, privacy: .public) selected=\(entry.explicitlySelected, privacy: .public) status=\(String(describing: entry.executionStatus), privacy: .public) failure=\(String(describing: entry.failureReason), privacy: .public) reclaimed=\(entry.reclaimedBytes, privacy: .public) path=\(entry.path.path, privacy: .private(mask: .hash))")
    }
}

public struct CleanupExecutionResult: Sendable, Equatable {
    public let planID: UUID
    public let startedAt: Date
    public let finishedAt: Date
    public let items: [CleanupExecutionItem]
    public let reclaimedBytes: UInt64
    public let audit: [CleanupAuditEntry]

    public init(
        planID: UUID,
        startedAt: Date,
        finishedAt: Date,
        items: [CleanupExecutionItem],
        reclaimedBytes: UInt64,
        audit: [CleanupAuditEntry]
    ) {
        self.planID = planID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.items = items
        self.reclaimedBytes = reclaimedBytes
        self.audit = audit
    }
}

public actor CleanupPlanner {
    private let safeDeleteEngine: SafeDeleteEngine
    private let classificationEngine: ClassificationEngine
    private let classificationRules: [CleanerRule]
    private let auditLogger: any CleanupAuditLogging

    /// Production-facing construction keeps deletion policy creation inside the
    /// Core boundary. Tests and specialized integrations may still inject the
    /// engine through the initializer below.
    public init(
        whitelistedRoots: [URL],
        classificationRules: [CleanerRule],
        applicationRoots: [URL] = ClassificationEngine.defaultApplicationRoots(),
        explicitlyAllowedApplicationBundles: [URL] = [],
        auditLogger: any CleanupAuditLogging = OSLogCleanupAuditLogger()
    ) {
        self.init(
            safeDeleteEngine: SafeDeleteEngine(policy: SafeDeletePolicy(whitelistedRoots: whitelistedRoots, explicitlyAllowedApplicationBundles: explicitlyAllowedApplicationBundles)),
            classificationRules: classificationRules,
            classificationEngine: ClassificationEngine(applicationRoots: applicationRoots),
            auditLogger: auditLogger
        )
    }

    public init(
        safeDeleteEngine: SafeDeleteEngine,
        classificationRules: [CleanerRule],
        classificationEngine: ClassificationEngine = ClassificationEngine(),
        auditLogger: any CleanupAuditLogging = OSLogCleanupAuditLogger()
    ) {
        self.safeDeleteEngine = safeDeleteEngine
        self.classificationRules = classificationRules
        self.classificationEngine = classificationEngine
        self.auditLogger = auditLogger
    }

    public func makePlan(
        candidates: [CleanerCandidate],
        selection: CleanupSelection,
        createdAt: Date = Date()
    ) async -> CleanupPlan {
        let planID = UUID()
        var items: [CleanupPlanItem] = []
        var seenKeys: Set<CleanupDuplicateKey> = []

        for candidate in candidates {
            let candidateIdentity = UUID()
            let path = candidate.path.standardizedFileURL
            let selected = selection.userConfirmed && selection.contains(path: path)
            let snapshot = snapshot(at: path)
            let canonicalPath = snapshot?.canonicalPath
            let identity = snapshot?.identity
            var reason: CleanupFailureReason?
            var decision: CleanupPlanDecision = .eligible

            if candidate.category == .unknown || candidate.matchedRule == "none" || candidate.estimatedReclaimableBytes > candidate.size {
                decision = .rejected
                reason = .invalidCandidate
            } else if candidate.cleanupReason == .sourceChanged {
                decision = .rejected
                reason = .sourceChanged
            } else if candidate.cleanupReason == .ruleConflict {
                decision = .rejected
                reason = .ruleConflict
            } else if let snapshot {
                let key = CleanupDuplicateKey(path: canonicalPath ?? path, identity: snapshot.identity)
                if !seenKeys.insert(key).inserted {
                    decision = .rejected
                    reason = .duplicateCandidate
                } else if snapshot.isSymbolicLink {
                    decision = .rejected
                    reason = .symlinkRejected
                } else if candidate.size != snapshot.contentSizeBytes || candidate.modifiedAt != snapshot.modifiedAt {
                    decision = .rejected
                    reason = .sourceChanged
                } else {
                    switch candidate.safetyLevel {
                    case .safe:
                        // A caller that has entered the explicit selection phase
                        // must be able to deselect even a default-safe item. The
                        // legacy unconfirmed selection remains useful for
                        // read-only Core dry-run callers.
                        if selection.userConfirmed && !selected {
                            decision = .rejected
                            reason = .notSelected
                        }
                    case .reviewRequired:
                        if !selected {
                            decision = .rejected
                            reason = .notSelected
                        }
                    case .protected:
                        decision = .rejected
                        reason = .protected
                    case .unknown:
                        decision = .rejected
                        reason = candidate.cleanupReason == .ruleConflict ? .ruleConflict : .unknown
                    }
                }
            } else {
                decision = .rejected
                reason = .sourceChanged
            }

            let item = CleanupPlanItem(
                candidateIdentity: candidateIdentity,
                originalPath: path,
                canonicalPath: canonicalPath,
                identity: identity,
                size: candidate.size,
                modifiedAt: candidate.modifiedAt,
                category: candidate.category,
                safetyLevel: candidate.safetyLevel,
                matchedRule: candidate.matchedRule,
                cleanupReason: candidate.cleanupReason,
                createdAt: createdAt,
                reclaimableBytes: decision == .eligible ? candidate.estimatedReclaimableBytes : 0,
                explicitlySelected: selected,
                deletionMethod: .trash,
                decision: decision,
                rejectionReason: reason
            )
            items.append(item)
            await auditLogger.record(CleanupAuditEntry(
                timestamp: createdAt,
                phase: .planCreated,
                planID: planID,
                candidateIdentity: candidateIdentity,
                path: path,
                explicitlySelected: selected,
                preflightStatus: nil,
                executionStatus: nil,
                reclaimedBytes: 0,
                failureReason: reason
            ))
        }

        return CleanupPlan(planID: planID, createdAt: createdAt, items: items)
    }

    public func dryRun(plan: CleanupPlan, generatedAt: Date = Date()) async -> CleanupDryRunResult {
        let items = plan.items.map { item in
            CleanupDryRunItem(
                candidateIdentity: item.candidateIdentity,
                path: item.originalPath,
                category: item.category,
                safetyLevel: item.safetyLevel,
                size: item.size,
                deletionMethod: item.deletionMethod,
                wouldProcess: item.isEligible,
                rejectionReason: item.rejectionReason
            )
        }
        for item in plan.items {
            await auditLogger.record(CleanupAuditEntry(
                timestamp: generatedAt,
                phase: .dryRun,
                planID: plan.planID,
                candidateIdentity: item.candidateIdentity,
                path: item.originalPath,
                explicitlySelected: item.explicitlySelected,
                preflightStatus: nil,
                executionStatus: nil,
                reclaimedBytes: 0,
                failureReason: item.rejectionReason
            ))
        }
        return CleanupDryRunResult(
            planID: plan.planID,
            generatedAt: generatedAt,
            processCount: plan.eligibleCount,
            processBytes: plan.eligibleBytes,
            rejectedCount: plan.items.count - plan.eligibleCount,
            items: items
        )
    }

    public func preflight(plan: CleanupPlan, checkedAt: Date = Date()) async -> CleanupPreflightResult {
        var results: [CleanupPreflightItem] = []
        results.reserveCapacity(plan.items.count)

        for item in plan.items {
            let result: CleanupPreflightItem
            if !item.isEligible {
                result = CleanupPreflightItem(
                    candidateIdentity: item.candidateIdentity,
                    status: .rejected,
                    checkedAt: checkedAt,
                    currentCanonicalPath: snapshot(at: item.originalPath)?.canonicalPath,
                    currentIdentity: snapshot(at: item.originalPath)?.identity,
                    currentSafetyLevel: nil,
                    currentCleanupReason: nil,
                    failureReason: item.rejectionReason ?? .preflightFailed
                )
            } else if Task.isCancelled {
                result = rejectedPreflight(item: item, checkedAt: checkedAt, reason: .cancelled)
            } else {
                result = await revalidate(item: item, checkedAt: checkedAt)
            }
            results.append(result)
            await auditLogger.record(CleanupAuditEntry(
                timestamp: checkedAt,
                phase: .preflight,
                planID: plan.planID,
                candidateIdentity: item.candidateIdentity,
                path: item.originalPath,
                explicitlySelected: item.explicitlySelected,
                preflightStatus: result.status,
                executionStatus: nil,
                reclaimedBytes: 0,
                failureReason: result.failureReason
            ))
        }

        return CleanupPreflightResult(planID: plan.planID, checkedAt: checkedAt, items: results)
    }

    public func execute(
        plan: CleanupPlan,
        preflight: CleanupPreflightResult,
        startedAt: Date = Date()
    ) async -> CleanupExecutionResult {
        var results: [CleanupExecutionItem] = []
        var audit: [CleanupAuditEntry] = []
        var reclaimedBytes: UInt64 = 0
        let preflightByID = Dictionary(uniqueKeysWithValues: preflight.items.map { ($0.candidateIdentity, $0) })

        for item in plan.items {
            let execution: CleanupExecutionItem
            if Task.isCancelled {
                execution = CleanupExecutionItem(candidateIdentity: item.candidateIdentity, path: item.originalPath, status: .skipped, reclaimedBytes: 0, operationID: nil, failureReason: .cancelled)
            } else if !item.isEligible {
                execution = CleanupExecutionItem(candidateIdentity: item.candidateIdentity, path: item.originalPath, status: .rejected, reclaimedBytes: 0, operationID: nil, failureReason: item.rejectionReason ?? .preflightFailed)
            } else if preflight.planID != plan.planID {
                execution = CleanupExecutionItem(candidateIdentity: item.candidateIdentity, path: item.originalPath, status: .rejected, reclaimedBytes: 0, operationID: nil, failureReason: .preflightRequired)
            } else if preflightByID[item.candidateIdentity]?.status != .passed {
                execution = CleanupExecutionItem(candidateIdentity: item.candidateIdentity, path: item.originalPath, status: .rejected, reclaimedBytes: 0, operationID: nil, failureReason: preflightByID[item.candidateIdentity]?.failureReason ?? .preflightRequired)
            } else {
                let executionRevalidation = await revalidate(item: item, checkedAt: Date())
                if executionRevalidation.status != .passed {
                    execution = CleanupExecutionItem(candidateIdentity: item.candidateIdentity, path: item.originalPath, status: .rejected, reclaimedBytes: 0, operationID: nil, failureReason: executionRevalidation.failureReason ?? .preflightFailed)
                } else {
                    do {
                        let deletion = try await safeDeleteEngine.delete(path: item.originalPath.path, mode: .trash)
                        reclaimedBytes += item.reclaimableBytes
                        execution = CleanupExecutionItem(candidateIdentity: item.candidateIdentity, path: item.originalPath, status: .success, reclaimedBytes: item.reclaimableBytes, operationID: deletion.operationID, failureReason: nil)
                    } catch {
                        execution = CleanupExecutionItem(candidateIdentity: item.candidateIdentity, path: item.originalPath, status: executionStatus(for: error), reclaimedBytes: 0, operationID: nil, failureReason: failureReason(for: error))
                    }
                }
            }
            results.append(execution)
            let entry = CleanupAuditEntry(
                timestamp: Date(),
                phase: .execution,
                planID: plan.planID,
                candidateIdentity: item.candidateIdentity,
                path: item.originalPath,
                explicitlySelected: item.explicitlySelected,
                preflightStatus: preflightByID[item.candidateIdentity]?.status,
                executionStatus: execution.status,
                reclaimedBytes: execution.reclaimedBytes,
                failureReason: execution.failureReason
            )
            audit.append(entry)
            await auditLogger.record(entry)
        }

        return CleanupExecutionResult(planID: plan.planID, startedAt: startedAt, finishedAt: Date(), items: results, reclaimedBytes: reclaimedBytes, audit: audit)
    }

    private func revalidate(item: CleanupPlanItem, checkedAt: Date) async -> CleanupPreflightItem {
        guard let expectedIdentity = item.identity, let expectedCanonicalPath = item.canonicalPath else {
            return rejectedPreflight(item: item, checkedAt: checkedAt, reason: .sourceChanged)
        }
        guard let current = snapshot(at: item.originalPath) else {
            return rejectedPreflight(item: item, checkedAt: checkedAt, reason: .notFound)
        }
        guard current.identity == expectedIdentity else {
            return rejectedPreflight(item: item, checkedAt: checkedAt, reason: .identityMismatch, current: current)
        }
        guard current.canonicalPath == expectedCanonicalPath else {
            return rejectedPreflight(item: item, checkedAt: checkedAt, reason: .canonicalPathChanged, current: current)
        }
        guard !current.isSymbolicLink else {
            return rejectedPreflight(item: item, checkedAt: checkedAt, reason: .symlinkRejected, current: current)
        }
        guard current.contentSizeBytes == item.size, current.modifiedAt == item.modifiedAt else {
            return rejectedPreflight(item: item, checkedAt: checkedAt, reason: .sourceChanged, current: current)
        }

        do {
            let assessment = try await safeDeleteEngine.assess(path: item.originalPath.path)
            guard assessment.normalizedPath.path == item.originalPath.path else {
                return rejectedPreflight(item: item, checkedAt: checkedAt, reason: .canonicalPathChanged, current: current)
            }
            guard assessment.resolvedPath.path == expectedCanonicalPath.path else {
                return rejectedPreflight(item: item, checkedAt: checkedAt, reason: .canonicalPathChanged, current: current)
            }
            guard assessment.targetIdentity == expectedIdentity, assessment.resolvedIdentity == expectedIdentity else {
                return rejectedPreflight(item: item, checkedAt: checkedAt, reason: .identityMismatch, current: current)
            }
            guard assessment.symlinkComponents.isEmpty && !assessment.containsSymlink else {
                return rejectedPreflight(item: item, checkedAt: checkedAt, reason: .symlinkRejected, current: current)
            }

            let scanItem = ScanItem(path: item.originalPath, category: scanCategory(for: item.category), fileType: current.fileType, sizeBytes: current.sizeBytes, lastModified: current.modifiedAt, riskLevel: .low)
            let classified = await classificationEngine.classify(items: [scanItem], rules: classificationRules, now: checkedAt).candidates[0]
            guard classified.safetyLevel == item.safetyLevel, classified.cleanupReason == item.cleanupReason, classified.matchedRule == item.matchedRule else {
                return CleanupPreflightItem(candidateIdentity: item.candidateIdentity, status: .rejected, checkedAt: checkedAt, currentCanonicalPath: current.canonicalPath, currentIdentity: current.identity, currentSafetyLevel: classified.safetyLevel, currentCleanupReason: classified.cleanupReason, failureReason: classified.cleanupReason == .ruleConflict ? .ruleConflict : .classificationChanged)
            }
            guard classified.safetyLevel == .safe || (classified.safetyLevel == .reviewRequired && item.explicitlySelected) else {
                return CleanupPreflightItem(candidateIdentity: item.candidateIdentity, status: .rejected, checkedAt: checkedAt, currentCanonicalPath: current.canonicalPath, currentIdentity: current.identity, currentSafetyLevel: classified.safetyLevel, currentCleanupReason: classified.cleanupReason, failureReason: failureReason(for: classified))
            }
            return CleanupPreflightItem(candidateIdentity: item.candidateIdentity, status: .passed, checkedAt: checkedAt, currentCanonicalPath: current.canonicalPath, currentIdentity: current.identity, currentSafetyLevel: classified.safetyLevel, currentCleanupReason: classified.cleanupReason, failureReason: nil)
        } catch {
            return rejectedPreflight(item: item, checkedAt: checkedAt, reason: failureReason(for: error), current: current)
        }
    }

    private func rejectedPreflight(item: CleanupPlanItem, checkedAt: Date, reason: CleanupFailureReason, current: CleanupFileSnapshot? = nil) -> CleanupPreflightItem {
        CleanupPreflightItem(candidateIdentity: item.candidateIdentity, status: .rejected, checkedAt: checkedAt, currentCanonicalPath: current?.canonicalPath, currentIdentity: current?.identity, currentSafetyLevel: nil, currentCleanupReason: nil, failureReason: reason)
    }
}

private struct CleanupFileSnapshot: Sendable, Equatable {
    let canonicalPath: URL
    let identity: SafeDeleteFileIdentity
    let fileType: ScanFileType
    let sizeBytes: UInt64
    let contentSizeBytes: UInt64
    let modifiedAt: Date?
    let isSymbolicLink: Bool
}

private struct CleanupDuplicateKey: Hashable, Sendable {
    let path: URL
    let device: UInt64
    let inode: UInt64
    let fileType: UInt16

    init(path: URL, identity: SafeDeleteFileIdentity) {
        self.path = path
        self.device = identity.device
        self.inode = identity.inode
        self.fileType = identity.fileType
    }
}

private func snapshot(at path: URL) -> CleanupFileSnapshot? {
    var info = stat()
    guard lstat(path.path, &info) == 0, let resolved = realpath(path.path, nil) else { return nil }
    defer { free(resolved) }
    let mode = info.st_mode & S_IFMT
    let fileType: ScanFileType
    switch mode {
    case S_IFREG: fileType = .regularFile
    case S_IFDIR: fileType = .directory
    case S_IFLNK: fileType = .symbolicLink
    default: fileType = .other
    }
    let contentSizeBytes = mode == S_IFDIR ? directoryContentSize(at: path) : (info.st_size > 0 ? UInt64(info.st_size) : 0)
    return CleanupFileSnapshot(
        canonicalPath: URL(fileURLWithPath: String(cString: resolved)),
        identity: SafeDeleteFileIdentity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino), fileType: UInt16(mode)),
        fileType: fileType,
        sizeBytes: info.st_size > 0 ? UInt64(info.st_size) : 0,
        contentSizeBytes: contentSizeBytes,
        modifiedAt: Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000),
        isSymbolicLink: mode == S_IFLNK
    )
}

private func directoryContentSize(at url: URL) -> UInt64 {
    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey], options: []) else { return 0 }
    var total: UInt64 = 0
    for case let entry as URL in enumerator {
        guard let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]), values.isSymbolicLink != true else {
            enumerator.skipDescendants()
            continue
        }
        if values.isDirectory != true { total += UInt64(max(values.fileSize ?? 0, 0)) }
    }
    return total
}

private func scanCategory(for category: CleanerCategory) -> ScanCategory {
    switch category {
    case .userCache: return .userCache
    case .applicationCache: return .applicationCache
    case .logs: return .logs
    case .temporaryFiles: return .temporaryFiles
    case .unknown: return .temporaryFiles
    }
}

private func failureReason(for candidate: CleanerCandidate) -> CleanupFailureReason {
    switch candidate.safetyLevel {
    case .protected: return candidate.cleanupReason == .symlinkProtected ? .symlinkRejected : .protected
    case .unknown: return candidate.cleanupReason == .ruleConflict ? .ruleConflict : .unknown
    case .safe, .reviewRequired: return .classificationChanged
    }
}

private func executionStatus(for error: Error) -> CleanupExecutionStatus {
    switch failureReason(for: error) {
    case .safeDeleteFailed: return .failed
    default: return .rejected
    }
}

private func failureReason(for error: Error) -> CleanupFailureReason {
    guard let error = error as? SafeDeleteError else { return .safeDeleteFailed }
    switch error {
    case .pathChanged: return .sourceChanged
    case .notFound: return .notFound
    case .identityUnavailable: return .identityMismatch
    case .symlinkEscape: return .symlinkRejected
    case .protectedPath, .rootDeletionForbidden, .homeDeletionForbidden, .notWhitelisted: return .protected
    case .operationFailed: return .safeDeleteFailed
    case .emptyPath, .relativePath: return .safeDeleteRejected
    }
}
