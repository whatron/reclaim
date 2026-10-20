import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    // Navigation and disk
    @Published var section: AppSection? = .overview
    @Published var disk: DiskInfo?
    @Published var hasFullDiskAccess = true

    // Smart Clean
    @Published var targets: [TargetDef] = []
    @Published var sizes: [String: TargetSize] = [:]
    @Published var busy: Set<String> = []
    @Published var checked: Set<String> = []
    @Published var batch: BatchRun?
    @Published var emptyTrashAfterBatch = false
    @Published var ollamaModels: [OllamaModel]?
    @Published var ollamaError: String?

    // Feedback
    @Published var log: [LogEntry] = []
    @Published var toast: Toast?
    @Published var pending: PendingAction?
    @Published var celebration: Int64?

    // Discover
    @Published var large: [LargeFile] = []
    @Published var largeState: LoadState = .idle
    @Published var projects: [Project] = []
    @Published var projectsState: LoadState = .idle
    @Published var projectsStatus = ""
    @Published var checkedArtifacts: Set<String> = []
    @Published var apps: [AppInfo] = []
    @Published var appsState: LoadState = .idle
    @Published var dupes: [DuplicateGroup] = []
    @Published var dupesState: LoadState = .idle
    @Published var dupesProgress: Double = 0
    @Published var dupesStatus = ""
    @Published var checkedDupes: Set<String> = []

    // Space map
    @Published var explorePath: String = Paths.home
    @Published var scan: FolderScan?
    @Published var homeScan: FolderScan?
    @Published var scanning = false
    @Published var scanError: String?
    @Published var selection: DiskNode?
    @Published var hovered: DiskNode?
    @Published var mapStyle: MapStyle = .rings

    // Tracking
    @Published var history: [Snapshot] = []
    @Published var lifetimeFreed: Int64 = 0

    let computerName: String
    var scanCache: [String: FolderScan] = [:]
    var lastSnapshotAt = Date.distantPast
    var lastLowSpaceAlert = Date.distantPast
    var didApplyDefaultChecks = false

    init() {
        computerName = Host.current().localizedName ?? "this Mac"
        history = HistoryStore.load()
        lastSnapshotAt = history.last?.date ?? .distantPast
        lifetimeFreed = Int64(UserDefaults.standard.integer(forKey: "lifetimeFreed"))
        refreshTargets()
        refreshDisk()
        hasFullDiskAccess = Shell.hasFullDiskAccess()
        measureAll()
        scanHome()
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                self.refreshDisk()
            }
        }
    }

    // MARK: Measuring

    func refreshTargets() {
        targets = Targets.all.filter { !$0.existingPaths.isEmpty || $0.always }
    }

    func refreshDisk() {
        if let d = Shell.disk(), d != disk {
            disk = d
            checkLowSpace()
        }
        recordSnapshotIfDue()
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
        if !isMeasuring {
            applyDefaultChecksOnce()
            recordSnapshotIfDue(force: history.last.map { $0.targets.isEmpty } ?? true)
        }
    }

    var isMeasuring: Bool { targets.contains { sizes[$0.id]?.measuring ?? true } }

    /// Ticks every "safe" item worth more than 50 MB the first time sizes are known.
    func applyDefaultChecksOnce() {
        guard !didApplyDefaultChecks else { return }
        didApplyDefaultChecks = true
        checked = Set(recommendedTargets.map { $0.id })
    }

    func rescan() {
        scanCache.removeAll()
        refreshTargets()
        refreshDisk()
        hasFullDiskAccess = Shell.hasFullDiskAccess()
        measureAll()
        ollamaModels = nil
        largeState = .idle
        appsState = .idle
        if section == .files { loadLarge() }
        if section == .apps { loadApps() }
        if scan != nil || scanning { explore(explorePath, force: true) } else { scanHome() }
        addLog("Started a fresh scan.", ok: true)
        flash("Scanning again.")
    }

    // MARK: Space map

    func scanHome() {
        if let cached = scanCache[Paths.home] {
            homeScan = cached
            return
        }
        Task {
            let result = await background { Shell.scanFolder(Paths.home) }
            self.scanCache[Paths.home] = result
            self.homeScan = result
            if self.explorePath == Paths.home && self.scan == nil && !self.scanning {
                self.scan = result
            }
        }
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

    func startExploringIfNeeded() {
        if scan == nil && !scanning && scanError == nil { explore(explorePath) }
    }

    func openInMap(_ path: String) {
        section = .map
        explore(path)
    }

    func goUp() {
        guard explorePath != Paths.home else { return }
        explore(Paths.parent(explorePath))
    }

    func select(_ node: DiskNode?) {
        withAnimation(.snappy(duration: 0.2)) {
            if let node, selection?.path != node.path { selection = node } else { selection = nil }
        }
    }

    func explore(_ path: String, force: Bool = false) {
        if path != explorePath { selection = nil }
        hovered = nil
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
            if path == Paths.home { self.homeScan = result }
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

    // MARK: Feedback

    func addLog(_ text: String, ok: Bool, output: String = "", freed: Int64 = 0) {
        log.append(LogEntry(text: text, ok: ok, output: output, freed: freed))
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

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func addFreed(_ bytes: Int64) {
        guard bytes > 0 else { return }
        lifetimeFreed += bytes
        UserDefaults.standard.set(Int(lifetimeFreed), forKey: "lifetimeFreed")
    }
}
