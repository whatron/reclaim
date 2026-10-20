import CryptoKit
import Foundation

struct DuplicateFile: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let name: String
    let created: Date
    let modified: Date
    var folder: String { Paths.parent(path) }
}

struct DuplicateGroup: Identifiable, Hashable {
    let id: String
    let size: Int64
    /// The first file is the one Reclaim suggests keeping.
    let files: [DuplicateFile]
    var keeper: DuplicateFile? { files.first }
    var extras: [DuplicateFile] { Array(files.dropFirst()) }
    var reclaimable: Int64 { size * Int64(max(0, files.count - 1)) }
}

enum DuplicateFinder {
    /// Finds identical files of at least `minBytes` in the home folder.
    /// Same size → same first/last 64 KB → same full SHA-256.
    static func find(minBytes: Int64 = 20_000_000,
                     progress: @escaping @Sendable (Double, String) -> Void) -> [DuplicateGroup] {
        progress(0.02, "Asking Spotlight for big files…")
        let query = "kMDItemFSSize >= \(minBytes)"
        let listed = Shell.run(["/usr/bin/mdfind", "-onlyin", Paths.home, query], timeout: 180).stdout
            .split(separator: "\n").map(String.init)
        let fm = FileManager.default

        var bySize: [Int64: [String]] = [:]
        for p in listed {
            var isDir: ObjCBool = false
            guard !p.hasPrefix(Paths.trash + "/"), !p.contains("/Library/"), !p.contains("/node_modules/"),
                  !p.contains("/.git/"), !Safety.packageInterior(p), !Safety.isProtected(p),
                  fm.fileExists(atPath: p, isDirectory: &isDir), !isDir.boolValue,
                  (try? fm.destinationOfSymbolicLink(atPath: p)) == nil,
                  let size = (try? fm.attributesOfItem(atPath: p))?[.size] as? NSNumber,
                  size.int64Value >= minBytes else { continue }
            bySize[size.int64Value, default: []].append(p)
        }

        let sameSize = bySize.filter { $0.value.count > 1 }
        progress(0.12, "Comparing \(sameSize.values.reduce(0) { $0 + $1.count }) files of matching size…")

        var candidates: [(Int64, [String])] = []
        for (size, paths) in sameSize {
            var bySample: [String: [String]] = [:]
            for p in paths {
                if let sample = sampleHash(p, size: size) { bySample[sample, default: []].append(p) }
            }
            for group in bySample.values where group.count > 1 { candidates.append((size, group)) }
        }

        let totalBytes = candidates.reduce(Int64(0)) { $0 + $1.0 * Int64($1.1.count) }
        var hashedBytes: Int64 = 0
        var groups: [DuplicateGroup] = []
        for (size, paths) in candidates.sorted(by: { $0.0 > $1.0 }) {
            var byHash: [String: [String]] = [:]
            for p in paths {
                progress(0.15 + 0.85 * Double(hashedBytes) / Double(max(1, totalBytes)), "Checking \(Paths.name(p))…")
                if let digest = fullHash(p) { byHash[digest, default: []].append(p) }
                hashedBytes += size
            }
            for (digest, same) in byHash where same.count > 1 {
                let files = same.compactMap { describe($0) }
                guard files.count > 1 else { continue }
                groups.append(DuplicateGroup(id: digest, size: size, files: rankKeeperFirst(files)))
            }
        }
        progress(1, "Done")
        return groups.sorted { $0.reclaimable > $1.reclaimable }
    }

    private static func describe(_ path: String) -> DuplicateFile? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return DuplicateFile(path: path, name: Paths.name(path),
                             created: (attrs[.creationDate] as? Date) ?? .distantPast,
                             modified: (attrs[.modificationDate] as? Date) ?? .distantPast)
    }

    /// Keep the copy that looks like the original: not in Downloads, no "copy" or "(1)" in the name, oldest.
    private static func rankKeeperFirst(_ files: [DuplicateFile]) -> [DuplicateFile] {
        func score(_ f: DuplicateFile) -> Int {
            var s = 0
            if !f.path.hasPrefix(Paths.h("Downloads")) { s += 4 }
            if !f.path.hasPrefix(Paths.h("Desktop")) { s += 1 }
            let lower = f.name.lowercased()
            if !lower.contains(" copy") && lower.range(of: #"\(\d+\)"#, options: .regularExpression) == nil
                && lower.range(of: #" \d+\.[a-z0-9]+$"#, options: .regularExpression) == nil {
                s += 2
            }
            return s
        }
        return files.sorted { a, b in
            let sa = score(a), sb = score(b)
            if sa != sb { return sa > sb }
            return a.created < b.created
        }
    }

    private static func sampleHash(_ path: String, size: Int64) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let chunk = 65_536
        var hasher = SHA256()
        if let head = try? handle.read(upToCount: chunk) { hasher.update(data: head) }
        if size > Int64(chunk * 2) {
            try? handle.seek(toOffset: UInt64(size - Int64(chunk)))
            if let tail = try? handle.read(upToCount: chunk) { hasher.update(data: tail) }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func fullHash(_ path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let more: Bool = autoreleasepool {
                guard let data = try? handle.read(upToCount: 4 * 1_048_576), !data.isEmpty else { return false }
                hasher.update(data: data)
                return true
            }
            if !more { break }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
