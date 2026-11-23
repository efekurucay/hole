import AppKit
import SwiftUI
import Charts

struct MaintenanceView: View {
    @State private var active: SystemTools.Maintenance?
    @State private var confirming = false
    @State private var results: [SystemTools.Maintenance: SystemTools.CommandResult] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(SystemTools.Maintenance.allCases) { item in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 13) {
                            Image(systemName: item.icon).foregroundStyle(lagoon).font(.title3).frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.rawValue).font(.headline)
                                Text(item.details).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if active == item { ProgressView().controlSize(.small) }
                            Button("Run") {
                                if item == .quickLook { confirming = true } else { run(item) }
                            }.disabled(active != nil)
                            .accessibilityLabel("Run \(item.rawValue)")
                        }
                        if let result = results[item] {
                            DisclosureGroup(result.status == 0 ? "Completed" : "Exit status \(result.status)") {
                                Text(result.output.isEmpty ? "No additional output." : result.output)
                                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }.padding(15)
                        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .confirmationDialog("Refresh Quick Look thumbnails?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Refresh cache") { run(.quickLook) }
        } message: {
            Text(SystemTools.Maintenance.quickLook.details)
        }
    }

    private func run(_ item: SystemTools.Maintenance) {
        guard active == nil else { return }
        active = item
        Task {
            do {
                results[item] = try await Task.detached(priority: .utility) { try item.execute() }.value
            } catch {
                results[item] = SystemTools.CommandResult(status: 1, output: error.localizedDescription)
            }
            active = nil
        }
    }
}

struct LiveView: View {
    @State private var readout = LiveReadout()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let sample = readout.sample {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 126), spacing: 11), count: 3), spacing: 11) {
                        metric("CPU", readout.cpuText, "cpu")
                        metric("Memory", sample.memoryUsed.map(FileTools.bytes) ?? "Unavailable", "memorychip",
                               detail: "of \(FileTools.bytes(sample.memoryTotal))")
                        metric("Disk available", sample.diskFree.map(FileTools.bytes) ?? "Unavailable", "internaldrive",
                               detail: sample.diskTotal.map { "of \(FileTools.bytes($0))" })
                        metric("Network", readout.network?.receive ?? "Sampling…", "arrow.down",
                               detail: readout.network.map { "\($0.send) up" })
                        metric("Battery", sample.battery ?? "No battery", "battery.75percent")
                        metric("Thermal pressure", sample.thermal, "thermometer.medium",
                               detail: "Uptime \(Duration.seconds(sample.uptime).formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2)))")
                    }
                    if !readout.history.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("CPU over the last minute").font(.headline)
                            Chart(readout.history) { point in
                                AreaMark(x: .value("Time", point.id), y: .value("CPU", point.value))
                                    .foregroundStyle(lagoon.opacity(0.19))
                                LineMark(x: .value("Time", point.id), y: .value("CPU", point.value))
                                    .foregroundStyle(lagoon)
                            }
                            .chartYScale(domain: 0...1)
                            .chartXAxis(.hidden)
                            .chartYAxis {
                                AxisMarks(values: [0.0, 0.5, 1.0]) { mark in
                                    AxisGridLine()
                                    AxisValueLabel { if let value = mark.as(Double.self) { Text(value.formatted(.percent)) } }
                                }
                            }
                            .frame(height: 82)
                        }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Top processes by CPU").font(.headline)
                        if sample.processes.isEmpty { Text("No process data available.").foregroundStyle(.secondary) }
                        ForEach(sample.processes) { process in
                            HStack {
                                Text(process.name).lineLimit(1)
                                Text(String(process.pid)).foregroundStyle(.tertiary)
                                Spacer()
                                Text((process.cpu / 100).formatted(.percent.precision(.fractionLength(1))))
                                    .frame(width: 80, alignment: .trailing)
                                Text(FileTools.bytes(process.residentBytes))
                                    .frame(width: 80, alignment: .trailing)
                            }.monospacedDigit()
                            Divider()
                        }
                    }
                } else {
                    ProgressView("Reading system metrics…")
                }
            }.padding(.trailing, 6)
        }.task { await readout.poll(includeProcesses: true) }
    }

    private func metric(_ label: String, _ value: String, _ symbol: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: symbol).foregroundStyle(.secondary).font(.caption)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            if let detail { Text(detail).foregroundStyle(.secondary).font(.caption).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, minHeight: 69, alignment: .topLeading)
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
    }
}

struct MenuStatus: View {
    @Environment(\.openWindow) private var openWindow
    @State private var readout = LiveReadout()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hole").font(.headline)
            if let sample = readout.sample {
                row("CPU", readout.cpuText)
                row("Memory", sample.memoryUsed.map(FileTools.bytes) ?? "Unavailable")
                row("Storage free", sample.diskFree.map(FileTools.bytes) ?? "Unavailable")
                if let battery = sample.battery { row("Battery", battery) }
            } else {
                ProgressView()
            }
            Divider()
            Button("Open Hole") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
        }.padding(15).frame(width: 235)
            .task { await readout.poll(includeProcesses: false) }
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack { Text(key); Spacer(); Text(value).monospacedDigit() }
    }
}

@MainActor @Observable
final class LiveReadout {
    struct Point: Identifiable {
        let id: TimeInterval
        let value: Double
    }

    var sample: SystemTools.Snapshot?
    var history: [Point] = []
    var network: (receive: String, send: String)?
    var cpuText = "Sampling…"

    func poll(includeProcesses: Bool) async {
        while !Task.isCancelled {
            let current = await Task.detached(priority: .utility) {
                SystemTools.snapshot(includeProcesses: includeProcesses)
            }.value
            guard !Task.isCancelled else { return }
            if let fraction = current.cpu?.usage(since: sample?.cpu) {
                cpuText = fraction.formatted(.percent.precision(.fractionLength(0)))
                history.append(Point(id: current.timestamp, value: fraction))
                history.removeAll { $0.id < current.timestamp - 60 }
            }
            if let previous = sample,
               let rates = current.network?.rates(since: previous.network, seconds: current.timestamp - previous.timestamp) {
                network = (FileTools.bytes(rates.receive) + "/s", FileTools.bytes(rates.send) + "/s")
            } else {
                network = nil
            }
            sample = current
            try? await Task.sleep(for: .seconds(2))
        }
    }
}
