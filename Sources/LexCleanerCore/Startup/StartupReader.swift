import Foundation

#if canImport(ServiceManagement)
import ServiceManagement
#endif

public struct StartupReader: Sendable {
    public let directories: [StartupDirectory]
    public let knownLoginItems: [KnownLoginItem]
    public let includeMainAppLoginItem: Bool

    public init(
        directories: [StartupDirectory] = StartupDirectory.standardDirectories(),
        knownLoginItems: [KnownLoginItem] = [],
        includeMainAppLoginItem: Bool = true
    ) {
        self.directories = directories
        self.knownLoginItems = knownLoginItems
        self.includeMainAppLoginItem = includeMainAppLoginItem
    }

    public func read() -> StartupSnapshot {
        var items: [StartupItem] = []
        var issues: [StartupIssue] = [
            StartupIssue(
                kind: .loginItemsEnumerationUnsupported,
                detail: "macOS does not expose a stable public API to enumerate arbitrary Login Items; only explicitly known SMAppService entries are queried."
            )
        ]

        if includeMainAppLoginItem {
            let item = mainAppLoginItem()
            items.append(item)
        }

        for loginItem in knownLoginItems {
            items.append(knownLoginItem(loginItem))
        }

        for directory in directories {
            read(directory: directory, items: &items, issues: &issues)
        }

        return StartupSnapshot(items: items.sorted { $0.id < $1.id }, issues: issues)
    }

    private func read(directory: StartupDirectory, items: inout [StartupItem], issues: inout [StartupIssue]) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.url.path) else {
            issues.append(StartupIssue(kind: .directoryUnavailable, location: directory.url, detail: "Directory does not exist."))
            return
        }

        let urls: [URL]
        do {
            urls = try fileManager.contentsOfDirectory(
                at: directory.url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ).filter { $0.pathExtension.caseInsensitiveCompare("plist") == .orderedSame }
        } catch {
            issues.append(StartupIssue(kind: .directoryUnavailable, location: directory.url, detail: error.localizedDescription))
            return
        }

        for url in urls.sorted(by: { $0.path < $1.path }) {
            do {
                let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                guard let dictionary = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
                    issues.append(StartupIssue(kind: .malformedPlist, location: url, detail: "The plist root is not a dictionary."))
                    continue
                }

                let label = dictionary["Label"] as? String
                let fallbackLabel = url.deletingPathExtension().lastPathComponent
                let resolvedLabel = label ?? fallbackLabel
                if label == nil {
                    issues.append(StartupIssue(kind: .missingLabel, location: url, detail: "The plist has no Label; the filename was used for display."))
                }

                let executablePath: String?
                if let program = dictionary["Program"] as? String {
                    executablePath = program
                } else if let arguments = dictionary["ProgramArguments"] as? [String] {
                    executablePath = arguments.first
                } else {
                    executablePath = nil
                }

                let disabled = dictionary["Disabled"] as? Bool
                let status: StartupStatus = disabled == true ? .disabled : (disabled == false ? .enabled : .unknown)
                let detail = disabled == nil
                    ? "The plist does not declare Disabled; runtime launchd state is not inferred."
                    : "Status reflects the plist Disabled declaration; runtime launchd state is not inferred."

                items.append(
                    StartupItem(
                        id: "\(directory.source.rawValue):\(directory.scope.rawValue):\(url.path)",
                        source: directory.source,
                        scope: directory.scope,
                        label: resolvedLabel,
                        location: url,
                        executablePath: executablePath,
                        status: status,
                        detail: detail
                    )
                )
            } catch {
                issues.append(StartupIssue(kind: .unreadablePlist, location: url, detail: error.localizedDescription))
            }
        }
    }

    private func mainAppLoginItem() -> StartupItem {
        #if canImport(ServiceManagement)
        if #available(macOS 13, *) {
            return StartupItem(
                id: "loginItem:mainApp",
                source: .loginItem,
                scope: .user,
                label: Bundle.main.bundleIdentifier ?? "main application",
                location: Bundle.main.bundleURL,
                executablePath: Bundle.main.executableURL?.path,
                status: map(SMAppService.mainApp.status),
                detail: "SMAppService status for the current application; this is not a system-wide Login Item enumeration."
            )
        }
        #endif
        return StartupItem(
            id: "loginItem:mainApp",
            source: .loginItem,
            scope: .user,
            label: Bundle.main.bundleIdentifier ?? "main application",
            location: Bundle.main.bundleURL,
            executablePath: Bundle.main.executableURL?.path,
            status: .unsupported,
            detail: "SMAppService requires macOS 13 or later."
        )
    }

    private func knownLoginItem(_ loginItem: KnownLoginItem) -> StartupItem {
        #if canImport(ServiceManagement)
        if #available(macOS 13, *) {
            return StartupItem(
                id: "loginItem:\(loginItem.identifier)",
                source: .loginItem,
                scope: .user,
                label: loginItem.label ?? loginItem.identifier,
                location: nil,
                executablePath: nil,
                status: map(SMAppService.loginItem(identifier: loginItem.identifier).status),
                detail: "SMAppService status for the explicitly supplied bundle identifier."
            )
        }
        #endif
        return StartupItem(
            id: "loginItem:\(loginItem.identifier)",
            source: .loginItem,
            scope: .user,
            label: loginItem.label ?? loginItem.identifier,
            location: nil,
            executablePath: nil,
            status: .unsupported,
            detail: "SMAppService requires macOS 13 or later."
        )
    }

    #if canImport(ServiceManagement)
    @available(macOS 13, *)
    private func map(_ status: SMAppService.Status) -> StartupStatus {
        switch status {
        case .enabled: return .enabled
        case .notRegistered: return .notRegistered
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .unknown
        }
    }
    #endif
}
