import AppKit
import SwiftUI

struct DiskView: View {
    @State private var locations: [URL] = []
    @State private var entries: [FileTools.Entry] = []
    @State private var skipped = 0
    @State private var scanning = false
    @State private var message = ""
    @State private var scanID = 0
    @State private var selected: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Button { if locations.count > 1 { locations.removeLast(); scan() } } label: {
                    Label("Up", systemImage: "arrow.up")
                }.disabled(locations.count < 2)
                if let folder = locations.last {
                    Text(folder.path).lineLimit(1).truncationMode(.head).help(folder.path)
                    Spacer()
                    if scanning {
                        Button("Cancel") { scanning = false; scanID += 1 }
                    } else {
                        Button("Refresh", action: scan)
                    }
                } else {
                    Spacer()
                }
                Button("Choose Folder…", action: chooseFolder).buttonStyle(.borderedProminent)
            }
            if scanning {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Measuring folder contents…").foregroundStyle(.secondary)
                }
            } else if !message.isEmpty {
                EmptyPanel(title: "Folder scan", text: message, symbol: "folder")
            } else if locations.isEmpty {
                EmptyPanel(title: "Choose a starting folder",
                           text: "Open a volume or directory to map its largest entries. Select a folder in the results to drill down.",
                           symbol: "square.split.2x2")
            } else if !entries.isEmpty {
                explorer
            }
        }
        .task(id: scanID) {
            guard let url = locations.last, scanning else { return }
            let worker = Task.detached(priority: .userInitiated) {
                guard FileTools.isPhysicalPath(url) else {
                    throw SystemTools.ToolError.message("This folder is unavailable.")
                }
                _ = try FileTools.children(url)
                return try FileTools.scan([("Storage", url)])
            }
            do {
                let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard !Task.isCancelled else { return }
                entries = result.entries
                skipped = result.skipped
                message = entries.isEmpty ? "This folder has no measurable entries." : ""
                scanning = false
            } catch {
                if !Task.isCancelled {
                    message = error.localizedDescription
                    scanning = false
                }
            }
        }
    }

    private var explorer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(entries.count) entries  •  \(FileTools.bytes(entries.reduce(0) { $0 + $1.bytes })) allocated")
                .foregroundStyle(.secondary).monospacedDigit()
            Treemap(entries: Array(entries.filter { $0.bytes > 0 }.prefix(14)), select: { item in
                if item.folder { enter(item) } else { selected = item.id }
            }).frame(height: 178)
            List(selection: $selected) {
                ForEach(entries) { item in
                    HStack {
                        Image(systemName: item.folder ? "folder" : "doc").foregroundStyle(lagoon)
                        Text(item.name).lineLimit(1)
                        Spacer()
                        Text(FileTools.bytes(item.bytes)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .tag(item.id)
                    .contextMenu {
                        if item.folder { Button("Open in Disk Explorer") { enter(item) } }
                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                    }
                }
            }.clipShape(RoundedRectangle(cornerRadius: 9))
            HStack {
                if skipped > 0 {
                    Text("\(skipped) paths were inaccessible or skipped.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let item = entries.first(where: { $0.id == selected }) {
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                    if item.folder { Button("Open Folder") { enter(item) } }
                }
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.resolvesAliases = true
        panel.prompt = "Scan Folder"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            locations = [url.resolvingSymlinksInPath()]
            scan()
        }
    }

    private func enter(_ item: FileTools.Entry) {
        locations.append(item.url)
        scan()
    }

    private func scan() {
        entries = []
        selected = nil
        skipped = 0
        message = ""
        scanning = true
        scanID += 1
    }
}

struct Treemap: View {
    let entries: [FileTools.Entry]
    var select: (FileTools.Entry) -> Void
    private let palette = [deepSea, lagoon, Color(red: 0.27, green: 0.56, blue: 0.54), seaFoam, shore]

    var body: some View {
        GeometryReader { geometry in
            let tiles = Self.partition(entries.map(\.bytes), rect: CGRect(origin: .zero, size: geometry.size))
            ForEach(Array(tiles.enumerated()), id: \.offset) { index, rect in
                let item = entries[index]
                Button { select(item) } label: {
                    ZStack(alignment: .topLeading) {
                        Rectangle().fill(palette[index % palette.count])
                        if rect.width > 85 && rect.height > 34 {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name).fontWeight(.semibold).lineLimit(1)
                                if rect.height > 55 {
                                    Text(FileTools.bytes(item.bytes)).font(.caption).monospacedDigit()
                                }
                            }
                            .padding(8)
                            .foregroundStyle(index % palette.count < 2 ? .white : deepSea)
                        }
                    }
                    .frame(width: max(1, rect.width - 2), height: max(1, rect.height - 2))
                    .clipped()
                }
                .buttonStyle(.plain)
                .help("\(item.name) · \(FileTools.bytes(item.bytes))")
                .accessibilityLabel("\(item.name), \(FileTools.bytes(item.bytes))")
                .position(x: rect.midX, y: rect.midY)
            }
        }.background(.quaternary.opacity(0.4)).clipShape(RoundedRectangle(cornerRadius: 10))
    }

    nonisolated static func partition(_ weights: [Int64], rect: CGRect) -> [CGRect] {
        guard let first = weights.first, first > 0 else { return [] }
        if weights.count == 1 { return [rect] }
        let total = weights.reduce(0, +)
        var split = 1
        var sum = first
        while split < weights.count - 1, sum + weights[split] / 2 < total / 2 {
            sum += weights[split]
            split += 1
        }
        let ratio = CGFloat(sum) / CGFloat(total)
        let (left, right) = rect.divided(atDistance: (rect.width >= rect.height ? rect.width : rect.height) * ratio,
                                         from: rect.width >= rect.height ? .minXEdge : .minYEdge)
        return partition(Array(weights[..<split]), rect: left)
            + partition(Array(weights[split...]), rect: right)
    }
}
