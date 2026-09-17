import LexCleanerCore
import SwiftUI

struct MenuBarQuickPanel: View {
    @ObservedObject var menuBar: MenuBarModel
    @ObservedObject var updates: AppUpdateModel
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            metricsSection
            updateSection
            footer
        }
        .padding(18)
        .frame(width: 360)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.text("app.name", locale: locale))
                    .font(.headline)
                Text(L10n.text("menuBar.quickPanel", locale: locale))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let snapshot = menuBar.snapshot {
                Text(snapshot.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("menuBar.displayItems", locale: locale))
                .font(.subheadline.weight(.semibold))
            ForEach(MenuBarMetric.allCases) { metric in
                Toggle(isOn: Binding(
                    get: { menuBar.visibleMetrics.contains(metric) },
                    set: { menuBar.setVisible(metric, isVisible: $0) }
                )) {
                    Label(metric.title(locale: locale), systemImage: icon(for: metric))
                }
                .toggleStyle(.checkbox)
            }
            if let snapshot = menuBar.snapshot {
                metricSummary(snapshot)
            } else if let error = menuBar.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private func metricSummary(_ snapshot: MonitoringSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            summaryRow(L10n.text("metric.cpu", locale: locale), Format.percent(snapshot.cpu.totalUsagePercent, locale: locale))
            summaryRow(
                L10n.text("metric.memory", locale: locale),
                "\(Format.bytes(snapshot.memory.usedMemoryBytes, locale: locale)) / \(Format.bytes(snapshot.memory.physicalMemoryBytes, locale: locale))"
            )
            summaryRow(
                L10n.text("metric.network", locale: locale),
                "↓ \(Format.rate(snapshot.network.downloadBytesPerSecond, locale: locale))  ↑ \(Format.rate(snapshot.network.uploadBytesPerSecond, locale: locale))"
            )
            summaryRow(
                L10n.text("metric.disk", locale: locale),
                "↓ \(Format.rate(snapshot.disk.readBytesPerSecond, locale: locale))  ↑ \(Format.rate(snapshot.disk.writeBytesPerSecond, locale: locale))"
            )
        }
        .font(.caption)
        .padding(.top, 3)
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
    }

    private var updateSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Divider()
            HStack {
                Text(L10n.text("update.title", locale: locale))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("v\(updates.currentVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if updates.isChecking {
                ProgressView(L10n.text("update.checking", locale: locale))
                    .controlSize(.small)
            } else {
                Button(L10n.text("update.check", locale: locale)) {
                    updates.checkForUpdates()
                }
                .buttonStyle(.bordered)
            }

            if let result = updates.result {
                updateResult(result)
            }
            if let actionError = updates.actionError {
                Text(actionError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func updateResult(_ result: UpdateCheckResult) -> some View {
        switch result.status {
        case .available:
            if let candidate = result.candidate {
                VStack(alignment: .leading, spacing: 7) {
                    Text(L10n.text("update.available", locale: locale) + " v" + candidate.metadata.version)
                        .font(.callout.weight(.semibold))
                    if let notes = candidate.metadata.releaseNotes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .lineLimit(5)
                    }
                    Text(L10n.text("update.sparkleConfirmation", locale: locale))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .upToDate:
            Text(L10n.text("update.upToDate", locale: locale))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .unsupported:
            Text(L10n.text("update.unsupported", locale: locale))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .unavailable, .failed:
            Text(result.detail ?? L10n.text("update.failed", locale: locale))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Text(L10n.text("menuBar.readOnly", locale: locale))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func icon(for metric: MenuBarMetric) -> String {
        switch metric {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .network: "network"
        case .disk: "internaldrive"
        }
    }
}
