import AppKit
import Darwin
import Foundation
import IOKit.ps

enum SystemTools {
    struct CommandResult: Sendable {
        let status: Int32
        let output: String
    }

    static func run(_ executable: String, _ arguments: [String], environmentOverrides: [String: String] = [:]) throws -> CommandResult {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        task.environment = environment.merging(environmentOverrides) { _, override in override }
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return CommandResult(status: task.terminationStatus, output: String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines))
    }

    enum Maintenance: String, CaseIterable, Identifiable, Sendable {
        case quickLook = "Refresh Quick Look"
        case spotlight = "Check Spotlight"
        case disk = "Verify startup volume"

        var id: Self { self }
        var icon: String {
            switch self {
            case .quickLook: "eye"
            case .spotlight: "magnifyingglass"
            case .disk: "internaldrive"
            }
        }

        var details: String {
            switch self {
            case .quickLook: "Reset the Quick Look thumbnail cache. macOS rebuilds previews as needed."
            case .spotlight: "Read the current indexing status of the startup volume."
            case .disk: "Ask Disk Utility to verify the startup volume. This can take a few minutes."
            }
        }

        func execute() throws -> CommandResult {
            switch self {
            case .quickLook: try run("/usr/bin/qlmanage", ["-r", "cache"])
            case .spotlight: try run("/usr/bin/mdutil", ["-s", "/"])
            case .disk: try run("/usr/sbin/diskutil", ["verifyVolume", "/"])
            }
        }
    }

    struct Update: Identifiable, Sendable {
        let name: String
        let installed: String
        let available: String
        let kind: String
        var id: String { kind + ":" + name }
    }

    static func brewUpdates() throws -> [Update]? {
        guard let binary = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else { return nil }
        let result = try run(binary, ["outdated", "--json=v2"], environmentOverrides: ["HOMEBREW_NO_AUTO_UPDATE": "1"])
        guard result.status == 0 else { throw ToolError.message(result.output) }
        // Homebrew uses a list for formulae and a scalar for installed cask versions.
        struct BrewItem: Decodable {
            let name: String
            let installed: String
            let currentVersion: String
            enum CodingKeys: String, CodingKey {
                case name, installed = "installed_versions", currentVersion = "current_version"
            }
            init(from decoder: Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                name = try values.decode(String.self, forKey: .name)
                currentVersion = try values.decode(String.self, forKey: .currentVersion)
                if let versions = try? values.decode([String].self, forKey: .installed) {
                    installed = versions.joined(separator: ", ")
                } else {
                    installed = (try? values.decode(String.self, forKey: .installed)) ?? ""
                }
            }
        }
        let payload = try JSONDecoder().decode([String: [BrewItem]].self, from: Data(result.output.utf8))
        return (payload["casks"] ?? []).map {
            Update(name: $0.name, installed: $0.installed, available: $0.currentVersion, kind: "Cask")
        } + (payload["formulae"] ?? []).map {
            Update(name: $0.name, installed: $0.installed, available: $0.currentVersion, kind: "Formula")
        }
    }

    enum ToolError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self { case .message(let value): value }
        }
    }

    struct CPU: Sendable {
        let active: UInt64
        let total: UInt64
        func usage(since previous: CPU?) -> Double? {
            guard let previous, total > previous.total, active >= previous.active else { return nil }
            return min(1, Double(active - previous.active) / Double(total - previous.total))
        }
    }

    struct Network: Sendable {
        let received: UInt64
        let sent: UInt64

        func rates(since previous: Network?, seconds: Double) -> (receive: Int64, send: Int64)? {
            guard let previous, seconds > 0, received >= previous.received, sent >= previous.sent else { return nil }
            return (Int64(Double(received - previous.received) / seconds),
                    Int64(Double(sent - previous.sent) / seconds))
        }
    }

    struct ProcessRow: Identifiable, Sendable {
        let pid: Int32
        let cpu: Double
        let residentBytes: Int64
        let name: String
        var id: Int32 { pid }
    }

    struct Snapshot: Sendable {
        let cpu: CPU?
        let memoryUsed: Int64?
        let memoryTotal: Int64
        let diskFree: Int64?
        let diskTotal: Int64?
        let network: Network?
        let battery: String?
        let thermal: String
        let uptime: TimeInterval
        let processes: [ProcessRow]
        let timestamp: TimeInterval
    }

    static func snapshot(includeProcesses: Bool) -> Snapshot {
        let info = ProcessInfo.processInfo
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var load = host_cpu_load_info()
        let cpuCount = MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size
        var count = mach_msg_type_number_t(cpuCount)
        let cpuResult = withUnsafeMutablePointer(to: &load) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: cpuCount) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        let active = UInt64(load.cpu_ticks.0) + UInt64(load.cpu_ticks.1) + UInt64(load.cpu_ticks.3)
        let cpu = cpuResult == KERN_SUCCESS ? CPU(active: active, total: active + UInt64(load.cpu_ticks.2)) : nil

        var memory = vm_statistics64()
        let vmCount = MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        count = mach_msg_type_number_t(vmCount)
        let memoryResult = withUnsafeMutablePointer(to: &memory) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: vmCount) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        let residentPages = Int64(memory.active_count) + Int64(memory.inactive_count) + Int64(memory.wire_count)
            + Int64(memory.compressor_page_count) - Int64(memory.external_page_count) - Int64(memory.purgeable_count)
        let totalMemory = Int64(info.physicalMemory)
        let used = memoryResult == KERN_SUCCESS ? min(totalMemory, max(0, residentPages) * Int64(vm_kernel_page_size)) : nil
        let volume = try? FileTools.home.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey])
        let thermal: String
        switch info.thermalState {
        case .nominal: thermal = "Normal"
        case .fair: thermal = "Warm"
        case .serious: thermal = "High"
        case .critical: thermal = "Critical"
        @unknown default: thermal = "Unknown"
        }
        return Snapshot(cpu: cpu, memoryUsed: used, memoryTotal: totalMemory,
                        diskFree: volume?.volumeAvailableCapacity.map(Int64.init),
                        diskTotal: volume?.volumeTotalCapacity.map(Int64.init), network: network(),
                        battery: battery(), thermal: thermal, uptime: info.systemUptime,
                        processes: includeProcesses ? processes() : [], timestamp: info.systemUptime)
    }

    static func network() -> Network? {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else { return nil }
        defer { freeifaddrs(first) }
        var current: UnsafeMutablePointer<ifaddrs>? = first
        var received: UInt64 = 0
        var sent: UInt64 = 0
        while let address = current {
            defer { current = address.pointee.ifa_next }
            guard let sockaddr = address.pointee.ifa_addr,
                  sockaddr.pointee.sa_family == AF_LINK,
                  address.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  let data = address.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            received += UInt64(data.pointee.ifi_ibytes)
            sent += UInt64(data.pointee.ifi_obytes)
        }
        return Network(received: received, sent: sent)
    }

    static func battery() -> String? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let values = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  values[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = values[kIOPSCurrentCapacityKey] as? Double,
                  let maximum = values[kIOPSMaxCapacityKey] as? Double, maximum > 0 else { continue }
            return (current / maximum).formatted(.percent.precision(.fractionLength(0)))
        }
        return nil
    }

    static func processes() -> [ProcessRow] {
        guard let result = try? run("/bin/ps", ["-A", "-o", "pid=,pcpu=,rss=,comm="]), result.status == 0 else { return [] }
        return Array(result.output.split(separator: "\n").compactMap { line -> ProcessRow? in
            let fields = line.split(maxSplits: 3, whereSeparator: \.isWhitespace)
            guard fields.count == 4, let pid = Int32(fields[0]), let cpu = Double(fields[1]),
                  let rss = Int64(fields[2]) else { return nil }
            return ProcessRow(pid: pid, cpu: cpu, residentBytes: rss * 1024,
                              name: String(fields[3]).components(separatedBy: "/").last ?? String(fields[3]))
        }.sorted { $0.cpu > $1.cpu }.prefix(12))
    }
}
