import AppKit
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
}

// MARK: - Safety

/// Folders Reclaim will never move to the Trash, even if you ask.
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
        return protectedTrees.contains { resolved == $0 || resolved.hasPrefix($0 + "/") }
    }

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
}

struct FolderScan: Equatable {
    let path: String
    let size: Int64
    let children: [DiskNode]
    let limited: Bool
}

struct LargeFile: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let name: String
    let size: Int64
    let modified: Date
    let isProtected: Bool
    var folder: String { Paths.parent(path) }
}

struct OllamaModel: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let size: String
    let modified: String
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

private final class DataBox: @unchecked Sendable {
    var data = Data()
}

// MARK: - Shell and file operations

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

    /// Sizes of a folder's direct children.
    static func scanFolder(_ path: String) -> FolderScan {
        let base = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        let result = run(["/usr/bin/du", "-k", "-a", "-d", "1", "-x", base], timeout: 1800)
        let fm = FileManager.default
        var total: Int64 = 0
        var kids: [DiskNode] = []
        for line in result.stdout.split(separator: "\n") {
            guard let tab = line.firstIndex(of: "\t"),
                  let kb = Int64(line[line.startIndex..<tab]) else { continue }
            let p = String(line[line.index(after: tab)...])
            let size = kb * 1024
            if p == base {
                total = size
            } else if Paths.parent(p) == base {
                var isDir: ObjCBool = false
                let exists = fm.fileExists(atPath: p, isDirectory: &isDir)
                let isLink = (try? fm.destinationOfSymbolicLink(atPath: p)) != nil
                kids.append(DiskNode(name: Paths.name(p), path: p, size: size,
                                     isDir: exists && isDir.boolValue && !isLink,
                                     isProtected: Safety.isProtected(p)))
            }
        }
        if total == 0 { total = kids.reduce(0) { $0 + $1.size } }
        kids.sort { $0.size > $1.size }
        return FolderScan(path: base, size: total, children: kids, limited: isLimited(result.stderr))
    }

    /// Moves items to the Trash the same way Finder does, so "Put Back" works.
    static func moveToTrash(_ paths: [String]) -> (moved: Int, errors: [String]) {
        var moved = 0
        var errors: [String] = []
        for p in paths {
            if Safety.isProtected(p) {
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

    static func largeFiles(minBytes: Int64 = 500_000_000) -> [LargeFile] {
        let result = run(["/usr/bin/mdfind", "-onlyin", Paths.home, "kMDItemFSSize > \(minBytes)"], timeout: 120)
        let fm = FileManager.default
        var files: [LargeFile] = []
        for p in result.stdout.split(separator: "\n").map(String.init) {
            var isDir: ObjCBool = false
            guard !p.hasPrefix(Paths.trash + "/"),
                  fm.fileExists(atPath: p, isDirectory: &isDir), !isDir.boolValue,
                  let attrs = try? fm.attributesOfItem(atPath: p),
                  let size = (attrs[.size] as? NSNumber)?.int64Value,
                  size >= minBytes else { continue }
            files.append(LargeFile(path: p, name: Paths.name(p), size: size,
                                   modified: (attrs[.modificationDate] as? Date) ?? .distantPast,
                                   isProtected: Safety.isProtected(p)))
        }
        files.sort { $0.size > $1.size }
        return Array(files.prefix(100))
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
                models.append(OllamaModel(name: cols[0], size: cols[2], modified: cols.count > 3 ? cols[3] : ""))
            }
        }
        return (models, nil)
    }

    static func hasFullDiskAccess() -> Bool {
        // ~/Library/Safari exists on every Mac and is only readable with Full Disk Access.
        let probe = Paths.h("Library/Safari")
        guard FileManager.default.fileExists(atPath: probe) else { return true }
        return (try? FileManager.default.contentsOfDirectory(atPath: probe)) != nil
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
        return String(format: gb < 10 ? "%.1f GB" : "%.0f GB", gb)
    }
}
