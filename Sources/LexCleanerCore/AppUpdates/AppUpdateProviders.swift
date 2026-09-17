import Foundation

/// Core-facing adapter boundary. The App target may implement SparkleUpdateAdapter
/// with Sparkle, while Core remains free of Sparkle imports and installation APIs.
public struct SparkleUpdateProvider: UpdateProvider {
    public let source: UpdateSource
    private let checker: any SparkleUpdateAdapter

    public init(checker: any SparkleUpdateAdapter, identifier: String? = nil, feedURL: URL? = nil) {
        self.checker = checker
        self.source = UpdateSource(kind: .sparkle, identifier: identifier, url: feedURL)
    }

    public func checkForUpdates() async -> UpdateCheckResult {
        await checker.checkForUpdates()
    }
}

/// App Store updates are managed by the system. This provider deliberately exposes
/// the source but never claims an update is available without a public query API.
public struct AppStoreUpdateProvider: UpdateProvider {
    public let source: UpdateSource
    private let currentVersion: String?

    public init(appStoreIdentifier: String? = nil, currentVersion: String? = nil) {
        self.source = UpdateSource(kind: .appStore, identifier: appStoreIdentifier)
        self.currentVersion = currentVersion
    }

    public func checkForUpdates() async -> UpdateCheckResult {
        UpdateCheckResult(
            status: .unsupported,
            currentVersion: currentVersion,
            detail: "The App Store manages updates outside this Core-only provider; no update result is inferred."
        )
    }
}

public struct UnavailableUpdateProvider: UpdateProvider {
    public let source: UpdateSource
    private let currentVersion: String?
    private let detail: String

    public init(source: UpdateSource, currentVersion: String? = nil, detail: String) {
        self.source = source
        self.currentVersion = currentVersion
        self.detail = detail
    }

    public func checkForUpdates() async -> UpdateCheckResult {
        UpdateCheckResult(status: .unavailable, currentVersion: currentVersion, detail: detail)
    }
}
