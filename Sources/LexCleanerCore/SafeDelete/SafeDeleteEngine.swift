import Foundation
import Darwin
import os

public enum SafeDeleteMode: Sendable, Equatable {
    case dryRun
    case trash
}

public enum SafeDeleteRiskLevel: String, Sendable, Equatable {
    case normal
    case elevated
}

public struct SafeDeletePolicy: Sendable {
    public let whitelistedRoots: [URL]
    public let resolvedWhitelistedRoots: [URL]
    public let protectedPaths: [URL]
    public let homeDirectory: URL
    /// Exact application bundle paths explicitly selected by App Manager.
    /// This does not unprotect `/Applications` or any descendant generally;
    /// it permits only the exact, non-symlink target supplied by the caller.
    public let explicitlyAllowedApplicationBundles: [URL]

    public init(
        whitelistedRoots: [URL],
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        additionalProtectedPaths: [URL] = [],
        explicitlyAllowedApplicationBundles: [URL] = []
    ) {
        self.homeDirectory = Self.normalize(homeDirectory)
        self.whitelistedRoots = whitelistedRoots.map { $0.standardizedFileURL }
        self.resolvedWhitelistedRoots = whitelistedRoots.map(Self.normalize)
        self.protectedPaths = Self.defaultProtectedPaths(homeDirectory: homeDirectory)
            .map(Self.normalize)
            + additionalProtectedPaths.map(Self.normalize)
        self.explicitlyAllowedApplicationBundles = explicitlyAllowedApplicationBundles.map(Self.normalize)
    }

    public static func userCacheRoots(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        let home = normalize(homeDirectory)
        return [
            home.appendingPathComponent("Library/Caches", isDirectory: true),
            home.appendingPathComponent("Library/Logs", isDirectory: true),
            home.appendingPathComponent("Library/Containers", isDirectory: true)
        ]
    }

    private static func defaultProtectedPaths(homeDirectory: URL) -> [URL] {
        let home = normalize(homeDirectory)
        return [
            URL(fileURLWithPath: "/"),
            home,
            URL(fileURLWithPath: "/System"),
            URL(fileURLWithPath: "/Library"),
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Users"),
            URL(fileURLWithPath: "/bin"),
            URL(fileURLWithPath: "/sbin"),
            URL(fileURLWithPath: "/usr"),
            URL(fileURLWithPath: "/var"),
            URL(fileURLWithPath: "/etc"),
            URL(fileURLWithPath: "/dev"),
            URL(fileURLWithPath: "/Volumes"),
            URL(fileURLWithPath: "/private/etc"),
            URL(fileURLWithPath: "/private/var/db"),
            URL(fileURLWithPath: "/private/var/root")
        ]
    }

    private static func normalize(_ url: URL) -> URL {
        let standardized = url.standardizedFileURL
        guard let resolved = realpath(standardized.path, nil) else { return standardized }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved))
    }
}

public struct SafeDeleteLogEntry: Sendable, Equatable {
    public enum Outcome: String, Sendable {
        case dryRun
        case trashed
        case rejected
        case failed
    }

    public let operationID: UUID
    public let timestamp: Date
    public let path: String
    public let mode: SafeDeleteMode
    public let outcome: Outcome
    public let detail: String

    public init(
        operationID: UUID,
        timestamp: Date = Date(),
        path: String,
        mode: SafeDeleteMode,
        outcome: Outcome,
        detail: String
    ) {
        self.operationID = operationID
        self.timestamp = timestamp
        self.path = path
        self.mode = mode
        self.outcome = outcome
        self.detail = detail
    }
}

public protocol SafeDeleteOperationLogging: Sendable {
    func record(_ entry: SafeDeleteLogEntry) async
}

public actor InMemorySafeDeleteLogger: SafeDeleteOperationLogging {
    private var entries: [SafeDeleteLogEntry] = []

    public init() {}

    public func record(_ entry: SafeDeleteLogEntry) {
        entries.append(entry)
    }

    public func allEntries() -> [SafeDeleteLogEntry] {
        entries
    }
}

public struct OSLogSafeDeleteLogger: SafeDeleteOperationLogging {
    private let logger = Logger(subsystem: "com.lexcleaner.app", category: "SafeDelete")

    public init() {}

    public func record(_ entry: SafeDeleteLogEntry) {
        logger.log(level: entry.outcome == .failed || entry.outcome == .rejected ? .error : .info,
                   "operation=\(entry.operationID.uuidString, privacy: .public) outcome=\(entry.outcome.rawValue, privacy: .public) mode=\(String(describing: entry.mode), privacy: .public) path=\(entry.path, privacy: .private(mask: .hash)) detail=\(entry.detail, privacy: .public)")
    }
}

