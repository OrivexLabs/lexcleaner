import Foundation
import LexCleanerCore
import SwiftUI

@MainActor
protocol AppUpdateSettings: AnyObject {
    var isConfigured: Bool { get }
    var automaticallyChecksForUpdates: Bool { get }
    func setAutomaticallyChecksForUpdates(_ enabled: Bool)
}

@MainActor
final class AppUpdateModel: ObservableObject {
    let currentVersion: String

    @Published private(set) var result: UpdateCheckResult?
    @Published private(set) var isChecking = false
    @Published private(set) var actionError: String?
    @Published private(set) var automaticallyChecksForUpdates: Bool
    let isUpdateConfigured: Bool

    private let provider: any UpdateProvider
    private let settings: (any AppUpdateSettings)?

    init(
        provider: any UpdateProvider,
        settings: (any AppUpdateSettings)? = nil,
        currentVersion: String = AppUpdateModel.bundleVersion()
    ) {
        self.provider = provider
        self.settings = settings
        self.currentVersion = currentVersion
        self.automaticallyChecksForUpdates = settings?.automaticallyChecksForUpdates ?? false
        self.isUpdateConfigured = settings?.isConfigured ?? false
    }

    func checkForUpdates() {
        guard !isChecking else { return }
        isChecking = true
        actionError = nil
        let provider = provider
        Task { @MainActor [weak self] in
            let result = await provider.checkForUpdates()
            guard let self else { return }
            self.result = result
            self.isChecking = false
        }
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard let settings, settings.isConfigured else {
            actionError = L10n.text("update.sparkleNotConfigured")
            automaticallyChecksForUpdates = false
            return
        }
        settings.setAutomaticallyChecksForUpdates(enabled)
        automaticallyChecksForUpdates = settings.automaticallyChecksForUpdates
    }

    nonisolated static func bundleVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}

@MainActor
final class AppUpdateRuntime {
    let provider: any UpdateProvider
    let settings: (any AppUpdateSettings)?

    init() {
        let version = AppUpdateModel.bundleVersion()
        let feedURL = (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String).flatMap(URL.init(string:))
        let publicEDKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        let configuration = SparkleUpdateConfiguration(feedURL: feedURL, publicEDKey: publicEDKey)
        let source = UpdateSource(kind: .sparkle, identifier: Bundle.main.bundleIdentifier, url: feedURL)

        guard configuration.isUsable else {
            provider = UnavailableUpdateProvider(
                source: source,
                currentVersion: version,
                detail: L10n.text("update.sparkleNotConfigured") + " " + configuration.unavailableDetail
            )
            settings = nil
            return
        }

        let adapter = SparkleUpdaterService(currentVersion: version, configuration: configuration)
        provider = SparkleUpdateProvider(
            checker: adapter,
            identifier: source.identifier,
            feedURL: source.url
        )
        settings = adapter
    }
}
