import AppKit
import SwiftUI

struct ScanPanel: View {
    enum Target: Sendable {
        case cleanup(Bool)
        case app(FileTools.InstalledApp)

        func scan() throws -> FileTools.Scan {
            switch self {
            case .cleanup(let ai): try FileTools.cleanup(includeAI: ai)
            case .app(let app): try FileTools.uninstallReview(app)
            }
        }

        var application: FileTools.InstalledApp? {
            if case .app(let app) = self { app } else { nil }
        }
    }

    let target: Target
    var didMoveApp: () -> Void = {}
    @State private var entries: [FileTools.Entry]?
    @State private var selected: Set<URL> = []
    @State private var query = ""
    @State private var skipped = 0
    @State private var busy = false
    @State private var scanID = 0
    @State private var confirming = false
    @State private var message = ""
    @State private var problems: [String] = []

    private var visible: [FileTools.Entry] {
        (entries ?? []).filter {
            query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
                || $0.group.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                if busy {
                    ProgressView().controlSize(.small)
                    Text("Scanning…").foregroundStyle(.secondary)
                } else if let entries {
                    Text("\(entries.count) items")
                    Text(FileTools.bytes(entries.reduce(0) { $0 + $1.bytes }))
                        .foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                if busy {
                    Button("Cancel") { busy = false; scanID += 1 }
                } else {
                    Button(entries == nil ? "Scan" : "Rescan") {
                        busy = true
                        message = ""
                        selected = []
                        scanID += 1
                    }.buttonStyle(.borderedProminent)
                }
            }
            if !message.isEmpty { Text(message).foregroundStyle(.secondary) }
            if !problems.isEmpty {
                DisclosureGroup("\(problems.count) items need attention") {
                    ForEach(Array(problems.enumerated()), id: \.offset) { _, problem in
                        Text(problem).textSelection(.enabled)
                    }
                }
            }
            if let entries, !busy {
                if entries.isEmpty {
                    EmptyPanel(title: "Nothing to review", text: "The scan found no matching items in the available folders.", symbol: "checkmark.circle")
                } else {
                    results
                }
                if skipped > 0 {
                    Text("\(skipped) paths were inaccessible or skipped. Sizes are estimates.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if !busy {
                EmptyPanel(title: target.application == nil ? "Review starts with a scan" : "Review app files",
                           text: target.application == nil
                           ? "Scan supported cache and log folders, then choose individual items."
                           : "Review the app bundle and files whose names match its bundle identifier.",
                           symbol: target.application == nil ? "sparkle.magnifyingglass" : "square.stack")
            }
        }
        .task(id: scanID) {
            guard busy else { return }
            let target = target
            let worker = Task.detached(priority: .userInitiated) { try target.scan() }
            do {
                let scan = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard !Task.isCancelled else { return }
                entries = scan.entries
                skipped = scan.skipped
                problems = []
                busy = false
            } catch is CancellationError {
                if !Task.isCancelled { busy = false }
            } catch {
                message = error.localizedDescription
                busy = false
            }
        }
        .confirmationDialog("Move \(selected.count) items to Trash?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive, action: moveSelected)
        } message: {
            Text("Selected items can be restored from the Finder’s Trash.")
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Filter results", text: $query)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 250)
                Button("Select visible") { selected.formUnion(visible.map(\.id)) }.disabled(visible.isEmpty)
                Button("Clear selection") { selected.removeAll() }.disabled(selected.isEmpty)
            }
            List(visible) { item in
                HStack(spacing: 12) {
                    Toggle(isOn: Binding(
                        get: { selected.contains(item.id) },
                        set: { if $0 { selected.insert(item.id) } else { selected.remove(item.id) } }
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name).fontWeight(.medium).lineLimit(1)
                            Text(item.group).foregroundStyle(.secondary).font(.caption)
                        }
                    }.toggleStyle(.checkbox)
                    Spacer()
                    Text(FileTools.bytes(item.bytes)).monospacedDigit().foregroundStyle(.secondary)
                }
                .help(item.url.path)
                .contextMenu {
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                    Text(item.url.path)
                }
            }.clipShape(RoundedRectangle(cornerRadius: 9))
            HStack {
                Text("\(selected.count) selected").foregroundStyle(.secondary)
                Spacer()
                Button("Move Selected to Trash", role: .destructive) { confirming = true }
                    .disabled(selected.isEmpty)
            }
        }
    }