public struct SafeDeleteRiskAssessment: Sendable, Equatable {
    public let targetIdentity: SafeDeleteFileIdentity
    public let resolvedIdentity: SafeDeleteFileIdentity
    public let normalizedPath: URL
    public let resolvedPath: URL
    public let symlinkComponents: [SafeDeleteSymlinkIdentity]
    public let isDirectory: Bool
    public let containsSymlink: Bool
    public let riskLevel: SafeDeleteRiskLevel

    public init(
        targetIdentity: SafeDeleteFileIdentity,
        resolvedIdentity: SafeDeleteFileIdentity,
        normalizedPath: URL,
        resolvedPath: URL,
        symlinkComponents: [SafeDeleteSymlinkIdentity],
        isDirectory: Bool,
        containsSymlink: Bool,
        riskLevel: SafeDeleteRiskLevel
    ) {
        self.targetIdentity = targetIdentity
        self.resolvedIdentity = resolvedIdentity
        self.normalizedPath = normalizedPath
        self.resolvedPath = resolvedPath
        self.symlinkComponents = symlinkComponents
        self.isDirectory = isDirectory
        self.containsSymlink = containsSymlink
        self.riskLevel = riskLevel
    }
}

public struct SafeDeleteFileIdentity: Sendable, Equatable {
    public let device: UInt64
    public let inode: UInt64
    public let fileType: UInt16

    public init(device: UInt64, inode: UInt64, fileType: UInt16) {
        self.device = device
        self.inode = inode
        self.fileType = fileType
    }
}

public struct SafeDeleteSymlinkIdentity: Sendable, Equatable {
    public let path: URL
    public let identity: SafeDeleteFileIdentity
    public let resolvedPath: URL

    public init(path: URL, identity: SafeDeleteFileIdentity, resolvedPath: URL) {
        self.path = path
        self.identity = identity
        self.resolvedPath = resolvedPath
    }
}

public struct SafeDeleteResult: Sendable, Equatable {
    public enum Action: String, Sendable {
        case wouldMoveToTrash
        case movedToTrash
    }

    public let operationID: UUID
    public let action: Action
    public let assessment: SafeDeleteRiskAssessment

    public init(operationID: UUID, action: Action, assessment: SafeDeleteRiskAssessment) {
        self.operationID = operationID
        self.action = action
        self.assessment = assessment
    }
}

public enum SafeDeleteError: Error, LocalizedError, Sendable, Equatable {
    case emptyPath
    case relativePath
    case notFound
    case rootDeletionForbidden
    case homeDeletionForbidden
    case protectedPath(URL)
    case notWhitelisted(URL)
    case symlinkEscape(URL, URL)
    case pathChanged
    case identityUnavailable
    case operationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyPath:
            return "The deletion path is empty."
        case .relativePath:
            return "Only absolute paths are accepted."
        case .notFound:
            return "The deletion path does not exist."
        case .rootDeletionForbidden:
            return "Deleting the filesystem root is forbidden."
        case .homeDeletionForbidden:
            return "Deleting the current user's home directory is forbidden."
        case let .protectedPath(path):
            return "The path is protected: \(path.path)"
        case let .notWhitelisted(path):
            return "The path is outside the configured whitelist: \(path.path)"
        case let .symlinkEscape(link, destination):
            return "The symlink escapes the allowed boundary: \(link.path) -> \(destination.path)"
        case .pathChanged:
            return "The file path or file identity changed during the safety checks; operation refused."
        case .identityUnavailable:
            return "The file identity could not be verified; operation refused."
        case let .operationFailed(message):
            return "The item could not be moved to Trash: \(message)"
        }
    }
}

