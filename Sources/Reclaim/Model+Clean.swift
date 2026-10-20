import Foundation
import SwiftUI

extension AppModel {
    // MARK: Single cleanups

    func requestRun(_ t: TargetDef) {
        let size = Format.bytes(sizes[t.id]?.bytes)
        switch t.kind {
        case .trashContents:
            let root = t.existingPaths.first ?? t.paths[0]
            pending = PendingAction(
                title: "Clear \(t.name)?",
                message: "Moves everything inside \(Paths.tilde(root)) (\(size)) to the Trash. You can put it back until you empty the Trash.",
                confirmLabel: "Move to Trash"
            ) { _ = await self.performRun(t, silent: false) }
        case .command:
            var message = "Reclaim runs this for you. It currently holds \(size)."
            if t.id == "docker" && Shell.which("colima") != nil {
                message += " Afterwards it asks Colima to hand the freed space back to your Mac."
            }
            pending = PendingAction(title: "Clean up \(t.name)?", message: message,
                                    command: t.commandText, confirmLabel: t.label) {
                _ = await self.performRun(t, silent: false)
            }
        case .emptyTrash:
            pending = PendingAction(
                title: "Empty the Trash?",
                message: "Permanently deletes \(size). This can't be undone.",
                confirmLabel: "Empty Trash", destructive: true, typeToConfirm: "empty"
            ) { _ = await self.performRun(t, silent: false) }
        case .ollama, .explore:
            break
        }
    }

