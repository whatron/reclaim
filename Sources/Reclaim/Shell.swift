import AppKit
import Foundation

private final class DataBox: @unchecked Sendable {
    var data = Data()
}

enum Shell {
    /// Apps launched from Finder get a minimal PATH, so add the usual tool folders.
    static let environment: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        let extra = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", Paths.h(".homebrew/bin"),
                     Paths.h("go/bin"), "/usr/local/go/bin", Paths.h(".local/bin"),
                     "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let existing = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        var parts: [String] = []
        for p in extra + existing where !p.isEmpty && !seen.contains(p) {
            seen.insert(p)
            parts.append(p)
        }
        env["PATH"] = parts.joined(separator: ":")
        return env
    }()

    static func which(_ tool: String) -> String? {
        let fm = FileManager.default
        if tool.hasPrefix("/") { return fm.isExecutableFile(atPath: tool) ? tool : nil }
        for dir in (environment["PATH"] ?? "").split(separator: ":") {
            let candidate = String(dir) + "/" + tool
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    static func run(_ argv: [String], timeout: TimeInterval = 900) -> ShellResult {
        guard let first = argv.first else { return ShellResult(ok: false, stdout: "", stderr: "Nothing to run.") }
        guard let exe = which(first) else {
            return ShellResult(ok: false, stdout: "", stderr: "\(first) isn't installed or isn't on your PATH.")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = Array(argv.dropFirst())
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            try process.run()
        } catch {
            return ShellResult(ok: false, stdout: "", stderr: error.localizedDescription)
        }
        let outBox = DataBox()
        let errBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            outBox.data = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        process.waitUntilExit()
        group.wait()
        killer.cancel()
        return ShellResult(ok: process.terminationStatus == 0,
                           stdout: String(decoding: outBox.data, as: UTF8.self),
                           stderr: String(decoding: errBox.data, as: UTF8.self))
    }

    static func disk() -> DiskInfo? {
        let url = URL(fileURLWithPath: Paths.home)
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey,
                                         .volumeAvailableCapacityForImportantUsageKey,
                                         .volumeAvailableCapacityKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity else { return nil }
        let free = values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)
        return DiskInfo(total: Int64(total), free: free)
    }

    private static func isLimited(_ stderr: String) -> Bool {
        stderr.contains("denied") || stderr.contains("not permitted")
    }

    /// Total size of a path, using du (fast, and counts hard links once).
    static func duBytes(_ path: String) -> (bytes: Int64?, limited: Bool) {
        let result = run(["/usr/bin/du", "-sk", path])
        let limited = isLimited(result.stderr)
        let firstField = result.stdout.split(whereSeparator: { $0 == "\t" || $0 == " " || $0 == "\n" }).first
        if let field = firstField, let kb = Int64(field) { return (kb * 1024, limited) }
        return (limited ? nil : 0, limited)
    }

    /// Sizes of many paths, measured a few at a time.
    static func sizes(of paths: [String]) -> [String: Int64] {
        let box = LockedBox<[String: Int64]>([:])
        DispatchQueue.concurrentPerform(iterations: paths.count) { i in
            let bytes = duBytes(paths[i]).bytes ?? 0
            box.mutate { $0[paths[i]] = bytes }
        }
        return box.current
    }

    /// Sizes of a folder's children and grandchildren (two rings of the space map).
    /// macOS `du` can't combine -a with -d, so folders come from `du -d` and files from the file system.
    static func scanFolder(_ path: String, depth: Int = 2) -> FolderScan {
        let base = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        let prefix = base + "/"
        let result = run(["/usr/bin/du", "-k", "-d", String(depth), "-x", base], timeout: 1800)
        var total: Int64 = 0
        var level1: [String: DiskNode] = [:]
        var level2: [String: [DiskNode]] = [:]

        for line in result.stdout.split(separator: "\n") {
            guard let tab = line.firstIndex(of: "\t"),
                  let kb = Int64(line[line.startIndex..<tab]) else { continue }
            let p = String(line[line.index(after: tab)...])
            let size = kb * 1024
            if p == base {
                total = size
                continue
            }
            guard p.hasPrefix(prefix) else { continue }
            let parts = p.dropFirst(prefix.count).split(separator: "/")
            let node = DiskNode(name: Paths.name(p), path: p, size: size, isDir: true,
                                isProtected: !Safety.canTrash(p))
            if parts.count == 1 {
                level1[p] = node
            } else if parts.count == 2 {
                level2[prefix + String(parts[0]), default: []].append(node)
            }
        }

        // Plain files (and symlinks) next to those folders.
        for file in looseFiles(in: base) { level1[file.path] = file }
        for dir in Array(level1.keys) where level1[dir]?.isDir == true {
            level2[dir, default: []] += looseFiles(in: dir)
        }

        var kids: [DiskNode] = level1.values.map { node in
            var copy = node
            copy.children = (level2[node.path] ?? []).sorted { $0.size > $1.size }
            return copy
        }
        kids.sort { $0.size > $1.size }
        let childTotal = kids.reduce(0) { $0 + $1.size }
        if total < childTotal { total = childTotal }
        return FolderScan(path: base, size: total, children: kids, limited: isLimited(result.stderr))
    }

    /// Files directly inside a folder, sized by the space they take on disk.
    private static func looseFiles(in dir: String) -> [DiskNode] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey,
                                      .fileAllocatedSizeKey, .fileSizeKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: dir), includingPropertiesForKeys: keys, options: []) else { return [] }
        var out: [DiskNode] = []
        for url in urls {
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if v.isDirectory == true && v.isSymbolicLink != true { continue }
            let size = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? v.fileSize ?? 0)
            let p = dir + "/" + url.lastPathComponent
            out.append(DiskNode(name: url.lastPathComponent, path: p, size: size, isDir: false,
                                isProtected: !Safety.canTrash(p)))
        }
        return out
    }

    /// Moves items to the Trash the way Finder does, so "Put Back" works.
    static func moveToTrash(_ paths: [String]) -> (moved: Int, errors: [String]) {
        var moved = 0
        var errors: [String] = []
        for p in paths {
            guard Safety.canTrash(p) else {
                errors.append("\(Paths.tilde(p)) is protected.")
                continue
            }
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: p), resultingItemURL: nil)
                moved += 1
            } catch {
                errors.append("\(Paths.tilde(p)): \(error.localizedDescription)")
            }
        }
        return (moved, errors)
    }

    static func emptyTrash() -> (ok: Bool, output: String) {
        let fm = FileManager.default
        if let names = try? fm.contentsOfDirectory(atPath: Paths.trash) {
            var errors: [String] = []
            var removed = 0
            for name in names {
                do {
                    try fm.removeItem(atPath: Paths.trash + "/" + name)
                    removed += 1
                } catch {
                    errors.append(name + ": " + error.localizedDescription)
                }
            }
            if errors.isEmpty { return (true, "Deleted \(removed) items.") }
        }
        // No access to ~/.Trash (or some items were locked): ask Finder instead.
        let finder = run(["/usr/bin/osascript", "-e", "tell application \"Finder\" to empty trash"], timeout: 1800)
        return (finder.ok, finder.ok ? "Finder emptied the Trash." : finder.output)
    }

    static func ollamaModels() -> (models: [OllamaModel], error: String?) {
        guard which("ollama") != nil else { return ([], "Ollama isn't installed.") }
        let result = run(["ollama", "list"], timeout: 30)
        guard result.ok else { return ([], "Couldn't list models. Open the Ollama app, then try again.") }
        var models: [OllamaModel] = []
        for line in result.stdout.split(separator: "\n").dropFirst() {
            let cols = line.components(separatedBy: "  ")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if cols.count >= 3 {
                let modified = cols.count > 3 ? cols[3] : ""
                models.append(OllamaModel(name: cols[0], size: cols[2], modified: modified,
                                          ageDays: approximateDays(modified)))
            }
        }
        return (models, nil)
    }

    /// Turns "3 weeks ago" into roughly 21.
    static func approximateDays(_ text: String) -> Int? {
        let words = text.lowercased().split(separator: " ")
        guard words.count >= 2 else { return nil }
        let count = Int(words[0]) ?? ((words[0] == "a" || words[0] == "an") ? 1 : 0)
        let unit = words[1]
        if unit.hasPrefix("second") || unit.hasPrefix("minute") || unit.hasPrefix("hour") { return 0 }
        if unit.hasPrefix("day") { return count }
        if unit.hasPrefix("week") { return count * 7 }
        if unit.hasPrefix("month") { return count * 30 }
        if unit.hasPrefix("year") { return count * 365 }
        return nil
    }

    static func hasFullDiskAccess() -> Bool {
        // ~/Library/Safari exists on every Mac and is only readable with Full Disk Access.
        let probe = Paths.h("Library/Safari")
        guard FileManager.default.fileExists(atPath: probe) else { return true }
        return (try? FileManager.default.contentsOfDirectory(atPath: probe)) != nil
    }
}
