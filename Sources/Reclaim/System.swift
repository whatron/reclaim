import AppKit
import CoreServices
import Foundation

// MARK: - Paths

enum Paths {
    static let home: String = NSHomeDirectory()
    static let trash: String = home + "/.Trash"

    static func h(_ relative: String) -> String { home + "/" + relative }

    static func tilde(_ path: String) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + String(path.dropFirst(home.count)) }
        return path
    }

    static func parent(_ path: String) -> String { (path as NSString).deletingLastPathComponent }
    static func name(_ path: String) -> String { (path as NSString).lastPathComponent }
    static func ext(_ path: String) -> String { (path as NSString).pathExtension.lowercased() }
}

// MARK: - Safety

/// Folders Reclaim will never move to the Trash, even if asked.
enum Safety {
    static let protectedExact: Set<String> = Set([
        Paths.home, Paths.trash,
        Paths.h("Library"), Paths.h("Desktop"), Paths.h("Documents"), Paths.h("Downloads"),
        Paths.h("Pictures"), Paths.h("Movies"), Paths.h("Music"), Paths.h("Applications"),
        Paths.h("Public"), Paths.h(".config"), Paths.h(".local"),
        Paths.h("Library/Application Support"), Paths.h("Library/Containers"),
        Paths.h("Library/Group Containers"), Paths.h("Library/Caches"),
        Paths.h("Library/Developer"), Paths.h("Library/Preferences"),
    ].map { ($0 as NSString).resolvingSymlinksInPath })

    static let protectedTrees: [String] = [
        Paths.h(".ssh"), Paths.h(".gnupg"), Paths.h(".aws"), Paths.h(".kube"),
        Paths.h("Library/Keychains"), Paths.h("Library/Mobile Documents"),
        Paths.h("Library/Mail"), Paths.h("Library/Messages"),
        Paths.h("Library/CloudStorage"), Paths.trash,
    ].map { ($0 as NSString).resolvingSymlinksInPath }

    static func isProtected(_ path: String) -> Bool {
        let resolved = (path as NSString).resolvingSymlinksInPath
        guard resolved.hasPrefix(Paths.home + "/") else { return true }
        if protectedExact.contains(resolved) { return true }
        if packageInterior(resolved) { return true }
        return protectedTrees.contains { resolved == $0 || resolved.hasPrefix($0 + "/") }
    }

    /// Files inside Photos/Music libraries and app bundles must never be touched one by one.
    static func packageInterior(_ path: String) -> Bool {
        let markers = [".photoslibrary/", ".musiclibrary/", ".tvlibrary/", ".imovielibrary/",
                       ".fcpbundle/", ".logicx/", ".app/", ".photolibrary/"]
        return markers.contains { path.contains($0) }
    }

    /// Third-party apps in /Applications or ~/Applications may be trashed; Apple's own may not.
    static func isTrashableApp(_ path: String) -> Bool {
        guard path.hasSuffix(".app") else { return false }
        let parent = Paths.parent(path)
        guard parent == "/Applications" || parent == Paths.h("Applications") else { return false }
        guard let id = Bundle(path: path)?.bundleIdentifier else { return true }
        if id.hasPrefix("com.apple.") { return false }
        if id == Bundle.main.bundleIdentifier { return false }
        return true
    }

    static func canTrash(_ path: String) -> Bool { !isProtected(path) || isTrashableApp(path) }

    static func isInsideHome(_ path: String) -> Bool {
        path == Paths.home || path.hasPrefix(Paths.home + "/")
    }
}

// MARK: - Data types

struct DiskInfo: Equatable {
    let total: Int64
    let free: Int64
    var used: Int64 { max(0, total - free) }
}

struct DiskNode: Identifiable, Hashable {
    var id: String { path }
    let name: String
    let path: String
    let size: Int64
    let isDir: Bool
    let isProtected: Bool
    var isGroup: Bool = false
    var children: [DiskNode] = []

    static func == (a: DiskNode, b: DiskNode) -> Bool { a.path == b.path && a.size == b.size }
    func hash(into hasher: inout Hasher) { hasher.combine(path) }
}

struct FolderScan: Equatable {
    let path: String
    let size: Int64
    let children: [DiskNode]
    let limited: Bool
}

struct OllamaModel: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let size: String
    let modified: String
    let ageDays: Int?
}

struct ShellResult {
    let ok: Bool
    let stdout: String
    let stderr: String
    var output: String {
        [stdout, stderr].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

/// Runs blocking work off the main thread.
func background<T>(_ work: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            continuation.resume(returning: work())
        }
    }
}

/// A value shared between threads behind a lock.
final class LockedBox<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()
    init(_ value: T) { self.value = value }
    func mutate(_ change: (inout T) -> Void) {
        lock.lock()
        change(&value)
        lock.unlock()
    }
    var current: T {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

// MARK: - Spotlight metadata

enum Spotlight {
    static func lastUsed(_ path: String) -> Date? {
        guard let item = MDItemCreate(kCFAllocatorDefault, path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    static func kind(_ path: String) -> String? {
        guard let item = MDItemCreate(kCFAllocatorDefault, path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemKind) as? String
    }
}

// MARK: - Formatting

enum Format {
    static func bytes(_ n: Int64?) -> String {
        guard let n else { return "—" }
        return ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    /// The big hero number: ("212", "GB free").
    static func bigFree(_ n: Int64) -> (number: String, unit: String) {
        let gb = Double(n) / 1e9
        if gb >= 1000 { return (String(format: "%.2f", gb / 1000), "TB free") }
        return (String(format: gb < 10 ? "%.1f" : "%.0f", gb), "GB free")
    }

    static func short(_ n: Int64) -> String {
        let gb = Double(n) / 1e9
        if gb >= 1000 { return String(format: "%.1f TB", gb / 1000) }
        if gb < 1 { return String(format: "%.0f MB", Double(n) / 1e6) }
        return String(format: gb < 10 ? "%.1f GB" : "%.0f GB", gb)
    }

    static func signed(_ n: Int64) -> String {
        (n >= 0 ? "+" : "−") + bytes(abs(n))
    }

    static func ago(_ date: Date?) -> String {
        guard let date else { return "Never" }
        if Date().timeIntervalSince(date) < 60 { return "Just now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }

    static func days(since date: Date?) -> Int? {
        guard let date else { return nil }
        return max(0, Int(Date().timeIntervalSince(date) / 86_400))
    }
}
