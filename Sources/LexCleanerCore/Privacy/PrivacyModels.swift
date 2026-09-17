import Foundation

public enum PrivacyPermission: String, Codable, CaseIterable, Equatable, Sendable {
    case camera
    case microphone
    case accessibility
    case screenRecording
    case fullDiskAccess
}

public enum PrivacyStatus: String, Codable, CaseIterable, Equatable, Sendable {
    case available
    case unavailable
    case unsupported
    case notDetermined
    case denied
    case authorized
}

public enum PrivacyCapability: String, Codable, CaseIterable, Equatable, Sendable {
    case available
    case unavailable
    case unsupported
}

public struct PrivacyPermissionStatus: Codable, Equatable, Sendable {
    public let permission: PrivacyPermission
    public let status: PrivacyStatus
    public let capability: PrivacyCapability
    public let source: String
    public let detail: String?

    public init(
        permission: PrivacyPermission,
        status: PrivacyStatus,
        source: String,
        detail: String? = nil,
        capability: PrivacyCapability = .unsupported
    ) {
        self.permission = permission
        self.status = status
        self.capability = capability
        self.source = source
        self.detail = detail
    }
}

public struct PrivacySnapshot: Codable, Equatable, Sendable {
    public let collectedAt: Date
    public let permissions: [PrivacyPermissionStatus]

    public init(collectedAt: Date = Date(), permissions: [PrivacyPermissionStatus]) {
        self.collectedAt = collectedAt
        self.permissions = permissions
    }

    public func status(for permission: PrivacyPermission) -> PrivacyPermissionStatus? {
        permissions.first { $0.permission == permission }
    }
}
