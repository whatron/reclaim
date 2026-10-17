import AppKit
import Foundation
import SwiftUI

// MARK: - Palette

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

extension Color {
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

enum Palette {
    static let safe = Color.adaptive(light: 0x0E9C7F, dark: 0x5EE0C1)
    static let review = Color.adaptive(light: 0xB07F05, dark: 0xF2C14E)
    static let careful = Color.adaptive(light: 0xD33852, dark: 0xFF7A8A)
    static let other = Color.adaptive(light: 0x9DB2CC, dark: 0x3A5576)
    static let tile = Color.adaptive(light: 0x6E9BD3, dark: 0x4B7FBE)
    static let tileFile = Color.adaptive(light: 0x9F90E0, dark: 0x8A79D6)
}

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
        case .safe: return Palette.safe
        case .review: return Palette.review
        case .careful: return Palette.careful
        }
    }
}

enum TargetKind {
    case trashContents
    case command([[String]])
    case ollama
    case explore
    case emptyTrash
}

struct TargetDef: Identifiable {
    let id: String
    let name: String
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

    var showsInMap: Bool {
        if case .explore = kind { return false }
        return id != "trash"
    }
}

enum Targets {
    static let all: [TargetDef] = [
        TargetDef(id: "ollama", name: "Ollama models", paths: [Paths.h(".ollama/models")], risk: .review,
                  kind: .ollama, label: "Choose Models",
                  about: "AI models you've pulled with Ollama. Each one is several gigabytes. Remove the ones you no longer run; you can pull them again later."),
        TargetDef(id: "docker", name: "Docker images and build cache",
                  paths: [Paths.h(".colima"), Paths.h("Library/Containers/com.docker.docker")], risk: .review,
                  kind: .command([["docker", "system", "prune", "-af"]]), label: "Prune Unused",
                  about: "Stopped containers, unused images and build cache. Volumes (your databases) are kept. Docker or Colima must be running."),
        TargetDef(id: "idea", name: "IntelliJ snapshots", paths: [Paths.h("IdeaSnapshots")], risk: .safe,
                  kind: .trashContents, label: "Move to Trash",
                  about: "Memory and CPU profiling snapshots saved by IntelliJ. Only needed while you're analysing one."),
        TargetDef(id: "maven", name: "Maven repository", paths: [Paths.h(".m2/repository")], risk: .safe,
                  kind: .trashContents, label: "Clear Repository",
                  about: "Downloaded Java dependencies. Maven downloads what it needs again on the next build."),
        TargetDef(id: "gradle", name: "Gradle caches", paths: [Paths.h(".gradle/caches")], risk: .safe,
                  kind: .trashContents, label: "Clear Caches",
                  about: "Gradle's dependency and build caches. Rebuilt on the next build."),
        TargetDef(id: "npm", name: "npm cache", paths: [Paths.h(".npm")], risk: .safe,
                  kind: .command([["npm", "cache", "clean", "--force"]]), label: "Clean Cache",
                  about: "Cached package downloads. npm fetches them again when a project needs them."),
        TargetDef(id: "go", name: "Go module cache", paths: [Paths.h("go/pkg/mod")], risk: .safe,
                  kind: .command([["go", "clean", "-modcache"]]), label: "Clean Cache",
                  about: "Downloaded Go modules. Go downloads them again on the next build."),
        TargetDef(id: "dotcache", name: "Command-line tool caches", paths: [Paths.h(".cache")], risk: .review,
                  kind: .trashContents, label: "Clear Caches",
                  about: "Caches from tools like pip, uv, Hugging Face and pre-commit. Hugging Face models live here too and are slow to download again, so look inside first."),
        TargetDef(id: "caches", name: "App caches", paths: [Paths.h("Library/Caches")], risk: .review,
                  kind: .trashContents, label: "Clear Caches",
                  about: "Caches kept by your Mac apps. Apps rebuild them, so they may be slower the first time. Quit open apps before clearing."),
        TargetDef(id: "brew", name: "Homebrew downloads and old versions", paths: [Paths.h("Library/Caches/Homebrew")],
                  risk: .safe, kind: .command([["brew", "cleanup", "--prune=all"]]), label: "Clean Up",
                  about: "Installer downloads and outdated package versions. Part of App caches, so it isn't counted twice.",
                  inTotal: false),
        TargetDef(id: "derived", name: "Xcode build data", paths: [Paths.h("Library/Developer/Xcode/DerivedData")],
                  risk: .safe, kind: .trashContents, label: "Clear Build Data",
                  about: "Intermediate build files. Xcode rebuilds them on the next build."),
        TargetDef(id: "devsupport", name: "Xcode device support", paths: [Paths.h("Library/Developer/Xcode/iOS DeviceSupport")],
                  risk: .safe, kind: .trashContents, label: "Move to Trash",
                  about: "Debug symbols for iPhones you've plugged in. Recreated when you connect the device again."),
        TargetDef(id: "sims", name: "iOS simulators", paths: [Paths.h("Library/Developer/CoreSimulator")], risk: .review,
                  kind: .command([["xcrun", "simctl", "delete", "unavailable"]]), label: "Remove Unavailable",
                  about: "Simulators for iOS versions that are no longer installed."),
        TargetDef(id: "downloads", name: "Downloads", paths: [Paths.h("Downloads")], risk: .review,
                  kind: .explore, label: "Explore",
                  about: "Old installers, disk images and archives tend to pile up here. Open it in the map to pick what to trash.",
                  inTotal: false),
        TargetDef(id: "trash", name: "Trash", paths: [Paths.trash], risk: .careful,
                  kind: .emptyTrash, label: "Empty Trash",
                  about: "Anything moved to the Trash, including by Reclaim, still uses space until you empty it. This can't be undone.",
                  inTotal: false, always: true),
    ]
}

