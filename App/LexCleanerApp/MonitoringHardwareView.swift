import Foundation
import SwiftUI
import LexCleanerCore

struct MonitoringDashboardView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @StateObject private var model = MonitoringDashboardModel()
    @AppStorage("lexcleaner.appearance") private var appearanceRawValue = AppearanceMode.system.rawValue
    @State private var selectedSection: DashboardSection = .overview

    private var copy: DashboardCopy { DashboardCopy(locale: locale) }
    private var appearance: AppearanceMode { AppearanceMode(rawValue: appearanceRawValue) ?? .system }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selectedSection: $selectedSection, copy: copy)
                .frame(width: 224)

            Divider()

            VStack(spacing: 0) {
                DashboardHeader(
                    copy: copy,
                    isSampling: model.isSampling,
                    lastUpdated: model.lastUpdated,
                    refreshRate: model.refreshRate,
                    appearance: appearance,
                    onRefreshRateChange: model.updateRefreshRate,
                    onAppearanceChange: { appearanceRawValue = $0.rawValue }
                )

                Divider()

                ScrollView {
                    DashboardContentView(
                        section: selectedSection,
                        copy: copy,
                        monitoring: model.monitoring,
                        hardware: model.hardware,
                        history: model.history,
                        errorMessage: model.errorMessage
                    )
                    .padding(24)
                }
                .background(Color(nsColor: .underPageBackgroundColor))
            }
        }
        .frame(minWidth: 960, minHeight: 640)
        .preferredColorScheme(appearance.colorScheme)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { model.start() } else { model.stop() }
        }
    }
}

@MainActor
private final class MonitoringDashboardModel: ObservableObject {
    @Published private(set) var monitoring: MonitoringSnapshot?
    @Published private(set) var hardware: HardwareSnapshot?
    @Published private(set) var history = MonitoringHistory()
    @Published private(set) var isSampling = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var refreshRate: RefreshRate = .balanced

    private var monitoringTask: Task<Void, Never>?
    private var hardwareTask: Task<Void, Never>?

    deinit {
        monitoringTask?.cancel()
        hardwareTask?.cancel()
    }

    func start() {
        guard monitoringTask == nil, hardwareTask == nil else { return }

        do {
            let monitoringConfiguration = try MonitoringSamplingConfiguration(interval: refreshRate.interval, processLimit: 24)
            let hardwareConfiguration = try HardwareSamplingConfiguration(interval: max(1, refreshRate.interval))
            let monitoringSampler = MonitoringSampler(configuration: monitoringConfiguration)
            let hardwareSampler = HardwareSampler(configuration: hardwareConfiguration)

            errorMessage = nil
            isSampling = true
            monitoringTask = Task { [weak self] in
                do {
                    for try await snapshot in monitoringSampler.snapshots() {
                        guard !Task.isCancelled else { return }
                        self?.receive(snapshot)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    self?.receive(error: error)
                }
            }
            hardwareTask = Task { [weak self] in
                do {
                    for try await snapshot in hardwareSampler.snapshots() {
                        guard !Task.isCancelled else { return }
                        self?.receive(snapshot)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    self?.receive(error: error)
                }
            }
        } catch {
            isSampling = false
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        monitoringTask?.cancel()
        hardwareTask?.cancel()
        monitoringTask = nil
        hardwareTask = nil
        isSampling = false
    }

    func updateRefreshRate(_ value: RefreshRate) {
        guard value != refreshRate else { return }
        let wasSampling = isSampling
        stop()
        refreshRate = value
        if wasSampling { start() }
    }

    private func receive(_ snapshot: MonitoringSnapshot) {
        monitoring = snapshot
        lastUpdated = snapshot.timestamp
        history.append(snapshot)
    }

    private func receive(_ snapshot: HardwareSnapshot) {
        hardware = snapshot
        lastUpdated = max(lastUpdated ?? snapshot.timestamp, snapshot.timestamp)
    }

    private func receive(error: Error) {
        errorMessage = error.localizedDescription
        isSampling = false
    }
}

private enum DashboardSection: String, CaseIterable, Identifiable {
    case overview, cpu, memory, disk, network, processes, thermal, hardware, battery, storage
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: return "rectangle.grid.2x2"
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .disk: return "internaldrive"
        case .network: return "network"
        case .processes: return "list.bullet.rectangle"
        case .thermal: return "thermometer.medium"
        case .hardware: return "desktopcomputer"
        case .battery: return "battery.100"
        case .storage: return "externaldrive"
        }
    }
}

private enum RefreshRate: String, CaseIterable, Identifiable {
    case slow, balanced, fast
    var id: String { rawValue }
    var interval: TimeInterval {
        switch self { case .slow: return 5; case .balanced: return 2; case .fast: return 1 }
    }
}

private enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
}

