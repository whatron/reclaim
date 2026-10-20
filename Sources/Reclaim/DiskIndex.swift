import AppKit
import Foundation

/// Folder sizes from one walk of the disk. The Space Map and Overview read from here, so moving
/// around the map is instant after the first scan instead of re-measuring every folder you open.
/// Cleanups patch the index (and every folder above what changed) rather than starting over.
final class DiskIndex: @unchecked Sendable {
    static let shared = DiskIndex()

    private let lock = NSLock()
    private var sizes: [String: Int64] = [:]
    private var children: [String: Set<String>] = [:]
    /// Folders that were walked, and how many levels of folders below each one are known.
    private var walked: [String: Int] = [:]
    /// Walked folders where some contents couldn't be read.
    private var limited: Set<String> = []

    func reset() {
        lock.withLock {
            sizes = [:]
            children = [:]
            walked = [:]
            limited = []
        }
    }

    /// How many levels of folders below `path` the index knows, or nil if it knows nothing there.
    func depthKnown(below path: String) -> Int? {
        lock.withLock { depthKnownLocked(path) }
    }

    func canShow(_ path: String) -> Bool {
        (depthKnown(below: path) ?? 0) >= 2
    }

    /// Measures `root` and its folders `depth` levels down. Each top-level folder is measured
    /// separately and in parallel, which is much faster on an SSD than one long walk.
    func walk(_ root: String, depth: Int, progress: (@Sendable (Int, Int) -> Void)? = nil) {
        let fm = FileManager.default
        var dirs: [String] = []
        for name in (try? fm.contentsOfDirectory(atPath: root)) ?? [] {
            let p = root + "/" + name
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue,
                  (try? fm.destinationOfSymbolicLink(atPath: p)) == nil else { continue }
            dirs.append(p)
        }
        let results = LockedBox<[(dir: String, output: String, limited: Bool)]>([])
        let done = LockedBox(0)
        progress?(0, dirs.count)
        DispatchQueue.concurrentPerform(iterations: dirs.count) { i in
            let r = Shell.run(["/usr/bin/du", "-k", "-d", String(max(0, depth - 1)), "-x", dirs[i]], timeout: 1800)
            results.mutate { $0.append((dirs[i], r.stdout, Shell.isLimited(r.stderr))) }
            done.mutate { $0 += 1 }
            progress?(done.current, dirs.count)
        }
        let looseBytes = Shell.looseFiles(in: root).reduce(Int64(0)) { $0 + $1.size }

        lock.withLock {
            removeLocked(below: root)
            var total = looseBytes
            var anyLimited = false
            var kids: Set<String> = []
            for r in results.current {
                ingestLocked(r.output)
                if let size = sizes[r.dir] {
                    total += size
                    kids.insert(r.dir)
                }
                anyLimited = anyLimited || r.limited
            }
            sizes[root] = total
            children[root] = kids
            walked[root] = depth
            if anyLimited { limited.insert(root) }
        }
    }

    /// Re-measures a folder after something inside it changed, and corrects every folder above it.
    func refresh(_ path: String, atLeast minimumDepth: Int = 1) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
            forget(path)
            return
        }
        let known = depthKnown(below: path)
        guard isDir.boolValue, known != nil || minimumDepth > 1 else { return }
        let old = lock.withLock { sizes[path] ?? 0 }
        walk(path, depth: max(known ?? 0, minimumDepth))
        lock.withLock {
            let new = sizes[path] ?? 0
            adjustAncestorsLocked(of: path, by: new - old)
            let parent = Paths.parent(path)
            if sizes[parent] != nil { children[parent, default: []].insert(path) }
        }
    }

    /// Drops something that was moved to the Trash or deleted, and shrinks every folder above it.
    func forget(_ path: String, bytes: Int64? = nil) {
        lock.withLock {
            let size = sizes[path] ?? bytes ?? 0
            removeLocked(below: path)
            sizes.removeValue(forKey: path)
            walked.removeValue(forKey: path)
            children[Paths.parent(path)]?.remove(path)
            adjustAncestorsLocked(of: path, by: -size)
        }
    }

    /// The two rings for `path`, or nil if the index doesn't reach that deep yet.
    func scan(_ path: String) -> FolderScan? {
        guard canShow(path) else { return nil }
        let snapshot = lock.withLock { () -> (total: Int64, level1: [(String, Int64)], level2: [String: [(String, Int64)]], limited: Bool) in
            let kids = Array(children[path] ?? [])
            var grand: [String: [(String, Int64)]] = [:]
            for k in kids {
                grand[k] = (children[k] ?? []).map { ($0, sizes[$0] ?? 0) }
            }
            let isLimited = limited.contains { path == $0 || path.hasPrefix($0 + "/") || $0.hasPrefix(path + "/") }
            return (sizes[path] ?? 0, kids.map { ($0, sizes[$0] ?? 0) }, grand, isLimited)
        }

        var nodes: [DiskNode] = snapshot.level1.map { item in
            var node = DiskNode(name: Paths.name(item.0), path: item.0, size: item.1, isDir: true,
                                isProtected: !Safety.canTrash(item.0))
            var inner = (snapshot.level2[item.0] ?? []).map {
                DiskNode(name: Paths.name($0.0), path: $0.0, size: $0.1, isDir: true, isProtected: !Safety.canTrash($0.0))
            }
            inner += Shell.looseFiles(in: item.0)
            node.children = inner.sorted { $0.size > $1.size }
            return node
        }
        nodes += Shell.looseFiles(in: path)
        nodes.sort { $0.size > $1.size }
        let sum = nodes.reduce(Int64(0)) { $0 + $1.size }
        return FolderScan(path: path, size: max(snapshot.total, sum), children: nodes, limited: snapshot.limited)
    }

    // MARK: Internals (call with the lock held)

    private func depthKnownLocked(_ path: String) -> Int? {
        var best: Int?
        for (root, depth) in walked {
            let relative: Int
            if path == root {
                relative = 0
            } else if path.hasPrefix(root + "/") {
                relative = path.dropFirst(root.count + 1).split(separator: "/").count
            } else {
                continue
            }
            let left = depth - relative
            if left >= 0 && left > (best ?? -1) { best = left }
        }
        return best
    }

    private func ingestLocked(_ output: String) {
        for line in output.split(separator: "\n") {
            guard let tab = line.firstIndex(of: "\t"),
                  let kb = Int64(line[line.startIndex..<tab]) else { continue }
            let p = String(line[line.index(after: tab)...])
            sizes[p] = kb * 1024
            children[Paths.parent(p), default: []].insert(p)
        }
    }

    /// Removes everything below `root` (not `root` itself).
    private func removeLocked(below root: String) {
        let prefix = root + "/"
        sizes = sizes.filter { !$0.key.hasPrefix(prefix) }
        children = children.filter { !$0.key.hasPrefix(prefix) }
        children[root] = nil
        walked = walked.filter { !$0.key.hasPrefix(prefix) }
        limited = limited.filter { !$0.hasPrefix(prefix) }
    }

    private func adjustAncestorsLocked(of path: String, by delta: Int64) {
        guard delta != 0 else { return }
        var folder = Paths.parent(path)
        while folder.count > 1 {
            if let size = sizes[folder] { sizes[folder] = max(0, size + delta) }
            folder = Paths.parent(folder)
        }
    }
}

/// File icons, loaded once per path instead of on every redraw.
enum Icons {
    nonisolated(unsafe) private static let cache = NSCache<NSString, NSImage>()

    static func icon(_ path: String) -> NSImage {
        if let image = cache.object(forKey: path as NSString) { return image }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}
