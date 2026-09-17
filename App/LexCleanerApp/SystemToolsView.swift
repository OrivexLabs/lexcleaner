import SwiftUI
import LexCleanerCore

enum SystemToolsDestination: Hashable {
    case overview
    case loginItems
    case launchAgents
    case launchDaemons
    case privacy
}

enum StartupFilter: String, CaseIterable, Identifiable {
    case all
    case enabled
    case disabled
    case attention

    var id: String { rawValue }
}

struct SystemToolsView: View {
    @ObservedObject var model: SystemToolsViewModel
    @ObservedObject var languageSettings: LanguageSettings
    @AppStorage("lexcleaner.languageOverride") private var languageRawValue = SystemToolsAppLanguage.system.rawValue
    @AppStorage("lexcleaner.appearance") private var appearanceRawValue = SystemToolsAppAppearance.system.rawValue
    @State private var destination: SystemToolsDestination? = .overview

    private var language: SystemToolsAppLanguage {
        SystemToolsAppLanguage(rawValue: languageRawValue) ?? .system
    }

    private var appearance: SystemToolsAppAppearance {
        SystemToolsAppAppearance(rawValue: appearanceRawValue) ?? .system
    }

    var body: some View {
        let l10n = SystemToolsL10n(language: language)
        NavigationSplitView {
            sidebar(l10n: l10n)
        } detail: {
            detail(l10n: l10n)
        }
        .frame(minWidth: 1_040, minHeight: 680)
        .preferredColorScheme(appearance.colorScheme)
        .environment(\.locale, Locale(identifier: language.localeIdentifier))
    }

