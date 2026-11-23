import Foundation

enum SmokeTest {
    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw SystemTools.ToolError.message(message) }
    }

    static func run() throws {
        let fm = FileManager.default
        let fixture = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .resolvingSymlinksInPath().appendingPathComponent("hole-fixture-\(UUID().uuidString)")
        let caches = fixture.appendingPathComponent("Library/Caches")
        let support = fixture.appendingPathComponent("Library/Application Support")
        let app = fixture.appendingPathComponent("Applications/Sample.app")
        for directory in [caches, support, app.appendingPathComponent("Contents")] {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleIdentifier": "example.fixture",
            "CFBundleName": "Sample",
            "CFBundlePackageType": "APPL"
        ], format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        let cache = caches.appendingPathComponent("example.fixture")
        let protected = fixture.appendingPathComponent("protected")
        try Data(repeating: 42, count: 8192).write(to: cache)
        try Data(repeating: 17, count: 4096).write(to: protected)
        try fm.createSymbolicLink(at: caches.appendingPathComponent("shortcut"), withDestinationURL: protected)
        try fm.createDirectory(at: support.appendingPathComponent("example.fixture"), withIntermediateDirectories: true)
        try fm.createDirectory(at: support.appendingPathComponent("example.fixture.other"), withIntermediateDirectories: true)
        let cleanup = try FileTools.cleanup(includeAI: true, home: fixture)
        try require(cleanup.entries.count == 1 && cleanup.entries.first?.name == "example.fixture", "Unexpected cleanup candidates")
        try require(cleanup.skipped == 1, "The link should be skipped")
        guard let entry = cleanup.entries.first else { throw SystemTools.ToolError.message("Missing fixture candidate") }
        try require(entry.bytes > 0, "Expected measurable cache")
        try require(FileTools.canTrash(entry, home: fixture), "Expected verified cache candidate")
        let sibling = caches.appendingPathComponent("different-inode")
        try Data(repeating: 0, count: 2048).write(to: sibling)
        let stale = FileTools.Entry(url: sibling, name: entry.name, group: entry.group,
                                    bytes: entry.bytes, folder: false, identity: entry.identity)
        try require(!FileTools.canTrash(stale, home: fixture), "Stale file identity should be rejected")
        let outside = FileTools.Entry(url: protected, name: "protected", group: entry.group,
                                      bytes: 4096, folder: false, identity: FileTools.Identity.read(protected))
        try require(!FileTools.canTrash(outside, home: fixture), "Paths outside supported folders should be rejected")
        let apps = FileTools.installedApps(roots: [fixture.appendingPathComponent("Applications")])
        try require(apps.map(\.identifier) == ["example.fixture"], "Expected one fixture app")
        let review = try FileTools.uninstallReview(apps[0], home: fixture)
        try require(Set(review.entries.map(\.group)) == Set(["Application", "Caches", "Application Support"]),
                    "Uninstall should return the app and exact bundle-ID matches")
        let tiles = Treemap.partition([80, 15, 5], rect: CGRect(x: 0, y: 0, width: 100, height: 100))
        try require(tiles.count == 3, "Expected three treemap tiles")
        try require(abs(tiles[0].width * tiles[0].height - 8000) < 0.1, "Treemap areas should be proportional")
        let status = SystemTools.snapshot(includeProcesses: true)
        try require(status.cpu != nil && status.memoryTotal > 0 && !status.processes.isEmpty, "Missing live metrics")
        try require(fm.fileExists(atPath: cache.path) && fm.fileExists(atPath: protected.path) && fm.fileExists(atPath: app.path),
                    "Read-only checks must preserve the fixture")
        print("Read-only fixture: \(fixture.path)")
    }
}