private struct MonitoringHistory {
    struct Sample: Identifiable {
        let id = UUID()
        let timestamp: Date
        let cpu: Double
        let memory: Double
        let diskRead: Double
        let diskWrite: Double
        let download: Double
        let upload: Double
    }

    private(set) var samples: [Sample] = []
    private let limit = 60

    mutating func append(_ snapshot: MonitoringSnapshot) {
        let physical = max(1, snapshot.memory.physicalMemoryBytes)
        samples.append(Sample(timestamp: snapshot.timestamp,
                              cpu: snapshot.cpu.totalUsagePercent,
                              memory: Double(snapshot.memory.usedMemoryBytes) / Double(physical) * 100,
                              diskRead: snapshot.disk.readBytesPerSecond,
                              diskWrite: snapshot.disk.writeBytesPerSecond,
                              download: snapshot.network.downloadBytesPerSecond,
                              upload: snapshot.network.uploadBytesPerSecond))
        if samples.count > limit { samples.removeFirst(samples.count - limit) }
    }
}

private struct DashboardCopy {
    let locale: Locale

    private func text(_ key: String) -> String {
        L10n.string("dashboard.monitoring.\(key)", locale: locale)
    }

    var appTitle: String { text("title") }
    var overview: String { L10n.string("navigation.dashboard", locale: locale) }
    var monitoring: String { L10n.string("navigation.monitoring", locale: locale) }
    var hardware: String { L10n.string("navigation.hardware", locale: locale) }
    var cpu: String { "CPU" }
    var memory: String { L10n.string("metric.memory", locale: locale) }
    var disk: String { L10n.string("metric.disk", locale: locale) }
    var network: String { L10n.string("metric.network", locale: locale) }
    var processes: String { text("processes") }
    var thermal: String { L10n.string("metric.thermal", locale: locale) }
    var hardwareInfo: String { text("hardwareInfo") }
    var battery: String { text("battery") }
    var storage: String { text("storage") }
    var live: String { L10n.string("dashboard.live", locale: locale) }
    var paused: String { text("paused") }
    var refresh: String { L10n.string("systemTools.refresh", locale: locale) }
    var appearance: String { L10n.string("systemTools.appearance", locale: locale) }
    var automatic: String { L10n.string("systemTools.systemDefault", locale: locale) }
    var light: String { L10n.string("systemTools.light", locale: locale) }
    var dark: String { L10n.string("systemTools.dark", locale: locale) }
    var cpuUsage: String { text("usage") }
    var user: String { L10n.string("metric.user", locale: locale) }
    var system: String { L10n.string("metric.system", locale: locale) }
    var idle: String { L10n.string("metric.idle", locale: locale) }
    var available: String { L10n.string("metric.free", locale: locale) }
    var wired: String { text("wired") }
    var compressed: String { text("compressed") }
    var pressure: String { text("pressure") }
    var read: String { text("read") }
    var write: String { text("write") }
    var download: String { text("download") }
    var upload: String { text("upload") }
    var topProcesses: String { text("topProcesses") }
    var pid: String { "PID" }
    var process: String { text("process") }
    var memoryShort: String { L10n.string("metric.memory", locale: locale) }
    var state: String { text("state") }
    var lowPowerMode: String { text("lowPowerMode") }
    var sensors: String { text("sensors") }
    var fans: String { text("fans") }
    var power: String { text("power") }
    var model: String { text("model") }
    var appleSilicon: String { "Apple Silicon" }
    var cores: String { text("cores") }
    var performanceCores: String { text("performanceCores") }
    var efficiencyCores: String { text("efficiencyCores") }
    var physicalMemory: String { text("physicalMemory") }
    var powerSource: String { text("powerSource") }
    var charging: String { text("charging") }
    var notCharging: String { text("notCharging") }
    var cycleCount: String { text("cycleCount") }
    var health: String { text("health") }
    var devices: String { text("devices") }
    var internalDisk: String { text("internalDisk") }
    var externalDisk: String { text("externalDisk") }
    var apfsContainer: String { "APFS Container" }
    var volumes: String { text("volumes") }
    var advanced: String { text("advanced") }
    var sharedCapacity: String { text("sharedCapacity") }
    var noPhysicalDisks: String { text("noPhysicalDisks") }
    var unknownVolume: String { text("unknownVolume") }
    var smart: String { "SMART" }
    var wear: String { text("wear") }
    var unavailable: String { text("unavailable") }
    var noData: String { text("noData") }
    var unsupported: String { text("unsupported") }
    var error: String { text("error") }
    var lastUpdated: String { text("lastUpdated") }
    var source: String { text("source") }
    var sourceValue: String { text("sourceValue") }
    var yes: String { text("yes") }
    var no: String { text("no") }
    var on: String { text("on") }
    var off: String { text("off") }

