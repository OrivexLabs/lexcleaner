import Foundation
import LexCleanerCore
import Sparkle

@MainActor
final class SparkleUpdaterService: NSObject, SparkleUpdateAdapter, AppUpdateSettings, SPUUpdaterDelegate {
    let isConfigured = true

    private let currentVersion: String
    private let configuration: SparkleUpdateConfiguration
    private let source: UpdateSource
    private var updaterController: SPUStandardUpdaterController!
    private var pendingResult: CheckedContinuation<UpdateCheckResult, Never>?

    init(currentVersion: String, configuration: SparkleUpdateConfiguration) {
        self.currentVersion = currentVersion
        self.configuration = configuration
        self.source = UpdateSource(
            kind: .sparkle,
            identifier: Bundle.main.bundleIdentifier,
            url: configuration.feedURL
        )
        super.init()

        // Sparkle weakly retains its delegate. AppUpdateRuntime retains this
        // service for the lifetime of the app, so callbacks remain valid.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    var automaticallyChecksForUpdates: Bool {
        updaterController.updater.automaticallyChecksForUpdates
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        updaterController.updater.automaticallyChecksForUpdates = enabled
    }

    func checkForUpdates() async -> UpdateCheckResult {
        guard configuration.isUsable else {
            return UpdateCheckResult(
                status: .unavailable,
                currentVersion: currentVersion,
                detail: configuration.unavailableDetail
            )
        }
        guard pendingResult == nil else {
            return UpdateCheckResult(
                status: .failed,
                currentVersion: currentVersion,
                detail: "An update check is already in progress."
            )
        }
        guard updaterController.updater.canCheckForUpdates else {
            return UpdateCheckResult(
                status: .failed,
                currentVersion: currentVersion,
                detail: "Sparkle is busy with another update session."
            )
        }

        return await withCheckedContinuation { continuation in
            pendingResult = continuation
            updaterController.checkForUpdates(nil)
        }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        switch item.signingValidationStatus {
        case .succeeded:
            break
        case .failed, .skipped:
            finish(
                UpdateCheckResult(
                    status: .failed,
                    currentVersion: currentVersion,
                    detail: "Sparkle rejected an update whose archive signature was not verified."
                )
            )
            return
        @unknown default:
            finish(
                UpdateCheckResult(
                    status: .failed,
                    currentVersion: currentVersion,
                    detail: "Sparkle returned an unknown archive signature state."
                )
            )
            return
        }

        let signatureStatus: UpdateSignatureStatus
        switch item.signingValidationStatus {
        case .succeeded:
            signatureStatus = .verified
        case .failed:
            signatureStatus = .unverified
        case .skipped:
            signatureStatus = .unavailable
        @unknown default:
            signatureStatus = .unavailable
        }

        let metadata = UpdateMetadata(
            version: item.displayVersionString,
            build: item.versionString,
            releaseDate: item.date,
            releaseNotes: item.itemDescription,
            releaseNotesURL: item.releaseNotesURL,
            downloadURL: item.fileURL,
            minimumOSVersion: item.minimumSystemVersion,
            signatureStatus: signatureStatus
        )
        finish(
            UpdateCheckResult(
                status: .available,
                currentVersion: currentVersion,
                candidate: UpdateCandidate(metadata: metadata, source: source)
            )
        )
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        let nsError = error as NSError
        if nsError.code == 1001 { // SUNoUpdateError; stable Sparkle error code.
            finish(UpdateCheckResult(status: .upToDate, currentVersion: currentVersion))
        } else {
            finish(
                UpdateCheckResult(
                    status: .failed,
                    currentVersion: currentVersion,
                    detail: nsError.localizedDescription
                )
            )
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        finish(UpdateCheckResult(status: .upToDate, currentVersion: currentVersion))
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        finish(
            UpdateCheckResult(
                status: .failed,
                currentVersion: currentVersion,
                detail: error.localizedDescription
            )
        )
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        guard pendingResult != nil else { return }
        if let error {
            let nsError = error as NSError
            if nsError.code == 1001 {
                finish(UpdateCheckResult(status: .upToDate, currentVersion: currentVersion))
            } else {
                finish(
                    UpdateCheckResult(
                        status: .failed,
                        currentVersion: currentVersion,
                        detail: nsError.localizedDescription
                    )
                )
            }
        } else {
            finish(UpdateCheckResult(status: .upToDate, currentVersion: currentVersion))
        }
    }

    private func finish(_ result: UpdateCheckResult) {
        guard let pendingResult else { return }
        self.pendingResult = nil
        pendingResult.resume(returning: result)
    }
}