    private func moveSelected() {
        if let app = target.application, !NSRunningApplication.runningApplications(withBundleIdentifier: app.identifier).isEmpty {
            message = "Quit \(app.name) before moving its files to Trash."
            return
        }
        let result = FileTools.trash((entries ?? []).filter { selected.contains($0.id) })
        entries?.removeAll { result.moved.contains($0.id) }
        selected.subtract(result.moved)
        message = "Moved \(result.moved.count) items to Trash."
        problems = result.errors
        if let app = target.application, result.moved.contains(app.id), result.errors.isEmpty { didMoveApp() }
    }
}

struct ApplicationsView: View {
    @State private var apps: [FileTools.InstalledApp] = []
    @State private var selection: URL?
    @State private var query = ""
    @State private var showUpdates = false
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                TextField("Find an application", text: $query).textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 230)
                Spacer()
                Button("Login Items") {
                    open("x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
                }
                Button("Software Updates") { showUpdates = true }
            }
            if loading { ProgressView("Loading applications…") }
            HSplitView {
                List(selection: $selection) {
                    ForEach(apps.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { app in
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                                .resizable().frame(width: 25, height: 25).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name).lineLimit(1)
                                Text(app.version).font(.caption).foregroundStyle(.secondary)
                            }
                        }.tag(app.id)
                    }
                }.frame(minWidth: 170, idealWidth: 190)
                VStack(alignment: .leading, spacing: 12) {
                    if let app = apps.first(where: { $0.id == selection }) {
                        Text(app.name).font(.title2.weight(.semibold))
                        Text(app.identifier).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        ScanPanel(target: .app(app)) {
                            apps.removeAll { $0.id == app.id }
                        }.id(app.id)
                    } else {
                        EmptyPanel(title: "Choose an application",
                                   text: "Select an installed app to inspect its footprint.", symbol: "square.stack")
                    }
                }.padding(.leading, 12).frame(minWidth: 375, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .task {
            let worker = Task.detached(priority: .userInitiated) { FileTools.installedApps() }
            apps = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            loading = false
        }
        .sheet(isPresented: $showUpdates) { UpdatesView() }
    }
}

struct UpdatesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var updates: [SystemTools.Update] = []
    @State private var message = "Select Check Homebrew to see outdated packages."
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Software Updates").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            HStack {
                Button("App Store") { open("macappstore://showUpdatesPage") }
                Button("macOS Software Update") { open("x-apple.systempreferences:com.apple.Software-Update-Settings.extension") }
                Button("Check Homebrew") { check() }.disabled(checking)
            }
            if checking { ProgressView().controlSize(.small) }
            Text(message).foregroundStyle(.secondary).textSelection(.enabled)
            List(updates) { update in
                HStack {
                    Text(update.name)
                    Text(update.kind).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(update.installed) → \(update.available)").monospacedDigit()
                }
            }
        }.padding(22).frame(width: 565, height: 365)
    }

    private func check() {
        checking = true
        Task {
            do {
                if let result = try await Task.detached(priority: .utility, operation: { try SystemTools.brewUpdates() }).value {
                    updates = result
                    message = result.isEmpty ? "Homebrew reports no available updates." : "\(result.count) Homebrew updates available."
                } else {
                    updates = []
                    message = "Homebrew was not found in its standard installation paths."
                }
            } catch {
                updates = []
                message = error.localizedDescription
            }
            checking = false
        }
    }
}

@MainActor
func open(_ url: String) {
    if let url = URL(string: url) { NSWorkspace.shared.open(url) }
}
