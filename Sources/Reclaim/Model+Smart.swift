import Foundation
import SwiftUI
import UserNotifications

extension AppModel {
    // MARK: Derived numbers

    var sortedTargets: [TargetDef] {
        targets.sorted { a, b in
            if a.id == "trash" { return false }
            if b.id == "trash" { return true }
            return (sizes[a.id]?.bytes ?? -1) > (sizes[b.id]?.bytes ?? -1)
        }
    }

    /// Safe, batchable items worth more than 50 MB.
    var recommendedTargets: [TargetDef] {
        sortedTargets.filter {
            $0.risk == .safe && $0.isBatchable && $0.isAvailable && $0.id != "trash"
                && (sizes[$0.id]?.bytes ?? 0) > 50_000_000
        }
    }

    var reviewTargets: [TargetDef] {
        sortedTargets.filter { $0.risk == .review && (sizes[$0.id]?.bytes ?? 0) > 0 }
    }

    var recommendedBytes: Int64 {
        recommendedTargets.compactMap { sizes[$0.id]?.bytes }.reduce(0, +)
    }

    var reclaimableBytes: Int64 {
        targets.filter { $0.inTotal }.compactMap { sizes[$0.id]?.bytes }.reduce(0, +)
    }

    var trashBytes: Int64 { sizes["trash"]?.bytes ?? 0 }

    /// Items ticked for a one-click clean. Homebrew's cache lives inside App caches, so it isn't counted twice.
    var checkedTargets: [TargetDef] {
        sortedTargets.filter {
            checked.contains($0.id) && $0.isBatchable && $0.isAvailable && $0.id != "trash"
                && (sizes[$0.id]?.bytes ?? 0) > 0
        }
    }

    var checkedBytes: Int64 {
        var total: Int64 = 0
        for t in checkedTargets {
            if !t.inTotal && checked.contains("caches") { continue }
            total += sizes[t.id]?.bytes ?? 0
        }
        if checked.contains("trash") || emptyTrashAfterBatch { total += trashBytes }
        return total
    }

    var reclaimPaths: [String] { targets.filter { $0.showsInMap }.flatMap { $0.paths } }

    var menuBarTitle: String {
        guard let d = disk else { return "Reclaim" }
        return Format.short(d.free)
    }

    var fullness: Double {
        guard let d = disk, d.total > 0 else { return 0 }
        return Double(d.used) / Double(d.total)
    }

    var forecast: Forecast? {
        guard let d = disk else { return nil }
        return HistoryStore.forecast(history, currentFree: d.free)
    }

    /// How much an item grew compared with about a week ago.
    func growth(of id: String) -> Int64? {
        guard let now = sizes[id]?.bytes,
              let base = HistoryStore.baseline(history, daysAgo: 7),
              let then = base.targets[id] else { return nil }
        let delta = now - then
        return abs(delta) >= 100_000_000 ? delta : nil
    }

    // MARK: Summary sentence

    var summary: String {
        guard let d = disk else { return "Reading your disk…" }
        var parts: [String] = []
        let pct = Int((fullness * 100).rounded())
        if fullness > 0.9 {
            parts.append("Your Mac is \(pct)% full, which is low enough to slow things down.")
        } else if fullness > 0.75 {
            parts.append("Your Mac is \(pct)% full.")
        } else {
            parts.append("You're in good shape at \(pct)% full.")
        }
        if let top = sortedTargets.first(where: { $0.inTotal && (sizes[$0.id]?.bytes ?? 0) > 1_000_000_000 }),
           let bytes = sizes[top.id]?.bytes {
            parts.append("The biggest cleanable item is \(top.name.lowercased()) at \(Format.short(bytes)).")
        }
        if recommendedBytes > 500_000_000 {
            parts.append("You can safely reclaim \(Format.short(recommendedBytes)) right now.")
        } else if isMeasuring {
            parts.append("Still measuring caches and models…")
        }
        if let f = forecast, let days = f.daysUntilFull, days < 120 {
            parts.append("At your current pace, the disk fills up in about \(days) days.")
        }
        if d.free < 10_000_000_000 {
            parts.append("Under 10 GB free can stop updates from installing.")
        }
        return parts.joined(separator: " ")
    }

