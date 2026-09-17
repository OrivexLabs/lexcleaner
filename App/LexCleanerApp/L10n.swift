import Foundation
import LexCleanerCore
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese
    case english

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .system:
            return Locale.current
        case .simplifiedChinese:
            return Locale(identifier: "zh-Hans")
        case .english:
            return Locale(identifier: "en")
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .system: return "settings.language.system"
        case .simplifiedChinese: return "settings.language.simplifiedChinese"
        case .english: return "settings.language.english"
        }
    }
}

@MainActor
final class LanguageSettings: ObservableObject {
    private static let defaultsKey = "lexcleaner.languageOverride"

    @Published private(set) var language: AppLanguage

    init() {
        let storedValue = UserDefaults.standard.string(forKey: Self.defaultsKey)
        language = AppLanguage(rawValue: storedValue ?? "") ?? .system
    }

    var locale: Locale { language.locale }

    func set(_ language: AppLanguage) {
        guard self.language != language else { return }
        self.language = language
        UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey)
    }
}

enum L10n {
    static func text(_ value: String, locale: Locale = .current) -> String {
        string(value, locale: locale)
    }

    static func key(_ value: String) -> LocalizedStringKey {
        LocalizedStringKey(value)
    }

    static func string(_ value: String, locale: Locale = .current) -> String {
        let resourceName = locale.identifier.lowercased().hasPrefix("zh") ? "zh-Hans" : "en"
        guard let path = Bundle.main.path(forResource: resourceName, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return Bundle.main.localizedString(forKey: value, value: value, table: "Localizable")
        }
        return bundle.localizedString(forKey: value, value: value, table: "Localizable")
    }

    static func format(_ value: String, locale: Locale = .current, _ arguments: CVarArg...) -> String {
        String(
            format: string(value, locale: locale),
            locale: locale,
            arguments: arguments
        )
    }

    static func safetyLevel(_ level: CleanupSafetyLevel, locale: Locale = .current) -> String {
        string("safety.\(level.rawValue)", locale: locale)
    }

    static func category(_ category: CleanerCategory, locale: Locale = .current) -> String {
        string("category.\(category.rawValue)", locale: locale)
    }

    static func reason(_ reason: CleanupReason, locale: Locale = .current) -> String {
        string("reason.\(reason.rawValue)", locale: locale)
    }

    static func rule(_ rule: String, locale: Locale = .current) -> String {
        switch rule {
        case "user-cache": return string("rule.userCache", locale: locale)
        case "application-cache": return string("rule.applicationCache", locale: locale)
        case "logs": return string("rule.logs", locale: locale)
        case "temporary-files": return string("rule.temporaryFiles", locale: locale)
        default: return rule
        }
    }

    static func appSource(_ source: AppSource, locale: Locale = .current) -> String {
        string("appSource.\(source.rawValue)", locale: locale)
    }

    static func signature(_ status: AppSignatureStatus, locale: Locale = .current) -> String {
        string("appSignature.\(status.rawValue)", locale: locale)
    }

    static func residualKind(_ kind: ResidualKind, locale: Locale = .current) -> String {
        string("residualKind.\(kind.rawValue)", locale: locale)
    }

    static func confidence(_ confidence: ResidualConfidence, locale: Locale = .current) -> String {
        string("confidence.\(confidence.rawValue)", locale: locale)
    }

    static func sentinel(_ status: SentinelFeasibilityStatus, locale: Locale = .current) -> String {
        string("sentinel.\(status.rawValue)", locale: locale)
    }

    static func residualReason(_ candidate: AppResidualCandidate, locale: Locale = .current) -> String {
        if candidate.isSharedData { return string("appManager.reason.shared", locale: locale) }
        if candidate.isUnknownData { return string("appManager.reason.unknown", locale: locale) }
        return string("appManager.reason.\(candidate.kind.rawValue)", locale: locale)
    }

    static func failure(_ reason: CleanupFailureReason, locale: Locale = .current) -> String {
        string("failure.\(reason.rawValue)", locale: locale)
    }
}

extension MemoryPressureLevel {
    func localizedName(locale: Locale = .current) -> String {
        L10n.string("memoryPressure.\(rawValue)", locale: locale)
    }
}

extension HardwareAvailability {
    func localizedName(locale: Locale = .current) -> String {
        L10n.string("availability.\(rawValue)", locale: locale)
    }
}

extension ThermalState {
    func localizedName(locale: Locale = .current) -> String {
        L10n.string("thermal.\(rawValue)", locale: locale)
    }
}

extension DashboardFormat {
    static func bytes(_ value: UInt64?, locale: Locale) -> String {
        guard let value else { return L10n.string("common.collecting", locale: locale) }
        return ByteUnitFormatter.string(bytes: value, locale: locale)
    }

    static func rate(_ value: Double?, locale: Locale) -> String {
        guard let value, value.isFinite, value >= 0 else { return L10n.string("common.notAvailable", locale: locale) }
        let formatted = ByteUnitFormatter.string(bytes: value, locale: locale)
        return L10n.format("common.perSecond", locale: locale, formatted)
    }

    static func percent(_ value: Double?, locale: Locale) -> String {
        guard let value, value.isFinite else { return L10n.string("common.notAvailable", locale: locale) }
        return "\(value.formatted(.number.precision(.fractionLength(1))))%"
    }

    static func date(_ value: Date?, locale: Locale) -> String {
        guard let value else { return L10n.string("common.waitingForSample", locale: locale) }
        return value.formatted(date: .omitted, time: .shortened)
    }
}
