import Foundation
import LexCleanerCore

let startup = StartupReader().read()
let privacy = PrivacyReader().read()
let appStoreResult = await AppStoreUpdateProvider(currentVersion: "0.1.0").checkForUpdates()

let startupSources = Set(startup.items.map(\.source))
let privacyStatuses = Set(privacy.permissions.map(\.status))

guard startupSources.contains(.launchAgent), startupSources.contains(.launchDaemon) else {
    fputs("System tools startup read failed: expected standard launch sources\n", stderr)
    exit(1)
}
guard privacy.permissions.count == PrivacyPermission.allCases.count,
      privacy.status(for: .fullDiskAccess)?.status == .unsupported else {
    fputs("System tools privacy read failed: status model mismatch\n", stderr)
    exit(1)
}
guard appStoreResult.status == .unsupported, appStoreResult.candidate == nil else {
    fputs("System tools update read failed: App Store provider inferred an update\n", stderr)
    exit(1)
}

print("System Tools real read-only verification passed")
print("Startup items: \(startup.items.count); issues: \(startup.issues.count)")
print("Privacy statuses observed: \(privacyStatuses.map(\.rawValue).sorted().joined(separator: ", "))")
print("App Store provider: \(appStoreResult.status.rawValue)")
