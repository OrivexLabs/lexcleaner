import Foundation
import Testing
@testable import LexCleanerCore

@Suite("SystemToolsFoundation")
struct SystemToolsEngineTests {
    @Test("reads launch plist declarations without invoking startup mutations")
    func readsLaunchPlistDeclarations() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LexCleaner-SystemTools-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let plist = root.appendingPathComponent("com.example.agent.plist")
        let data = try PropertyListSerialization.data(fromPropertyList: [
            "Label": "com.example.agent",
            "ProgramArguments": ["/tmp/example-agent"],
            "Disabled": true
        ], format: .xml, options: 0)
        try data.write(to: plist, options: .atomic)

        let snapshot = StartupReader(
            directories: [StartupDirectory(source: .launchAgent, scope: .user, url: root)],
            includeMainAppLoginItem: false
        ).read()

        let item = try #require(snapshot.items.first)
        #expect(item.source == .launchAgent)
        #expect(item.status == .disabled)
        #expect(item.label == "com.example.agent")
        #expect(item.executablePath == "/tmp/example-agent")
        #expect(snapshot.issues.contains { $0.kind == .loginItemsEnumerationUnsupported })
    }

    @Test("does not pretend to enumerate arbitrary login items")
    func loginItemEnumerationIsExplicitlyUnsupported() {
        let snapshot = StartupReader(directories: [], includeMainAppLoginItem: false).read()
        #expect(snapshot.items.isEmpty)
        #expect(snapshot.issues.contains { $0.kind == .loginItemsEnumerationUnsupported })
    }

    @Test("reports privacy states only through audited public APIs")
    func reportsPrivacyStates() {
        let snapshot = PrivacyReader().read()
        #expect(snapshot.permissions.count == PrivacyPermission.allCases.count)
        #expect(snapshot.permissions.allSatisfy {
            PrivacyStatus.allCases.contains($0.status)
        })
        #expect(snapshot.status(for: .fullDiskAccess)?.status == .unsupported)
        #expect(snapshot.status(for: .camera)?.source.contains("AVCaptureDevice") == true)
        #expect(snapshot.status(for: .microphone)?.source.contains("AVCaptureDevice") == true)
        #expect(snapshot.status(for: .camera)?.capability != .unsupported)
        #expect(snapshot.status(for: .microphone)?.capability != .unsupported)
        #expect(snapshot.status(for: .fullDiskAccess)?.capability == .unsupported)
    }

    @Test("App Store provider does not infer or install updates")
    func appStoreProviderIsReadOnly() async {
        let result = await AppStoreUpdateProvider(appStoreIdentifier: "123", currentVersion: "0.1.0").checkForUpdates()
        #expect(result.status == .unsupported)
        #expect(result.candidate == nil)
        #expect(result.currentVersion == "0.1.0")
    }

    @Test("Sparkle adapter returns metadata through a Core protocol boundary")
    func sparkleAdapterBoundary() async {
        let metadata = UpdateMetadata(
            version: "0.2.0",
            build: "2",
            releaseNotes: "Improves monitoring stability.",
            downloadURL: URL(string: "https://updates.example.test/LexCleaner.dmg"),
            signatureStatus: .verified
        )
        let source = UpdateSource(kind: .sparkle, identifier: "com.lexcleaner.app", url: URL(string: "https://updates.example.test/appcast.xml"))
        let candidate = UpdateCandidate(metadata: metadata, source: source, manualActionURL: metadata.downloadURL)
        let checker = TestSparkleChecker(result: UpdateCheckResult(status: .available, currentVersion: "0.1.0", candidate: candidate))
        let result = await SparkleUpdateProvider(checker: checker).checkForUpdates()

        #expect(result.status == .available)
        #expect(result.candidate?.metadata.version == "0.2.0")
        #expect(result.candidate?.metadata.releaseNotes == "Improves monitoring stability.")
        #expect(result.candidate?.manualActionURL?.scheme == "https")
        #expect(result.candidate?.metadata.signatureStatus == .verified)
    }

    @Test("Sparkle configuration fails closed without HTTPS feed and Ed25519 key")
    func sparkleConfigurationFailsClosed() {
        let missing = SparkleUpdateConfiguration(feedURL: nil, publicEDKey: nil)
        #expect(!missing.isUsable)
        #expect(missing.unavailableDetail.contains("feed URL"))

        let insecure = SparkleUpdateConfiguration(
            feedURL: URL(string: "http://updates.example.test/appcast.xml"),
            publicEDKey: String(repeating: "A", count: 44)
        )
        #expect(!insecure.isUsable)
        #expect(insecure.unavailableDetail.contains("HTTPS"))

        let invalidKey = SparkleUpdateConfiguration(
            feedURL: URL(string: "https://updates.example.test/appcast.xml"),
            publicEDKey: "not-a-base64-ed25519-key"
        )
        #expect(!invalidKey.isUsable)
        #expect(invalidKey.unavailableDetail.contains("public key"))
    }
}

private struct TestSparkleChecker: SparkleUpdateAdapter {
    let result: UpdateCheckResult

    func checkForUpdates() async -> UpdateCheckResult {
        result
    }
}
