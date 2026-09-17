import Foundation
import AVFoundation
import ApplicationServices
import CoreGraphics

public struct PrivacyReader: Sendable {
    public init() {}

    public func read() -> PrivacySnapshot {
        PrivacySnapshot(permissions: [
            mediaStatus(.video, permission: .camera, source: "AVCaptureDevice.authorizationStatus(for: .video)"),
            mediaStatus(.audio, permission: .microphone, source: "AVCaptureDevice.authorizationStatus(for: .audio)"),
            accessibilityStatus(),
            screenRecordingStatus(),
            PrivacyPermissionStatus(
                permission: .fullDiskAccess,
                status: .unsupported,
                source: "No public macOS API",
                detail: "The app does not inspect TCC databases or infer Full Disk Access from file probes."
            )
        ])
    }

    private func mediaStatus(
        _ mediaType: AVMediaType,
        permission: PrivacyPermission,
        source: String
    ) -> PrivacyPermissionStatus {
        let status: PrivacyStatus
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            status = .authorized
        case .denied:
            status = .denied
        case .notDetermined:
            status = .notDetermined
        case .restricted:
            status = .unavailable
        @unknown default:
            status = .unavailable
        }
        let capability: PrivacyCapability
        let detail: String
        if AVCaptureDevice.default(for: mediaType) != nil {
            capability = .available
            detail = "A compatible input device is discoverable through public AVFoundation APIs."
        } else {
            capability = .unavailable
            detail = "No compatible input device is currently discoverable through public AVFoundation APIs."
        }
        return PrivacyPermissionStatus(
            permission: permission,
            status: status,
            source: source,
            detail: detail,
            capability: capability
        )
    }

    private func accessibilityStatus() -> PrivacyPermissionStatus {
        PrivacyPermissionStatus(
            permission: .accessibility,
            status: AXIsProcessTrustedWithOptions(nil) ? .authorized : .denied,
            source: "AXIsProcessTrustedWithOptions",
            detail: "The query does not request or display a permission prompt."
        )
    }

    private func screenRecordingStatus() -> PrivacyPermissionStatus {
        PrivacyPermissionStatus(
            permission: .screenRecording,
            status: CGPreflightScreenCaptureAccess() ? .authorized : .denied,
            source: "CGPreflightScreenCaptureAccess",
            detail: "The query does not request access."
        )
    }
}
