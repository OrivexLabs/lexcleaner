import Foundation
import Testing
@testable import LexCleanerCore

@Suite("ByteUnitFormatter")
struct ByteFormatterTests {
    @Test("uses decimal storage units for user-facing capacity")
    func decimalCapacity() {
        let bytes: UInt64 = 494_384_795_648
        #expect(ByteUnitFormatter.string(bytes: bytes, locale: Locale(identifier: "en_US_POSIX")) == "494.38 GB")
        #expect(abs(ByteUnitFormatter.decimalGigabytes(from: bytes) - 494.384795648) < 0.000000001)
    }

    @Test("keeps binary conversion explicitly labelled as GiB")
    func binaryCapacityIsExplicit() {
        let bytes: UInt64 = 494_384_795_648
        #expect(abs(ByteUnitFormatter.gibibytes(from: bytes) - 460.433) < 0.002)
        #expect(ByteUnitFormatter.string(bytes: bytes, system: .binary, locale: Locale(identifier: "en_US_POSIX")) == "460.43 GiB")
    }

    @Test("formats transfer rates with the same decimal byte policy")
    func decimalRate() {
        #expect(ByteUnitFormatter.string(bytes: UInt64(1_000_000_000), locale: Locale(identifier: "en_US_POSIX")) == "1 GB")
        #expect(ByteUnitFormatter.string(bytes: UInt64(1_048_576), locale: Locale(identifier: "en_US_POSIX")) == "1.05 MB")
    }

    @Test("diagnostic reports redact private paths, file names, and credentials")
    func diagnosticReportRedaction() {
        let input = DiagnosticsReportInput(
            appName: "LexCleaner",
            version: "0.1.0",
            build: "2",
            macOSVersion: "macOS 26.5.1",
            modelIdentifier: "Mac16,7",
            architecture: "arm64",
            modules: [.monitoring: .available],
            recentErrors: [DiagnosticLogEntry(
                severity: .error,
                message: "failed /Users/alice/Library/Logs/private.log token=do-not-share"
            )],
            crashes: DiagnosticCrashSummary(
                matchingReportCount: 1,
                latestReportDate: Date(timeIntervalSince1970: 0),
                accessStatus: .available
            ),
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        let report = DiagnosticsReportBuilder.text(from: input)
        #expect(report.contains("Version: 0.1.0 (build 2)"))
        #expect(report.contains("<private-path>"))
        #expect(!report.contains("/Users/alice"))
        #expect(!report.contains("private.log"))
        #expect(!report.contains("do-not-share"))
        #expect(report.contains("Nothing is uploaded automatically"))
    }

    @Test("diagnostic report defaults omitted module states to not tested")
    func diagnosticModuleDefaults() {
        let input = DiagnosticsReportInput(
            appName: "LexCleaner",
            version: "0.1.0",
            build: "2",
            macOSVersion: "macOS",
            modelIdentifier: "Mac",
            architecture: "arm64",
            modules: [:],
            recentErrors: [],
            crashes: DiagnosticCrashSummary(
                matchingReportCount: 0,
                latestReportDate: nil,
                accessStatus: .notTested
            )
        )

        let report = DiagnosticsReportBuilder.text(from: input)
        #expect(report.contains("- Cleaner: notTested"))
        #expect(report.contains("- Updater: notTested"))
        #expect(report.contains("Crash report inspection not tested"))
    }
}
