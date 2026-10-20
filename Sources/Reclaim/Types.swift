import Foundation
import SwiftUI

// MARK: - Cleanup targets

enum Risk {
    case safe, review, careful

    var label: String {
        switch self {
        case .safe: return "Safe to clear"
        case .review: return "Check first"
        case .careful: return "Can't be undone"
        }
    }

    var color: Color {
        switch self {
        case .safe: return Palette.mint
        case .review: return Palette.sand
        case .careful: return Palette.coral
        }
    }
}

enum TargetKind {
    case trashContents
    case command([[String]])
    case ollama
    case explore
    case emptyTrash

    var isOllama: Bool { if case .ollama = self { return true } else { return false } }
    var isExplore: Bool { if case .explore = self { return true } else { return false } }
    var movesToTrash: Bool { if case .trashContents = self { return true } else { return false } }
}

struct TargetDef: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let paths: [String]
    let risk: Risk
    let kind: TargetKind
    let label: String
    let about: String
    var inTotal: Bool = true
    var always: Bool = false

    var existingPaths: [String] { paths.filter { FileManager.default.fileExists(atPath: $0) } }

    var tool: String? {
        switch kind {
        case .command(let cmds): return cmds.first?.first
        case .ollama: return "ollama"
        default: return nil
        }
    }

    var isAvailable: Bool {
        guard let tool else { return true }
        return Shell.which(tool) != nil
    }

    var commandText: String? {
        if case .command(let cmds) = kind {
            return cmds.map { $0.joined(separator: " ") }.joined(separator: " && ")
        }
        return nil
    }

    /// Whether this item can be ticked for a one-click clean.
    var isBatchable: Bool {
        switch kind {
        case .trashContents, .command, .emptyTrash: return true
        case .ollama, .explore: return false
        }
    }

    var showsInMap: Bool {
        if case .explore = kind { return false }
        return id != "trash"
    }
}

enum Targets {
    static let all: [TargetDef] = [
        TargetDef(id: "ollama", name: "Ollama models", symbol: "brain", paths: [Paths.h(".ollama/models")],
                  risk: .review, kind: .ollama, label: "Choose Models",
                  about: "Local AI models. Each is several gigabytes; remove the ones you no longer run."),
        TargetDef(id: "docker", name: "Docker images & build cache", symbol: "shippingbox",
                  paths: [Paths.h(".colima"), Paths.h("Library/Containers/com.docker.docker")],
                  risk: .review, kind: .command([["docker", "system", "prune", "-af"]]), label: "Prune",
                  about: "Stopped containers, unused images and build cache. Volumes are kept. Docker must be running."),
        TargetDef(id: "idea", name: "IntelliJ snapshots", symbol: "camera.metering.matrix",
                  paths: [Paths.h("IdeaSnapshots")], risk: .safe, kind: .trashContents, label: "Clear",
                  about: "Profiler snapshots. Only needed while you're analysing one."),
        TargetDef(id: "maven", name: "Maven repository", symbol: "cup.and.saucer",
                  paths: [Paths.h(".m2/repository")], risk: .safe, kind: .trashContents, label: "Clear",
                  about: "Downloaded Java dependencies. Fetched again on the next build."),
        TargetDef(id: "gradle", name: "Gradle caches", symbol: "cup.and.saucer.fill",
                  paths: [Paths.h(".gradle/caches")], risk: .safe, kind: .trashContents, label: "Clear",
                  about: "Dependency and build caches. Rebuilt on the next build."),
        TargetDef(id: "npm", name: "npm cache", symbol: "curlybraces", paths: [Paths.h(".npm")], risk: .safe,
                  kind: .command([["npm", "cache", "clean", "--force"]]), label: "Clean",
                  about: "Cached package downloads. npm fetches them again when needed."),
        TargetDef(id: "go", name: "Go module cache", symbol: "chevron.left.forwardslash.chevron.right",
                  paths: [Paths.h("go/pkg/mod")], risk: .safe,
                  kind: .command([["go", "clean", "-modcache"]]), label: "Clean",
                  about: "Downloaded Go modules. Downloaded again on the next build."),
        TargetDef(id: "dotcache", name: "Command-line tool caches", symbol: "terminal",
                  paths: [Paths.h(".cache")], risk: .review, kind: .trashContents, label: "Clear",
                  about: "pip, uv, pre-commit and friends. Hugging Face models live here too, so look first."),
        TargetDef(id: "caches", name: "App caches", symbol: "archivebox", paths: [Paths.h("Library/Caches")],
                  risk: .review, kind: .trashContents, label: "Clear",
                  about: "Temporary data apps rebuild on their own. Some apps keep offline downloads here, so quit apps and look first."),
        TargetDef(id: "brew", name: "Homebrew leftovers", symbol: "mug",
                  paths: [Paths.h("Library/Caches/Homebrew")], risk: .safe,
                  kind: .command([["brew", "cleanup", "--prune=all"]]), label: "Clean",
                  about: "Old package versions and installer downloads. Counted inside App caches.",
                  inTotal: false),
        TargetDef(id: "derived", name: "Xcode build data", symbol: "hammer",
                  paths: [Paths.h("Library/Developer/Xcode/DerivedData")], risk: .safe,
                  kind: .trashContents, label: "Clear",
                  about: "Intermediate build files. Xcode rebuilds them on the next build."),
        TargetDef(id: "devsupport", name: "Xcode device support", symbol: "iphone",
                  paths: [Paths.h("Library/Developer/Xcode/iOS DeviceSupport")], risk: .safe,
                  kind: .trashContents, label: "Clear",
                  about: "Debug symbols for iPhones you've plugged in. Recreated when you reconnect."),
        TargetDef(id: "sims", name: "Unavailable simulators", symbol: "ipad.and.iphone",
                  paths: [Paths.h("Library/Developer/CoreSimulator")], risk: .review,
                  kind: .command([["xcrun", "simctl", "delete", "unavailable"]]), label: "Remove",
                  about: "Simulators for iOS versions that are no longer installed."),
        TargetDef(id: "downloads", name: "Downloads", symbol: "arrow.down.circle",
                  paths: [Paths.h("Downloads")], risk: .review, kind: .explore, label: "Explore",
                  about: "Old installers and archives pile up here.", inTotal: false),
        TargetDef(id: "trash", name: "Trash", symbol: "trash", paths: [Paths.trash], risk: .careful,
                  kind: .emptyTrash, label: "Empty",
                  about: "Trashed files still use space until the Trash is emptied.",
                  inTotal: false, always: true),
    ]
}