    /// Runs one cleanup. Returns whether it worked and how much the item shrank.
    func performRun(_ t: TargetDef, silent: Bool) async -> (ok: Bool, cleared: Int64) {
        busy.insert(t.id)
        defer { busy.remove(t.id) }
        let before = sizes[t.id]?.bytes ?? 0
        let freeBefore = Shell.disk()?.free ?? disk?.free ?? 0
        var ok = true
        var message = ""
        var output = ""

        switch t.kind {
        case .trashContents:
            guard let root = t.existingPaths.first else { return (false, 0) }
            let r = await background { () -> (moved: Int, errors: [String], readError: String?) in
                guard let names = try? FileManager.default.contentsOfDirectory(atPath: root) else {
                    return (0, [], "Couldn't read \(Paths.tilde(root)). Turn on Full Disk Access and try again.")
                }
                let m = Shell.moveToTrash(names.map { root + "/" + $0 })
                return (m.moved, m.errors, nil)
            }
            if let readError = r.readError {
                ok = false
                message = readError
            } else {
                ok = r.errors.isEmpty
                message = "Moved \(t.name) to the Trash (\(r.moved) item\(r.moved == 1 ? "" : "s"))."
                if !ok { message += " Some items were in use and stayed put." }
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
            message = ok ? "Cleaned \(t.name)." : "\(t.name) didn't finish."
            if !ok && isDocker { message += " Start Docker or Colima, then try again." }
        case .emptyTrash:
            let r = await background { Shell.emptyTrash() }
            ok = r.ok
            output = r.output
            message = ok ? "Emptied the Trash." : "The Trash wasn't fully emptied."
        case .ollama, .explore:
            return (false, 0)
        }

        scanCache.removeAll()
        await measure(t)
        if case .trashContents = t.kind, let trashTarget = targets.first(where: { $0.id == "trash" }) {
            await measure(trashTarget)
        }
        let after = sizes[t.id]?.bytes ?? before
        let cleared = max(0, before - after)

        if !silent {
            refreshDisk()
            let freed = max(0, (disk?.free ?? freeBefore) - freeBefore)
            if case .trashContents = t.kind {
                if ok { message += " Empty the Trash to get the space back." }
            } else if freed > 0 {
                message += " Freed \(Format.bytes(freed))."
                addFreed(freed)
                celebration = freed
            }
            addLog(message, ok: ok, output: output, freed: freed)
            flash(message, ok: ok)
            refreshExploredFolder()
        } else {
            addLog(message, ok: ok, output: output)
        }
        return (ok, cleared)
    }

    // MARK: One-click clean

    func requestBatchClean(only ids: Set<String>? = nil) {
        let wanted = ids ?? checked
        let list = sortedTargets.filter {
            wanted.contains($0.id) && $0.isBatchable && $0.isAvailable && $0.id != "trash"
                && (sizes[$0.id]?.bytes ?? 0) > 0
        }
        let emptyTrash = emptyTrashAfterBatch || wanted.contains("trash")
        guard !list.isEmpty || emptyTrash else {
            flash("Tick at least one item to clean.", ok: false)
            return
        }
        let total = list.filter { $0.inTotal || !wanted.contains("caches") }
            .compactMap { sizes[$0.id]?.bytes }.reduce(0, +) + (emptyTrash ? trashBytes : 0)
        var items = list.map { "\($0.name), \(Format.bytes(sizes[$0.id]?.bytes))" }
        if emptyTrash { items.append("Then empty the Trash") }
        let message = emptyTrash
            ? "Files are moved to the Trash, then the Trash is emptied. Emptying can't be undone."
            : "Files go to the Trash, so you can put them back. Commands run in the background."
        pending = PendingAction(
            title: "Reclaim \(Format.short(total))?", message: message, items: items,
            confirmLabel: "Clean \(list.count + (emptyTrash ? 1 : 0)) Items",
            destructive: emptyTrash, typeToConfirm: emptyTrash ? "empty" : nil
        ) { await self.performBatch(list.map { $0.id }, emptyTrash: emptyTrash) }
    }

    func performBatch(_ ids: [String], emptyTrash: Bool) async {
        let list = ids.compactMap { (id: String) -> TargetDef? in targets.first { $0.id == id } }
        let freeBefore = Shell.disk()?.free ?? disk?.free ?? 0
        batch = BatchRun(total: list.count + (emptyTrash ? 1 : 0), done: 0, current: "", freed: 0)
        var failures: [String] = []
        var moved: Int64 = 0
        for t in list {
            batch?.current = t.name
            let r = await performRun(t, silent: true)
            if !r.ok { failures.append(t.name) }
            if case .trashContents = t.kind { moved += r.cleared }
            batch?.done += 1
            batch?.freed = max(0, (Shell.disk()?.free ?? freeBefore) - freeBefore)
        }
        if emptyTrash, let trashTarget = targets.first(where: { $0.id == "trash" }) {
            batch?.current = "Emptying the Trash"
            let r = await performRun(trashTarget, silent: true)
            if !r.ok { failures.append("Trash") }
            batch?.done += 1
        }
        refreshDisk()
        let freed = max(0, (disk?.free ?? freeBefore) - freeBefore)
        addFreed(freed)
        var message = freed > 0 ? "Freed \(Format.bytes(freed))." : "Cleanup finished."
        if moved > 0 && !emptyTrash {
            message += " \(Format.bytes(moved)) is waiting in the Trash."
        }
        if !failures.isEmpty { message += " Didn't finish: \(failures.joined(separator: ", "))." }
        addLog(message, ok: failures.isEmpty, freed: freed)
        flash(message, ok: failures.isEmpty)
        checked.subtract(ids)
        withAnimation(.snappy) { batch = nil }
        if freed > 0 { celebration = freed }
        refreshExploredFolder()
    }

    func refreshExploredFolder() {
        scanCache.removeAll()
        if scan != nil { explore(explorePath, force: true) }
        if homeScan != nil { scanHome() }
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

    var unusedModels: [OllamaModel] {
        (ollamaModels ?? []).filter { ($0.ageDays ?? 0) >= 60 }
    }

    func requestRemoveModels(_ models: [OllamaModel]) {
        guard !models.isEmpty else { return }
        let single = models.count == 1
        pending = PendingAction(
            title: single ? "Remove \(models[0].name)?" : "Remove \(models.count) models?",
            message: "You can download \(single ? "it" : "them") again later with ollama pull.",
            items: models.map { "\($0.name), \($0.size)" },
            command: single ? "ollama rm \(models[0].name)" : nil,
            confirmLabel: single ? "Remove Model" : "Remove Models", destructive: true
        ) { await self.performRemoveModels(models) }
    }

    func performRemoveModels(_ models: [OllamaModel]) async {
        let names = models.map { $0.name }.filter {
            $0.range(of: #"^[A-Za-z0-9_.:/@\-]+$"#, options: .regularExpression) != nil
        }
        names.forEach { busy.insert("m:" + $0) }
        let freeBefore = Shell.disk()?.free ?? 0
        let results = await background { names.map { ($0, Shell.run(["ollama", "rm", $0], timeout: 300)) } }
        names.forEach { busy.remove("m:" + $0) }
        let failed = results.filter { !$0.1.ok }.map { $0.0 }
        refreshDisk()
        let freed = max(0, (disk?.free ?? freeBefore) - freeBefore)
        addFreed(freed)
        var message = "Removed \(names.count - failed.count) model\(names.count - failed.count == 1 ? "" : "s")."
        if freed > 0 { message += " Freed \(Format.bytes(freed))." }
        if !failed.isEmpty { message += " Couldn't remove \(failed.joined(separator: ", ")). Is Ollama running?" }
        addLog(message, ok: failed.isEmpty, output: results.map { "$ ollama rm \($0.0)\n\($0.1.output)" }.joined(separator: "\n\n"), freed: freed)
        flash(message, ok: failed.isEmpty)
        if freed > 0 { celebration = freed }
        loadOllama()
        if let t = targets.first(where: { $0.id == "ollama" }) { await measure(t) }
    }

    // MARK: Moving things to the Trash

    func requestTrash(_ items: [TrashItem], title: String? = nil) {
        let allowed = items.filter { Safety.canTrash($0.path) }
        guard !allowed.isEmpty else {
            flash("That's protected, so Reclaim won't move it to the Trash.", ok: false)
            return
        }
        let total = allowed.reduce(Int64(0)) { $0 + $1.size }
        let single = allowed.count == 1
        let paths = allowed.map { $0.path }
        pending = PendingAction(
            title: title ?? (single ? "Move “\(allowed[0].name)” to the Trash?" : "Move \(allowed.count) items to the Trash?"),
            message: "\(Format.bytes(total)) in total. You can put \(single ? "it" : "them") back from the Trash until you empty it.",
            items: single ? [] : Array(allowed.prefix(12).map { "\($0.name), \(Format.bytes($0.size))" }),
            command: single ? Paths.tilde(allowed[0].path) : nil,
            confirmLabel: "Move to Trash"
        ) { await self.performTrash(paths, bytes: total) }
    }

    func performTrash(_ paths: [String], bytes: Int64) async {
        let r = await background { Shell.moveToTrash(paths) }
        let ok = r.errors.isEmpty
        var message = paths.count == 1 && r.moved == 1
            ? "Moved \(Paths.name(paths[0])) to the Trash."
            : "Moved \(r.moved) item\(r.moved == 1 ? "" : "s") (\(Format.bytes(bytes))) to the Trash."
        if !ok { message += " Some couldn't be moved." }
        addLog(message, ok: ok, output: r.errors.joined(separator: "\n"))
        flash(message, ok: ok)

        let gone = Set(paths)
        large.removeAll { gone.contains($0.path) }
        apps.removeAll { gone.contains($0.path) }
        projects = projects.compactMap { (p: Project) -> Project? in
            let left = p.artifacts.filter { !gone.contains($0.path) }
            return left.isEmpty ? nil : Project(path: p.path, name: p.name, ecosystem: p.ecosystem, symbol: p.symbol,
                                                lastActivity: p.lastActivity, artifacts: left)
        }
        checkedArtifacts.subtract(gone)
        dupes = dupes.compactMap { (g: DuplicateGroup) -> DuplicateGroup? in
            let left = g.files.filter { !gone.contains($0.path) }
            return left.count > 1 ? DuplicateGroup(id: g.id, size: g.size, files: left) : nil
        }
        checkedDupes.subtract(gone)
        if let sel = selection, gone.contains(sel.path) { selection = nil }

        for t in targets {
            let touched = t.id == "trash" || t.paths.contains { tp in
                paths.contains { $0 == tp || $0.hasPrefix(tp + "/") || tp.hasPrefix($0 + "/") }
            }
            if touched { Task { await self.measure(t) } }
        }
        refreshDisk()
        refreshExploredFolder()
    }
}
