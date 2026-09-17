import SwiftUI

enum LexSection: String, CaseIterable, Identifiable {
    case dashboard
    case cleaner
    case appManager
    case diskAnalyzer
    case systemTools
    case network
    case monitoring
    case hardware
    case settings

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .dashboard: return "navigation.dashboard"
        case .cleaner: return "navigation.cleaner"
        case .appManager: return "navigation.appManager"
        case .diskAnalyzer: return "navigation.diskAnalyzer"
        case .systemTools: return "navigation.systemTools"
        case .network: return "navigation.network"
        case .monitoring: return "navigation.monitoring"
        case .hardware: return "navigation.hardware"
        case .settings: return "navigation.settings"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: return "rectangle.3.group"
        case .cleaner: return "sparkles"
        case .appManager: return "square.stack.3d.up"
        case .diskAnalyzer: return "externaldrive"
        case .systemTools: return "gearshape.2"
        case .network: return "network"
        case .monitoring: return "waveform.path.ecg"
        case .hardware: return "memorychip"
        case .settings: return "slider.horizontal.3"
        }
    }
}

struct AppShellView: View {
    @ObservedObject var languageSettings: LanguageSettings
    @ObservedObject var updates: AppUpdateModel
    @State private var selection: LexSection? = .dashboard
    private let diskScanRoot: URL

    init(languageSettings: LanguageSettings, updates: AppUpdateModel) {
        self.languageSettings = languageSettings
        self.updates = updates
        // Validation-only launch argument. It keeps production navigation unchanged
        // while allowing a real Home scan to be profiled without accessibility
        // automation continuously rebuilding the entire SwiftUI tree.
        let arguments = CommandLine.arguments
        _selection = State(initialValue: arguments.contains("--lexcleaner-disk-analyzer") || arguments.contains("--lexcleaner-disk-analyzer-cache") ? .diskAnalyzer : arguments.contains("--lexcleaner-network") ? .network : .dashboard)
        diskScanRoot = arguments.contains("--lexcleaner-disk-analyzer-cache")
            ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches", isDirectory: true)
            : FileManager.default.homeDirectoryForCurrentUser
    }