    private func sidebar(l10n: SystemToolsL10n) -> some View {
        List(selection: $destination) {
            Section {
                NavigationLink(value: SystemToolsDestination.overview) {
                    Label(l10n.overview, systemImage: "square.grid.2x2")
                }
            }

            Section(l10n.systemTools) {
                NavigationLink(value: SystemToolsDestination.loginItems) {
                    Label(l10n.loginItems, systemImage: "rectangle.on.rectangle")
                }
                NavigationLink(value: SystemToolsDestination.launchAgents) {
                    Label(l10n.launchAgents, systemImage: "person.crop.circle.badge.checkmark")
                }
                NavigationLink(value: SystemToolsDestination.launchDaemons) {
                    Label(l10n.launchDaemons, systemImage: "gearshape.2")
                }
                NavigationLink(value: SystemToolsDestination.privacy) {
                    Label(l10n.privacy, systemImage: "lock.shield")
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(l10n.appName)
                        .font(.headline)
                    Text(l10n.systemTools)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.bar)
        }
    }

    @ViewBuilder
    private func detail(l10n: SystemToolsL10n) -> some View {
        switch destination ?? .overview {
        case .overview:
            OverviewPage(model: model, l10n: l10n, select: { destination = $0 })
        case .loginItems:
            StartupPage(model: model, destination: .loginItems, l10n: l10n)
        case .launchAgents:
            StartupPage(model: model, destination: .launchAgents, l10n: l10n)
        case .launchDaemons:
            StartupPage(model: model, destination: .launchDaemons, l10n: l10n)
        case .privacy:
            PrivacyPage(model: model, l10n: l10n)
        }
    }
}

private struct PageHeader: View {
    @ObservedObject var model: SystemToolsViewModel
    let title: String
    let subtitle: String
    let l10n: SystemToolsL10n
    @Binding var languageRawValue: String
    @Binding var appearanceRawValue: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Text(title)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text(l10n.readOnly.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            HStack(spacing: 8) {
                Picker(l10n.language, selection: $languageRawValue) {
                    Text("EN").tag(SystemToolsAppLanguage.english.rawValue)
                    Text("简中").tag(SystemToolsAppLanguage.simplifiedChinese.rawValue)
                    Text(l10n.systemDefault).tag(SystemToolsAppLanguage.system.rawValue)
                }
                .pickerStyle(.menu)
                .frame(width: 112)
                .accessibilityLabel(l10n.language)

                Picker(l10n.appearance, selection: $appearanceRawValue) {
                    Label(l10n.systemDefault, systemImage: "circle.lefthalf.filled").tag(SystemToolsAppAppearance.system.rawValue)
                    Label(l10n.light, systemImage: "sun.max").tag(SystemToolsAppAppearance.light.rawValue)
                    Label(l10n.dark, systemImage: "moon").tag(SystemToolsAppAppearance.dark.rawValue)
                }
                .pickerStyle(.menu)
                .frame(width: 122)
                .accessibilityLabel(l10n.appearance)

                Button(action: model.refresh) {
                    Image(systemName: model.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help(model.isRefreshing ? l10n.refreshing : l10n.refresh)
                .accessibilityLabel(model.isRefreshing ? l10n.refreshing : l10n.refresh)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 26)
        .padding(.bottom, 18)
    }
}

private struct OverviewPage: View {
    @ObservedObject var model: SystemToolsViewModel
    let l10n: SystemToolsL10n
    let select: (SystemToolsDestination) -> Void
    @AppStorage("lexcleaner.languageOverride") private var languageRawValue = SystemToolsAppLanguage.system.rawValue
    @AppStorage("lexcleaner.appearance") private var appearanceRawValue = SystemToolsAppAppearance.system.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    model: model,
                    title: l10n.systemTools,
                    subtitle: l10n.startupSubtitle,
                    l10n: l10n,
                    languageRawValue: $languageRawValue,
                    appearanceRawValue: $appearanceRawValue
                )

                if model.isRefreshing && model.startupSnapshot == nil {
                    ProgressView(l10n.refreshing)
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    overviewContent
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var overviewContent: some View {
        let startupItems = model.startupSnapshot?.items ?? []
        let permissions = model.privacySnapshot?.permissions ?? []
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                MetricCard(title: l10n.startup, value: startupItems.count, icon: "bolt.fill", tint: .orange, l10n: l10n)
                MetricCard(title: l10n.privacy, value: permissions.count, icon: "lock.shield.fill", tint: .green, l10n: l10n)
                MetricCard(title: l10n.issues, value: model.startupSnapshot?.issues.count ?? 0, icon: "exclamationmark.triangle.fill", tint: .yellow, l10n: l10n)
            }

            HStack(alignment: .top, spacing: 18) {
                OverviewCard(title: l10n.startup, subtitle: l10n.startupSubtitle, icon: "bolt.fill", tint: .orange) {
                    OverviewLink(title: l10n.loginItems, detail: l10n.loginItemsSubtitle, icon: "rectangle.on.rectangle") { select(.loginItems) }
                    OverviewLink(title: l10n.launchAgents, detail: l10n.launchAgentsSubtitle, icon: "person.crop.circle.badge.checkmark") { select(.launchAgents) }
                    OverviewLink(title: l10n.launchDaemons, detail: l10n.launchDaemonsSubtitle, icon: "gearshape.2") { select(.launchDaemons) }
                }
                OverviewCard(title: l10n.privacy, subtitle: l10n.privacySubtitle, icon: "lock.shield.fill", tint: .green) {
                    ForEach([PrivacyPermission.camera, .microphone, .accessibility], id: \.self) { permission in
                        let status = model.privacySnapshot?.status(for: permission)
                        HStack(spacing: 10) {
                            Image(systemName: permissionIcon(permission))
                                .frame(width: 24)
                                .foregroundStyle(.secondary)
                            Text(l10n.permissionName(permission))
                            Spacer()
                            Text(status.map { l10n.privacyStatusName($0.status) } ?? l10n.unavailable)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(statusColor(status?.status ?? .unavailable))
                        }
                    }
                    Button(l10n.details) { select(.privacy) }
                        .buttonStyle(.link)
                        .padding(.top, 3)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 28)
    }
}

private struct MetricCard: View {
    let title: String
    let value: Int
    let icon: String
    let tint: Color
    let l10n: SystemToolsL10n

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                Spacer()
                Text(l10n.count(value))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08)))
    }
}

private struct OverviewCard<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(tint)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.08)))
    }
}

