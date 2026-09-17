import Foundation
import Darwin
import IOKit

private struct CPUCounterSample: Sendable {
    let user: [UInt64]
    let system: [UInt64]
    let idle: [UInt64]
    let total: [UInt64]
}

private struct ProcessCounter: Sendable {
    let cpuNanoseconds: UInt64
    let timestamp: Date
}

private struct NetworkCounter: Sendable {
    let received: UInt64
    let sent: UInt64
}

private struct DiskCounter: Sendable {
    let read: UInt64
    let written: UInt64
}

struct MonitoringCollector: Sendable {
    let volumeURL: URL
    let processLimit: Int
    let includeProcesses: Bool
    private var previousCPU: CPUCounterSample?
    private var previousProcesses: [Int32: ProcessCounter] = [:]
    private var previousNetwork: [String: NetworkCounter] = [:]
    private var previousDisk: DiskCounter?
    private var previousTimestamp: Date?

    init(volumeURL: URL, processLimit: Int, includeProcesses: Bool = true) {
        self.volumeURL = volumeURL
        self.processLimit = max(0, processLimit)
        self.includeProcesses = includeProcesses
    }

    mutating func collect(at timestamp: Date = Date()) throws -> MonitoringSnapshot {
        let elapsed = previousTimestamp.map { max(0.001, timestamp.timeIntervalSince($0)) }
        let cpu = try collectCPU(at: timestamp)
        let memory = try collectMemory(at: timestamp)
        let disk = collectDisk(at: timestamp, elapsed: elapsed)
        let network = collectNetwork(at: timestamp, elapsed: elapsed)
        let processes = includeProcesses ? try collectProcesses(at: timestamp, elapsed: elapsed) : []
        previousTimestamp = timestamp
        return MonitoringSnapshot(timestamp: timestamp, cpu: cpu, memory: memory, disk: disk, network: network, processes: processes)
    }

    private mutating func collectCPU(at timestamp: Date) throws -> CPUSnapshot {
        var processorCount: natural_t = 0
        var processorInfo: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &infoCount
        )
        guard result == KERN_SUCCESS, let processorInfo else {
            throw MonitoringError.cpuStatisticsUnavailable(result)
        }

        let cpuStateCount = Int(CPU_STATE_MAX)
        let values = UnsafeBufferPointer(start: processorInfo, count: Int(infoCount))
        var user = [UInt64](repeating: 0, count: Int(processorCount))
        var system = [UInt64](repeating: 0, count: Int(processorCount))
        var idle = [UInt64](repeating: 0, count: Int(processorCount))
        var total = [UInt64](repeating: 0, count: Int(processorCount))
        for core in 0..<Int(processorCount) {
            let offset = core * cpuStateCount
            guard offset + Int(CPU_STATE_MAX) <= values.count else { continue }
            let userTicks = UInt64(max(0, values[offset + Int(CPU_STATE_USER)])) + UInt64(max(0, values[offset + Int(CPU_STATE_NICE)]))
            let systemTicks = UInt64(max(0, values[offset + Int(CPU_STATE_SYSTEM)]))
            let idleTicks = UInt64(max(0, values[offset + Int(CPU_STATE_IDLE)]))
            user[core] = userTicks
            system[core] = systemTicks
            idle[core] = idleTicks
            total[core] = userTicks &+ systemTicks &+ idleTicks
        }
        let address = vm_address_t(bitPattern: processorInfo)
        let byteCount = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
        _ = vm_deallocate(mach_task_self_, address, byteCount)

        let current = CPUCounterSample(user: user, system: system, idle: idle, total: total)
        let previous = previousCPU
        previousCPU = current
        guard let previous else {
            return CPUSnapshot(timestamp: timestamp, totalUsagePercent: 0, userUsagePercent: 0, systemUsagePercent: 0, idleUsagePercent: 100, perCoreUsagePercent: Array(repeating: 0, count: Int(processorCount)))
        }

