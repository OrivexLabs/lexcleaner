import Foundation
import LexCleanerCore
import SwiftUI

enum MenuBarMetric: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case cpu
    case memory
    case network
    case disk

    var id: String { rawValue }

    func title(locale: Locale = .current) -> String {
        L10n.text("metric.\(rawValue)", locale: locale)
    }
}

@MainActor
final class MenuBarModel: ObservableObject {
    @Published private(set) var snapshot: MonitoringSnapshot?
    @Published private(set) var lastError: String?
    @Published private(set) var visibleMetrics: Set<MenuBarMetric>

    private let sampler: MonitoringSampler
    private let defaults: UserDefaults
    private var samplingTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.visibleMetrics = Self.loadMetrics(from: defaults)
        self.sampler = MenuBarModel.makeSampler()
        startSampling()
    }

    deinit {
        samplingTask?.cancel()
    }

    func setVisible(_ metric: MenuBarMetric, isVisible: Bool) {
        if isVisible {
            visibleMetrics.insert(metric)
        } else {
            visibleMetrics.remove(metric)
        }
        defaults.set(visibleMetrics.map(\.rawValue).sorted(), forKey: Self.metricsDefaultsKey)
    }

    func refreshNow() {
        samplingTask?.cancel()
        startSampling()
    }

    private func startSampling() {
        let sampler = sampler
        samplingTask = Task { [weak self] in
            do {
                for try await snapshot in sampler.snapshots() {
                    guard !Task.isCancelled else { return }
                    self?.snapshot = snapshot
                    self?.lastError = nil
                }
            } catch is CancellationError {
                return
            } catch {
                self?.lastError = error.localizedDescription
                DiagnosticsStore.shared.record(.error, message: "Menu bar monitoring failed")
            }
        }
    }

    private static let metricsDefaultsKey = "menuBar.visibleMetrics"

    private static func loadMetrics(from defaults: UserDefaults) -> Set<MenuBarMetric> {
        guard let values = defaults.array(forKey: metricsDefaultsKey) as? [String] else {
            return Set(MenuBarMetric.allCases)
        }
        return Set(values.compactMap(MenuBarMetric.init(rawValue:)))
    }

    private static func makeSampler() -> MonitoringSampler {
        MonitoringSampler(configuration: .lowOverhead)
    }
}

struct MenuBarStatusLabel: View {
    let snapshot: MonitoringSnapshot?
    let visibleMetrics: Set<MenuBarMetric>
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "leaf.fill")
            ForEach(MenuBarMetric.allCases.filter(visibleMetrics.contains)) { metric in
                metricValue(metric)
                    .monospacedDigit()
            }
        }
        .accessibilityLabel(L10n.text("menuBar.accessibilityLabel", locale: locale))
    }

    @ViewBuilder
    private func metricValue(_ metric: MenuBarMetric) -> some View {
        switch metric {
        case .cpu:
            Text(snapshot.map { L10n.text("metric.cpu.short", locale: locale) + " " + Format.percent($0.cpu.totalUsagePercent, locale: locale) } ?? L10n.text("common.notAvailable", locale: locale))
        case .memory:
            Text(snapshot.map { L10n.text("metric.memory.short", locale: locale) + " " + Format.percent($0.memory.physicalMemoryBytes == 0 ? 0 : Double($0.memory.usedMemoryBytes) / Double($0.memory.physicalMemoryBytes) * 100, locale: locale) } ?? L10n.text("common.notAvailable", locale: locale))
        case .network:
            Text(snapshot.map { L10n.text("metric.network.short", locale: locale) + " " + Format.rate($0.network.downloadBytesPerSecond, locale: locale) } ?? L10n.text("common.notAvailable", locale: locale))
        case .disk:
            Text(snapshot.map { L10n.text("metric.disk.short", locale: locale) + " " + Format.rate($0.disk.readBytesPerSecond + $0.disk.writeBytesPerSecond, locale: locale) } ?? L10n.text("common.notAvailable", locale: locale))
        }
    }
}

enum Format {
    static func percent(_ value: Double, locale: Locale = .current) -> String {
        value.formatted(.number.locale(locale).precision(.fractionLength(0))) + "%"
    }

    static func rate(_ bytesPerSecond: Double, locale: Locale = .current) -> String {
        ByteUnitFormatter.string(bytes: max(0, bytesPerSecond), locale: locale) + "/s"
    }

    static func bytes(_ value: UInt64, locale: Locale = .current) -> String {
        ByteUnitFormatter.string(bytes: value, locale: locale)
    }
}
