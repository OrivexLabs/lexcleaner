import Foundation

public enum DiagnosticSeverity: String, CaseIterable, Codable, Sendable {
    case error
    case warning
    case info
}

public struct DiagnosticLogEntry: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let severity: DiagnosticSeverity
    public let message: String

    public init(timestamp: Date = Date(), severity: DiagnosticSeverity, message: String) {
        self.timestamp = timestamp
        self.severity = severity
        self.message = message
    }
}

public enum DiagnosticModule: String, CaseIterable, Codable, Sendable {
    case cleaner
    case appManager
    case diskAnalyzer
    case monitoring
    case hardware
    case network
    case updater
}

public enum DiagnosticModuleStatus: String, Codable, Sendable {
    case available
    case unavailable
    case unsupported
    case notTested
}

public struct DiagnosticCrashSummary: Codable, Equatable, Sendable {
    public let matchingReportCount: Int
    public let latestReportDate: Date?
    public let accessStatus: DiagnosticModuleStatus

    public init(
        matchingReportCount: Int,
        latestReportDate: Date?,
        accessStatus: DiagnosticModuleStatus
    ) {
        self.matchingReportCount = matchingReportCount
        self.latestReportDate = latestReportDate
        self.accessStatus = accessStatus
    }
}

public struct DiagnosticsReportInput: Sendable {
    public let appName: String
    public let version: String
    public let build: String
    public let macOSVersion: String
    public let modelIdentifier: String
    public let architecture: String
    public let modules: [DiagnosticModule: DiagnosticModuleStatus]
    public let recentErrors: [DiagnosticLogEntry]
    public let crashes: DiagnosticCrashSummary
    public let generatedAt: Date

    public init(
        appName: String,
        version: String,
        build: String,
        macOSVersion: String,
        modelIdentifier: String,
        architecture: String,
        modules: [DiagnosticModule: DiagnosticModuleStatus],
        recentErrors: [DiagnosticLogEntry],
        crashes: DiagnosticCrashSummary,
        generatedAt: Date = Date()
    ) {
        self.appName = appName
        self.version = version
        self.build = build
        self.macOSVersion = macOSVersion
        self.modelIdentifier = modelIdentifier
        self.architecture = architecture
        self.modules = modules
        self.recentErrors = recentErrors
        self.crashes = crashes
        self.generatedAt = generatedAt
    }
}

public enum DiagnosticsReportBuilder {
    public static func text(from input: DiagnosticsReportInput) -> String {
        var lines: [String] = []
        lines.append("LexCleaner Diagnostic Report")
        lines.append("Generated: \(formatDate(input.generatedAt))")
        lines.append("")
        lines.append("Application")
        lines.append("- Name: \(safe(input.appName))")
        lines.append("- Version: \(safe(input.version)) (build \(safe(input.build)))")
        lines.append("")
        lines.append("System")
        lines.append("- macOS: \(safe(input.macOSVersion))")
        lines.append("- Model: \(safe(input.modelIdentifier))")
        lines.append("- Architecture: \(safe(input.architecture))")
        lines.append("")
        lines.append("Module status")
        for module in DiagnosticModule.allCases {
            let status = input.modules[module] ?? .notTested
            lines.append("- \(module.displayName): \(status.rawValue)")
        }
        lines.append("")
        lines.append("Recent diagnostic errors")
        if input.recentErrors.isEmpty {
            lines.append("- None recorded")
        } else {
            for entry in input.recentErrors.suffix(20) {
                lines.append("- [\(formatDate(entry.timestamp))] \(entry.severity.rawValue): \(safe(entry.message))")
            }
        }
        lines.append("")
        lines.append("Crash information")
        switch input.crashes.accessStatus {
        case .available:
            lines.append("- Matching recent crash reports: \(max(0, input.crashes.matchingReportCount))")
            if let latest = input.crashes.latestReportDate {
                lines.append("- Latest report date: \(formatDate(latest))")
            }
        case .unavailable:
            lines.append("- Crash report directory unavailable")
        case .unsupported:
            lines.append("- Crash report inspection unsupported")
        case .notTested:
            lines.append("- Crash report inspection not tested")
        }
        lines.append("")
        lines.append("Privacy")
        lines.append("- This report contains no username, private path, file name, file content, token, password, or credential.")
        lines.append("- Nothing is uploaded automatically. Export or copy is user initiated.")
        return lines.joined(separator: "\n") + "\n"
    }

    public static func redacted(_ value: String) -> String {
        var result = value
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if !home.isEmpty {
            result = result.replacingOccurrences(of: home, with: "<private-home>")
        }
        let username = NSUserName()
        if !username.isEmpty {
            result = result.replacingOccurrences(of: username, with: "<private-user>")
        }
        let fullName = NSFullUserName()
        if !fullName.isEmpty {
            result = result.replacingOccurrences(of: fullName, with: "<private-user>")
        }
        result = replacing(pattern: #"(?i)(token|password|secret|api[-_ ]?key|authorization)\s*[:=]\s*\S+"#, in: result, with: "$1=<redacted>")
        result = replacing(pattern: #"(?:file://)?/(?:Users|private|var|tmp|Volumes)/[^\s,;]+"#, in: result, with: "<private-path>")
        result = replacing(pattern: #"\b[^\s/]+\.(?:log|ips|crash|sqlite|db|plist|json|swift|txt|tmp|cache)\b"#, in: result, with: "<private-file>")
        return result
    }

    private static func safe(_ value: String) -> String {
        redacted(value).replacingOccurrences(of: "\n", with: " ")
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func replacing(pattern: String, in value: String, with replacement: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return value }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.stringByReplacingMatches(in: value, range: range, withTemplate: replacement)
    }
}

private extension DiagnosticModule {
    var displayName: String {
        switch self {
        case .cleaner: return "Cleaner"
        case .appManager: return "App Manager"
        case .diskAnalyzer: return "Disk Analyzer"
        case .monitoring: return "Monitoring"
        case .hardware: return "Hardware"
        case .network: return "Network"
        case .updater: return "Updater"
        }
    }
}
