import Foundation

public enum NetworkStatistics {
    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    public static func percentile(_ values: [Double], _ percentile: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let clamped = min(max(percentile, 0), 1)
        let index = Int((Double(sorted.count - 1) * clamped).rounded())
        return sorted[index]
    }

    public static func jitter(_ values: [Double]) -> Double? {
        guard values.count > 1 else { return nil }
        let sorted = values.sorted()
        let differences = zip(sorted, sorted.dropFirst()).map { abs($1 - $0) }
        return differences.reduce(0, +) / Double(differences.count)
    }

    public static func failureRate(failures: Int, total: Int) -> Double? {
        guard total > 0 else { return nil }
        return Double(max(0, failures)) / Double(total)
    }

    public static func score(latencyMilliseconds: Double?, jitterMilliseconds: Double?, failureRate: Double?) -> Int? {
        guard let latencyMilliseconds, let failureRate else { return nil }
        let latencyPenalty = min(70, max(0, latencyMilliseconds - 20) * 0.75)
        let jitterPenalty = min(15, max(0, jitterMilliseconds ?? 0) * 0.5)
        let lossPenalty = min(40, failureRate * 100 * 2)
        return min(100, max(0, Int((100 - latencyPenalty - jitterPenalty - lossPenalty).rounded())))
    }
}