        var userDelta: UInt64 = 0
        var systemDelta: UInt64 = 0
        var idleDelta: UInt64 = 0
        var perCore = [Double](repeating: 0, count: min(current.total.count, previous.total.count))
        for core in perCore.indices {
            let userValue = current.user[core] &- previous.user[core]
            let systemValue = current.system[core] &- previous.system[core]
            let idleValue = current.idle[core] &- previous.idle[core]
            let totalValue = userValue &+ systemValue &+ idleValue
            userDelta &+= userValue
            systemDelta &+= systemValue
            idleDelta &+= idleValue
            perCore[core] = percentage(used: userValue &+ systemValue, total: totalValue)
        }
        let totalDelta = userDelta &+ systemDelta &+ idleDelta
        return CPUSnapshot(
            timestamp: timestamp,
            totalUsagePercent: percentage(used: userDelta &+ systemDelta, total: totalDelta),
            userUsagePercent: percentage(used: userDelta, total: totalDelta),
            systemUsagePercent: percentage(used: systemDelta, total: totalDelta),
            idleUsagePercent: percentage(used: idleDelta, total: totalDelta),
            perCoreUsagePercent: perCore
        )
    }

    private func collectMemory(at timestamp: Date) throws -> MemorySnapshot {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &statistics) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            throw MonitoringError.memoryStatisticsUnavailable(result)
        }

        var kernelPageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &kernelPageSize)
        let pageSize = UInt64(kernelPageSize == 0 ? 4096 : kernelPageSize)
        let physical = ProcessInfo.processInfo.physicalMemory
        let wired = UInt64(statistics.wire_count) * pageSize
        let compressed = UInt64(statistics.compressor_page_count) * pageSize
        let available = min(
            physical,
            (UInt64(statistics.free_count) &+ UInt64(statistics.inactive_count) &+ UInt64(statistics.speculative_count) &+ UInt64(statistics.purgeable_count)) * pageSize
        )
        let used = physical &- available
        let swap = readSwapUsage()
        let pressure = derivePressure(available: available, physical: physical, swapUsed: swap.used)
        return MemorySnapshot(
            timestamp: timestamp,
            physicalMemoryBytes: physical,
            usedMemoryBytes: used,
            availableMemoryBytes: available,
            wiredMemoryBytes: wired,
            compressedMemoryBytes: compressed,
            swapTotalBytes: swap.total,
            swapUsedBytes: swap.used,
            pressure: pressure,
            pressureSource: .derivedFromPublicVMStatistics
        )
    }

    private mutating func collectDisk(at timestamp: Date, elapsed: TimeInterval?) -> DiskSnapshot {
        let values = try? volumeURL.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        let total = UInt64(max(0, values?.volumeTotalCapacity ?? 0))
        let available = UInt64(max(0, values?.volumeAvailableCapacityForImportantUsage ?? 0))
        let counters = readDiskCounters()
        let readRate = rate(current: counters.read, previous: previousDisk?.read, elapsed: elapsed)
        let writeRate = rate(current: counters.written, previous: previousDisk?.written, elapsed: elapsed)
        previousDisk = counters.available ? DiskCounter(read: counters.read, written: counters.written) : previousDisk
        return DiskSnapshot(
            timestamp: timestamp,
            volumePath: volumeURL,
            totalBytes: total,
            usedBytes: total >= available ? total - available : 0,
            availableBytes: available,
            cumulativeReadBytes: counters.read,
            cumulativeWrittenBytes: counters.written,
            readBytesPerSecond: readRate,
            writeBytesPerSecond: writeRate,
            ioStatisticsAvailable: counters.available
        )
    }

    private mutating func collectNetwork(at timestamp: Date, elapsed: TimeInterval?) -> NetworkSnapshot {
        let current = readNetworkCounters()
        let previous = previousNetwork
        let interfaces = current.keys.sorted().map { name in
            let counter = current[name] ?? NetworkCounter(received: 0, sent: 0)
            let previousCounter = previous[name]
            return NetworkInterfaceSnapshot(
                name: name,
                cumulativeReceivedBytes: counter.received,
                cumulativeSentBytes: counter.sent,
                downloadBytesPerSecond: rate(current: counter.received, previous: previousCounter?.received, elapsed: elapsed),
                uploadBytesPerSecond: rate(current: counter.sent, previous: previousCounter?.sent, elapsed: elapsed)
            )
        }
        previousNetwork = current
        let received = current.values.reduce(UInt64(0)) { $0 &+ $1.received }
        let sent = current.values.reduce(UInt64(0)) { $0 &+ $1.sent }
        let previousReceived = previous.values.reduce(UInt64(0)) { $0 &+ $1.received }
        let previousSent = previous.values.reduce(UInt64(0)) { $0 &+ $1.sent }
        return NetworkSnapshot(
            timestamp: timestamp,
            interfaces: interfaces,
            cumulativeReceivedBytes: received,
            cumulativeSentBytes: sent,
            downloadBytesPerSecond: rate(current: received, previous: previousReceived, elapsed: elapsed),
            uploadBytesPerSecond: rate(current: sent, previous: previousSent, elapsed: elapsed)
        )
    }

    private mutating func collectProcesses(at timestamp: Date, elapsed: TimeInterval?) throws -> [ProcessSnapshot] {
        var pids = [pid_t](repeating: 0, count: 4096)
        let bufferSize = Int32(pids.count * MemoryLayout<pid_t>.stride)
        let result = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, bufferSize)
        }
        guard result >= 0 else { throw MonitoringError.processStatisticsUnavailable }
        let count = min(Int(result), pids.count)
        var snapshots: [ProcessSnapshot] = []
        var nextCounters: [Int32: ProcessCounter] = [:]
        for rawPID in pids.prefix(count) {
            let pid = Int32(rawPID)
            guard pid > 0 else { continue }
            var info = proc_taskallinfo()
            let infoSize = Int32(MemoryLayout<proc_taskallinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &info, infoSize) == infoSize else { continue }
            let cpuNanoseconds = info.ptinfo.pti_total_user &+ info.ptinfo.pti_total_system
            let previous = previousProcesses[pid]
            let cpuPercent: Double
            if let previous, let elapsed, elapsed > 0, cpuNanoseconds >= previous.cpuNanoseconds {
                cpuPercent = Double(cpuNanoseconds - previous.cpuNanoseconds) / (elapsed * 1_000_000_000) * 100
            } else {
                cpuPercent = 0
            }
            nextCounters[pid] = ProcessCounter(cpuNanoseconds: cpuNanoseconds, timestamp: timestamp)
            snapshots.append(ProcessSnapshot(pid: pid, name: processName(pid), cpuUsagePercent: max(0, cpuPercent), residentMemoryBytes: info.ptinfo.pti_resident_size))
        }
        previousProcesses = nextCounters
        let sorted = snapshots.sorted { lhs, rhs in
            if lhs.cpuUsagePercent == rhs.cpuUsagePercent { return lhs.residentMemoryBytes > rhs.residentMemoryBytes }
            return lhs.cpuUsagePercent > rhs.cpuUsagePercent
        }
        return processLimit == 0 ? sorted : Array(sorted.prefix(processLimit))
    }
}

