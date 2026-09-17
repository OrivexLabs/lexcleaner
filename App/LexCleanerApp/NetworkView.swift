import LexCleanerCore
import SwiftUI

@MainActor
private final class NetworkViewModel: ObservableObject {
    @Published private(set) var health: NetworkHealthSnapshot?
    @Published private(set) var monitoringNetwork: NetworkSnapshot?
    @Published private(set) var dnsResults: [DNSBenchmarkResult] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isBenchmarking = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var optimizationPlan: NetworkOptimizationPlan?
    @Published private(set) var optimizationResult: NetworkOptimizationResult?
    @Published var isShowingDNSConfirmation = false

    private let collector: NetworkHealthCollector
    private let optimizer = NetworkOptimizationService()
    private var healthTask: Task<Void, Never>?
    private var samplingTask: Task<Void, Never>?
    private var benchmarkTask: Task<Void, Never>?
    private var optimizationTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?

    init() {
        collector = NetworkHealthCollector()
    }

    func start() {
        guard healthTask == nil, samplingTask == nil else { return }
        isLoading = true
        healthTask = Task { [weak self] in
            guard let self else { return }
            do {
                let value = try await collector.collect()
                guard !Task.isCancelled else { return }
                health = value
                isLoading = false
            } catch is CancellationError {
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                DiagnosticsStore.shared.record(.error, message: "Network health collection failed")
                isLoading = false
            }
            healthTask = nil
        }
        samplingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let configuration = try MonitoringSamplingConfiguration(interval: 1, processLimit: 0, includeProcesses: false)
                let sampler = MonitoringSampler(configuration: configuration)
                for try await snapshot in sampler.snapshots() {
                    guard !Task.isCancelled else { break }
                    monitoringNetwork = snapshot.network
                }
            } catch is CancellationError {
                // Page disappearance is an expected cancellation.
            } catch {
                errorMessage = error.localizedDescription
                DiagnosticsStore.shared.record(.error, message: "Network monitoring failed")
            }
            samplingTask = nil
        }
        recoveryTask = Task { [weak self] in
            guard let self else { return }
            if let result = await optimizer.recoverPendingChange() {
                optimizationResult = result
            }
            recoveryTask = nil
        }
    }

    func stop() {
        healthTask?.cancel()
        samplingTask?.cancel()
        benchmarkTask?.cancel()
        optimizationTask?.cancel()
        recoveryTask?.cancel()
        healthTask = nil
        samplingTask = nil
        benchmarkTask = nil
        optimizationTask = nil
        recoveryTask = nil
        isBenchmarking = false
    }

    func benchmarkDNS() {
        guard !isBenchmarking else { return }
        isBenchmarking = true
        errorMessage = nil
        benchmarkTask = Task { [weak self] in
            guard let self else { return }
            do {
                let current = health?.dns.servers ?? []
                let unique = Dictionary(uniqueKeysWithValues: current.map { ($0, DNSBenchmarkServer(name: "Current DNS", address: $0)) })
                let servers = [
                    DNSBenchmarkServer(name: "Cloudflare", address: "1.1.1.1"),
                    DNSBenchmarkServer(name: "Google", address: "8.8.8.8"),
                    DNSBenchmarkServer(name: "Quad9", address: "9.9.9.9")
                ] + current.filter { unique[$0] != nil }.map { DNSBenchmarkServer(name: "Current DNS", address: $0) }
                let results = try await collector.benchmarkDNS(Array(Dictionary(grouping: servers, by: \.address).compactMap { $0.value.first }))
                guard !Task.isCancelled else { return }
                dnsResults = results
                isBenchmarking = false
            } catch is CancellationError {
                isBenchmarking = false
            } catch {
                errorMessage = error.localizedDescription
                DiagnosticsStore.shared.record(.error, message: "DNS benchmark failed")
                isBenchmarking = false
            }
            benchmarkTask = nil
        }
    }

    func prepareBestDNSPlan() {
        guard let health, let best = dnsResults
            .filter({ $0.availability == .available })
            .min(by: { ($0.medianLatencyMilliseconds ?? .infinity) < ($1.medianLatencyMilliseconds ?? .infinity) }) else {
            return
        }
        let store = SystemNetworkDNSConfigurationStore()
        let snapshot: NetworkDNSServiceSnapshot
        do {
            snapshot = try store.read(serviceID: nil, interfaceBSDName: health.path.activeInterface)
        } catch {
            errorMessage = error.localizedDescription
            optimizationPlan = nil
            return
        }
        optimizationPlan = optimizer.makeDNSPlan(
            current: snapshot.servers,
            proposed: [best.server.address],
            targetServiceID: snapshot.serviceID,
            targetServiceName: snapshot.serviceName,
            targetInterface: snapshot.interfaceBSDName
        )
        optimizationResult = nil
    }

    func requestApplyPlan() {
        isShowingDNSConfirmation = true
    }

    func applyPlan() {
        guard let plan = optimizationPlan else { return }
        optimizationTask = Task { [weak self] in
            guard let self else { return }
            optimizationResult = await optimizer.apply(plan, userConfirmed: true)
            optimizationTask = nil
        }
    }

    func rollbackPlan() {
        guard let plan = optimizationPlan else { return }
        optimizationTask = Task { [weak self] in
            guard let self else { return }
            optimizationResult = await optimizer.rollback(plan)
            optimizationTask = nil
        }
    }
}

