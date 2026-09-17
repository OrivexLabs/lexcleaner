import LexCleanerCore
import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: DashboardViewModel
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                dashboardHeader
                overviewCards
                monitoringGrid
                footerStatus
            }
            .padding(28)
        }
        .background(LexTheme.canvas)
        .task {
            model.start()
        }
        .onDisappear {
            model.stop()
        }
    }

    private var dashboardHeader: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("dashboard.title")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("dashboard.subtitle")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isSampling {
                Label("dashboard.live", systemImage: "circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LexTheme.positive)
            }
        }
    }

    private var overviewCards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
            OverviewCard(
                title: L10n.string("dashboard.reclaimableSpace", locale: locale),
                value: DashboardFormat.bytes(model.safeReclaimableBytes, locale: locale),
                detail: model.safeCandidateCount.map { L10n.format("dashboard.safeDetail", locale: locale, String($0)) } ?? L10n.string("dashboard.classifying", locale: locale),
                symbol: "sparkles",
                tint: LexTheme.accentSecondary
            )
            OverviewCard(
                title: L10n.string("dashboard.installedApps", locale: locale),
                value: model.installedAppCount.map(String.init) ?? L10n.string("common.collecting", locale: locale),
                detail: L10n.string("dashboard.appEnumeration", locale: locale),
                symbol: "square.stack.3d.up",
                tint: LexTheme.accent
            )
            OverviewCard(
                title: L10n.string("dashboard.systemHealth", locale: locale),
                value: healthTitle,
                detail: healthDetail,
                symbol: healthSymbol,
                tint: healthTint
            )
        }
    }

    private var monitoringGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
            CPUCard(snapshot: model.monitoringSnapshot?.cpu)
            MemoryCard(snapshot: model.monitoringSnapshot?.memory)
            DiskCard(snapshot: model.monitoringSnapshot?.disk)
            NetworkCard(snapshot: model.monitoringSnapshot?.network)
            ThermalCard(snapshot: model.hardwareSnapshot?.thermal)
        }
    }

    private var footerStatus: some View {
        HStack(spacing: 14) {
            Label("dashboard.readOnlyData", systemImage: "lock.shield")
            Text(L10n.format("dashboard.monitoringTimestamp", locale: locale, DashboardFormat.date(model.monitoringSnapshot?.timestamp, locale: locale)))
            if let issueCount = model.scanIssueCount {
                Text(L10n.format("dashboard.scanIssues", locale: locale, String(issueCount)))
            }
            if let lastError = model.lastError {
                Text(model.lastErrorKey.map { L10n.format($0, locale: locale, lastError) } ?? lastError)
                    .foregroundStyle(.red)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var healthTitle: String {
        guard let monitoring = model.monitoringSnapshot, let hardware = model.hardwareSnapshot else { return L10n.string("dashboard.health.waiting", locale: locale) }
        if monitoring.memory.pressure == .critical || hardware.thermal.state == .critical { return L10n.string("dashboard.health.attention", locale: locale) }
        if monitoring.memory.pressure == .warning || hardware.thermal.state == .serious { return L10n.string("dashboard.health.observing", locale: locale) }
        return L10n.string("dashboard.health.good", locale: locale)
    }

    private var healthDetail: String {
        guard let monitoring = model.monitoringSnapshot, let hardware = model.hardwareSnapshot else { return L10n.string("dashboard.health.waitingDetail", locale: locale) }
        return L10n.format("dashboard.health.detail", locale: locale, monitoring.memory.pressure.localizedName(locale: locale), hardware.thermal.localizedName(locale: locale))
    }

    private var healthSymbol: String {
        switch healthTitle {
        case L10n.string("dashboard.health.good", locale: locale): return "checkmark.shield"
        case L10n.string("dashboard.health.attention", locale: locale): return "exclamationmark.shield"
        default: return "waveform.path.ecg"
        }
    }

    private var healthTint: Color {
        switch healthTitle {
        case L10n.string("dashboard.health.good", locale: locale): return LexTheme.positive
        case L10n.string("dashboard.health.attention", locale: locale): return .red
        default: return LexTheme.caution
        }
    }
}

private struct OverviewCard: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color

    var body: some View {
        CardSurface {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Text(value).font(.title2.weight(.bold).monospacedDigit())
                    Text(detail).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct CPUCard: View {
    let snapshot: CPUSnapshot?
    @Environment(\.locale) private var locale

    var body: some View {
        MetricCard(title: L10n.string("metric.cpu", locale: locale), symbol: "cpu", tint: LexTheme.accent) {
            Text(DashboardFormat.percent(snapshot?.totalUsagePercent, locale: locale))
                .font(.title.weight(.bold).monospacedDigit())
            if let snapshot {
                ProgressView(value: snapshot.totalUsagePercent, total: 100)
                    .tint(LexTheme.accent)
                HStack {
                    StatPair(label: L10n.string("metric.user", locale: locale), value: DashboardFormat.percent(snapshot.userUsagePercent, locale: locale))
                    StatPair(label: L10n.string("metric.system", locale: locale), value: DashboardFormat.percent(snapshot.systemUsagePercent, locale: locale))
                    StatPair(label: L10n.string("metric.idle", locale: locale), value: DashboardFormat.percent(snapshot.idleUsagePercent, locale: locale))
                }
                Text(L10n.format("metric.coresSampled", locale: locale, String(snapshot.perCoreUsagePercent.count)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct MemoryCard: View {
    let snapshot: MemorySnapshot?
    @Environment(\.locale) private var locale

    var body: some View {
        MetricCard(title: L10n.string("metric.memory", locale: locale), symbol: "memorychip", tint: LexTheme.accentSecondary) {
            Text(DashboardFormat.bytes(snapshot?.usedMemoryBytes, locale: locale))
                .font(.title.weight(.bold).monospacedDigit())
            if let snapshot {
                ProgressView(value: Double(snapshot.usedMemoryBytes), total: Double(max(snapshot.physicalMemoryBytes, 1)))
                    .tint(LexTheme.accentSecondary)
                HStack {
                    StatPair(label: L10n.string("metric.total", locale: locale), value: DashboardFormat.bytes(snapshot.physicalMemoryBytes, locale: locale))
                    StatPair(label: L10n.string("metric.free", locale: locale), value: DashboardFormat.bytes(snapshot.availableMemoryBytes, locale: locale))
                }
                Text(L10n.format("metric.pressureSwap", locale: locale, snapshot.pressure.localizedName(locale: locale), DashboardFormat.bytes(snapshot.swapUsedBytes, locale: locale)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct DiskCard: View {
    let snapshot: DiskSnapshot?
    @Environment(\.locale) private var locale

    var body: some View {
        MetricCard(title: L10n.string("metric.disk", locale: locale), symbol: "internaldrive", tint: .orange) {
            Text(DashboardFormat.bytes(snapshot?.availableBytes, locale: locale))
                .font(.title.weight(.bold).monospacedDigit())
            if let snapshot {
                ProgressView(value: Double(snapshot.usedBytes), total: Double(max(snapshot.totalBytes, 1)))
                    .tint(.orange)
                HStack {
                    StatPair(label: L10n.string("metric.used", locale: locale), value: DashboardFormat.bytes(snapshot.usedBytes, locale: locale))
                    StatPair(label: L10n.string("metric.total", locale: locale), value: DashboardFormat.bytes(snapshot.totalBytes, locale: locale))
                }
                Text(L10n.format("metric.readWrite", locale: locale, DashboardFormat.rate(snapshot.readBytesPerSecond, locale: locale), DashboardFormat.rate(snapshot.writeBytesPerSecond, locale: locale)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct NetworkCard: View {
    let snapshot: NetworkSnapshot?
    @Environment(\.locale) private var locale

    var body: some View {
        MetricCard(title: L10n.string("metric.network", locale: locale), symbol: "network", tint: .purple) {
            if let snapshot {
                HStack(spacing: 16) {
                    StatPair(label: L10n.string("metric.download", locale: locale), value: DashboardFormat.rate(snapshot.downloadBytesPerSecond, locale: locale))
                    StatPair(label: L10n.string("metric.upload", locale: locale), value: DashboardFormat.rate(snapshot.uploadBytesPerSecond, locale: locale))
                }
                Text(L10n.format("metric.interfacesTotal", locale: locale, String(snapshot.interfaces.count), DashboardFormat.bytes(snapshot.cumulativeReceivedBytes, locale: locale)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("common.collecting")
                    .font(.title.weight(.bold))
            }
        }
    }
}

private struct ThermalCard: View {
    let snapshot: ThermalSnapshot?
    @Environment(\.locale) private var locale

    var body: some View {
        MetricCard(title: L10n.string("metric.thermal", locale: locale), symbol: "thermometer.medium", tint: .red) {
            Text(snapshot.map { $0.localizedName(locale: locale) } ?? L10n.string("common.collecting", locale: locale))
                .font(.title.weight(.bold))
            if let snapshot {
                    Text(snapshot.status.availability.localizedName(locale: locale))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let lowPowerMode = snapshot.lowPowerModeEnabled {
                    Text(lowPowerMode ? "metric.lowPowerOn" : "metric.lowPowerOff")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

private struct MetricCard<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: symbol)
                    .font(.headline)
                    .foregroundStyle(tint)
                content()
            }
        }
    }
}

private struct CardSurface<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(LexTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.primary.opacity(0.07))
            }
    }
}

private struct StatPair: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(.tertiary)
            Text(value).font(.caption.monospacedDigit())
        }
    }
}

private extension ThermalSnapshot {
    func localizedName(locale: Locale) -> String {
        if let state {
            return state.localizedName(locale: locale)
        }
        return status.availability.localizedName(locale: locale)
    }
}