    func diagnosticDetail(_ value: String?) -> String? {
        guard let value else { return nil }
        switch value {
        case "no power sources reported by this Mac":
            return text("diagnostic.noPowerSource")
        case "SMART/wear is not exposed through a stable product-level public API":
            return text("diagnostic.smartWearUnsupported")
        case "storage wear is not exposed through a stable product-level public API":
            return text("diagnostic.storageWearUnsupported")
        default:
            return value
        }
    }

    func refreshRate(_ rate: RefreshRate) -> String {
        switch rate {
        case .slow: return text("refreshRate.slow")
        case .balanced: return text("refreshRate.balanced")
        case .fast: return text("refreshRate.fast")
        }
    }

    func availability(_ value: HardwareAvailability) -> String {
        switch value {
        case .available: return text("availability.available")
        case .unavailable: return unavailable
        case .unsupported: return unsupported
        }
    }

    func pressure(_ value: MemoryPressureLevel) -> String {
        switch value {
        case .normal: return text("pressure.normal")
        case .warning: return text("pressure.warning")
        case .critical: return text("pressure.critical")
        case .unknown: return text("pressure.unknown")
        }
    }

    func thermal(_ value: ThermalState?) -> String {
        guard let value else { return unavailable }
        switch value {
        case .nominal: return text("thermal.nominal")
        case .fair: return text("thermal.fair")
        case .serious: return text("thermal.serious")
        case .critical: return text("thermal.critical")
        }
    }

    func powerSource(_ value: PowerSourceKind?) -> String {
        guard let value else { return unavailable }
        switch value {
        case .internalBattery: return text("powerSource.internalBattery")
        case .ac: return text("powerSource.ac")
        case .ups: return "UPS"
        case .unknown: return text("powerSource.unknown")
        }
    }

    func diskKind(_ value: StorageDiskKind) -> String {
        switch value {
        case .internalDisk: return internalDisk
        case .externalDisk: return externalDisk
        case .unknown: return text("unknownDisk")
        }
    }

    func volumeRole(_ value: StorageVolumeRole) -> String {
        switch value {
        case .system: return text("volumeRole.system")
        case .data: return text("volumeRole.data")
        case .preboot: return "Preboot"
        case .recovery: return text("volumeRole.recovery")
        case .vm: return "VM"
        case .update: return text("volumeRole.update")
        case .xART: return "xART"
        case .hardware: return text("volumeRole.hardware")
        case .other: return text("volumeRole.other")
        case .unknown: return text("volumeRole.unknown")
        }
    }
}

private struct SidebarView: View {
    @Binding var selectedSection: DashboardSection
    let copy: DashboardCopy

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg").font(.title2.weight(.semibold)).foregroundStyle(.tint)
                Text("LexCleaner").font(.title3.weight(.bold))
            }
            .padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 28)

            SidebarGroup(title: copy.monitoring) {
                SidebarItem(section: .overview, title: copy.overview, selectedSection: $selectedSection)
                SidebarItem(section: .cpu, title: copy.cpu, selectedSection: $selectedSection)
                SidebarItem(section: .memory, title: copy.memory, selectedSection: $selectedSection)
                SidebarItem(section: .disk, title: copy.disk, selectedSection: $selectedSection)
                SidebarItem(section: .network, title: copy.network, selectedSection: $selectedSection)
                SidebarItem(section: .processes, title: copy.processes, selectedSection: $selectedSection)
            }
            SidebarGroup(title: copy.hardware) {
                SidebarItem(section: .thermal, title: copy.thermal, selectedSection: $selectedSection)
                SidebarItem(section: .hardware, title: copy.hardwareInfo, selectedSection: $selectedSection)
                SidebarItem(section: .battery, title: copy.battery, selectedSection: $selectedSection)
                SidebarItem(section: .storage, title: copy.storage, selectedSection: $selectedSection)
            }
            Spacer()
            Text(copy.source + ": " + copy.sourceValue).font(.caption2).foregroundStyle(.secondary).padding(18)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct SidebarGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.bottom, 4)
            content
        }.padding(.bottom, 20)
    }
}

private struct SidebarItem: View {
    let section: DashboardSection
    let title: String
    @Binding var selectedSection: DashboardSection

