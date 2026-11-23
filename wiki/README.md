# Hole design and artifact notes

## Reference artifact

The supplied Mole disk image contains Mole for Mac 1.21.0 (build 392, bundle ID `com.tw93.MoleApp`). Its SHA-256 is `c3950043c551a1ed15f945c29c3af69fbe4d71f336c911aa9de112054d3ddbe1`. A read-only REA inspection found 429 occurrences, including 343 regular files, 79 directories, and seven symbolic links, with zero integrity contradictions. The inventory is identified by `ev_d004520ef0d1335a7fec37277dce5a3e08809f736b519efbe6a58962315debfd`.

Local bundle inspection confirmed the following:

- `Info.plist` declares macOS 14 as the minimum version. The app and its packaged privileged helper are universal Mach-O binaries. The app passes strict bundle signature verification.
- The main executable links SwiftUI, AppKit, IOKit, ServiceManagement, and Sparkle. The Sparkle appcast is declared in `Info.plist`. The helper is declared under `SMPrivilegedExecutables`.
- Localized entries and executable strings provide evidence of cleanup and orphan detection, software management, disk scanning, maintenance, live status, and fan controls. Bundled JSON resources include app-file mappings and folder notes. The scope of each runtime action cannot be established from those names alone.

The public repository ships the GPL-3.0 command-line tool. The native Mac app is a separate distribution. The public website describes the desktop workflows and which operations require authorization. [Mole repository](https://github.com/tw93/Mole) · [Mole for Mac](https://mole.fit/)

The reference inspection was static. The DMG was mounted read-only. No source recovery, runtime execution, helper installation, or license interaction was needed.

## Implementation

- `HoleApp.swift` defines the window, feature navigation, app settings, and menu-bar entry.
- `ReviewViews.swift` implements the cleanup review, app footprint review, and Homebrew update list.
- `FileTools.swift` scans with cancellation, matches exact bundle identifiers, and checks candidate identity and allowed parent paths before a Finder Trash operation.
- `DiskView.swift` maps allocated file bytes into proportional treemap areas, with a folder chooser, drill-down, and Finder reveal. Sizes are estimates for APFS clones, shared blocks, cross-volume locations, and inaccessible paths.
- `SystemTools.swift` samples system metrics and wraps the macOS maintenance commands. `StatusViews.swift` presents the measurements and maintenance results.
- `scripts/render-icon.swift` draws the original AkdenizOS icon. `scripts/build.sh` compiles, packages, and verifies the app with macOS tools.

Hole covers core workflows with a narrower scope. It uses exact bundle identifiers instead of the shipped app's curated catalog, and checks Homebrew updates while delegating App Store and macOS updates to the system. Maintenance works at user level. Mole-specific features such as privileged maintenance, fan control, AI session and worktree management, and vendor-specific update integrations are outside this release.
