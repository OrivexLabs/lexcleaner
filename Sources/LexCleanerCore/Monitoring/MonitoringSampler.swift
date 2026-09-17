import Foundation

public struct MonitoringSamplingConfiguration: Sendable, Hashable {
    public let interval: TimeInterval
    public let volumeURL: URL
    public let processLimit: Int
    public let includeProcesses: Bool

    public static let standard = MonitoringSamplingConfiguration(uncheckedInterval: 1, volumeURL: URL(fileURLWithPath: "/"), processLimit: 0, includeProcesses: true)
    public static let lowOverhead = MonitoringSamplingConfiguration(uncheckedInterval: 2, volumeURL: URL(fileURLWithPath: "/"), processLimit: 0, includeProcesses: false)

    public init(
        interval: TimeInterval = 1,
        volumeURL: URL = URL(fileURLWithPath: "/"),
        processLimit: Int = 0,
        includeProcesses: Bool = true
    ) throws {
        guard interval >= 0.1 else { throw MonitoringError.invalidSamplingInterval }
        self.init(uncheckedInterval: interval, volumeURL: volumeURL, processLimit: processLimit, includeProcesses: includeProcesses)
    }

    private init(uncheckedInterval interval: TimeInterval, volumeURL: URL, processLimit: Int, includeProcesses: Bool) {
        self.interval = interval
        self.volumeURL = volumeURL.standardizedFileURL
        self.processLimit = max(0, processLimit)
        self.includeProcesses = includeProcesses
    }
}

public final class MonitoringSampler: Sendable {
    private let configuration: MonitoringSamplingConfiguration

    public init(configuration: MonitoringSamplingConfiguration = .standard) {
        self.configuration = configuration
    }

    public func sample() async throws -> MonitoringSnapshot {
        let configuration = configuration
        return try await Task.detached(priority: .utility) {
            var collector = MonitoringCollector(
                volumeURL: configuration.volumeURL,
                processLimit: configuration.processLimit,
                includeProcesses: configuration.includeProcesses
            )
            return try collector.collect()
        }.value
    }

    public func snapshots() -> AsyncThrowingStream<MonitoringSnapshot, Error> {
        let configuration = configuration
        return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task.detached(priority: .utility) {
                var collector = MonitoringCollector(
                    volumeURL: configuration.volumeURL,
                    processLimit: configuration.processLimit,
                    includeProcesses: configuration.includeProcesses
                )
                do {
                    while !Task.isCancelled {
                        let snapshot = try collector.collect()
                        continuation.yield(snapshot)
                        try await Task.sleep(for: .seconds(configuration.interval))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