// MARK: - UI state

struct TargetSize {
    var bytes: Int64?
    var limited: Bool
    var measuring: Bool
}

struct LogEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let text: String
    let ok: Bool
    let output: String
    var freed: Int64 = 0
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let ok: Bool
}

struct PendingAction: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var items: [String] = []
    var command: String? = nil
    let confirmLabel: String
    var destructive: Bool = false
    var typeToConfirm: String? = nil
    let perform: @MainActor () async -> Void
}

struct TrashItem {
    let path: String
    let name: String
    let size: Int64
}

struct Crumb: Hashable {
    let label: String
    let path: String
}

enum LoadState: Equatable {
    case idle, loading, loaded
}

enum MapStyle: String, CaseIterable, Identifiable {
    case rings, blocks
    var id: String { rawValue }
}

/// Progress of a one-click clean.
struct BatchRun: Equatable {
    var total: Int
    var done: Int
    var current: String
    var freed: Int64
}

enum InsightAction {
    case open(AppSection)
    case runTarget(String)
    case explore(String)
    case quickClean
    case fullDiskAccess
}

struct Insight: Identifiable {
    let id: String
    let symbol: String
    let tint: Color
    let headline: String
    let detail: String
    let bytes: Int64?
    let actionTitle: String
    let action: InsightAction
    let priority: Double
}

enum AppSection: String, CaseIterable, Identifiable {
    case overview, clean, map, projects, files, duplicates, apps, history
    var id: AppSection { self }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .clean: return "Smart Clean"
        case .map: return "Space Map"
        case .projects: return "Projects"
        case .files: return "Large Files"
        case .duplicates: return "Duplicates"
        case .apps: return "Apps"
        case .history: return "History"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.67percent"
        case .clean: return "sparkles"
        case .map: return "circle.circle"
        case .projects: return "folder.badge.gearshape"
        case .files: return "doc.text.magnifyingglass"
        case .duplicates: return "square.on.square"
        case .apps: return "square.grid.3x3"
        case .history: return "chart.xyaxis.line"
        }
    }

    var group: String {
        switch self {
        case .overview, .clean: return "Reclaim"
        case .map, .projects, .files, .duplicates, .apps: return "Discover"
        case .history: return "Track"
        }
    }
}