    // MARK: Insights

    var insights: [Insight] {
        var out: [Insight] = []
        if recommendedBytes > 500_000_000 {
            out.append(Insight(id: "quick", symbol: "sparkles", tint: Palette.mint,
                               headline: "\(Format.short(recommendedBytes)) is safe to clear",
                               detail: "\(recommendedTargets.count) caches and build files that rebuild themselves.",
                               bytes: recommendedBytes, actionTitle: "Clean Now", action: .quickClean,
                               priority: Double(recommendedBytes) * 1.5))
        }
        if trashBytes > 1_000_000_000 {
            out.append(Insight(id: "trash", symbol: "trash", tint: Palette.coral,
                               headline: "\(Format.short(trashBytes)) is sitting in the Trash",
                               detail: "Trashed files still take up space until you empty it.",
                               bytes: trashBytes, actionTitle: "Empty Trash", action: .runTarget("trash"),
                               priority: Double(trashBytes) * 1.2))
        }
        if let bytes = sizes["ollama"]?.bytes, bytes > 4_000_000_000 {
            let unused = unusedModels.count
            out.append(Insight(id: "ollama", symbol: "brain", tint: Palette.violet,
                               headline: "AI models use \(Format.short(bytes))",
                               detail: unused > 0 ? "\(unused) haven't been touched in two months or more."
                                   : "Remove the models you no longer run.",
                               bytes: bytes, actionTitle: "Review Models", action: .open(.clean),
                               priority: Double(bytes)))
        }
        if let bytes = sizes["docker"]?.bytes, bytes > 4_000_000_000 {
            out.append(Insight(id: "docker", symbol: "shippingbox", tint: Palette.sky,
                               headline: "Docker is holding \(Format.short(bytes))",
                               detail: "Unused images and build cache usually make up most of it.",
                               bytes: bytes, actionTitle: "Prune Docker", action: .runTarget("docker"),
                               priority: Double(bytes) * 0.9))
        }
        if projectsState == .loaded {
            let stale = staleProjects
            let bytes = stale.reduce(Int64(0)) { $0 + $1.size }
            if bytes > 500_000_000 {
                out.append(Insight(id: "projects", symbol: "folder.badge.gearshape", tint: Palette.sand,
                                   headline: "\(stale.count) idle projects carry \(Format.short(bytes))",
                                   detail: "node_modules, build and target folders from projects untouched for a month.",
                                   bytes: bytes, actionTitle: "Review Projects", action: .open(.projects),
                                   priority: Double(bytes)))
            }
        } else {
            out.append(Insight(id: "projects-scan", symbol: "folder.badge.gearshape", tint: Palette.sand,
                               headline: "Find forgotten build folders",
                               detail: "Scan your code projects for node_modules, target and .venv folders you can rebuild.",
                               bytes: nil, actionTitle: "Scan Projects", action: .open(.projects),
                               priority: 2_000_000_000))
        }
        let idleApps = unusedApps
        if !idleApps.isEmpty {
            let bytes = idleApps.reduce(Int64(0)) { $0 + $1.size }
            out.append(Insight(id: "apps", symbol: "square.grid.3x3", tint: Palette.sky,
                               headline: "\(idleApps.count) apps you haven't opened in months",
                               detail: "Together they take \(Format.short(bytes)).",
                               bytes: bytes, actionTitle: "Review Apps", action: .open(.apps),
                               priority: Double(bytes) * 0.8))
        }
        let oldInstallers = large.filter { $0.category == .installer && $0.idleDays > 14 }
        if !oldInstallers.isEmpty {
            let bytes = oldInstallers.reduce(Int64(0)) { $0 + $1.size }
            out.append(Insight(id: "installers", symbol: "shippingbox", tint: Palette.mint,
                               headline: "\(oldInstallers.count) old installers",
                               detail: "Disk images and packages you no longer need, \(Format.short(bytes)) in total.",
                               bytes: bytes, actionTitle: "Show Files", action: .open(.files),
                               priority: Double(bytes)))
        }
        if let grower = targets.compactMap({ t -> (TargetDef, Int64)? in
            guard let g = growth(of: t.id), g > 1_000_000_000 else { return nil }
            return (t, g)
        }).max(by: { $0.1 < $1.1 }) {
            out.append(Insight(id: "growth", symbol: "chart.line.uptrend.xyaxis", tint: Palette.coral,
                               headline: "\(grower.0.name) grew \(Format.short(grower.1)) this week",
                               detail: "It's the fastest-growing item on your disk.",
                               bytes: grower.1, actionTitle: "Open History", action: .open(.history),
                               priority: Double(grower.1) * 1.1))
        }
        if let f = forecast, let days = f.daysUntilFull, days < 90 {
            out.append(Insight(id: "forecast", symbol: "hourglass", tint: Palette.coral,
                               headline: "Full in about \(days) days",
                               detail: "Based on how fast free space has been shrinking over the last two weeks.",
                               bytes: nil, actionTitle: "See Trend", action: .open(.history),
                               priority: 50_000_000_000 / Double(max(days, 1))))
        }
        if !hasFullDiskAccess {
            out.append(Insight(id: "fda", symbol: "lock.shield", tint: Palette.sand,
                               headline: "Some folders are hidden from Reclaim",
                               detail: "Turn on Full Disk Access for exact numbers in Library and the Trash.",
                               bytes: nil, actionTitle: "Set Up Access", action: .fullDiskAccess,
                               priority: 1_500_000_000))
        }
        return out.sorted { $0.priority > $1.priority }
    }

