import AppKit
import Foundation

enum FileTools {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let keys: Set<URLResourceKey> = [
        .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey, .fileSizeKey
    ]

    struct Entry: Identifiable, Sendable {
        let url: URL
        let name: String
        let group: String
        let bytes: Int64
        let folder: Bool
        let identity: Identity?
        var id: URL { url }
    }

    struct Identity: Equatable, Sendable {
        let device: dev_t
        let inode: ino_t
        let birthSeconds: Int
        let birthNanoseconds: Int

        static func read(_ url: URL) -> Self? {
            var info = stat()
            guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT != S_IFLNK else { return nil }
            return Self(device: info.st_dev, inode: info.st_ino,
                        birthSeconds: info.st_birthtimespec.tv_sec, birthNanoseconds: info.st_birthtimespec.tv_nsec)
        }
    }

    struct Scan: Sendable {
        let entries: [Entry]
        let skipped: Int
    }

    struct InstalledApp: Identifiable, Sendable {
        let url: URL
        let name: String
        let identifier: String
        let version: String
        var id: URL { url }
    }

    static func children(_ url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys), options: [])
    }

    static func allocatedSize(_ values: URLResourceValues) -> Int64 {
        Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
    }

    static func scan(_ roots: [(String, URL)], includeHidden: Bool = true) throws -> Scan {
        var entries: [Entry] = []
        var skipped = 0
        for (group, root) in roots {
            try Task.checkCancellation()
            guard Identity.read(root) != nil, isPhysicalPath(root) else { continue }
            let urls: [URL]
            do { urls = try children(root) } catch { skipped += 1; continue }
            for url in urls where includeHidden || !url.lastPathComponent.hasPrefix(".") {
                try Task.checkCancellation()
                if let entry = try measure(url, group: group, skipped: &skipped) {
                    entries.append(entry)
                }
            }
        }
        return Scan(entries: entries.sorted { $0.bytes == $1.bytes ? $0.name < $1.name : $0.bytes > $1.bytes }, skipped: skipped)
    }

    static func measure(_ url: URL, group: String, skipped: inout Int) throws -> Entry? {
        guard let values = try? url.resourceValues(forKeys: keys), let identity = Identity.read(url) else {
            skipped += 1
            return nil
        }
        let directory = values.isDirectory == true
        var bytes = allocatedSize(values)
        var unreadable = 0
        if directory {
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys),
                                                            options: [], errorHandler: { _, _ in unreadable += 1; return true })
            var visited: Set<ino_t> = []
            while let child = enumerator?.nextObject() as? URL {
                try Task.checkCancellation()
                guard let childIdentity = Identity.read(child), childIdentity.device == identity.device,
                      let childValues = try? child.resourceValues(forKeys: keys) else {
                    enumerator?.skipDescendants()
                    unreadable += 1
                    continue
                }
                if visited.insert(childIdentity.inode).inserted {
                    bytes += allocatedSize(childValues)
                }
            }
            if enumerator == nil { unreadable += 1 }
        }
        skipped += unreadable
        return Entry(url: url, name: url.lastPathComponent, group: group, bytes: bytes,
                     folder: directory && values.isPackage != true, identity: identity)
    }

    static func cleanup(includeAI: Bool, home: URL = home) throws -> Scan {
        var roots = [
            ("User caches", home.appendingPathComponent("Library/Caches")),
            ("User logs", home.appendingPathComponent("Library/Logs"))
        ]
        if includeAI {
            roots += [
                ("Hugging Face cache", home.appendingPathComponent(".cache/huggingface/hub")),
                ("uv cache", home.appendingPathComponent(".cache/uv"))
            ]
        }
        return try scan(roots, includeHidden: false)
    }

    static func installedApps(roots: [URL] = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]) -> [InstalledApp] {
        var apps: [InstalledApp] = []
        for root in roots where isPhysicalPath(root) {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator {
                if Task.isCancelled { return [] }
                guard let values = try? url.resourceValues(forKeys: keys), values.isSymbolicLink != true else {
                    enumerator.skipDescendants()
                    continue
                }
                guard url.pathExtension.lowercased() == "app" else { continue }
                enumerator.skipDescendants()
                guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier,
                      identifier != Bundle.main.bundleIdentifier else { continue }
                let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? url.deletingPathExtension().lastPathComponent
                let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
                apps.append(InstalledApp(url: url, name: name, identifier: identifier, version: version))
            }
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func uninstallReview(_ app: InstalledApp, home: URL = home) throws -> Scan {
        var skipped = 0
        var entries: [Entry] = []
        if let item = try measure(app.url, group: "Application", skipped: &skipped) { entries.append(item) }
        let id = app.identifier
        guard !id.isEmpty, id != ".", id != "..",
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || ".-_".contains($0)) }) else {
            return Scan(entries: entries, skipped: skipped)
        }
        // Exact bundle-identifier matches avoid treating similarly named apps as related.
        let candidates = [
            ("Caches", "Caches/\(id)"),
            ("Logs", "Logs/\(id)"),
            ("Application Support", "Application Support/\(id)"),
            ("Preferences", "Preferences/\(id).plist"),
            ("Saved State", "Saved Application State/\(id).savedState"),
            ("Container", "Containers/\(id)")
        ]
        for (group, path) in candidates {
            let url = home.appendingPathComponent("Library").appendingPathComponent(path)
            guard isPhysicalPath(url) else { continue }
            if let item = try measure(url, group: group, skipped: &skipped) { entries.append(item) }
        }
        return Scan(entries: entries, skipped: skipped)
    }

    static func isPhysicalPath(_ url: URL) -> Bool {
        // Reject ancestor symlinks as well as symlink entries.
        let path = url.standardizedFileURL.path
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().path == path && Identity.read(url) != nil
    }

    static func canTrash(_ entry: Entry, home: URL = home) -> Bool {
        guard let identity = entry.identity, isPhysicalPath(entry.url),
              Identity.read(entry.url) == identity,
              Identity.read(entry.url.deletingLastPathComponent())?.device == identity.device else { return false }
        let path = entry.url.standardizedFileURL.path
        if entry.group == "Application" {
            return entry.url.pathExtension.lowercased() == "app"
                && (path.hasPrefix("/Applications/") || path.hasPrefix(home.appendingPathComponent("Applications").path + "/"))
        }
        let allowedParents = [
            "Library/Caches", "Library/Logs", "Library/Application Support", "Library/Preferences",
            "Library/Saved Application State", "Library/Containers", ".cache/huggingface/hub", ".cache/uv"
        ].map { home.appendingPathComponent($0).path }
        return allowedParents.contains(entry.url.deletingLastPathComponent().standardizedFileURL.path)
    }

    static func trash(_ entries: [Entry]) -> (moved: Set<URL>, errors: [String]) {
        var moved: Set<URL> = []
        var errors: [String] = []
        for entry in entries {
            guard canTrash(entry) else {
                errors.append("\(entry.name) changed since the scan or is outside the allowed folders.")
                continue
            }
            do {
                try FileManager.default.trashItem(at: entry.url, resultingItemURL: nil)
                moved.insert(entry.id)
            } catch {
                errors.append("\(entry.name) — \(error.localizedDescription)")
            }
        }
        return (moved, errors)
    }

    static func bytes(_ size: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