// MARK: - UI state types

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
    let command: String?
    let confirmLabel: String
    let destructive: Bool
    let typeToConfirm: String?
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

enum AppSection: String, CaseIterable, Identifiable {
    case cleanup, explore, large, activity
    var id: AppSection { self }

    var title: String {
        switch self {
        case .cleanup: return "Clean Up"
        case .explore: return "Explore"
        case .large: return "Large Files"
        case .activity: return "Activity"
        }
    }

    var icon: String {
        switch self {
        case .cleanup: return "sparkles"
        case .explore: return "square.grid.3x3.square"
        case .large: return "doc.on.doc"
        case .activity: return "clock.arrow.circlepath"
        }
    }
}

// MARK: - App model

@MainActor
final class AppModel: ObservableObject {
    @Published var section: AppSection? = .cleanup
    @Published var disk: DiskInfo?
    @Published var targets: [TargetDef] = []
    @Published var sizes: [String: TargetSize] = [:]
    @Published var busy: Set<String> = []
    @Published var log: [LogEntry] = []
    @Published var toast: Toast?
    @Published var pending: PendingAction?
    @Published var hasFullDiskAccess = true

    @Published var ollamaModels: [OllamaModel]?
    @Published var ollamaError: String?

    @Published var large: [LargeFile] = []
    @Published var largeState: LoadState = .idle

    @Published var explorePath: String = Paths.home
    @Published var scan: FolderScan?
    @Published var scanning = false
    @Published var scanError: String?
    @Published var selection: DiskNode?

    let computerName: String
    private var scanCache: [String: FolderScan] = [:]

