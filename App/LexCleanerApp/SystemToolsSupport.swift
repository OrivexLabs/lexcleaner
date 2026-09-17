import Combine
import Foundation
import SwiftUI
import LexCleanerCore

enum SystemToolsAppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case simplifiedChinese

    var id: String { rawValue }

    var localeIdentifier: String {
        switch self {
        case .system: return Locale.preferredLanguages.first ?? "en"
        case .english: return "en_US"
        case .simplifiedChinese: return "zh-Hans"
        }
    }

    var usesSimplifiedChinese: Bool {
        switch self {
        case .simplifiedChinese: return true
        case .english: return false
        case .system: return localeIdentifier.lowercased().hasPrefix("zh")
        }
    }
}

enum SystemToolsAppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct SystemToolsL10n {
    let locale: Locale

    init(language: SystemToolsAppLanguage) {
        locale = Locale(identifier: language.localeIdentifier)
    }

    private func text(_ key: String) -> String {
        L10n.string(key, locale: locale)
    }
    var appName: String { text("systemTools.appName") }
    var systemTools: String { text("systemTools.systemTools") }
    var overview: String { text("systemTools.overview") }
    var startup: String { text("systemTools.startup") }
    var loginItems: String { text("systemTools.loginItems") }
    var launchAgents: String { text("systemTools.launchAgents") }
    var launchDaemons: String { text("systemTools.launchDaemons") }
    var privacy: String { text("systemTools.privacy") }
    var privacySubtitle: String { text("systemTools.privacySubtitle") }
    var startupSubtitle: String { text("systemTools.startupSubtitle") }
    var loginItemsSubtitle: String { text("systemTools.loginItemsSubtitle") }
    var launchAgentsSubtitle: String { text("systemTools.launchAgentsSubtitle") }
    var launchDaemonsSubtitle: String { text("systemTools.launchDaemonsSubtitle") }
    var readOnly: String { text("systemTools.readOnly") }
    var refresh: String { text("systemTools.refresh") }
    var refreshing: String { text("systemTools.refreshing") }
    var search: String { text("systemTools.search") }
    var searchPlaceholder: String { text("systemTools.searchPlaceholder") }
    var filter: String { text("systemTools.filter") }
    var all: String { text("systemTools.all") }
    var enabled: String { text("systemTools.enabled") }
    var disabled: String { text("systemTools.disabled") }
    var attention: String { text("systemTools.attention") }
    var details: String { text("systemTools.details") }
    var status: String { text("systemTools.status") }
    var source: String { text("systemTools.source") }
    var scope: String { text("systemTools.scope") }
    var location: String { text("systemTools.location") }
    var executable: String { text("systemTools.executable") }
    var declaration: String { text("systemTools.declaration") }
    var collectedAt: String { text("systemTools.collectedAt") }
    var noSelection: String { text("systemTools.noSelection") }
    var noItems: String { text("systemTools.noItems") }
    var issues: String { text("systemTools.issues") }
    var globalLoginItemsUnavailable: String { text("systemTools.globalLoginItemsUnavailable") }
    var startupReadOnlyNotice: String { text("systemTools.startupReadOnlyNotice") }
    var privacyReadOnlyNotice: String { text("systemTools.privacyReadOnlyNotice") }
    var authorization: String { text("systemTools.authorization") }
    var capability: String { text("systemTools.capability") }
    var available: String { text("systemTools.available") }
    var unavailable: String { text("systemTools.unavailable") }
    var unsupported: String { text("systemTools.unsupported") }
    var notDetermined: String { text("systemTools.notDetermined") }
    var denied: String { text("systemTools.denied") }
    var authorized: String { text("systemTools.authorized") }
    var notRegistered: String { text("systemTools.notRegistered") }
    var requiresApproval: String { text("systemTools.requiresApproval") }
    var notFound: String { text("systemTools.notFound") }
    var unknown: String { text("systemTools.unknown") }
    var system: String { text("systemTools.system") }
    var user: String { text("systemTools.user") }
    var protected: String { text("systemTools.protected") }
    var language: String { text("systemTools.language") }
    var appearance: String { text("systemTools.appearance") }
    var systemDefault: String { text("systemTools.systemDefault") }
    var light: String { text("systemTools.light") }
    var dark: String { text("systemTools.dark") }
    var camera: String { text("systemTools.camera") }
    var microphone: String { text("systemTools.microphone") }
    var accessibility: String { text("systemTools.accessibility") }
    var screenRecording: String { text("systemTools.screenRecording") }
    var fullDiskAccess: String { text("systemTools.fullDiskAccess") }
    var launchAgent: String { text("systemTools.launchAgent") }
    var launchDaemon: String { text("systemTools.launchDaemon") }
    var loginItem: String { text("systemTools.loginItem") }
    var noPath: String { text("systemTools.noPath") }
    var noExecutable: String { text("systemTools.noExecutable") }
    var capabilityDetail: String { text("systemTools.capabilityDetail") }
    var noPermissionDetail: String { text("systemTools.noPermissionDetail") }

    func count(_ value: Int) -> String {
        L10n.format("systemTools.count", locale: locale, String(value))
    }

    func permissionName(_ permission: PrivacyPermission) -> String {
        switch permission {
        case .camera: return camera
        case .microphone: return microphone
        case .accessibility: return accessibility
        case .screenRecording: return screenRecording
        case .fullDiskAccess: return fullDiskAccess
        }
    }

    func sourceName(_ source: StartupSource) -> String {
        switch source {
        case .loginItem: return loginItem
        case .launchAgent: return launchAgent
        case .launchDaemon: return launchDaemon
        }
    }

    func scopeName(_ scope: StartupScope) -> String {
        switch scope {
        case .user: return user
        case .system: return system
        case .systemProtected: return protected
        case .unknown: return unknown
        }
    }

    func statusName(_ status: StartupStatus) -> String {
        switch status {
        case .enabled: return enabled
        case .disabled: return disabled
        case .notRegistered: return notRegistered
        case .requiresApproval: return requiresApproval
        case .notFound: return notFound
        case .unknown: return unknown
        case .unavailable: return unavailable
        case .unsupported: return unsupported
        }
    }

    func privacyStatusName(_ status: PrivacyStatus) -> String {
        switch status {
        case .available: return available
        case .unavailable: return unavailable
        case .unsupported: return unsupported
        case .notDetermined: return notDetermined
        case .denied: return denied
        case .authorized: return authorized
        }
    }

    func capabilityName(_ capability: PrivacyCapability) -> String {
        switch capability {
        case .available: return available
        case .unavailable: return unavailable
        case .unsupported: return unsupported
        }
    }
}

@MainActor
final class SystemToolsViewModel: ObservableObject {
    @Published private(set) var startupSnapshot: StartupSnapshot?
    @Published private(set) var privacySnapshot: PrivacySnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?

    private var refreshTask: Task<Void, Never>?

    init() {
        refresh()
    }

    func refresh() {
        refreshTask?.cancel()
        isRefreshing = true
        refreshTask = Task { [weak self] in
            let snapshots = await Task.detached(priority: .userInitiated) {
                (StartupReader().read(), PrivacyReader().read())
            }.value

            guard !Task.isCancelled, let self else { return }
            startupSnapshot = snapshots.0
            privacySnapshot = snapshots.1
            lastRefresh = Date()
            isRefreshing = false
        }
    }

    deinit {
        refreshTask?.cancel()
    }
}
