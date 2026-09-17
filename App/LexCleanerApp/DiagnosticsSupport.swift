import AppKit
import Combine
import Darwin
import Foundation
import LexCleanerCore
import UniformTypeIdentifiers

@MainActor
final class DiagnosticsStore: ObservableObject {
    static let shared = DiagnosticsStore()

    private(set) var entries: [DiagnosticLogEntry] = []
    private let maximumEntries = 40

    func record(_ severity: DiagnosticSeverity, message: String) {
        let entry = DiagnosticLogEntry(
            severity: severity,
            message: DiagnosticsReportBuilder.redacted(message)
        )
        entries.append(entry)
        if entries.count > maximumEntries {
            entries.removeFirst(entries.count - maximumEntries)
        }
    }

    func report(updates: AppUpdateModel) -> String {
        DiagnosticsReportBuilder.text(from: DiagnosticsReportInput(
            appName: Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? "LexCleaner",
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            modelIdentifier: modelIdentifier(),
            architecture: architecture,
            modules: moduleStatuses(updates: updates),
            recentErrors: entries,
            crashes: crashSummary()
        ))
    }

    @discardableResult
    func copyReport(updates: AppUpdateModel) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(report(updates: updates), forType: .string)
    }

    func exportReport(updates: AppUpdateModel) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = false
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        panel.nameFieldStringValue = "LexCleaner-Diagnostics-\(version)-\(build).txt"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try report(updates: updates).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            record(.error, message: "Diagnostic report export failed")
        }
    }

    func openFeedbackPage(updates: AppUpdateModel) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        var components = URLComponents(string: "https://github.com/OrivexLabs/LexCleaner-Releases/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "title", value: "LexCleaner feedback v\(version) (build \(build))"),
            URLQueryItem(name: "body", value: "Version: \(version) (build \(build))\n\nPlease describe the issue. Paste the copied diagnostic report only if you choose to share it.")
        ]
        guard let url = components?.url else {
            record(.error, message: "Feedback URL could not be created")
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func moduleStatuses(updates: AppUpdateModel) -> [DiagnosticModule: DiagnosticModuleStatus] {
        [
            // A diagnostic report must not turn the presence of a view into a
            // claim that its live runtime path was exercised in this session.
            .cleaner: .notTested,
            .appManager: .notTested,
            .diskAnalyzer: .notTested,
            .monitoring: .notTested,
            .hardware: .notTested,
            .network: .notTested,
            .updater: updates.isUpdateConfigured ? .available : .unavailable
        ]
    }

    private func crashSummary() -> DiagnosticCrashSummary {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            let processName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "LexCleaner").lowercased()
            let reports = urls.filter { url in
                let name = url.deletingPathExtension().lastPathComponent.lowercased()
                let ext = url.pathExtension.lowercased()
                return (ext == "ips" || ext == "crash") && name.contains(processName)
            }
            let latest = reports.compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }.max()
            return DiagnosticCrashSummary(
                matchingReportCount: reports.count,
                latestReportDate: latest,
                accessStatus: .available
            )
        } catch {
            return DiagnosticCrashSummary(matchingReportCount: 0, latestReportDate: nil, accessStatus: .unavailable)
        }
    }

    private var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private func modelIdentifier() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 1 else { return "unknown" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "unknown" }
        return String(cString: bytes)
    }
}
