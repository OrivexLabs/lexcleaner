import Foundation

/// Explicit byte-unit formatting shared by the macOS UI and tests.
///
/// Storage capacity and transfer rates use decimal SI units by product policy:
/// 1 KB = 1,000 bytes and 1 GB = 1,000,000,000 bytes. Binary units are kept
/// explicit and are never labelled as GB/MB.
public enum ByteUnitFormatter {
    public enum System: Sendable {
        case decimal
        case binary
    }

    public static func string(
        bytes: UInt64,
        system: System = .decimal,
        locale: Locale = .current,
        maximumFractionDigits: Int = 2
    ) -> String {
        string(
            bytes: Double(bytes),
            system: system,
            locale: locale,
            maximumFractionDigits: maximumFractionDigits
        )
    }

    public static func string(
        bytes: Double,
        system: System = .decimal,
        locale: Locale = .current,
        maximumFractionDigits: Int = 2
    ) -> String {
        guard bytes.isFinite, bytes >= 0 else { return "—" }
        let base: Double = system == .decimal ? 1_000 : 1_024
        let units = system == .decimal
            ? ["B", "KB", "MB", "GB", "TB", "PB"]
            : ["B", "KiB", "MiB", "GiB", "TiB", "PiB"]
        var scaled = bytes
        var index = 0
        while scaled >= base, index < units.count - 1 {
            scaled /= base
            index += 1
        }

        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = max(0, maximumFractionDigits)
        let number = formatter.string(from: NSNumber(value: scaled)) ?? String(scaled)
        return "\(number) \(units[index])"
    }

    public static func decimalGigabytes(from bytes: UInt64) -> Double {
        Double(bytes) / 1_000_000_000
    }

    public static func gibibytes(from bytes: UInt64) -> Double {
        Double(bytes) / 1_073_741_824
    }
}
