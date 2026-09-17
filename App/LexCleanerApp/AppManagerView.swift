import AppKit
import LexCleanerCore
import SwiftUI

struct AppManagerView: View {
    @ObservedObject var model: AppManagerViewModel
    @Environment(\.locale) private var locale

    var body: some View {
        HSplitView {
            appList
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 430)
            detail
                .frame(minWidth: 520)
        }
        .background(LexTheme.canvas)
        .navigationTitle(Text(L10n.string("navigation.appManager", locale: locale)))
        .toolbar {
            ToolbarItemGroup {
                if model.phase == .loading || model.phase == .analyzing {
                    ProgressView().controlSize(.small)
                }
                Button("appManager.refresh", systemImage: "arrow.clockwise") { model.refresh() }
                    .disabled(model.phase == .loading || model.phase == .analyzing)
            }
        }
        .alert("appManager.confirmTitle", isPresented: $model.isConfirmationPresented) {
            Button("common.cancel", role: .cancel) {}
            Button("appManager.moveToTrash", role: .destructive) { model.executeAfterConfirmation() }
        } message: {
            Text(confirmationMessage)
        }
        .onAppear { model.loadIfNeeded() }
        .onDisappear { model.cancel() }
    }

    private var appList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("appManager.search", text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
                Picker("appManager.sort", selection: $model.sortOrder) {
                    ForEach(AppManagerSortOrder.allCases) { order in
                        Text(order.titleKey).tag(order)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            .padding(12)
            Divider()
            if model.apps.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: model.phase == .loading ? "hourglass" : "square.stack.3d.up.slash")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(model.phase == .loading ? "appManager.loading" : "appManager.empty")
                        .font(.headline)
                    if model.isControlledFixture {
                        Text("appManager.controlledFixture")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding(
                    get: { model.selectedApp?.path },
                    set: { path in
                        if let app = model.apps.first(where: { $0.path == path }) { model.select(app) }
                    }
                )) {
                    ForEach(model.apps, id: \.path) { app in
                        AppListRow(app: app)
                            .tag(app.path)
                    }
                }
                .listStyle(.sidebar)
            }
            if let inventory = model.inventory {
                HStack {
                    Text(L10n.format("appManager.appCount", locale: locale, String(inventory.apps.count)))
                    Spacer()
                    if !inventory.issues.isEmpty {
                        Label(String(inventory.issues.count), systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let app = model.selectedApp {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    appHeader(app)
                    metadataCard(app)
                    residualCard(app)
                    actionCard
                }
                .padding(26)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(LexTheme.accent)
                Text("appManager.selectApp")
                    .font(.title2.weight(.semibold))
                Text("appManager.selectAppHint")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func appHeader(_ app: InstalledApp) -> some View {
        HStack(spacing: 14) {
            AppIcon(app: app, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(app.displayName)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                Text(app.bundleIdentifier ?? L10n.string("appManager.noBundleID", locale: locale))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    StatusPill(text: L10n.appSource(app.source, locale: locale), color: .secondary)
                    StatusPill(text: L10n.signature(app.signature, locale: locale), color: signatureColor(app.signature))
                    if model.isControlledFixture {
                        StatusPill(text: L10n.string("appManager.controlledFixture", locale: locale), color: .orange)
                    }
                }
            }
            Spacer()
        }
    }

    private func metadataCard(_ app: InstalledApp) -> some View {
        AppManagerCard {
            Text("appManager.basicInfo").font(.headline)
            MetadataGrid(rows: [
                ("appManager.version", app.metadata.shortVersion ?? app.metadata.version ?? L10n.string("detail.unavailable", locale: locale)),
                ("appManager.size", DashboardFormat.bytes(app.sizeBytes, locale: locale)),
                ("appManager.modified", DashboardFormat.date(app.modifiedAt, locale: locale)),
                ("appManager.source", L10n.appSource(app.source, locale: locale)),
                ("appManager.path", app.path.path),
                ("appManager.executable", app.metadata.executableName ?? L10n.string("detail.unavailable", locale: locale))
            ])
        }
    }

    @ViewBuilder
    private func residualCard(_ app: InstalledApp) -> some View {
        AppManagerCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("appManager.residualAnalysis").font(.headline)
                    if let analysis = model.analysis {
                        Text(L10n.format("appManager.residualCount", locale: locale, String(analysis.candidates.count), String(analysis.issues.count)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(model.phase == .analyzing ? "appManager.analyzing" : "appManager.analysisUnavailable")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let analysis = model.analysis {
                    StatusPill(text: L10n.sentinel(analysis.sentinel.status, locale: locale), color: .secondary)
                }
            }
            if let analysis = model.analysis {
                AppBundleSelection(app: app, model: model)
                Divider().padding(.vertical, 3)
                if analysis.candidates.isEmpty {
                    Text("appManager.noResiduals")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(analysis.candidates, id: \.id) { candidate in
                        ResidualRow(candidate: candidate, model: model)
                    }
                }
                if !analysis.issues.isEmpty {
                    Label(L10n.format("appManager.analysisIssues", locale: locale, String(analysis.issues.count)), systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private var actionCard: some View {
        if model.phase == .ready {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.format("appManager.selectedSummary", locale: locale, String(model.selectableCount), DashboardFormat.bytes(model.selectedBytes, locale: locale)))
                        .font(.callout)
                    Text("appManager.reviewRequiredHint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("appManager.createDryRun", systemImage: "eye") { model.createDryRun() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canCreateDryRun)
            }
        } else if model.phase == .dryRun, let dryRun = model.dryRun {
            AppManagerCard {
                Label("appManager.dryRunTitle", systemImage: "eye")
                    .font(.headline)
                Text(L10n.format("appManager.dryRunSummary", locale: locale, String(dryRun.processCount), DashboardFormat.bytes(dryRun.processBytes, locale: locale), String(dryRun.rejectedCount)))
                    .font(.callout)
                Text("appManager.trashOnly")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(dryRun.items.filter { !$0.wouldProcess }, id: \.candidateIdentity) { item in
                    Text(L10n.format("appManager.dryRunRejected", locale: locale, item.path.path, item.rejectionReason.map { L10n.failure($0, locale: locale) } ?? L10n.string("safety.unknown", locale: locale)))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
                Button("appManager.confirm", systemImage: "trash") { model.confirmAndExecute() }
                    .buttonStyle(.borderedProminent)
                    .disabled(dryRun.processCount == 0)
            }
        } else if model.phase == .preflighting || model.phase == .executing {
            AppManagerCard {
                Label(model.phase.titleKey, systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)
                ProgressView()
                if let preflight = model.preflight {
                    Text(L10n.format("appManager.preflightSummary", locale: locale, String(preflight.items.filter { $0.status == .passed }.count), String(preflight.items.filter { $0.status == .rejected }.count)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else if model.phase == .completed, let execution = model.execution {
            AppManagerCard {
                Label("appManager.auditRecorded", systemImage: "checkmark.seal")
                    .font(.headline)
                let success = execution.items.filter { $0.status == .success }.count
                let skipped = execution.items.filter { $0.status == .skipped }.count
                let failed = execution.items.filter { $0.status == .failed || $0.status == .rejected }.count
                Text(L10n.format("appManager.executionSummary", locale: locale, String(success), String(skipped), String(failed), DashboardFormat.bytes(execution.reclaimedBytes, locale: locale)))
                    .font(.callout)
                Text(L10n.format("appManager.auditEntries", locale: locale, String(execution.audit.count)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(execution.items.filter { $0.status != .success }, id: \.candidateIdentity) { item in
                    Text(L10n.format("appManager.failure", locale: locale, item.path.path, item.failureReason.map { L10n.failure($0, locale: locale) } ?? L10n.string("safety.unknown", locale: locale)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var confirmationMessage: String {
        guard let dryRun = model.dryRun else { return "" }
        return L10n.format("appManager.confirmMessage", locale: locale, String(dryRun.processCount), DashboardFormat.bytes(dryRun.processBytes, locale: locale))
    }

    private func signatureColor(_ signature: AppSignatureStatus) -> Color {
        switch signature {
        case .valid: return LexTheme.positive
        case .invalid: return .red
        case .unavailable, .unknown: return .secondary
        }
    }
}

private struct AppListRow: View {
    let app: InstalledApp
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 10) {
            AppIcon(app: app, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.displayName).font(.body.weight(.medium)).lineLimit(1)
                Text(app.metadata.shortVersion ?? app.metadata.version ?? L10n.string("detail.unavailable", locale: locale))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(DashboardFormat.bytes(app.sizeBytes, locale: locale))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }
}

private struct AppIcon: View {
    let app: InstalledApp
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path.path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
    }
}

private struct AppBundleSelection: View {
    let app: InstalledApp
    @ObservedObject var model: AppManagerViewModel
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { model.appBundleSelected }, set: { value in model.setAppBundleSelected(value) }))
                .labelsHidden()
                .toggleStyle(.checkbox)
            Image(systemName: "shippingbox")
                .foregroundStyle(LexTheme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("appManager.appBundle").font(.body.weight(.medium))
                Text(app.path.path).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                Text(L10n.format("appManager.appBundleDetail", locale: locale, DashboardFormat.bytes(app.sizeBytes, locale: locale)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusPill(text: L10n.safetyLevel(.reviewRequired, locale: locale), color: LexTheme.caution)
        }
        .padding(.vertical, 5)
    }
}

private struct ResidualRow: View {
    let candidate: AppResidualCandidate
    @ObservedObject var model: AppManagerViewModel
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: Binding(get: { model.isSelected(candidate) }, set: { model.setSelected($0, for: candidate) }))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(!model.canSelect(candidate))
            Image(systemName: candidate.kind == .logs ? "doc.text" : "shippingbox")
                .foregroundStyle(candidate.cleanupSafetyLevel == .reviewRequired ? LexTheme.caution : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L10n.residualKind(candidate.kind, locale: locale)).font(.body.weight(.medium))
                    StatusPill(text: L10n.safetyLevel(candidate.cleanupSafetyLevel, locale: locale), color: candidate.cleanupSafetyLevel == .reviewRequired ? LexTheme.caution : .secondary)
                    StatusPill(text: L10n.confidence(candidate.confidence, locale: locale), color: .secondary)
                }
                Text(candidate.path.path).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                Text(L10n.format("appManager.residualDetail", locale: locale, DashboardFormat.bytes(candidate.sizeBytes, locale: locale), L10n.reason(candidate.cleanupReason, locale: locale)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(L10n.residualReason(candidate, locale: locale)).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

private struct MetadataGrid: View {
    let rows: [(LocalizedStringKey, String)]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    Text(row.0).font(.caption).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                    Text(row.1).font(.caption.monospaced()).textSelection(.enabled).lineLimit(2)
                }
            }
        }
        .padding(.top, 4)
    }
}

private struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.11), in: Capsule())
    }
}

private struct AppManagerCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(LexTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.07)) }
    }
}