    var body: some View {
        NavigationSplitView {
            List(LexSection.allCases, selection: $selection) { section in
                Label(section.titleKey, systemImage: section.symbol)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationTitle("LexCleaner")
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                    Label("app.readOnlyFoundation", systemImage: "lock.shield")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("app.coreConnected")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        } detail: {
            switch selection ?? .dashboard {
            case .dashboard:
                DashboardScreen()
            case .cleaner:
                CleanerScreen()
            case .appManager:
                AppManagerScreen()
            case .diskAnalyzer:
                DiskAnalyzerScreen(scanRoot: diskScanRoot)
            case .settings:
                SettingsView(languageSettings: languageSettings, updates: updates)
            case .network:
                NetworkScreen()
            case .monitoring, .hardware:
                MonitoringDashboardView()
            case .systemTools:
                SystemToolsScreen(languageSettings: languageSettings)
            case let section:
                FoundationPageView(section: section)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

// Keep page-specific observable models owned by the page that uses them. This
// avoids constructing unrelated services and their state when a Home disk
// analysis is the selected screen, while preserving SwiftUI lifetime semantics
// as the user navigates between sections.
private struct DashboardScreen: View {
    @StateObject private var model = DashboardViewModel()

    var body: some View { DashboardView(model: model) }
}

private struct CleanerScreen: View {
    @StateObject private var model = CleanerViewModel()

    var body: some View { CleanerView(model: model) }
}

private struct AppManagerScreen: View {
    @StateObject private var model = AppManagerViewModel()

    var body: some View { AppManagerView(model: model) }
}

private struct DiskAnalyzerScreen: View {
    @StateObject private var model: DiskAnalyzerViewModel

    init(scanRoot: URL) {
        _model = StateObject(wrappedValue: DiskAnalyzerViewModel(scanRoot: scanRoot))
    }

    var body: some View { DiskAnalyzerView(model: model) }
}

private struct SystemToolsScreen: View {
    @StateObject private var model = SystemToolsViewModel()
    @ObservedObject var languageSettings: LanguageSettings

    var body: some View {
        SystemToolsView(model: model, languageSettings: languageSettings)
    }
}

struct FoundationPageView: View {
    let section: LexSection

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: section.symbol)
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(LexTheme.accent)
            Text(section.titleKey)
                .font(.title2.weight(.semibold))
            Text("app.foundationReady")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            Label("app.foundationOnly", systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(LexTheme.canvas)
    }
}

private struct SettingsView: View {
    @ObservedObject var languageSettings: LanguageSettings
    @ObservedObject var updates: AppUpdateModel
    @ObservedObject private var diagnostics = DiagnosticsStore.shared
    @Environment(\.locale) private var locale

    var body: some View {
        Form {
            Section {
                Picker("settings.language", selection: Binding(
                    get: { languageSettings.language },
                    set: { languageSettings.set($0) }
                )) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.titleKey).tag(language)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("settings.general")
            }

            Section {
                Button {
                    diagnostics.exportReport(updates: updates)
                } label: {
                    Label(
                        L10n.text("diagnostics.export", locale: locale),
                        systemImage: "square.and.arrow.down"
                    )
                }

                Button {
                    _ = diagnostics.copyReport(updates: updates)
                } label: {
                    Label(
                        L10n.text("diagnostics.copy", locale: locale),
                        systemImage: "doc.on.doc"
                    )
                }

                Button {
                    diagnostics.openFeedbackPage(updates: updates)
                } label: {
                    Label(
                        L10n.text("diagnostics.feedback", locale: locale),
                        systemImage: "bubble.left.and.bubble.right"
                    )
                }

                Text(L10n.text("diagnostics.privacyNotice", locale: locale))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L10n.text("diagnostics.title", locale: locale))
            }

            Section {
                Toggle(
                    "update.automaticChecks",
                    isOn: Binding(
                        get: { updates.automaticallyChecksForUpdates },
                        set: { updates.setAutomaticallyChecksForUpdates($0) }
                    )
                )
                .disabled(!updates.isUpdateConfigured)
                Text(
                    updates.automaticallyChecksForUpdates
                        ? "update.automaticChecksEnabled"
                        : "update.automaticChecksDisabled"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Text("update.automaticChecksSafety")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } header: {
                Text("update.title")
            }

            Section {
                HStack {
                    Text(L10n.text("update.version", locale: locale))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("v\(updates.currentVersion)")
                        .monospacedDigit()
                }
                if updates.isChecking {
                    ProgressView(L10n.text("update.checking", locale: locale))
                        .controlSize(.small)
                } else {
                    Button(L10n.text("update.check", locale: locale)) {
                        updates.checkForUpdates()
                    }
                }
                if let result = updates.result {
                    switch result.status {
                    case .available:
                        if let candidate = result.candidate {
                            Text(L10n.text("update.available", locale: locale) + " v" + candidate.metadata.version)
                                .font(.callout.weight(.semibold))
                            if let notes = candidate.metadata.releaseNotes, !notes.isEmpty {
                                Text(notes)
                                    .font(.caption)
                            }
                        }
                    case .upToDate:
                        Text("update.upToDate")
                            .foregroundStyle(.secondary)
                    case .unsupported:
                        Text(L10n.text("update.unsupported", locale: locale))
                        .foregroundStyle(.secondary)
                    case .unavailable, .failed:
                        Text(result.detail ?? L10n.text("update.failed", locale: locale))
                            .foregroundStyle(.red)
                    }
                }
                if let actionError = updates.actionError {
                    Text(actionError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("update.title")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 520, alignment: .leading)
        .padding(28)
        .background(LexTheme.canvas)
        .navigationTitle(Text(L10n.string("navigation.settings", locale: locale)))
    }
}

enum LexTheme {
    static let accent = Color(red: 0.16, green: 0.42, blue: 0.76)
    static let accentSecondary = Color(red: 0.16, green: 0.60, blue: 0.58)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let positive = Color(red: 0.16, green: 0.55, blue: 0.35)
    static let caution = Color(red: 0.78, green: 0.48, blue: 0.12)
}