private func percentage(used: UInt64, total: UInt64) -> Double {
    guard total > 0 else { return 0 }
    return min(100, max(0, Double(used) / Double(total) * 100))
}

private func rate(current: UInt64, previous: UInt64?, elapsed: TimeInterval?) -> Double {
    guard let previous, let elapsed, elapsed > 0, current >= previous else { return 0 }
    return Double(current - previous) / elapsed
}

private func readSwapUsage() -> (total: UInt64, used: UInt64) {
    var usage = xsw_usage()
    var size = MemoryLayout<xsw_usage>.size
    guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return (0, 0) }
    return (usage.xsu_total, usage.xsu_used)
}

private func derivePressure(available: UInt64, physical: UInt64, swapUsed: UInt64) -> MemoryPressureLevel {
    guard physical > 0 else { return .unknown }
    let ratio = Double(available) / Double(physical)
    if ratio < 0.05 || swapUsed > physical / 2 { return .critical }
    if ratio < 0.15 || swapUsed > physical / 10 { return .warning }
    return .normal
}

private func readNetworkCounters() -> [String: NetworkCounter] {
    var addresses: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&addresses) == 0, let addresses else { return [:] }
    defer { freeifaddrs(addresses) }
    var result: [String: NetworkCounter] = [:]
    var current: UnsafeMutablePointer<ifaddrs>? = addresses
    while let entry = current {
        let interface = entry.pointee
        let name = String(cString: interface.ifa_name)
        if name != "lo0", interface.ifa_addr?.pointee.sa_family == UInt8(AF_LINK), let data = interface.ifa_data {
            let statistics = data.assumingMemoryBound(to: if_data.self).pointee
            result[name] = NetworkCounter(received: UInt64(statistics.ifi_ibytes), sent: UInt64(statistics.ifi_obytes))
        }
        current = interface.ifa_next
    }
    return result
}

private func processName(_ pid: pid_t) -> String {
    var buffer = [CChar](repeating: 0, count: 512)
    let count = proc_name(pid, &buffer, UInt32(buffer.count))
    guard count > 0 else { return "pid-\(pid)" }
    let bytes = buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
    return String(decoding: bytes, as: UTF8.self)
}

private struct DiskCounterResult {
    let read: UInt64
    let written: UInt64
    let available: Bool
}

private func readDiskCounters() -> DiskCounterResult {
    let matching = IOServiceMatching("IOBlockStorageDriver")
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
        return DiskCounterResult(read: 0, written: 0, available: false)
    }
    defer { IOObjectRelease(iterator) }
    var read: UInt64 = 0
    var written: UInt64 = 0
    var found = false
    while true {
        let service = IOIteratorNext(iterator)
        guard service != 0 else { break }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any],
              let statistics = dictionary["Statistics"] as? [String: Any]
        else { continue }
        let bytesRead = (statistics["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
        let bytesWritten = (statistics["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        read &+= bytesRead
        written &+= bytesWritten
        found = true
    }
    return DiskCounterResult(read: read, written: written, available: found)
}