    var body: some View {
        Button { selectedSection = section } label: {
            Label(title, systemImage: section.symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 7).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selectedSection == section ? Color.accentColor : .primary)
        .background { if selectedSection == section { RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.12)).padding(.horizontal, 10) } }
        .padding(.horizontal, 8)
        .accessibilityLabel(title)
    }
}

private struct DashboardHeader: View {
    let copy: DashboardCopy
    let isSampling: Bool
    let lastUpdated: Date?
    let refreshRate: RefreshRate
    let appearance: AppearanceMode
    let onRefreshRateChange: (RefreshRate) -> Void
    let onAppearanceChange: (AppearanceMode) -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(copy.appTitle).font(.title2.weight(.bold))
                Text(lastUpdated.map { copy.lastUpdated + " · " + $0.formatted(date: .omitted, time: .standard) } ?? copy.noData).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 7) {
                Circle().fill(isSampling ? Color.green : Color.secondary).frame(width: 7, height: 7)
                Text(isSampling ? copy.live : copy.paused).font(.subheadline.weight(.medium))
            }.foregroundStyle(isSampling ? .green : .secondary)

            Menu {
                ForEach(RefreshRate.allCases) { rate in
                    Button { onRefreshRateChange(rate) } label: { Label(copy.refreshRate(rate), systemImage: rate == refreshRate ? "checkmark" : "") }
                }
            } label: { Label(copy.refresh + " · " + copy.refreshRate(refreshRate), systemImage: "arrow.clockwise") }
                .menuStyle(.borderlessButton)

            Menu {
                ForEach(AppearanceMode.allCases) { mode in
                    Button { onAppearanceChange(mode) } label: { Label(appearanceTitle(mode), systemImage: mode == appearance ? "checkmark" : "") }
                }
            } label: { Image(systemName: appearance == .dark ? "moon.fill" : "sun.max").frame(width: 26, height: 26) }
                .menuStyle(.borderlessButton).help(copy.appearance)
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
    }

    private func appearanceTitle(_ mode: AppearanceMode) -> String {
        switch mode { case .system: return copy.automatic; case .light: return copy.light; case .dark: return copy.dark }
    }
}