public actor SafeDeleteEngine {
    private let fileManager: FileManager
    private let policy: SafeDeletePolicy
    private let logger: any SafeDeleteOperationLogging
    private let preExecutionObserver: (@Sendable (URL) async -> Void)?

    public init(
        policy: SafeDeletePolicy,
        fileManager: FileManager = .default,
        logger: any SafeDeleteOperationLogging = OSLogSafeDeleteLogger()
    ) {
        self.init(policy: policy, fileManager: fileManager, logger: logger, preExecutionObserver: nil)
    }

    @_spi(Testing)
    public init(
        policy: SafeDeletePolicy,
        fileManager: FileManager = .default,
        logger: any SafeDeleteOperationLogging = OSLogSafeDeleteLogger(),
        preExecutionObserver: (@Sendable (URL) async -> Void)?
    ) {
        self.policy = policy
        self.fileManager = fileManager
        self.logger = logger
        self.preExecutionObserver = preExecutionObserver
    }

    public func assess(path: String) async throws -> SafeDeleteRiskAssessment {
        let operationID = UUID()
        do {
            let assessment = try assessPath(path)
            return assessment
        } catch {
            await logError(operationID: operationID, path: path, mode: .dryRun, error: error)
            throw error
        }
    }

    @discardableResult
    public func delete(path: String, mode: SafeDeleteMode = .dryRun) async throws -> SafeDeleteResult {
        let operationID = UUID()
        do {
            let assessment = try assessPath(path)

            switch mode {
            case .dryRun:
                let result = SafeDeleteResult(operationID: operationID, action: .wouldMoveToTrash, assessment: assessment)
                await logger.record(SafeDeleteLogEntry(
                    operationID: operationID,
                    path: assessment.normalizedPath.path,
                    mode: mode,
                    outcome: .dryRun,
                    detail: "risk=\(assessment.riskLevel.rawValue)"
                ))
                return result

            case .trash:
                await preExecutionObserver?(assessment.normalizedPath)
                let executionAssessment = try assessPath(path)
                guard executionAssessment == assessment else {
                    throw SafeDeleteError.pathChanged
                }

                let finalAssessment = try assessPath(path)
                guard finalAssessment == executionAssessment else {
                    throw SafeDeleteError.pathChanged
                }

                do {
                    var resultingURL: NSURL?
                    try fileManager.trashItem(at: finalAssessment.normalizedPath, resultingItemURL: &resultingURL)
                    let result = SafeDeleteResult(operationID: operationID, action: .movedToTrash, assessment: finalAssessment)
                    await logger.record(SafeDeleteLogEntry(
                        operationID: operationID,
                        path: finalAssessment.normalizedPath.path,
                        mode: mode,
                        outcome: .trashed,
                        detail: resultingURL?.path ?? "moved"
                    ))
                    return result
                } catch {
                    let wrapped = SafeDeleteError.operationFailed(error.localizedDescription)
                    throw wrapped
                }
            }
        } catch {
            await logError(operationID: operationID, path: path, mode: mode, error: error)
            throw error
        }
    }

    private func assessPath(_ rawPath: String) throws -> SafeDeleteRiskAssessment {
        let trimmedPath = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { throw SafeDeleteError.emptyPath }
        guard trimmedPath.hasPrefix("/") else { throw SafeDeleteError.relativePath }

        let normalizedPath = URL(fileURLWithPath: trimmedPath, isDirectory: false).standardizedFileURL
        guard fileManager.fileExists(atPath: normalizedPath.path) else {
            throw SafeDeleteError.notFound
        }

        let resolvedPath = try resolvePath(normalizedPath)
        let homePath = policy.homeDirectory.path
        if normalizedPath.path == "/" || resolvedPath.path == "/" {
            throw SafeDeleteError.rootDeletionForbidden
        }
        if normalizedPath.path == homePath || resolvedPath.path == homePath {
            throw SafeDeleteError.homeDeletionForbidden
        }

        guard isWithinAnyRoot(normalizedPath, roots: policy.whitelistedRoots)
                || isWithinAnyRoot(resolvedPath, roots: policy.resolvedWhitelistedRoots) else {
            throw SafeDeleteError.notWhitelisted(normalizedPath)
        }

        let symlinks = try symlinkComponents(in: normalizedPath)
        for symlink in symlinks {
            let link = symlink.path
            let destination = symlink.resolvedPath
            guard isWithinAnyRoot(destination, roots: policy.resolvedWhitelistedRoots) else {
                throw SafeDeleteError.symlinkEscape(link, destination)
            }
            if isProtected(destination) {
                throw SafeDeleteError.protectedPath(destination)
            }
        }

        guard isWithinAnyRoot(resolvedPath, roots: policy.resolvedWhitelistedRoots) else {
            throw SafeDeleteError.notWhitelisted(normalizedPath)
        }

        let explicitlyAllowedAppBundle = isExplicitlyAllowedApplicationBundle(normalizedPath, resolvedPath: resolvedPath)
        if let protectedPath = policy.protectedPaths.first(where: {
            isProtectedMatch(normalizedPath, against: $0) || isProtectedMatch(resolvedPath, against: $0)
        }), !explicitlyAllowedAppBundle {
            if protectedPath.path == "/" {
                throw SafeDeleteError.rootDeletionForbidden
            }
            if protectedPath.path == homePath {
                throw SafeDeleteError.homeDeletionForbidden
            }
            throw SafeDeleteError.protectedPath(protectedPath)
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: normalizedPath.path, isDirectory: &isDirectory) else {
            throw SafeDeleteError.notFound
        }
        let targetIdentity = try fileIdentity(at: normalizedPath)
        let resolvedIdentity = try fileIdentity(at: resolvedPath)
        return SafeDeleteRiskAssessment(
            targetIdentity: targetIdentity,
            resolvedIdentity: resolvedIdentity,
            normalizedPath: normalizedPath,
            resolvedPath: resolvedPath,
            symlinkComponents: symlinks,
            isDirectory: isDirectory.boolValue,
            containsSymlink: !symlinks.isEmpty,
            riskLevel: symlinks.isEmpty ? .normal : .elevated
        )
    }

    private func symlinkComponents(in path: URL) throws -> [SafeDeleteSymlinkIdentity] {
        let components = path.path.split(separator: "/").map(String.init)
        var cursor = URL(fileURLWithPath: "/", isDirectory: true)
        var result: [SafeDeleteSymlinkIdentity] = []

        for component in components {
            cursor.appendPathComponent(component, isDirectory: false)
            guard isSymbolicLink(cursor) else { continue }
            guard isWithinAnyRoot(cursor, roots: policy.whitelistedRoots) else { continue }

            result.append(SafeDeleteSymlinkIdentity(
                path: cursor,
                identity: try fileIdentity(at: cursor),
                resolvedPath: try resolvePath(path)
            ))
        }
        return result
    }

    private func resolvePath(_ path: URL) throws -> URL {
        var current = path.standardizedFileURL
        for _ in 0..<64 {
            let components = current.path.split(separator: "/").map(String.init)
            var cursor = URL(fileURLWithPath: "/", isDirectory: true)
            var firstLink: URL?
            for component in components {
                cursor.appendPathComponent(component, isDirectory: false)
                if isSymbolicLink(cursor) {
                    firstLink = cursor
                    break
                }
            }
            guard let link = firstLink else { return current }

            let destinationText = try fileManager.destinationOfSymbolicLink(atPath: link.path)
            let destination: URL
            if destinationText.hasPrefix("/") {
                destination = URL(fileURLWithPath: destinationText)
            } else {
                destination = link.deletingLastPathComponent().appendingPathComponent(destinationText)
            }
            let suffix = Array(current.pathComponents.dropFirst(link.pathComponents.count))
            var replacement = URL(fileURLWithPath: destination.path)
            for component in suffix {
                replacement.appendPathComponent(component, isDirectory: false)
            }
            current = URL(fileURLWithPath: replacement.path)
        }
        throw SafeDeleteError.operationFailed("symbolic link resolution exceeded the safety limit")
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFLNK
    }

    private func fileIdentity(at url: URL) throws -> SafeDeleteFileIdentity {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            throw SafeDeleteError.identityUnavailable
        }
        return SafeDeleteFileIdentity(
            device: UInt64(info.st_dev),
            inode: UInt64(info.st_ino),
            fileType: UInt16(info.st_mode & S_IFMT)
        )
    }

    private func isProtected(_ path: URL) -> Bool {
        policy.protectedPaths.contains { isProtectedMatch(path, against: $0) }
    }

    private func isExplicitlyAllowedApplicationBundle(_ normalizedPath: URL, resolvedPath: URL) -> Bool {
        guard normalizedPath.pathExtension.lowercased() == "app",
              normalizedPath == resolvedPath,
              !isSymbolicLink(normalizedPath) else { return false }
        return policy.explicitlyAllowedApplicationBundles.contains { $0 == normalizedPath }
    }

    private func isProtectedMatch(_ path: URL, against protectedPath: URL) -> Bool {
        if protectedPath.path == "/" || protectedPath.path == policy.homeDirectory.path {
            return path.path == protectedPath.path
        }
        if protectedPath.path == "/private/var" {
            return path.path == protectedPath.path
        }
        return isSameOrDescendant(path, of: protectedPath)
    }

    private func isWithinAnyRoot(_ path: URL, roots: [URL]) -> Bool {
        roots.contains { isSameOrDescendant(path, of: $0) }
    }

    private func isSameOrDescendant(_ path: URL, of root: URL) -> Bool {
        let pathString = path.path
        let rootString = root.path == "/" ? "/" : root.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if rootString == "/" { return pathString.hasPrefix("/") }
        return pathString == "/\(rootString)" || pathString.hasPrefix("/\(rootString)/")
    }

    private func logError(operationID: UUID, path: String, mode: SafeDeleteMode, error: Error) async {
        let outcome: SafeDeleteLogEntry.Outcome
        if let safeError = error as? SafeDeleteError,
           case .operationFailed = safeError {
            outcome = .failed
        } else {
            outcome = .rejected
        }
        await logger.record(SafeDeleteLogEntry(
            operationID: operationID,
            path: path,
            mode: mode,
            outcome: outcome,
            detail: error.localizedDescription
        ))
    }
}
