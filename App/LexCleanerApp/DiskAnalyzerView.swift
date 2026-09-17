import LexCleanerCore
import SwiftUI

struct DiskAnalyzerView: View {
    @ObservedObject var model: DiskAnalyzerViewModel
    @Environment(\.locale) private var locale
    @State private var showsCapacityDetails = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                header
                volumeOverview
                treemapSection
                contentTypeSection
                largeFilesSection
                issuesSection
            }
            .padding(28)
        }
        .background(LexTheme.canvas)
        .task { model.startIfNeeded() }
        .onDisappear { model.deactivate() }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("diskAnalyzer.title")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("diskAnalyzer.subtitle")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            HStack(spacing: 10) {
                Label(model.phase.titleKey, systemImage: phaseSymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(model.isScanning ? LexTheme.accent : .secondary)
                if model.isScanning {
                    Button("diskAnalyzer.cancel", action: model.cancel)
                        .buttonStyle(.bordered)
                } else {
                    Button("diskAnalyzer.scanAgain", action: model.scan)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var phaseSymbol: String {
        switch model.phase {
        case .idle: return "circle"
        case .scanning: return "arrow.triangle.2.circlepath"
        case .enriching: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle"
        case .cancelled: return "pause.circle"
        case .failed: return "exclamationmark.circle"
        }
    }

    @ViewBuilder
    private var volumeOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 185), spacing: 12)], spacing: 12) {
                DiskSummaryCard(title: L10n.string("diskAnalyzer.volume.total", locale: locale), value: DashboardFormat.bytes(model.volume?.totalBytes, locale: locale), symbol: "internaldrive", tint: LexTheme.accent)
                DiskSummaryCard(title: L10n.string("diskAnalyzer.volume.actualScanned", locale: locale), value: DashboardFormat.bytes(model.scannedAllocatedBytes, locale: locale), symbol: "internaldrive.fill", tint: .orange, detail: L10n.string("diskAnalyzer.volume.actualScannedDetail", locale: locale))
                DiskSummaryCard(title: L10n.string("diskAnalyzer.volume.available", locale: locale), value: DashboardFormat.bytes(model.volume?.availableBytes, locale: locale), symbol: "checkmark.circle.fill", tint: LexTheme.positive)
            }

            DisclosureGroup(isExpanded: $showsCapacityDetails) {
                VStack(alignment: .leading, spacing: 8) {
                    capacityDetailRow(
                        title: L10n.string("diskAnalyzer.volume.logicalSize", locale: locale),
                        value: DashboardFormat.bytes(model.scannedLogicalBytes, locale: locale)
                    )
                    capacityDetailRow(
                        title: L10n.string("diskAnalyzer.volume.scanCoverage", locale: locale),
                        value: L10n.format("diskAnalyzer.scannedDetail", locale: locale, String(model.scannedFileCount), String(model.scannedDirectoryCount))
                    )
                    Text(L10n.string("diskAnalyzer.volume.logicalSizeExplanation", locale: locale))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if model.allocationStatus == .filesystemReportedSharedExtentsUnknown {
                        Text(L10n.string("diskAnalyzer.volume.apfsLimitation", locale: locale))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 8)
            } label: {
                Label(
                    L10n.string("diskAnalyzer.volume.details", locale: locale),
                    systemImage: "info.circle"
                )
                .font(.subheadline.weight(.medium))
            }
            .tint(.secondary)
        }
    }

    private func capacityDetailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout.monospacedDigit())
        }
    }

    private var treemapSection: some View {
        DiskPanel(title: L10n.string("diskAnalyzer.treemap.title", locale: locale), subtitle: L10n.format("diskAnalyzer.treemap.scope", locale: locale, model.scanRoot.path), symbol: "square.grid.3x3.fill") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Button(L10n.string("diskAnalyzer.treemap.root", locale: locale), action: model.goToRoot)
                        .buttonStyle(.link)
                    if model.currentDirectory?.standardizedFileURL.path != model.scanRoot.path {
                        Text("/").foregroundStyle(.tertiary)
                        Button(model.currentDirectoryName, action: model.goToParent)
                            .buttonStyle(.link)
                    }
                    Spacer()
                    Text(L10n.string("diskAnalyzer.treemap.clickToOpen", locale: locale))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if model.treemapNodes.isEmpty {
                    DiskEmptyState(title: "diskAnalyzer.treemap.empty", detail: "diskAnalyzer.treemap.emptyDetail", symbol: "square.grid.3x3")
                        .frame(minHeight: 270)
                } else {
                    DiskTreemap(nodes: model.treemapNodes) { node in
                        model.enter(node)
                    }
                    .frame(minHeight: 300, idealHeight: 350, maxHeight: 480)
                }
                HStack(spacing: 14) {
                    Label("diskAnalyzer.treemap.directory", systemImage: "folder.fill")
                    Label("diskAnalyzer.treemap.largeFile", systemImage: "doc.fill")
                    Text(L10n.format("diskAnalyzer.treemap.nodeCount", locale: locale, String(model.treemapNodes.count)))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var contentTypeSection: some View {
        DiskPanel(title: L10n.string("diskAnalyzer.types.title", locale: locale), subtitle: L10n.string("diskAnalyzer.types.subtitle", locale: locale), symbol: "doc.on.doc") {
            if model.contentStatistics.isEmpty {
                DiskEmptyState(title: "diskAnalyzer.types.waiting", detail: "diskAnalyzer.types.waitingDetail", symbol: "chart.bar.xaxis")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(DiskContentCategory.allCases, id: \.self) { category in
                        let stats = model.contentStatistics[category]
                        VStack(alignment: .leading, spacing: 6) {
                            Label(L10n.string("diskAnalyzer.type.\(category.rawValue)", locale: locale), systemImage: contentSymbol(category))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text(L10n.format("diskAnalyzer.type.logical", locale: locale, DashboardFormat.bytes(stats?.totalBytes, locale: locale)))
                                .font(.headline.monospacedDigit())
                            Text(L10n.format("diskAnalyzer.type.actual", locale: locale, DashboardFormat.bytes(stats?.allocatedBytes, locale: locale)))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(L10n.format("diskAnalyzer.type.files", locale: locale, String(stats?.fileCount ?? 0)))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(LexTheme.canvas, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    private func contentSymbol(_ category: DiskContentCategory) -> String {
        switch category {
        case .documents: return "doc.text"
        case .images: return "photo"
        case .videos: return "film"
        case .audio: return "waveform"
        case .archives: return "archivebox"
        case .development: return "chevron.left.forwardslash.chevron.right"
        case .other: return "doc"
        }
    }

    private var largeFilesSection: some View {
        DiskPanel(
            title: L10n.string("diskAnalyzer.largeFiles.title", locale: locale),
            subtitle: L10n.format(
                "diskAnalyzer.largeFiles.subtitle",
                locale: locale,
                "100",
                DashboardFormat.bytes(50 * 1024 * 1024, locale: locale)
            ),
            symbol: "arrow.up.right.and.arrow.down.left.rectangle"
        ) {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    TextField(L10n.string("diskAnalyzer.largeFiles.search", locale: locale), text: $model.searchText)
                        .textFieldStyle(.roundedBorder)
                    Picker(L10n.string("diskAnalyzer.largeFiles.filter", locale: locale), selection: $model.contentFilter) {
                        ForEach(DiskContentFilter.allCases) { filter in
                            Text(filter.titleKey).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                    Picker(L10n.string("diskAnalyzer.largeFiles.sort", locale: locale), selection: $model.sortOrder) {
                        ForEach(DiskLargeFileSort.allCases) { sort in
                            Text(sort.titleKey).tag(sort)
                        }
                    }
                    .pickerStyle(.menu)
                }
                if model.filteredLargeFileEntries.isEmpty {
                    DiskEmptyState(title: "diskAnalyzer.largeFiles.empty", detail: "diskAnalyzer.largeFiles.emptyDetail", symbol: "doc.text.magnifyingglass")
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.filteredLargeFileEntries.prefix(100)), id: \.canonicalPath) { entry in
                            LargeFileRow(entry: entry, locale: locale)
                            if entry.canonicalPath != model.filteredLargeFileEntries.prefix(100).last?.canonicalPath {
                                Divider()
                            }
                        }
                    }
                    .background(LexTheme.canvas, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    @ViewBuilder
    private var issuesSection: some View {
        if !model.issues.isEmpty {
            DiskPanel(title: L10n.string("diskAnalyzer.issues.title", locale: locale), subtitle: L10n.format("diskAnalyzer.issues.count", locale: locale, String(model.issueCount)), symbol: "exclamationmark.triangle") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(model.issues.prefix(12)), id: \.self) { issue in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.string("diskAnalyzer.issue.\(issue.kind.rawValue)", locale: locale))
                                .font(.caption.weight(.semibold))
                            Text(issue.path.path)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(issue.detail)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Divider()
                    }
                    if model.issueCount > 12 {
                        Text(L10n.format("diskAnalyzer.issues.more", locale: locale, String(model.issueCount - 12)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct DiskSummaryCard: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color
    var detail: String?

    init(title: String, value: String, symbol: String, tint: Color, detail: String? = nil) {
        self.title = title
        self.value = value
        self.symbol = symbol
        self.tint = tint
        self.detail = detail
    }

    var body: some View {
        DiskCardSurface {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Text(value).font(.headline.monospacedDigit())
                    if let detail { Text(detail).font(.caption2).foregroundStyle(.tertiary) }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct DiskPanel<Content: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Label(title, systemImage: symbol).font(.headline)
                Spacer()
                Text(subtitle).font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.trailing)
            }
            content()
        }
        .padding(16)
        .background(LexTheme.card, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct DiskEmptyState: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let symbol: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(26)
    }
}

private struct LargeFileRow: View {
    let entry: LargeFileEntry
    let locale: Locale

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.fileType == .regularFile ? "doc" : "folder")
                .foregroundStyle(LexTheme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.path.lastPathComponent)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(entry.path.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(L10n.format("diskAnalyzer.largeFiles.actual", locale: locale, DashboardFormat.bytes(entry.allocatedSizeBytes, locale: locale)))
                    .font(.callout.monospacedDigit())
                Text(L10n.format("diskAnalyzer.largeFiles.logical", locale: locale, DashboardFormat.bytes(entry.sizeBytes, locale: locale)))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(entry.lastModified.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? L10n.string("common.notAvailable", locale: locale))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .help(entry.path.path)
    }
}

private struct DiskCardSurface<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(14)
            .background(LexTheme.card, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct DiskTreemap: View {
    let nodes: [TreemapNode]
    let onOpen: (TreemapNode) -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        GeometryReader { geometry in
            let rectangles = DiskTreemapLayout.layout(nodes: nodes, size: geometry.size)
            ZStack(alignment: .topLeading) {
                ForEach(rectangles) { item in
                    Button {
                        onOpen(item.node)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            if item.rect.width > 76 && item.rect.height > 42 {
                                Image(systemName: item.node.category == .directory ? "folder.fill" : "doc.fill")
                                    .font(.caption)
                                Text(item.node.name)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(2)
                                Text(L10n.format("diskAnalyzer.treemap.actual", locale: locale, DashboardFormat.bytes(item.node.allocatedSizeBytes, locale: locale)))
                                    .font(.caption2.monospacedDigit())
                                    .opacity(0.85)
                                Text(L10n.format("diskAnalyzer.treemap.logical", locale: locale, DashboardFormat.bytes(item.node.sizeBytes, locale: locale)))
                                    .font(.caption2.monospacedDigit())
                                    .opacity(0.7)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(7)
                        .foregroundStyle(.white)
                        .background(DiskTreemapColor.color(for: item.node))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .frame(width: item.rect.width, height: item.rect.height)
                    .position(x: item.rect.midX, y: item.rect.midY)
                    .help(item.node.path.path)
                }
            }
            .clipped()
        }
        .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct DiskTreemapItem: Identifiable {
    let node: TreemapNode
    let rect: CGRect
    var id: String { node.id }
}

private enum DiskTreemapLayout {
    static func layout(nodes: [TreemapNode], size: CGSize) -> [DiskTreemapItem] {
        guard size.width > 1, size.height > 1 else { return [] }
        let sorted = nodes.filter { $0.allocatedSizeBytes > 0 }.sorted { $0.allocatedSizeBytes > $1.allocatedSizeBytes }
        guard !sorted.isEmpty else { return [] }
        return partition(sorted, rect: CGRect(origin: .zero, size: size), horizontal: size.width >= size.height)
    }

    private static func partition(_ nodes: [TreemapNode], rect: CGRect, horizontal: Bool) -> [DiskTreemapItem] {
        guard nodes.count > 1 else { return nodes.map { DiskTreemapItem(node: $0, rect: rect.insetBy(dx: 2, dy: 2)) } }
        let total = Double(nodes.reduce(0) { $0 &+ $1.allocatedSizeBytes })
        guard total > 0 else { return [] }
        let half = total / 2
        var running = 0.0
        var split = 1
        for index in nodes.indices {
            running += Double(nodes[index].allocatedSizeBytes)
            if running >= half { split = max(1, index + 1); break }
        }
        split = min(split, nodes.count - 1)
        let first = Array(nodes[..<split])
        let second = Array(nodes[split...])
        let firstBytes = Double(first.reduce(0) { $0 &+ $1.allocatedSizeBytes })
        let fraction = max(0.08, min(0.92, firstBytes / total))
        if horizontal {
            let firstRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width * fraction, height: rect.height)
            let secondRect = CGRect(x: firstRect.maxX, y: rect.minY, width: rect.width - firstRect.width, height: rect.height)
            return partition(first, rect: firstRect, horizontal: !horizontal) + partition(second, rect: secondRect, horizontal: !horizontal)
        } else {
            let firstRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * fraction)
            let secondRect = CGRect(x: rect.minX, y: firstRect.maxY, width: rect.width, height: rect.height - firstRect.height)
            return partition(first, rect: firstRect, horizontal: !horizontal) + partition(second, rect: secondRect, horizontal: !horizontal)
        }
    }
}

private enum DiskTreemapColor {
    static func color(for node: TreemapNode) -> Color {
        if node.isLargeFile { return .purple.opacity(0.86) }
        let palette: [Color] = [.blue, .teal, .indigo, .orange, .green, .pink, .cyan]
        let hash = node.name.utf8.reduce(0) { ($0 &* 31) &+ Int($1) }
        return palette[abs(hash) % palette.count].opacity(0.82)
    }
}