private struct OverviewLink: View {
    let title: String
    let detail: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 26)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.medium))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct StartupPage: View {
    @ObservedObject var model: SystemToolsViewModel
    let destination: SystemToolsDestination
    let l10n: SystemToolsL10n
    @AppStorage("lexcleaner.languageOverride") private var languageRawValue = SystemToolsAppLanguage.system.rawValue
    @AppStorage("lexcleaner.appearance") private var appearanceRawValue = SystemToolsAppAppearance.system.rawValue
    @State private var searchText = ""
    @State private var filter: StartupFilter = .all
    @State private var selectedID: String?

    private var source: StartupSource {
        switch destination {
        case .loginItems: return .loginItem
        case .launchAgents: return .launchAgent
        case .launchDaemons: return .launchDaemon
        default: return .launchAgent
        }
    }

    private var title: String {
        switch destination {
        case .loginItems: return l10n.loginItems
        case .launchAgents: return l10n.launchAgents
        case .launchDaemons: return l10n.launchDaemons
        default: return l10n.startup
        }
    }

    private var subtitle: String {
        switch destination {
        case .loginItems: return l10n.loginItemsSubtitle
        case .launchAgents: return l10n.launchAgentsSubtitle
        case .launchDaemons: return l10n.launchDaemonsSubtitle
        default: return l10n.startupSubtitle
        }
    }

    private var items: [StartupItem] {
        let sourceItems = model.startupSnapshot?.items.filter { $0.source == source } ?? []
        return sourceItems.filter { item in
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let matchesSearch = query.isEmpty || [item.label, item.location?.path, item.executablePath, item.status.rawValue]
                .compactMap { $0?.lowercased() }
                .contains { $0.contains(query) }
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .enabled: matchesFilter = item.status == .enabled
            case .disabled: matchesFilter = item.status == .disabled
            case .attention: matchesFilter = item.status != .enabled
            }
            return matchesSearch && matchesFilter
        }
    }

    private var selectedItem: StartupItem? {
        if let selectedID, let item = items.first(where: { $0.id == selectedID }) { return item }
        return items.first
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                model: model,
                title: title,
                subtitle: subtitle,
                l10n: l10n,
                languageRawValue: $languageRawValue,
                appearanceRawValue: $appearanceRawValue
            )

            if source == .loginItem {
                NoticeBanner(icon: "info.circle.fill", tint: .blue, text: l10n.globalLoginItemsUnavailable)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 14)
            }

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        FilterPicker(filter: $filter, l10n: l10n)
                        Spacer()
                        Text(l10n.count(items.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)

                    if let snapshot = model.startupSnapshot {
                        if items.isEmpty {
                            EmptyState(icon: "magnifyingglass", title: l10n.noItems)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 8) {
                                    ForEach(items) { item in
                                        StartupRow(item: item, isSelected: selectedItem?.id == item.id, l10n: l10n) {
                                            selectedID = item.id
                                        }
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.bottom, 20)
                            }
                            .overlay(alignment: .bottom) {
                                if !snapshot.issues.isEmpty {
                                    Text("\(l10n.issues): \(snapshot.issues.count)")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.orange)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(.thinMaterial, in: Capsule())
                                        .padding(.bottom, 8)
                                }
                            }
                        }
                    } else if model.isRefreshing {
                        ProgressView(l10n.refreshing)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        EmptyState(icon: "exclamationmark.triangle", title: l10n.unavailable)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 360, idealWidth: 430, maxWidth: 470)
                .padding(.top, 4)

                Divider()

                if let item = selectedItem {
                    StartupDetail(item: item, l10n: l10n)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    EmptyState(icon: "sidebar.right", title: l10n.noSelection)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .searchable(text: $searchText, placement: .toolbar, prompt: l10n.searchPlaceholder)
    }
}

private struct FilterPicker: View {
    @Binding var filter: StartupFilter
    let l10n: SystemToolsL10n

    var body: some View {
        Picker(l10n.filter, selection: $filter) {
            Text(l10n.all).tag(StartupFilter.all)
            Text(l10n.enabled).tag(StartupFilter.enabled)
            Text(l10n.disabled).tag(StartupFilter.disabled)
            Text(l10n.attention).tag(StartupFilter.attention)
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .accessibilityLabel(l10n.filter)
    }
}

private struct StartupRow: View {
    let item: StartupItem
    let isSelected: Bool
    let l10n: SystemToolsL10n
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: sourceIcon(item.source))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 30, height: 30)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.label)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(l10n.scopeName(item.scope))
                        Text("•")
                        Text(item.location?.lastPathComponent ?? l10n.noPath)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 8)
                StatusBadge(text: l10n.statusName(item.status), tint: startupStatusColor(item.status))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor.opacity(0.13) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.label), \(l10n.statusName(item.status))")
    }
}

private struct StartupDetail: View {
    let item: StartupItem
    let l10n: SystemToolsL10n

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: sourceIcon(item.source))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 48, height: 48)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.label)
                            .font(.title3.weight(.bold))
                            .textSelection(.enabled)
                        HStack(spacing: 7) {
                            Text(l10n.sourceName(item.source))
                            Text("•")
                            Text(l10n.scopeName(item.scope))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(text: l10n.statusName(item.status), tint: startupStatusColor(item.status))
                }

                DetailSection(title: l10n.details) {
                    DetailRow(label: l10n.status, value: l10n.statusName(item.status))
                    DetailRow(label: l10n.source, value: l10n.sourceName(item.source))
                    DetailRow(label: l10n.scope, value: l10n.scopeName(item.scope))
                    DetailRow(label: l10n.location, value: item.location?.path ?? l10n.noPath)
                    DetailRow(label: l10n.executable, value: item.executablePath ?? l10n.noExecutable)
                }

                if let detail = item.detail {
                    DetailSection(title: l10n.declaration) {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }

                NoticeBanner(icon: "lock.shield.fill", tint: .green, text: l10n.startupReadOnlyNotice)
            }
            .padding(28)
        }
    }
}

