import Foundation

public enum StartupSource: String, Codable, Equatable, Sendable {
    case loginItem
    case launchAgent
    case launchDaemon
}

public enum StartupScope: String, Codable, Equatable, Sendable {
    case user
    case system
    case systemProtected
    case unknown
}

public enum StartupStatus: String, Codable, Equatable, Sendable {
    case enabled
    case disabled
    case notRegistered
    case requiresApproval
    case notFound
    case unknown
    case unavailable
    case unsupported
}

public struct StartupItem: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let source: StartupSource
    public let scope: StartupScope
    public let label: String
    public let location: URL?
    public let executablePath: String?
    public let status: StartupStatus
    public let detail: String?

    public init(
        id: String,
        source: StartupSource,
        scope: StartupScope,
        label: String,
        location: URL?,
        executablePath: String?,
        status: StartupStatus,
        detail: String? = nil
    ) {
        self.id = id
        self.source = source
        self.scope = scope
        self.label = label
        self.location = location
        self.executablePath = executablePath
        self.status = status
        self.detail = detail
    }
}

public enum StartupIssueKind: String, Codable, Equatable, Sendable {
    case loginItemsEnumerationUnsupported
    case directoryUnavailable
    case unreadablePlist
    case malformedPlist
    case missingLabel
}

public struct StartupIssue: Codable, Equatable, Sendable {
    public let kind: StartupIssueKind
    public let location: URL?
    public let detail: String

    public init(kind: StartupIssueKind, location: URL? = nil, detail: String) {
        self.kind = kind
        self.location = location
        self.detail = detail
    }
}

public struct StartupSnapshot: Codable, Equatable, Sendable {
    public let collectedAt: Date
    public let items: [StartupItem]
    public let issues: [StartupIssue]

    public init(collectedAt: Date = Date(), items: [StartupItem], issues: [StartupIssue]) {
        self.collectedAt = collectedAt
        self.items = items
        self.issues = issues
    }
}

public struct StartupDirectory: Equatable, Sendable {
    public let source: StartupSource
    public let scope: StartupScope
    public let url: URL

    public init(source: StartupSource, scope: StartupScope, url: URL) {
        self.source = source
        self.scope = scope
        self.url = url
    }

    public static func standardDirectories(fileManager: FileManager = .default) -> [StartupDirectory] {
        let home = fileManager.homeDirectoryForCurrentUser
        return [
            StartupDirectory(source: .launchAgent, scope: .user, url: home.appendingPathComponent("Library/LaunchAgents")),
            StartupDirectory(source: .launchAgent, scope: .system, url: URL(fileURLWithPath: "/Library/LaunchAgents", isDirectory: true)),
            StartupDirectory(source: .launchAgent, scope: .systemProtected, url: URL(fileURLWithPath: "/System/Library/LaunchAgents", isDirectory: true)),
            StartupDirectory(source: .launchDaemon, scope: .system, url: URL(fileURLWithPath: "/Library/LaunchDaemons", isDirectory: true)),
            StartupDirectory(source: .launchDaemon, scope: .systemProtected, url: URL(fileURLWithPath: "/System/Library/LaunchDaemons", isDirectory: true))
        ]
    }
}

public struct KnownLoginItem: Equatable, Sendable {
    public let identifier: String
    public let label: String?

    public init(identifier: String, label: String? = nil) {
        self.identifier = identifier
        self.label = label
    }
}
