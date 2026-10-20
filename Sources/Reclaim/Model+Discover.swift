import Foundation
import SwiftUI

extension AppModel {
    // MARK: Large files

    func loadLargeIfNeeded() {
        if largeState == .idle { loadLarge() }
    }

    func loadLarge() {
        largeState = .loading
        Task {
            let files = await background { Scanners.largeFiles() }
            withAnimation(.snappy) {
                self.large = files
                self.largeState = .loaded
            }
        }
    }

    // MARK: Apps

    func loadAppsIfNeeded() {
        if appsState == .idle { loadApps() }
    }

    func loadApps() {
        appsState = .loading
        Task {
            let found = await background { Scanners.apps() }
            withAnimation(.snappy) {
                self.apps = found
                self.appsState = .loaded
            }
        }
    }

    /// Third-party apps over 100 MB that haven't been opened for 90 days.
    var unusedApps: [AppInfo] {
        apps.filter { $0.canTrash && $0.size > 100_000_000 && ($0.idleDays ?? 9999) >= 90 }
    }

    func requestTrashApps(_ list: [AppInfo]) {
        requestTrash(list.filter { $0.canTrash }.map { TrashItem(path: $0.path, name: $0.name, size: $0.size) },
                     title: list.count == 1 ? "Move \(list[0].name) to the Trash?" : "Move \(list.count) apps to the Trash?")
    }

    // MARK: Projects

    func loadProjectsIfNeeded() {
        if projectsState == .idle { loadProjects() }
    }

    func loadProjects() {
        projectsState = .loading
        projectsStatus = "Looking for code projects…"
        Task {
            let found = await background {
                Scanners.projects { status in
                    Task { @MainActor in self.projectsStatus = status }
                }
            }
            withAnimation(.snappy) {
                self.projects = found
                self.projectsState = .loaded
                self.checkedArtifacts = Set(found.filter { $0.isStale }.flatMap { $0.artifacts.map { $0.path } })
            }
        }
    }

    var staleProjects: [Project] { projects.filter { $0.isStale } }

    var checkedArtifactBytes: Int64 {
        projects.flatMap { $0.artifacts }.filter { checkedArtifacts.contains($0.path) }.reduce(0) { $0 + $1.size }
    }

    func requestTrashArtifacts() {
        let chosen = projects.flatMap { p in
            p.artifacts.filter { checkedArtifacts.contains($0.path) }
                .map { TrashItem(path: $0.path, name: "\(p.name)/\($0.name)", size: $0.size) }
        }
        guard !chosen.isEmpty else { return }
        requestTrash(chosen, title: "Move \(chosen.count) build folder\(chosen.count == 1 ? "" : "s") to the Trash?")
    }

    // MARK: Duplicates

    func findDuplicates() {
        dupesState = .loading
        dupesProgress = 0
        dupesStatus = "Starting…"
        Task {
            let groups = await background {
                DuplicateFinder.find { fraction, status in
                    Task { @MainActor in
                        self.dupesProgress = fraction
                        self.dupesStatus = status
                    }
                }
            }
            withAnimation(.snappy) {
                self.dupes = groups
                self.dupesState = .loaded
                self.checkedDupes = Set(groups.flatMap { $0.extras.map { $0.path } })
            }
        }
    }

    var checkedDupeBytes: Int64 {
        dupes.reduce(Int64(0)) { sum, g in
            sum + Int64(g.files.filter { checkedDupes.contains($0.path) }.count) * g.size
        }
    }

    func requestTrashDupes() {
        var items: [TrashItem] = []
        for g in dupes {
            let chosen = g.files.filter { checkedDupes.contains($0.path) }
            // Never trash every copy.
            let safeChosen = chosen.count == g.files.count ? Array(chosen.dropFirst()) : chosen
            items += safeChosen.map { TrashItem(path: $0.path, name: $0.name, size: g.size) }
        }
        guard !items.isEmpty else { return }
        requestTrash(items, title: "Move \(items.count) duplicate\(items.count == 1 ? "" : "s") to the Trash?")
    }
}