    init() {
        computerName = Host.current().localizedName ?? "this Mac"
        refreshTargets()
        refreshDisk()
        hasFullDiskAccess = Shell.hasFullDiskAccess()
        measureAll()
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                self.refreshDisk()
            }
        }
    }

    // MARK: Derived values

    var reclaimableBytes: Int64 {
        targets.filter { $0.inTotal }.compactMap { sizes[$0.id]?.bytes }.reduce(0, +)
    }

    var trashBytes: Int64 { sizes["trash"]?.bytes ?? 0 }

    var isMeasuring: Bool { targets.contains { sizes[$0.id]?.measuring ?? true } }

    var sortedTargets: [TargetDef] {
        targets.sorted { a, b in
            if a.id == "trash" { return false }
            if b.id == "trash" { return true }
            return (sizes[a.id]?.bytes ?? -1) > (sizes[b.id]?.bytes ?? -1)
        }
    }

    var reclaimPaths: [String] { targets.filter { $0.showsInMap }.flatMap { $0.paths } }

    var menuBarTitle: String {
        guard let d = disk else { return "Reclaim" }
        return Format.short(d.free)
    }

    var crumbs: [Crumb] {
        var out = [Crumb(label: "Home", path: Paths.home)]
        guard explorePath != Paths.home, explorePath.hasPrefix(Paths.home + "/") else { return out }
        var acc = Paths.home
        for seg in explorePath.dropFirst(Paths.home.count + 1).split(separator: "/") {
            acc += "/" + String(seg)
            out.append(Crumb(label: String(seg), path: acc))
        }
        return out
    }

    // MARK: Measuring

    func refreshTargets() {
        targets = Targets.all.filter { !$0.existingPaths.isEmpty || $0.always }
    }

    func refreshDisk() {
        if let d = Shell.disk(), d != disk { disk = d }
    }

    func measureAll() {
        for t in targets {
            Task { await self.measure(t) }
        }
    }

    func measure(_ t: TargetDef) async {
        var current = sizes[t.id] ?? TargetSize(bytes: nil, limited: false, measuring: true)
        current.measuring = true
        sizes[t.id] = current
        let paths = t.existingPaths
        let result = await background { () -> (Int64, Bool) in
            var total: Int64 = 0
            var limited = false
            for p in paths {
                let r = Shell.duBytes(p)
                total += r.bytes ?? 0
                limited = limited || r.limited
            }
            return (total, limited)
        }
        sizes[t.id] = TargetSize(bytes: result.0, limited: result.1, measuring: false)
    }

    func rescan() {
        scanCache.removeAll()
        refreshTargets()
        refreshDisk()
        hasFullDiskAccess = Shell.hasFullDiskAccess()
        measureAll()
        ollamaModels = nil
        largeState = .idle
        if section == .large { loadLarge() }
        if scan != nil || scanning { explore(explorePath, force: true) }
        addLog("Started a fresh scan.", ok: true)
        flash("Scanning again.")
    }

    // MARK: Explore

    func startExploringIfNeeded() {
        if scan == nil && !scanning && scanError == nil { explore(explorePath) }
    }

    func openInExplorer(_ path: String) {
        section = .explore
        explore(path)
    }

    func goUp() {
        guard explorePath != Paths.home else { return }
        explore(Paths.parent(explorePath))
    }

    func select(_ node: DiskNode) {
        withAnimation(.snappy(duration: 0.2)) {
            selection = selection?.path == node.path ? nil : node
        }
    }

    func explore(_ path: String, force: Bool = false) {
        if path != explorePath { selection = nil }
        explorePath = path
        scanError = nil
        guard Safety.isInsideHome(path) else {
            scanError = "Only folders inside your home folder can be explored."
            return
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            scanError = "\(Paths.tilde(path)) isn't a folder any more."
            return
        }
        if !force, let cached = scanCache[path] {
            withAnimation(.snappy) {
                scan = cached
                scanning = false
            }
            return
        }
        scanning = true
        Task {
            let result = await background { Shell.scanFolder(path) }
            self.scanCache[path] = result
            guard self.explorePath == path else { return }
            withAnimation(.snappy) {
                self.scan = result
                self.scanning = false
                if let sel = self.selection, !result.children.contains(where: { $0.path == sel.path }) {
                    self.selection = nil
                }
            }
        }
    }

    // MARK: Cleanups

    func requestRun(_ t: TargetDef) {
        let size = Format.bytes(sizes[t.id]?.bytes)
        switch t.kind {
        case .trashContents:
            let root = t.existingPaths.first ?? t.paths[0]
            pending = PendingAction(
                title: "Move \(t.name) to the Trash?",
                message: "Moves everything inside \(Paths.tilde(root)) (\(size)) to the Trash. The space comes back when you empty the Trash.",
                command: nil, confirmLabel: t.label, destructive: false, typeToConfirm: nil
            ) { await self.performRun(t) }
        case .command:
            var message = "Reclaim runs this command for you (\(size) right now)."
            if t.id == "docker" && Shell.which("colima") != nil {
                message += " Afterwards it asks Colima to hand the freed space back to your Mac."
            }
            pending = PendingAction(
                title: "Clean up \(t.name)?", message: message, command: t.commandText,
                confirmLabel: t.label, destructive: false, typeToConfirm: nil
            ) { await self.performRun(t) }
        case .emptyTrash:
            pending = PendingAction(
                title: "Empty the Trash?",
                message: "Permanently deletes \(size) in the Trash. This can't be undone.",
                command: nil, confirmLabel: "Empty Trash", destructive: true, typeToConfirm: "empty"
            ) { await self.performRun(t) }
        case .ollama, .explore:
            break
        }
    }

    func performRun(_ t: TargetDef) async {
        busy.insert(t.id)
        let before = sizes[t.id]?.bytes
        var ok = true
        var message = ""
        var output = ""
        var reportFreed = true

        switch t.kind {
        case .trashContents:
            reportFreed = false
            guard let root = t.existingPaths.first else {
                busy.remove(t.id)
                return
            }
            let r = await background { () -> (moved: Int, errors: [String], readError: String?) in
                guard let names = try? FileManager.default.contentsOfDirectory(atPath: root) else {
                    return (0, [], "Couldn't read \(Paths.tilde(root)).")
                }
                let m = Shell.moveToTrash(names.map { root + "/" + $0 })
                return (m.moved, m.errors, nil)
            }
            if let readError = r.readError {
                ok = false
                message = readError
            } else {
                ok = r.errors.isEmpty
                message = "Moved \(r.moved) item\(r.moved == 1 ? "" : "s") from \(Paths.tilde(root)) to the Trash."
                if !ok { message += " Some items couldn't be moved." }
                output = r.errors.joined(separator: "\n")
            }
        case .command(let cmds):
            let isDocker = t.id == "docker"
            let r = await background { () -> (Bool, String) in
                var outs: [String] = []
                var good = true
                for argv in cmds {
                    let res = Shell.run(argv)
                    outs.append("$ " + argv.joined(separator: " ") + "\n" + res.output)
                    if !res.ok {
                        good = false
                        break
                    }
                }
                if good && isDocker && Shell.which("colima") != nil {
                    let res = Shell.run(["colima", "ssh", "--", "sudo", "fstrim", "-a"])
                    outs.append("$ colima ssh -- sudo fstrim -a\n" + res.output)
                }
                return (good, outs.joined(separator: "\n\n"))
            }
            ok = r.0
            output = r.1
            message = ok ? "Cleaned up \(t.name)." : "\(t.name) didn't finish."
            if !ok && isDocker { message += " Start Docker or Colima and try again." }
        case .emptyTrash:
            let r = await background { Shell.emptyTrash() }
            ok = r.ok
            output = r.output
            message = ok ? "Emptied the Trash." : "The Trash wasn't fully emptied."
        case .ollama, .explore:
            busy.remove(t.id)
            return
        }

        scanCache.removeAll()
        await measure(t)
        if case .trashContents = t.kind, let trashTarget = targets.first(where: { $0.id == "trash" }) {
            Task { await self.measure(trashTarget) }
        }
        refreshDisk()
        if ok, reportFreed, let b = before, let a = sizes[t.id]?.bytes, b > a {
            message += " \(Format.bytes(b - a)) freed."
        }
        addLog(message, ok: ok, output: output)
        flash(message, ok: ok)
        busy.remove(t.id)
        if scan != nil { explore(explorePath, force: true) }
    }

    // MARK: Trash individual items

    func requestTrash(_ items: [TrashItem]) {
        let allowed = items.filter { !Safety.isProtected($0.path) }
        guard !allowed.isEmpty else {
            flash("That's a protected folder, so Reclaim won't move it to the Trash.", ok: false)
            return
        }
        let total = allowed.reduce(Int64(0)) { $0 + $1.size }
        let single = allowed.count == 1
        let title = single ? "Move “\(allowed[0].name)” to the Trash?" : "Move \(allowed.count) items to the Trash?"
        let paths = allowed.map { $0.path }
        pending = PendingAction(
            title: title,
            message: "\(Format.bytes(total)). You can put \(single ? "it" : "them") back from the Trash until you empty it.",
            command: single ? Paths.tilde(allowed[0].path) : nil,
            confirmLabel: "Move to Trash", destructive: false, typeToConfirm: nil
        ) { await self.performTrash(paths) }
    }

    func performTrash(_ paths: [String]) async {
        let r = await background { Shell.moveToTrash(paths) }
        let ok = r.errors.isEmpty
        var message = paths.count == 1 && r.moved == 1
            ? "Moved \(Paths.tilde(paths[0])) to the Trash."
            : "Moved \(r.moved) item\(r.moved == 1 ? "" : "s") to the Trash."
        if !ok { message += " Some couldn't be moved." }
        addLog(message, ok: ok, output: r.errors.joined(separator: "\n"))
        flash(message, ok: ok)
        large.removeAll { paths.contains($0.path) }
        if let sel = selection, paths.contains(sel.path) { selection = nil }
        scanCache.removeAll()
        for t in targets {
            let touched = t.id == "trash" || t.paths.contains { tp in
                paths.contains { $0 == tp || $0.hasPrefix(tp + "/") || tp.hasPrefix($0 + "/") }
            }
            if touched { Task { await self.measure(t) } }
        }
        refreshDisk()
        if scan != nil { explore(explorePath, force: true) }
    }

    // MARK: Ollama

    func loadOllama() {
        ollamaError = nil
        Task {
            let r = await background { Shell.ollamaModels() }
            self.ollamaModels = r.models
            self.ollamaError = r.error
        }
    }

    func requestRemoveModel(_ m: OllamaModel) {
        pending = PendingAction(
            title: "Remove \(m.name)?",
            message: "Frees about \(m.size). You can download it again later with ollama pull.",
            command: "ollama rm \(m.name)", confirmLabel: "Remove Model", destructive: true, typeToConfirm: nil
        ) { await self.performRemoveModel(m) }
    }

    func performRemoveModel(_ m: OllamaModel) async {
        guard m.name.range(of: #"^[A-Za-z0-9_.:/@\-]+$"#, options: .regularExpression) != nil else { return }
        let key = "m:" + m.name
        busy.insert(key)
        let name = m.name
        let r = await background { Shell.run(["ollama", "rm", name], timeout: 300) }
        busy.remove(key)
        let message = r.ok ? "Removed the model \(name)." : "Couldn't remove \(name). Open the Ollama app and try again."
        addLog(message, ok: r.ok, output: r.output)
        flash(message, ok: r.ok)
        loadOllama()
        scanCache.removeAll()
        if let t = targets.first(where: { $0.id == "ollama" }) { await measure(t) }
        refreshDisk()
    }

    // MARK: Large files

    func loadLargeIfNeeded() {
        if largeState == .idle { loadLarge() }
    }

    func loadLarge() {
        largeState = .loading
        Task {
            let files = await background { Shell.largeFiles() }
            self.large = files
            self.largeState = .loaded
        }
    }

    // MARK: Misc

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func addLog(_ text: String, ok: Bool, output: String = "") {
        log.append(LogEntry(text: text, ok: ok, output: output))
        if log.count > 300 { log.removeFirst(log.count - 300) }
    }

    func flash(_ text: String, ok: Bool = true) {
        let t = Toast(text: text, ok: ok)
        withAnimation(.snappy) { toast = t }
        Task {
            try? await Task.sleep(nanoseconds: ok ? 3_500_000_000 : 6_000_000_000)
            if self.toast?.id == t.id {
                withAnimation(.snappy) { self.toast = nil }
            }
        }
    }
}
