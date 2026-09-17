import Foundation

/// Build-time configuration required before the App target may start Sparkle.
///
/// The feed and Ed25519 public key are deliberately supplied by the distribution
/// build. An unconfigured local/debug build must stay in an explicit unavailable
/// state instead of starting a partially configured updater.
public struct SparkleUpdateConfiguration: Equatable, Sendable {
    public let feedURL: URL?
    public let publicEDKey: String?

    public init(feedURL: URL?, publicEDKey: String?) {
        self.feedURL = feedURL
        self.publicEDKey = publicEDKey
    }

    public var isUsable: Bool {
        guard let feedURL,
              feedURL.scheme?.lowercased() == "https",
              let host = feedURL.host,
              !host.isEmpty,
              let publicEDKey,
              let keyData = Data(base64Encoded: publicEDKey),
              keyData.count == 32 else {
            return false
        }
        return true
    }

    public var unavailableDetail: String {
        if feedURL == nil {
            return "Sparkle feed URL is not configured for this build."
        }
        if feedURL?.scheme?.lowercased() != "https" || feedURL?.host?.isEmpty != false {
            return "Sparkle feed URL must be an HTTPS URL with a host."
        }
        if publicEDKey == nil || Data(base64Encoded: publicEDKey ?? "")?.count != 32 {
            return "Sparkle Ed25519 public key is not configured for this build."
        }
        return "Sparkle update configuration is invalid."
    }
}