private struct DashboardContentView: View {
    let section: DashboardSection
    let copy: DashboardCopy
    let monitoring: MonitoringSnapshot?
    let hardware: HardwareSnapshot?
    let history: MonitoringHistory
    let errorMessage: String?
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let errorMessage { InlineMessage(title: copy.error, detail: errorMessage) }
            switch section {
            case .overview: overview
            case .cpu: singleCard { cpuCard }
            case .memory: singleCard { memoryCard }
            case .disk: singleCard { diskCard }
            case .network: singleCard { networkCard }
            case .processes: singleCard { processesCard }
            case .thermal: singleCard { thermalCard }
            case .hardware: singleCard { hardwareCard }
            case .battery: singleCard { batteryCard }
            case .storage: singleCard { storageCard }
            }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 285), spacing: 18)], spacing: 18) { cpuCard; memoryCard; diskCard; networkCard }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 18)], spacing: 18) { processesCard; thermalCard; hardwareCard; batteryCard; storageCard }
        }
    }

    private func singleCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View { content().frame(maxWidth: 920, alignment: .leading) }

    @ViewBuilder private var cpuCard: some View {
        if let snapshot = monitoring {
            MetricCard(title: copy.cpu, symbol: "cpu") {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) { Text(formatPercent(snapshot.cpu.totalUsagePercent, locale: locale)).font(.system(size: 34, weight: .bold, design: .rounded)); Text(copy.cpuUsage).foregroundStyle(.secondary); Spacer() }
                    TrendChart(values: history.samples.map(\.cpu), color: .blue, label: copy.cpu)
                    HStack(spacing: 16) {
                        ValuePair(label: copy.user, value: formatPercent(snapshot.cpu.userUsagePercent, locale: locale), tint: .blue)
                        ValuePair(label: copy.system, value: formatPercent(snapshot.cpu.systemUsagePercent, locale: locale), tint: .orange)
                        ValuePair(label: copy.idle, value: formatPercent(snapshot.cpu.idleUsagePercent, locale: locale), tint: .secondary)
                    }
                }
            }
        } else { LoadingCard(title: copy.cpu, symbol: "cpu", copy: copy) }
    }

    @ViewBuilder private var memoryCard: some View {
        if let snapshot = monitoring {
            let usedRatio = Double(snapshot.memory.usedMemoryBytes) / Double(max(1, snapshot.memory.physicalMemoryBytes))
            MetricCard(title: copy.memory, symbol: "memorychip") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) { Text(formatBytes(snapshot.memory.usedMemoryBytes, locale: locale)).font(.system(size: 28, weight: .bold, design: .rounded)); Text("/ " + formatBytes(snapshot.memory.physicalMemoryBytes, locale: locale)).foregroundStyle(.secondary); Spacer(); StatusPill(text: copy.pressure(snapshot.memory.pressure), tone: pressureTone(snapshot.memory.pressure)) }
                    ProgressBar(value: usedRatio, tint: .purple)
                    HStack(spacing: 16) { ValuePair(label: copy.available, value: formatBytes(snapshot.memory.availableMemoryBytes, locale: locale), tint: .green); ValuePair(label: copy.wired, value: formatBytes(snapshot.memory.wiredMemoryBytes, locale: locale), tint: .purple); ValuePair(label: copy.compressed, value: formatBytes(snapshot.memory.compressedMemoryBytes, locale: locale), tint: .orange) }
                }
            }
        } else { LoadingCard(title: copy.memory, symbol: "memorychip", copy: copy) }
    }

    @ViewBuilder private var diskCard: some View {
        if let snapshot = monitoring {
            let hasCapacity = snapshot.disk.totalBytes > 0
            MetricCard(title: copy.disk, symbol: "internaldrive") {
                VStack(alignment: .leading, spacing: 14) {
                    if hasCapacity {
                        HStack(alignment: .firstTextBaseline) { Text(formatBytes(snapshot.disk.usedBytes, locale: locale)).font(.system(size: 28, weight: .bold, design: .rounded)); Text("/ " + formatBytes(snapshot.disk.totalBytes, locale: locale)).foregroundStyle(.secondary); Spacer() }
                        ProgressBar(value: Double(snapshot.disk.usedBytes) / Double(snapshot.disk.totalBytes), tint: .teal)
                    } else { StatusPill(text: copy.unavailable, tone: .unavailable) }
                    HStack(spacing: 18) { ValuePair(label: copy.available, value: hasCapacity ? formatBytes(snapshot.disk.availableBytes, locale: locale) : copy.unavailable, tint: .green); ValuePair(label: copy.read, value: snapshot.disk.ioStatisticsAvailable ? formatRate(snapshot.disk.readBytesPerSecond, locale: locale) : copy.unavailable, tint: .blue); ValuePair(label: copy.write, value: snapshot.disk.ioStatisticsAvailable ? formatRate(snapshot.disk.writeBytesPerSecond, locale: locale) : copy.unavailable, tint: .orange) }
                }
            }
        } else { LoadingCard(title: copy.disk, symbol: "internaldrive", copy: copy) }
    }

    @ViewBuilder private var networkCard: some View {
        if let snapshot = monitoring {
            MetricCard(title: copy.network, symbol: "network") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 18) { ValuePair(label: copy.download, value: formatRate(snapshot.network.downloadBytesPerSecond, locale: locale), tint: .blue); ValuePair(label: copy.upload, value: formatRate(snapshot.network.uploadBytesPerSecond, locale: locale), tint: .orange); Spacer() }
                    TrendChart(values: history.samples.map { $0.download + $0.upload }, color: .cyan, label: copy.network)
                    HStack { Text(snapshot.network.interfaces.isEmpty ? copy.unavailable : snapshot.network.interfaces.map(\.name).joined(separator: "  ·  ")).font(.caption).foregroundStyle(.secondary); Spacer(); Text(formatBytes(snapshot.network.cumulativeReceivedBytes, locale: locale) + " ↓  " + formatBytes(snapshot.network.cumulativeSentBytes, locale: locale) + " ↑").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                }
            }
        } else { LoadingCard(title: copy.network, symbol: "network", copy: copy) }
    }

    @ViewBuilder private var processesCard: some View {
        if let snapshot = monitoring {
            MetricCard(title: copy.topProcesses, symbol: "list.bullet.rectangle") {
                VStack(spacing: 0) {
                    HStack { Text(copy.process).frame(maxWidth: .infinity, alignment: .leading); Text(copy.pid).frame(width: 70, alignment: .trailing); Text(copy.cpuUsage).frame(width: 76, alignment: .trailing); Text(copy.memoryShort).frame(width: 92, alignment: .trailing) }.font(.caption.weight(.medium)).foregroundStyle(.secondary).padding(.bottom, 8)
                    ForEach(0..<min(8, snapshot.processes.count), id: \.self) { index in
                        let process = snapshot.processes[index]
                        HStack { HStack(spacing: 8) { Text("\(index + 1)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 18, alignment: .leading); Text(process.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading) }; Text(String(process.pid)).frame(width: 70, alignment: .trailing); Text(formatPercent(process.cpuUsagePercent, locale: locale)).frame(width: 76, alignment: .trailing); Text(formatBytes(process.residentMemoryBytes, locale: locale)).frame(width: 92, alignment: .trailing) }.font(.callout.monospacedDigit()).padding(.vertical, 6)
                        if index < min(8, snapshot.processes.count) - 1 { Divider() }
                    }
                }
            }
        } else { LoadingCard(title: copy.topProcesses, symbol: "list.bullet.rectangle", copy: copy) }
    }

    @ViewBuilder private var thermalCard: some View {
        if let snapshot = hardware {
            MetricCard(title: copy.thermal, symbol: "thermometer.medium") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text(copy.state).foregroundStyle(.secondary); Spacer(); StatusPill(text: copy.thermal(snapshot.thermal.state), tone: thermalTone(snapshot.thermal.state)) }
                    HStack { Text(copy.lowPowerMode).foregroundStyle(.secondary); Spacer(); Text(snapshot.thermal.lowPowerModeEnabled == true ? copy.on : snapshot.thermal.lowPowerModeEnabled == false ? copy.off : copy.unavailable) }
                    Divider(); AvailabilityRow(title: copy.sensors, status: snapshot.sensors.status, copy: copy); AvailabilityRow(title: copy.fans, status: snapshot.fans.status, copy: copy); AvailabilityRow(title: copy.power, status: snapshot.power.status, copy: copy)
                }
            }
        } else { LoadingCard(title: copy.thermal, symbol: "thermometer.medium", copy: copy) }
    }

    @ViewBuilder private var hardwareCard: some View {
        if let snapshot = hardware {
            MetricCard(title: copy.hardwareInfo, symbol: "desktopcomputer") {
                VStack(alignment: .leading, spacing: 10) { InfoRow(label: copy.model, value: snapshot.hardware.modelIdentifier ?? copy.unavailable); InfoRow(label: copy.appleSilicon, value: snapshot.hardware.isAppleSilicon.map { $0 ? copy.yes : copy.no } ?? copy.unavailable); InfoRow(label: copy.cores, value: coreSummary(snapshot.hardware, copy: copy)); InfoRow(label: copy.physicalMemory, value: snapshot.hardware.physicalMemoryBytes.map { formatBytes($0, locale: locale) } ?? copy.unavailable); Divider(); StatusPill(text: copy.availability(snapshot.hardware.status.availability), tone: availabilityTone(snapshot.hardware.status.availability)) }
            }
        } else { LoadingCard(title: copy.hardwareInfo, symbol: "desktopcomputer", copy: copy) }
    }

    @ViewBuilder private var batteryCard: some View {
        if let snapshot = hardware {
            let battery = snapshot.battery
            MetricCard(title: copy.battery, symbol: "battery.100") {
                VStack(alignment: .leading, spacing: 11) {
                    HStack { Text(copy.powerSource).foregroundStyle(.secondary); Spacer(); StatusPill(text: copy.powerSource(battery.sourceKind), tone: availabilityTone(battery.status.availability)) }
                    if battery.status.availability == .available {
                        if let chargePercent = battery.chargePercent { HStack(alignment: .firstTextBaseline) { Text(formatPercent(chargePercent, locale: locale)).font(.system(size: 28, weight: .bold, design: .rounded)); Text(battery.isCharging == true ? copy.charging : copy.notCharging).foregroundStyle(.secondary) }; ProgressBar(value: chargePercent / 100, tint: .green) }
                        InfoRow(label: copy.cycleCount, value: battery.cycleCount.map(String.init) ?? copy.availability(battery.cycleCountStatus.availability)); InfoRow(label: copy.health, value: battery.health ?? battery.healthCondition ?? copy.availability(battery.healthStatus.availability))
                    } else { Text(copy.diagnosticDetail(battery.status.detail) ?? copy.unavailable).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true); StatusPill(text: copy.availability(battery.status.availability), tone: availabilityTone(battery.status.availability)) }
                }
            }
        } else { LoadingCard(title: copy.battery, symbol: "battery.100", copy: copy) }
    }

    @ViewBuilder private var storageCard: some View {
        if let snapshot = hardware {
            let storage = snapshot.storage
            MetricCard(title: copy.storage, symbol: "externaldrive") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text(copy.devices).font(.headline); Spacer(); StatusPill(text: copy.availability(storage.status.availability), tone: availabilityTone(storage.status.availability)) }
                    if storage.physicalDisks.isEmpty {
                        Text(storage.status.detail ?? copy.noPhysicalDisks).font(.callout).foregroundStyle(.secondary)
                    } else {
                        ForEach(storage.physicalDisks) { disk in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Label(disk.displayName, systemImage: disk.kind == .externalDisk ? "externaldrive" : "internaldrive")
                                        .font(.callout.weight(.medium)).lineLimit(1)
                                    Spacer()
                                    Text(disk.capacityBytes.map { formatDecimalCapacity($0, locale: locale) } ?? copy.unavailable)
                                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                Text(copy.diskKind(disk.kind)).font(.caption).foregroundStyle(.secondary)

                                ForEach(disk.containers) { container in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(copy.apfsContainer).font(.subheadline.weight(.medium))
                                            Spacer()
                                            Text(container.capacityBytes.map { formatDecimalCapacity($0, locale: locale) } ?? copy.unavailable)
                                                .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                                        }
                                        if container.volumes.isEmpty {
                                            Text(copy.volumes + ": " + copy.noData).font(.caption).foregroundStyle(.secondary)
                                        } else {
                                            ForEach(container.volumes) { volume in
                                                VStack(alignment: .leading, spacing: 4) {
                                                    HStack(spacing: 8) {
                                                        Image(systemName: volume.role == .data ? "folder" : "internaldrive").foregroundStyle(.secondary)
                                                        Text(volume.displayName.isEmpty ? copy.unknownVolume : volume.displayName).lineLimit(1)
                                                        Spacer()
                                                        Text(copy.volumeRole(volume.role)).font(.caption).foregroundStyle(.secondary)
                                                    }
                                                    DisclosureGroup(copy.advanced) {
                                                        InfoRow(label: "BSD", value: volume.bsdName ?? copy.unavailable)
                                                        InfoRow(label: "UUID", value: volume.uuid ?? copy.unavailable)
                                                        InfoRow(label: "Volume group", value: volume.volumeGroupUUID ?? copy.unavailable)
                                                        InfoRow(label: "Reported size", value: volume.reportedSizeBytes.map { formatDecimalCapacity($0, locale: locale) } ?? copy.unavailable)
                                                    }
                                                    .font(.caption)
                                                    .padding(.leading, 22)
                                                }
                                            }
                                            let hasSystemData = container.volumes.contains { $0.role == .system } && container.volumes.contains { $0.role == .data }
                                            if hasSystemData {
                                                Text(copy.sharedCapacity).font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                        DisclosureGroup(copy.advanced) {
                                            InfoRow(label: "BSD", value: container.bsdName ?? copy.unavailable)
                                            InfoRow(label: "UUID", value: container.uuid ?? copy.unavailable)
                                            InfoRow(label: "Physical store", value: container.physicalStoreBSDNames.isEmpty ? copy.unavailable : container.physicalStoreBSDNames.joined(separator: ", "))
                                        }
                                        .font(.caption)
                                    }
                                    .padding(.leading, 10)
                                }

                                DisclosureGroup(copy.advanced) {
                                    InfoRow(label: "BSD", value: disk.bsdName ?? copy.unavailable)
                                    InfoRow(label: "UUID", value: disk.uuid ?? copy.unavailable)
                                    InfoRow(label: "Vendor", value: disk.vendor ?? copy.unavailable)
                                    InfoRow(label: "Revision", value: disk.revision ?? copy.unavailable)
                                }
                                .font(.caption)
                            }
                            if disk.id != storage.physicalDisks.last?.id { Divider() }
                        }
                    }
                    Divider()
                    AvailabilityRow(title: copy.smart, status: storage.smartStatus, copy: copy)
                    if let detail = copy.diagnosticDetail(storage.smartStatus.detail) { Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    AvailabilityRow(title: copy.wear, status: storage.wearStatus, copy: copy)
                    if let detail = copy.diagnosticDetail(storage.wearStatus.detail) { Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }
            }
        } else { LoadingCard(title: copy.storage, symbol: "externaldrive", copy: copy) }
    }
}