    func perform(_ action: InsightAction) {
        switch action {
        case .open(let s): section = s
        case .runTarget(let id):
            if let t = targets.first(where: { $0.id == id }) { requestRun(t) }
        case .explore(let path): openInMap(path)
        case .quickClean: requestBatchClean(only: Set(recommendedTargets.map { $0.id }))
        case .fullDiskAccess: showAccessSheet = true
        }
    }

    // MARK: History

    func recordSnapshotIfDue(force: Bool = false) {
        guard let d = disk else { return }
        guard force || Date().timeIntervalSince(lastSnapshotAt) >= 3600 else { return }
        var known: [String: Int64] = [:]
        if !isMeasuring {
            for t in targets { if let b = sizes[t.id]?.bytes { known[t.id] = b } }
        }
        lastSnapshotAt = Date()
        let snapshot = Snapshot(date: Date(), free: d.free, total: d.total, targets: known)
        // The first reading of a session is taken before sizes are known; replace it once they are.
        if let last = history.last, last.targets.isEmpty, Date().timeIntervalSince(last.date) < 3600 {
            history[history.count - 1] = snapshot
        } else {
            history.append(snapshot)
        }
        history = HistoryStore.compact(history)
        let copy = history
        Task.detached(priority: .background) { HistoryStore.save(copy) }
    }

    // MARK: Low-space alerts

    func checkLowSpace() {
        guard UserDefaults.standard.object(forKey: "lowSpaceAlerts") as? Bool ?? true else { return }
        guard let d = disk, d.total > 0 else { return }
        let low = d.free < 15_000_000_000 || Double(d.free) / Double(d.total) < 0.07
        guard low, Date().timeIntervalSince(lastLowSpaceAlert) > 6 * 3600 else { return }
        lastLowSpaceAlert = Date()
        let body = recommendedBytes > 500_000_000
            ? "Only \(Format.short(d.free)) left. Reclaim can safely free \(Format.short(recommendedBytes))."
            : "Only \(Format.short(d.free)) left. Open Reclaim to see what's using space."
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Your Mac is running low on space"
            content.body = body
            UNUserNotificationCenter.current()
                .add(UNNotificationRequest(identifier: "low-space", content: content, trigger: nil))
        }
    }
}