struct NetworkScreen: View {
    @StateObject private var model = NetworkViewModel()
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let errorMessage = model.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: 16)], spacing: 16) {
                    healthCard
                    throughputCard
                    resolverCard
                    diagnosticsCard
                    usageCard
                    optimizationCard
                }
            }
            .padding(28)
        }
        .background(LexTheme.canvas)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .confirmationDialog(
            L10n.text("network.optimization.confirmTitle", locale: locale),
            isPresented: $model.isShowingDNSConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.text("network.optimization.confirm", locale: locale), role: .destructive) {
                model.applyPlan()
            }
            Button(L10n.text("common.cancel", locale: locale), role: .cancel) {}
        } message: {
            Text(L10n.text("network.optimization.confirmMessage", locale: locale))
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.text("network.title", locale: locale)).font(.largeTitle.bold())
                Text(L10n.text("network.subtitle", locale: locale)).foregroundStyle(.secondary)
            }
            Spacer()
            NetworkStatusPill(text: statusText, color: model.health?.path.status == .satisfied ? .green : .orange)
        }
    }

    private var statusText: String {
        guard let health = model.health else { return L10n.text("common.loading", locale: locale) }
        return health.path.status == .satisfied
            ? L10n.text("network.connected", locale: locale)
            : L10n.text("network.unavailable", locale: locale)
    }

    private var healthCard: some View {
        networkCard(title: "network.health", symbol: "heart.text.square") {
            if let health = model.health {
                NetworkInfoRow(label: L10n.text("network.path", locale: locale), value: health.path.status.rawValue)
                NetworkInfoRow(label: L10n.text("network.interface", locale: locale), value: health.path.activeInterface ?? unavailable)
                NetworkInfoRow(label: L10n.text("network.type", locale: locale), value: interfaceKind(health.path.activeInterfaceKind))
                NetworkInfoRow(label: L10n.text("network.score", locale: locale), value: health.score.value.map { "\($0)/100" } ?? unavailable)
                if let latency = health.latency.medianLatencyMilliseconds { MetricLine(label: L10n.text("network.latency", locale: locale), value: "\(latency.formatted(.number.precision(.fractionLength(1)))) ms") }
                if let jitter = health.latency.jitterMilliseconds { MetricLine(label: L10n.text("network.jitter", locale: locale), value: "\(jitter.formatted(.number.precision(.fractionLength(1)))) ms") }
                MetricLine(label: L10n.text("network.packetLoss", locale: locale), value: health.packetLossPercentage.value.map { "\($0.formatted(.number.precision(.fractionLength(1))))%" } ?? unavailable)
                Text(L10n.text("network.tcpProbeNote", locale: locale)).font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView(L10n.text("common.loading", locale: locale))
            }
        }
    }

    private var throughputCard: some View {
        networkCard(title: "network.throughput", symbol: "arrow.up.arrow.down") {
            if let snapshot = model.monitoringNetwork {
                MetricLine(label: L10n.text("network.download", locale: locale), value: ByteUnitFormatter.string(bytes: snapshot.downloadBytesPerSecond, locale: locale) + "/s")
                MetricLine(label: L10n.text("network.upload", locale: locale), value: ByteUnitFormatter.string(bytes: snapshot.uploadBytesPerSecond, locale: locale) + "/s")
                MetricLine(label: L10n.text("network.received", locale: locale), value: ByteUnitFormatter.string(bytes: snapshot.cumulativeReceivedBytes, locale: locale))
                MetricLine(label: L10n.text("network.sent", locale: locale), value: ByteUnitFormatter.string(bytes: snapshot.cumulativeSentBytes, locale: locale))
            } else {
                ProgressView(L10n.text("common.loading", locale: locale))
            }
        }
    }

    private var resolverCard: some View {
        networkCard(title: "network.dnsBenchmark", symbol: "server.rack") {
            if let health = model.health {
                NetworkInfoRow(label: L10n.text("network.currentDNS", locale: locale), value: health.dns.servers.isEmpty ? unavailable : health.dns.servers.joined(separator: ", "))
            }
            Button {
                model.benchmarkDNS()
            } label: {
                Label(model.isBenchmarking ? L10n.text("network.benchmarking", locale: locale) : L10n.text("network.runBenchmark", locale: locale), systemImage: "speedometer")
            }
            .disabled(model.isBenchmarking || model.health == nil)
            ForEach(model.dnsResults) { result in
                HStack {
                    Text(result.server.name).lineLimit(1)
                    Spacer()
                    Text(result.medianLatencyMilliseconds.map { "\($0.formatted(.number.precision(.fractionLength(1)))) ms" } ?? unavailable).monospacedDigit()
                }
                .font(.caption)
            }
        }
    }

    private var diagnosticsCard: some View {
        networkCard(title: "network.diagnostics", symbol: "stethoscope") {
            if let health = model.health {
                if health.issues.isEmpty {
                    Label(L10n.text("network.noIssues", locale: locale), systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                } else {
                    ForEach(health.issues) { issue in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.text(issue.titleKey, locale: locale)).font(.callout.weight(.medium))
                            Text(issueDetail(issue)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                NetworkInfoRow(label: L10n.text("network.gateway", locale: locale), value: health.gateway.value ?? unavailable)
                NetworkInfoRow(label: L10n.text("network.proxy", locale: locale), value: health.proxy.value ?? unavailable)
                NetworkInfoRow(label: L10n.text("network.vpn", locale: locale), value: health.vpn.value ?? unavailable)
            } else {
                ProgressView(L10n.text("common.loading", locale: locale))
            }
        }
    }

    private var usageCard: some View {
        networkCard(title: "network.appUsage", symbol: "app.connected.to.app.below.fill") {
            Label(L10n.text("network.appUsageUnavailable", locale: locale), systemImage: "info.circle")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.text("network.appUsageSource", locale: locale)).font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var optimizationCard: some View {
        networkCard(title: "network.optimization", symbol: "wand.and.stars") {
            Text(L10n.text("network.optimizationReadOnly", locale: locale)).font(.caption).foregroundStyle(.secondary)
            if let plan = model.optimizationPlan {
                NetworkInfoRow(label: L10n.text("network.originalDNS", locale: locale), value: plan.originalDNS.joined(separator: ", "))
                NetworkInfoRow(label: L10n.text("network.proposedDNS", locale: locale), value: plan.proposedDNS.joined(separator: ", "))
                Button(L10n.text("network.requestAuthorization", locale: locale)) { model.requestApplyPlan() }
                Button(L10n.text("network.rollback", locale: locale)) { model.rollbackPlan() }
            } else {
                Button(L10n.text("network.preparePlan", locale: locale)) { model.prepareBestDNSPlan() }
                    .disabled(model.dnsResults.isEmpty)
            }
            if let result = model.optimizationResult {
                Text(optimizationResultText(result)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func optimizationResultText(_ result: NetworkOptimizationResult) -> String {
        var text = L10n.text("network.optimization.status.\(result.status.rawValue)", locale: locale)
        if result.improved == false {
            text += " · " + L10n.text("network.optimization.noImprovement", locale: locale)
        }
        if result.rollbackVerified == true {
            text += " · " + L10n.text("network.optimization.rollbackVerified", locale: locale)
        }
        return text
    }

    private func networkCard<Content: View>(title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L10n.text(title, locale: locale), systemImage: symbol)
                .font(.headline)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var unavailable: String { L10n.text("common.notAvailable", locale: locale) }

    private func interfaceKind(_ kind: NetworkInterfaceKind) -> String {
        L10n.text("network.kind.\(kind.rawValue)", locale: locale)
    }

    private func issueDetail(_ issue: NetworkIssue) -> String {
        guard let detailValue = issue.detailValue else {
            return L10n.text(issue.detailKey, locale: locale)
        }
        return L10n.format(issue.detailKey, locale: locale, detailValue)
    }
}

private struct MetricLine: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
    }
}

private struct NetworkInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .font(.callout)
    }
}

private struct NetworkStatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }
}