private struct PrivacyPage: View {
    @ObservedObject var model: SystemToolsViewModel
    let l10n: SystemToolsL10n
    @AppStorage("lexcleaner.languageOverride") private var languageRawValue = SystemToolsAppLanguage.system.rawValue
    @AppStorage("lexcleaner.appearance") private var appearanceRawValue = SystemToolsAppAppearance.system.rawValue
    @State private var selectedPermission: PrivacyPermission = .camera

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                model: model,
                title: l10n.privacy,
                subtitle: l10n.privacySubtitle,
                l10n: l10n,
                languageRawValue: $languageRawValue,
                appearanceRawValue: $appearanceRawValue
            )
            NoticeBanner(icon: "lock.shield.fill", tint: .green, text: l10n.privacyReadOnlyNotice)
                .padding(.horizontal, 28)
                .padding(.bottom, 16)

            HStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(PrivacyPermission.allCases, id: \.self) { permission in
                            PrivacyCard(
                                permission: permission,
                                value: model.privacySnapshot?.status(for: permission),
                                isSelected: selectedPermission == permission,
                                l10n: l10n
                            ) {
                                selectedPermission = permission
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .frame(minWidth: 360, idealWidth: 430, maxWidth: 500)

                Divider()

                if let value = model.privacySnapshot?.status(for: selectedPermission) {
                    PrivacyDetail(permission: selectedPermission, value: value, l10n: l10n)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else if model.isRefreshing {
                    ProgressView(l10n.refreshing)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EmptyState(icon: "lock.slash", title: l10n.unavailable)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct PrivacyCard: View {
    let permission: PrivacyPermission
    let value: PrivacyPermissionStatus?
    let isSelected: Bool
    let l10n: SystemToolsL10n
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: permissionIcon(permission))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 4) {
                    Text(l10n.permissionName(permission))
                        .font(.subheadline.weight(.semibold))
                    Text(value.map { l10n.privacyStatusName($0.status) } ?? l10n.unavailable)
                        .font(.caption)
                        .foregroundStyle(statusColor(value?.status ?? .unavailable))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(13)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.clear))
        }
        .buttonStyle(.plain)
    }
}

private struct PrivacyDetail: View {
    let permission: PrivacyPermission
    let value: PrivacyPermissionStatus
    let l10n: SystemToolsL10n

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Image(systemName: permissionIcon(permission))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 48, height: 48)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(l10n.permissionName(permission))
                            .font(.title3.weight(.bold))
                        Text(l10n.privacyStatusName(value.status))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(statusColor(value.status))
                    }
                    Spacer()
                }

                DetailSection(title: l10n.details) {
                    DetailRow(label: l10n.authorization, value: l10n.privacyStatusName(value.status))
                    DetailRow(label: l10n.capability, value: l10n.capabilityName(value.capability))
                    DetailRow(label: l10n.source, value: value.source)
                }

                if permission == .camera || permission == .microphone {
                    DetailSection(title: l10n.capability) {
                        Text(l10n.capabilityDetail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        StatusBadge(text: l10n.capabilityName(value.capability), tint: capabilityColor(value.capability))
                    }
                }

                if let detail = value.detail {
                    DetailSection(title: l10n.declaration) {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }

                Text(permission == .fullDiskAccess ? l10n.noPermissionDetail : l10n.privacyReadOnlyNotice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(28)
        }
    }
}

private struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 116, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct StatusBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct NoticeBanner: View {
    let icon: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct EmptyState: View {
    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(30)
    }
}

private func permissionIcon(_ permission: PrivacyPermission) -> String {
    switch permission {
    case .camera: return "camera.fill"
    case .microphone: return "mic.fill"
    case .accessibility: return "figure.wave.circle.fill"
    case .screenRecording: return "rectangle.inset.filled.and.person.filled"
    case .fullDiskAccess: return "internaldrive.fill"
    }
}

private func sourceIcon(_ source: StartupSource) -> String {
    switch source {
    case .loginItem: return "rectangle.on.rectangle"
    case .launchAgent: return "person.crop.circle.badge.checkmark"
    case .launchDaemon: return "gearshape.2"
    }
}

private func startupStatusColor(_ status: StartupStatus) -> Color {
    switch status {
    case .enabled: return .green
    case .disabled: return .orange
    case .notRegistered, .requiresApproval: return .yellow
    case .notFound, .unknown, .unavailable, .unsupported: return .secondary
    }
}

private func statusColor(_ status: PrivacyStatus) -> Color {
    switch status {
    case .authorized, .available: return .green
    case .notDetermined: return .orange
    case .denied: return .red
    case .unavailable, .unsupported: return .secondary
    }
}

private func capabilityColor(_ capability: PrivacyCapability) -> Color {
    switch capability {
    case .available: return .green
    case .unavailable: return .orange
    case .unsupported: return .secondary
    }
}
