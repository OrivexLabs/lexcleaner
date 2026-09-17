import LexCleanerCore
import SwiftUI

struct CleanerView: View {
    @ObservedObject var model: CleanerViewModel
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                statisticsGrid
                statusPanel
                candidateList
                actionPanel
                executionPanel
            }
            .padding(28)
        }
        .background(LexTheme.canvas)
        .alert("cleaner.confirmTitle", isPresented: $model.isConfirmationPresented) {
            Button("common.cancel", role: .cancel) {}
            Button("cleaner.moveToTrash", role: .destructive) {
                model.executeAfterConfirmation()
            }
        } message: {
            Text(confirmationMessage)
        }
        .alert("cleaner.highRiskTitle", isPresented: $model.isHighRiskConfirmationPresented) {
            Button("common.cancel", role: .cancel) {}
            Button("cleaner.highRiskContinue") {
                model.continueAfterHighRiskConfirmation()
            }
        } message: {
            Text(highRiskConfirmationMessage)
        }
        .onDisappear { model.stop() }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("cleaner.title")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("cleaner.subtitle")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.phase == .scanning {
                Button("cleaner.cancelScan", role: .cancel) { model.cancel() }
            } else {
                Button(model.phase == .idle ? L10n.string("cleaner.startScan", locale: locale) : L10n.string("cleaner.rescan", locale: locale)) {
                    model.startScan()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canStartScan)
            }
        }
    }

    private var statisticsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
            CleanerStatCard(title: L10n.safetyLevel(.safe, locale: locale), count: model.statistics?.safeCount, bytes: model.statistics?.safeBytes, color: LexTheme.positive, symbol: "checkmark.shield", locale: locale)
            CleanerStatCard(title: L10n.safetyLevel(.reviewRequired, locale: locale), count: model.statistics?.reviewRequiredCount, bytes: model.statistics?.reviewRequiredBytes, color: LexTheme.caution, symbol: "eye", locale: locale)
            CleanerStatCard(title: L10n.safetyLevel(.protected, locale: locale), count: model.statistics?.protectedCount, bytes: model.statistics?.protectedBytes, color: .red, symbol: "lock.shield", locale: locale)
            CleanerStatCard(title: L10n.safetyLevel(.unknown, locale: locale), count: model.statistics?.unknownCount, bytes: model.statistics?.unknownBytes, color: .secondary, symbol: "questionmark.circle", locale: locale)
        }
    }

    @ViewBuilder
    private var statusPanel: some View {
        CleanerCardSurface {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(model.phase.title, systemImage: phaseSymbol)
                        .font(.headline)
                    Spacer()
                    if model.scope.isControlledFixture {
                        Label("cleaner.controlledFixture", systemImage: "testtube.2")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                }
                if let progress = model.scanProgress {
                    ProgressView(value: min(Double(progress.visitedPathCount) / 1000, 1))
                    Text(L10n.format("cleaner.scanProgress", locale: locale, String(progress.visitedPathCount), String(progress.discoveredFileCount), DashboardFormat.bytes(progress.discoveredBytes, locale: locale)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let path = progress.currentPath {
                        Text(path.path)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                } else if let scan = model.scanResult {
                    Text(L10n.format("cleaner.scanSummary", locale: locale, String(scan.fileCount), String(scan.directoryCount), String(scan.issues.count)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !scan.issues.isEmpty {
                        DisclosureGroup(L10n.string("cleaner.scanIssues", locale: locale)) {
                            ForEach(Array(scan.issues.prefix(8)), id: \.self) { issue in
                                Text("\(issue.kind.rawValue) · \(issue.path.path)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .font(.caption)
                    }
                } else {
                    Text("cleaner.readOnlyResult")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let error = model.errorMessage {
                    Label(L10n.string(error, locale: locale), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private var candidateList: some View {
        if model.candidates.isEmpty {
            CleanerCardSurface {
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        model.phase == .idle ? L10n.string("cleaner.emptyTitle", locale: locale) : (model.phase == .scanning ? L10n.string("cleaner.scanningTitle", locale: locale) : L10n.string("cleaner.noCandidatesTitle", locale: locale)),
                        systemImage: model.phase == .scanning ? "magnifyingglass" : "tray"
                    )
                        .font(.headline)
                    Text(model.phase == .idle ? L10n.string("cleaner.startReadOnly", locale: locale) : (model.phase == .scanning ? L10n.string("cleaner.resultsAfterScan", locale: locale) : L10n.string("cleaner.noVisibleItems", locale: locale)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("cleaner.candidates").font(.title3.weight(.semibold))
                    Spacer()
                    Text(L10n.format("cleaner.selectedCount", locale: locale, String(model.selectableSelectedCount)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(CleanupSafetyLevel.allCases, id: \.self) { safetyLevel in
                        let groups = model.groups(for: safetyLevel)
                        if !groups.isEmpty {
                            CleanerSafetySection(safetyLevel: safetyLevel, groups: groups, model: model)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var actionPanel: some View {
        if model.phase == .ready {
            HStack {
                Text("cleaner.selectionHint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("cleaner.planDryRun") { model.createDryRun() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.selectableSelectedCount == 0)
            }
        } else if model.phase == .dryRun, let dryRun = model.dryRun {
            CleanerCardSurface {
                VStack(alignment: .leading, spacing: 10) {
                    Label("cleaner.dryRunTitle", systemImage: "eye")
                        .font(.headline)
                    Text(L10n.format("cleaner.dryRunSummary", locale: locale, String(dryRun.processCount), DashboardFormat.bytes(dryRun.processBytes, locale: locale), String(dryRun.rejectedCount)))
                        .font(.callout)
                    if let plan = model.plan {
                        Text(L10n.format("cleaner.planID", locale: locale, plan.planID.uuidString))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                    Button("cleaner.confirmContinue") { model.confirmAndExecute() }
                        .buttonStyle(.borderedProminent)
                        .disabled(dryRun.processCount == 0)
                }
            }
        }
    }

    @ViewBuilder
    private var executionPanel: some View {
        if model.phase == .preflighting || model.phase == .executing {
            CleanerCardSurface {
                Label(model.phase.title, systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)
                ProgressView().padding(.top, 4)
                if let preflight = model.preflight {
                    Text(L10n.format("cleaner.preflightSummary", locale: locale, String(preflight.items.filter { $0.status == .passed }.count), String(preflight.items.filter { $0.status == .rejected }.count)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else if (model.phase == .completed || model.phase == .failed), let execution = model.execution {
            CleanerCardSurface {
                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.string(model.phase == .failed ? "cleaner.phase.failed" : "cleaner.auditRecorded", locale: locale), systemImage: model.phase == .failed ? "exclamationmark.triangle" : "checkmark.seal")
                        .font(.headline)
                    let success = execution.items.filter { $0.status == .success }.count
                    let skipped = execution.items.filter { $0.status == .skipped }.count
                    let failed = execution.items.filter { $0.status == .failed || $0.status == .rejected }.count
                    Text(L10n.format("cleaner.executionSummary", locale: locale, String(success), String(skipped), String(failed), DashboardFormat.bytes(execution.reclaimedBytes, locale: locale)))
                        .font(.callout)
                    Text(L10n.format("cleaner.auditEntries", locale: locale, String(execution.audit.count)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(execution.items.filter { $0.status != .success }, id: \.candidateIdentity) { item in
                        Text(L10n.format("cleaner.failureDetail", locale: locale, item.path.path, item.failureReason.map { L10n.string("failure.\($0.rawValue)", locale: locale) } ?? L10n.string("safety.unknown", locale: locale)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var confirmationMessage: String {
        guard let dryRun = model.dryRun else { return "" }
        return L10n.format("cleaner.confirmMessage", locale: locale, String(dryRun.processCount), DashboardFormat.bytes(dryRun.processBytes, locale: locale))
    }

    private var highRiskConfirmationMessage: String {
        L10n.format(
            "cleaner.highRiskMessage",
            locale: locale,
            String(model.highRiskSelectedCount),
            DashboardFormat.bytes(model.highRiskSelectedBytes, locale: locale)
        )
    }

    private var phaseSymbol: String {
        switch model.phase {
        case .idle: return "pause.circle"
        case .scanning: return "magnifyingglass"
        case .ready: return "checkmark.circle"
        case .planning, .preflighting, .executing: return "arrow.triangle.2.circlepath"
        case .dryRun: return "eye"
        case .completed: return "checkmark.seal"
        case .cancelled: return "xmark.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }
}

private struct CleanerSafetySection: View {
    let safetyLevel: CleanupSafetyLevel
    let groups: [CleanerCandidateGroup]
    @ObservedObject var model: CleanerViewModel
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(L10n.safetyLevel(safetyLevel, locale: locale), systemImage: symbol)
                    .font(.headline)
                    .foregroundStyle(color)
                Spacer()
                Text(L10n.format("cleaner.groupCount", locale: locale, String(groups.count)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(groups) { group in
                    CleanerCandidateGroupView(group: group, model: model)
                }
            }
        }
    }

    private var symbol: String {
        switch safetyLevel {
        case .safe: return "checkmark.shield"
        case .reviewRequired: return "eye"
        case .protected: return "lock.shield"
        case .unknown: return "questionmark.circle"
        }
    }

    private var color: Color {
        switch safetyLevel {
        case .safe: return LexTheme.positive
        case .reviewRequired: return LexTheme.caution
        case .protected: return .red
        case .unknown: return .secondary
        }
    }
}

private struct CleanerCandidateGroupView: View {
    let group: CleanerCandidateGroup
    @ObservedObject var model: CleanerViewModel
    @Environment(\.locale) private var locale

    var body: some View {
        CleanerCardSurface {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Button {
                        model.toggleGroup(group)
                    } label: {
                        Image(systemName: selectionSymbol)
                            .font(.title3)
                            .foregroundStyle(selectionColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.selectionState(for: group) == .disabled)
                    .accessibilityLabel(L10n.string("cleaner.groupToggle", locale: locale))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(groupTitle)
                            .font(.subheadline.weight(.semibold))
                        Text(L10n.format("cleaner.groupMetadata", locale: locale, appTitle, categoryTitle, ruleTitle))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(L10n.format("cleaner.groupItems", locale: locale, String(group.candidates.count), DashboardFormat.bytes(group.totalBytes, locale: locale)))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                    if model.selectionState(for: group) != .disabled {
                        Text(selectionActionTitle)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(group.candidates, id: \.path) { candidate in
                        CandidateRow(candidate: candidate, model: model)
                    }
                }
                .padding(.leading, 28)
            }
        }
    }

    private var groupTitle: String {
        appTitle == L10n.string("detail.unrecognized", locale: locale) ? categoryTitle : appTitle
    }

    private var appTitle: String {
        group.key.owningApp ?? L10n.string("detail.unrecognized", locale: locale)
    }

    private var categoryTitle: String { L10n.category(group.key.category, locale: locale) }
    private var ruleTitle: String { L10n.rule(group.key.rule, locale: locale) }

    private var selectionActionTitle: String {
        switch model.selectionState(for: group) {
        case .allSelected: return L10n.string("cleaner.deselectGroup", locale: locale)
        case .partiallySelected: return L10n.string("cleaner.groupMixed", locale: locale)
        case .noneSelected: return L10n.string("cleaner.selectGroup", locale: locale)
        case .disabled: return ""
        }
    }

    private var selectionSymbol: String {
        switch model.selectionState(for: group) {
        case .allSelected: return "checkmark.square.fill"
        case .partiallySelected: return "minus.square.fill"
        case .noneSelected: return "square"
        case .disabled: return "lock.square"
        }
    }

    private var selectionColor: Color {
        model.selectionState(for: group) == .disabled ? .secondary : LexTheme.accent
    }
}

private struct CleanerCardSurface<Content: View>: View {
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

private struct CleanerStatCard: View {
    let title: String
    let count: UInt64?
    let bytes: UInt64?
    let color: Color
    let symbol: String
    let locale: Locale

    var body: some View {
        CleanerCardSurface {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .frame(width: 30, height: 30)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Text(count.map(String.init) ?? "—").font(.title3.weight(.bold).monospacedDigit())
                    Text(DashboardFormat.bytes(bytes, locale: locale)).font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct CandidateRow: View {
    let candidate: CleanerCandidate
    @ObservedObject var model: CleanerViewModel
    @Environment(\.locale) private var locale

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 5) {
                detail(L10n.string("detail.category", locale: locale), L10n.category(candidate.category, locale: locale))
                detail(L10n.string("detail.rule", locale: locale), L10n.rule(candidate.matchedRule, locale: locale))
                detail(L10n.string("detail.reason", locale: locale), L10n.reason(candidate.cleanupReason, locale: locale))
                detail(L10n.string("detail.modified", locale: locale), candidate.modifiedAt?.formatted() ?? L10n.string("detail.unavailable", locale: locale))
                detail(L10n.string("detail.owningApp", locale: locale), candidate.owningApp ?? L10n.string("detail.unrecognized", locale: locale))
                detail(L10n.string("detail.reclaimable", locale: locale), DashboardFormat.bytes(candidate.estimatedReclaimableBytes, locale: locale))
            }
            .padding(.leading, 30)
            .padding(.vertical, 5)
        } label: {
            HStack(spacing: 10) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { model.isSelected(candidate) },
                        set: { model.setSelected($0, for: candidate) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(!model.canSelect(candidate))
                Image(systemName: icon)
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.path.path)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(L10n.category(candidate.category, locale: locale))
                        Text(L10n.reason(candidate.cleanupReason, locale: locale))
                        Text(DashboardFormat.bytes(candidate.size, locale: locale))
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(L10n.safetyLevel(candidate.safetyLevel, locale: locale))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color)
            }
            .padding(10)
            .background(LexTheme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var icon: String {
        switch candidate.safetyLevel {
        case .safe: return "checkmark.shield"
        case .reviewRequired: return "eye"
        case .protected: return "lock.shield"
        case .unknown: return "questionmark.circle"
        }
    }

    private var color: Color {
        switch candidate.safetyLevel {
        case .safe: return LexTheme.positive
        case .reviewRequired: return LexTheme.caution
        case .protected: return .red
        case .unknown: return .secondary
        }
    }

    private func detail(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.caption2).foregroundStyle(.tertiary).frame(width: 80, alignment: .leading)
            Text(value).font(.caption2.monospaced()).textSelection(.enabled)
        }
    }
}
