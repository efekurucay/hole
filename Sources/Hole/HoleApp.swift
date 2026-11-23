import AppKit
import SwiftUI

@main
struct HoleApp: App {
    @AppStorage("showMenuBar") private var showMenuBar = false

    init() {
        if CommandLine.arguments.dropFirst() == ["--self-test"] {
            do {
                try SmokeTest.run()
                print("Hole self-test passed.")
                exit(0)
            } catch {
                fputs("Hole self-test failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
    }

    var body: some Scene {
        Window("Hole", id: "main") {
            Workspace()
                .frame(minWidth: 900, minHeight: 610)
        }
        .defaultSize(width: 1080, height: 720)

        Settings {
            Form {
                Toggle("Show live status in menu bar", isOn: $showMenuBar)
            }.padding(22).frame(width: 350)
        }

        MenuBarExtra("Hole", systemImage: "circle.dotted.circle", isInserted: $showMenuBar) {
            MenuStatus()
        }
        .menuBarExtraStyle(.window)
    }
}

enum Area: String, CaseIterable, Identifiable {
    case cleanup = "Cleanup"
    case apps = "Applications"
    case disk = "Disk explorer"
    case maintenance = "Maintenance"
    case status = "Live status"

    var id: Self { self }
    var symbol: String {
        switch self {
        case .cleanup: "sparkle.magnifyingglass"
        case .apps: "square.stack"
        case .disk: "square.split.2x2"
        case .maintenance: "wrench.adjustable"
        case .status: "waveform.path"
        }
    }
    var subtitle: String {
        switch self {
        case .cleanup: "Find caches and logs and review what you can reclaim."
        case .apps: "Browse installed software, review related files, and check for updates."
        case .disk: "See which files and folders take up the most space."
        case .maintenance: "Run focused macOS checks and maintenance tasks."
        case .status: "Watch this Mac’s resource use and busiest processes."
        }
    }
}

let lagoon = Color(red: 0.06, green: 0.40, blue: 0.42)
let deepSea = Color(red: 0.045, green: 0.15, blue: 0.18)
let seaFoam = Color(red: 0.63, green: 0.94, blue: 0.79)
let shore = Color(red: 0.99, green: 0.77, blue: 0.46)

struct Workspace: View {
    @State private var area: Area = .cleanup
    @State private var ai = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(area.rawValue).font(.system(size: 35, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(area.subtitle).foregroundStyle(.secondary)
                }
                Divider()
                Group {
                    switch area {
                    case .cleanup: cleanup
                    case .apps: ApplicationsView()
                    case .disk: DiskView()
                    case .maintenance: MaintenanceView()
                    case .status: LiveView()
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(28)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(lagoon)
    }

    private var cleanup: some View {
        VStack(alignment: .leading, spacing: 15) {
            Toggle("Include AI and developer caches", isOn: $ai)
                .toggleStyle(.switch)
            ScanPanel(target: .cleanup(ai)).id(ai)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 11) {
                if let icon = NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: icon).resizable().interpolation(.high)
                        .frame(width: 45, height: 45).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Hole").font(.title2.weight(.semibold))
                    Text("by AkdenizOS").font(.caption).foregroundStyle(seaFoam)
                }
            }.padding(.bottom, 27)
            ForEach(Area.allCases) { item in
                Button { area = item } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.symbol).frame(width: 19)
                        Text(item.rawValue)
                        Spacer(minLength: 0)
                        if item == area {
                            Circle().fill(seaFoam).frame(width: 5, height: 5).accessibilityHidden(true)
                        }
                    }
                    .font(.system(size: 13, weight: item == area ? .semibold : .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 11).padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .background(item == area ? .white.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(item == area ? .isSelected : [])
            }
            Spacer()
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }.buttonStyle(.plain)
            .padding(10)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18).padding(.vertical, 24)
        .frame(width: 206)
        .frame(maxHeight: .infinity)
        .background(deepSea)
    }
}

struct EmptyPanel: View {
    let title: String
    let text: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Image(systemName: symbol).foregroundStyle(lagoon).font(.title)
            Text(title).font(.title2.weight(.semibold))
            Text(text).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}
