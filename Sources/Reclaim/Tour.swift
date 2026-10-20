import AppKit
import Foundation

/// Screenshot tour for the GitHub build check. Only runs when RECLAIM_TOUR is set to a folder.
/// The app opens each page in turn and writes its name to <folder>/now; the build script photographs
/// the window and answers by creating <folder>/<name>.done.
@MainActor
enum Tour {
    static var folder: String? { ProcessInfo.processInfo.environment["RECLAIM_TOUR"] }

    static func run(_ model: AppModel, updater: Updater) async {
        guard let folder else { return }
        let fm = FileManager.default
        try? fm.createDirectory(atPath: folder, withIntermediateDirectories: true)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.activate()

        let started = Date()
        model.loadLarge()
        model.loadProjects()
        model.loadApps()
        model.findDuplicates()

        // Give the slow scans up to three minutes.
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            let done = model.homeScan != nil && !model.isMeasuring && model.largeState == .loaded
                && model.projectsState == .loaded && model.appsState == .loaded && model.dupesState == .loaded
            if done { break }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        // Timings for the build report: the first measurement, then opening folders from the index.
        var timings = ["First measurement of the home folder (plus the other scans): \(String(format: "%.1f", Date().timeIntervalSince(started))) s"]
        let folders = (model.homeScan?.children ?? []).filter { $0.isDir }.prefix(4).map(\.path)
        for path in folders + [Paths.home] {
            let t0 = Date()
            model.explore(path)
            while !(model.scan?.path == path && !model.scanning) && Date().timeIntervalSince(t0) < 60 {
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            timings.append("Open \(Paths.tilde(path)): \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
        }
        timings.append(await updater.tourShowLatest())
        try? timings.joined(separator: "\n").write(toFile: folder + "/timings.txt", atomically: true, encoding: .utf8)

        // Show the one-click clean with everything big ticked, so the live bar has something to draw.
        model.checked = Set(model.targets.filter {
            $0.isBatchable && $0.id != "trash" && (model.sizes[$0.id]?.bytes ?? 0) > 1_000_000
        }.map(\.id))

        let pages: [(name: String, section: AppSection, dark: Bool)] = [
            ("dark-overview", .overview, true), ("dark-clean", .clean, true), ("dark-map", .map, true),
            ("dark-projects", .projects, true), ("dark-files", .files, true),
            ("dark-duplicates", .duplicates, true), ("dark-apps", .apps, true), ("dark-history", .history, true),
            ("dark-blocks", .map, true),
            ("dark-access", .overview, true), ("light-access", .overview, false),
            ("dark-update", .overview, true),
            ("light-overview", .overview, false), ("light-clean", .clean, false), ("light-map", .map, false),
            ("light-projects", .projects, false), ("light-files", .files, false), ("light-apps", .apps, false),
        ]
        for page in pages {
            NSApp.appearance = NSAppearance(named: page.dark ? .darkAqua : .aqua)
            model.section = page.section
            model.showAccessSheet = page.name.hasSuffix("access")
            updater.showSheet = page.name.hasSuffix("update")
            if page.section == .map {
                model.mapStyle = page.name.hasSuffix("blocks") ? .blocks : .rings
                model.explore(Paths.home)
                if let biggest = model.homeScan?.children.first(where: { $0.isDir }) {
                    model.selection = biggest
                }
            }
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            try? page.name.write(toFile: folder + "/now", atomically: true, encoding: .utf8)
            let waitUntil = Date().addingTimeInterval(20)
            while !fm.fileExists(atPath: folder + "/" + page.name + ".done") && Date() < waitUntil {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        try? "finished".write(toFile: folder + "/now", atomically: true, encoding: .utf8)
    }
}
