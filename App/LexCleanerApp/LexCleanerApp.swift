import SwiftUI

@main
struct LexCleanerApp: App {
    @StateObject private var languageSettings = LanguageSettings()
    @StateObject private var menuBar = MenuBarModel()
    @StateObject private var updates: AppUpdateModel

    init() {
        let runtime = AppUpdateRuntime()
        _updates = StateObject(wrappedValue: AppUpdateModel(provider: runtime.provider, settings: runtime.settings))
    }

    var body: some Scene {
        WindowGroup {
            AppShellView(languageSettings: languageSettings, updates: updates)
                .environment(\.locale, languageSettings.locale)
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1_180, height: 780)

        MenuBarExtra {
            MenuBarQuickPanel(menuBar: menuBar, updates: updates)
                .environment(\.locale, languageSettings.locale)
        } label: {
            MenuBarStatusLabel(snapshot: menuBar.snapshot, visibleMetrics: menuBar.visibleMetrics)
                .environment(\.locale, languageSettings.locale)
        }
        .menuBarExtraStyle(.window)
    }
}
