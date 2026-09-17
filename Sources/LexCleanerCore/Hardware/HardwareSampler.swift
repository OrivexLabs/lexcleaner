import Foundation

public enum HardwareSamplingError: Error, Equatable, Sendable {
    case invalidSamplingInterval
}

public struct HardwareSamplingConfiguration: Sendable, Hashable {
    public let interval: TimeInterval

    public static let standard = HardwareSamplingConfiguration(uncheckedInterval: 1)

    public init(interval: TimeInterval = 1) throws {
        guard interval >= 0.1 else { throw HardwareSamplingError.invalidSamplingInterval }
        self.init(uncheckedInterval: interval)
    }

    private init(uncheckedInterval interval: TimeInterval) {
        self.interval = interval
    }
}

public final class HardwareSampler: Sendable {
    private let configuration: HardwareSamplingConfiguration

    public init(configuration: HardwareSamplingConfiguration = .standard) {
        self.configuration = configuration
    }

    public func sample() async throws -> HardwareSnapshot {
        try Task.checkCancellation()
        return try await Task.detached(priority: .utility) {
            try Task.checkCancellation()
            return HardwareCollector().collect()
        }.value
    }

    public func snapshots() -> AsyncThrowingStream<HardwareSnapshot, Error> {
        let configuration = configuration
        return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task.detached(priority: .utility) {
                do {
                    while !Task.isCancelled {
                        continuation.yield(HardwareCollector().collect())
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