private struct MetricCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { Label(title, systemImage: symbol).font(.headline); content }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background { RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)) }
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08), lineWidth: 1) }
    }
}

private struct LoadingCard: View {
    let title: String
    let symbol: String
    let copy: DashboardCopy
    var body: some View { MetricCard(title: title, symbol: symbol) { HStack(spacing: 10) { ProgressView(); Text(copy.noData).foregroundStyle(.secondary) }.frame(minHeight: 90, alignment: .leading) } }
}

private struct InlineMessage: View {
    let title: String
    let detail: String
    var body: some View {
        Label { VStack(alignment: .leading, spacing: 2) { Text(title).font(.callout.weight(.semibold)); Text(detail).font(.caption) } } icon: { Image(systemName: "exclamationmark.triangle") }
            .foregroundStyle(.orange).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct TrendChart: View {
    let values: [Double]
    let color: Color
    let label: String
    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                guard values.count > 1 else { return }
                let maximum = max(values.max() ?? 1, 1)
                let step = size.width / CGFloat(max(values.count - 1, 1))
                var line = Path()
                for (index, value) in values.enumerated() {
                    let x = CGFloat(index) * step
                    let y = size.height - (CGFloat(min(max(value, 0), maximum)) / CGFloat(maximum) * size.height)
                    if index == 0 { line.move(to: CGPoint(x: x, y: y)) } else { line.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(line, with: .color(color), lineWidth: 2)
            }.accessibilityLabel(label)
        }.frame(height: 58)
    }
}

private struct ProgressBar: View {
    let value: Double
    let tint: Color
    @Environment(\.locale) private var locale
    var body: some View {
        GeometryReader { proxy in ZStack(alignment: .leading) { Capsule().fill(Color.primary.opacity(0.08)); Capsule().fill(tint).frame(width: proxy.size.width * min(max(value, 0), 1)) } }
            .frame(height: 7).accessibilityValue(formatPercent(value * 100, locale: locale))
    }
}

private struct ValuePair: View {
    let label: String
    let value: String
    let tint: Color
    var body: some View { VStack(alignment: .leading, spacing: 4) { HStack(spacing: 5) { Circle().fill(tint).frame(width: 6, height: 6); Text(label).font(.caption).foregroundStyle(.secondary) }; Text(value).font(.callout.weight(.medium).monospacedDigit()) } }
}

private struct InfoRow: View {
    let label: String
    let value: String
    var body: some View { HStack(alignment: .firstTextBaseline) { Text(label).foregroundStyle(.secondary); Spacer(minLength: 12); Text(value).multilineTextAlignment(.trailing).lineLimit(2) }.font(.callout) }
}

private struct AvailabilityRow: View {
    let title: String
    let status: HardwareMetricStatus
    let copy: DashboardCopy
    var body: some View { HStack { Text(title).foregroundStyle(.secondary); Spacer(); StatusPill(text: copy.availability(status.availability), tone: availabilityTone(status.availability)) }.help(status.detail ?? status.source) }
}

private struct StatusPill: View {
    enum Tone { case good, warning, unavailable, unsupported, neutral }
    let text: String
    let tone: Tone
    var body: some View { Text(text).font(.caption.weight(.semibold)).foregroundStyle(foreground).padding(.horizontal, 8).padding(.vertical, 4).background(background, in: Capsule()) }
    private var foreground: Color { switch tone { case .good: return .green; case .warning: return .orange; case .unavailable, .unsupported: return .secondary; case .neutral: return .primary } }
    private var background: Color { switch tone { case .good: return .green.opacity(0.13); case .warning: return .orange.opacity(0.13); case .unavailable, .unsupported: return .secondary.opacity(0.13); case .neutral: return .primary.opacity(0.08) } }
}

private func availabilityTone(_ value: HardwareAvailability) -> StatusPill.Tone { switch value { case .available: return .good; case .unavailable: return .unavailable; case .unsupported: return .unsupported } }
private func pressureTone(_ value: MemoryPressureLevel) -> StatusPill.Tone { switch value { case .normal: return .good; case .warning, .critical: return .warning; case .unknown: return .neutral } }
private func thermalTone(_ value: ThermalState?) -> StatusPill.Tone { switch value { case .nominal: return .good; case .fair, .serious, .critical: return .warning; case nil: return .unavailable } }

private func coreSummary(_ info: HardwareInfo, copy: DashboardCopy) -> String {
    let total = [info.physicalCoreCount, info.logicalCoreCount].compactMap { $0 }.map(String.init).joined(separator: " / ")
    let split = [info.performanceCoreCount.map { copy.performanceCores + " \($0)" }, info.efficiencyCoreCount.map { copy.efficiencyCores + " \($0)" }].compactMap { $0 }.joined(separator: ", ")
    return split.isEmpty ? (total.isEmpty ? copy.unavailable : total) : "\(total) (\(split))"
}

private func formatPercent(_ value: Double, locale: Locale = .current) -> String {
    guard value.isFinite else { return "—" }
    return value.formatted(.number.locale(locale).precision(.fractionLength(value >= 10 ? 0 : 1))) + "%"
}

private func formatBytes(_ value: UInt64, locale: Locale = .current) -> String {
    ByteUnitFormatter.string(bytes: value, locale: locale)
}

private func formatDecimalCapacity(_ value: UInt64, locale: Locale = .current) -> String {
    ByteUnitFormatter.string(bytes: value, locale: locale, maximumFractionDigits: 1)
}

private func formatRate(_ value: Double, locale: Locale = .current) -> String {
    guard value.isFinite else { return "—" }
    return ByteUnitFormatter.string(bytes: value, locale: locale) + "/s"
}
