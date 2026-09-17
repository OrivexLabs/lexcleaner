import Foundation

public enum UpdateSourceKind: String, Codable, Equatable, Sendable {
    case appStore
    case directDownload
    case sparkle
    case unknown
}

public struct UpdateSource: Codable, Equatable, Sendable {
    public let kind: UpdateSourceKind
    public let identifier: String?
    public let url: URL?

    public init(kind: UpdateSourceKind, identifier: String? = nil, url: URL? = nil) {
        self.kind = kind
        self.identifier = identifier
        self.url = url
    }
}

public enum UpdateSignatureStatus: String, Codable, Equatable, Sendable {
    case verified
    case unverified
    case unavailable
}

public struct UpdateMetadata: Codable, Equatable, Sendable {
    public let version: String
    public let build: String?
    public let releaseDate: Date?
    public let releaseNotes: String?
    public let releaseNotesURL: URL?
    public let downloadURL: URL?
    public let minimumOSVersion: String?
    public let signatureStatus: UpdateSignatureStatus

    public init(
        version: String,
        build: String? = nil,
        releaseDate: Date? = nil,
        releaseNotes: String? = nil,
        releaseNotesURL: URL? = nil,
        downloadURL: URL? = nil,
        minimumOSVersion: String? = nil,
        signatureStatus: UpdateSignatureStatus = .unavailable
    ) {
        self.version = version
        self.build = build
        self.releaseDate = releaseDate
        self.releaseNotes = releaseNotes
        self.releaseNotesURL = releaseNotesURL
        self.downloadURL = downloadURL
        self.minimumOSVersion = minimumOSVersion
        self.signatureStatus = signatureStatus
    }
}

public enum UpdateCheckStatus: String, Codable, Equatable, Sendable {
    case available
    case upToDate
    case unavailable
    case unsupported
    case failed
}

public struct UpdateCandidate: Codable, Equatable, Sendable {
    public let metadata: UpdateMetadata
    public let source: UpdateSource
    public let manualActionURL: URL?

    public init(metadata: UpdateMetadata, source: UpdateSource, manualActionURL: URL? = nil) {
        self.metadata = metadata
        self.source = source
        self.manualActionURL = manualActionURL
    }
}

public struct UpdateCheckResult: Codable, Equatable, Sendable {
    public let checkedAt: Date
    public let status: UpdateCheckStatus
    public let currentVersion: String?
    public let candidate: UpdateCandidate?
    public let detail: String?

    public init(
        checkedAt: Date = Date(),
        status: UpdateCheckStatus,
        currentVersion: String? = nil,
        candidate: UpdateCandidate? = nil,
        detail: String? = nil
    ) {
        self.checkedAt = checkedAt
        self.status = status
        self.currentVersion = currentVersion
        self.candidate = candidate
        self.detail = detail
    }
}

public protocol UpdateProvider: Sendable {
    var source: UpdateSource { get }
    func checkForUpdates() async -> UpdateCheckResult
}

public protocol SparkleUpdateAdapter: Sendable {
    func checkForUpdates() async -> UpdateCheckResult
}

@available(*, deprecated, renamed: "SparkleUpdateAdapter")
public typealias SparkleUpdateChecking = SparkleUpdateAdapter
