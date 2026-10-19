import AppKit
import Foundation

// MARK: - File categories

enum FileCategory: String, CaseIterable, Identifiable {
    case all, video, installer, archive, virtualMachine, audio, other
    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .video: return "Videos"
        case .installer: return "Installers"
        case .archive: return "Archives"
        case .virtualMachine: return "Disk images"
        case .audio: return "Audio"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .all: return "square.stack.3d.up"
        case .video: return "film"
        case .installer: return "shippingbox"
        case .archive: return "archivebox"
        case .virtualMachine: return "externaldrive"
        case .audio: return "waveform"
        case .other: return "doc"
        }
    }

    static func of(_ path: String) -> FileCategory {
        switch Paths.ext(path) {
        case "mov", "mp4", "m4v", "mkv", "avi", "webm", "mts", "braw", "prores": return .video
        case "dmg", "pkg", "mpkg", "iso", "xip", "msi", "exe": return .installer
        case "zip", "tar", "gz", "tgz", "7z", "rar", "bz2", "xz", "zst": return .archive
        case "vmdk", "vdi", "qcow2", "vhd", "vhdx", "img", "raw", "sparseimage", "sparsebundle", "ova":
            return .virtualMachine
        case "wav", "aif", "aiff", "flac", "mp3", "m4a", "caf": return .audio
        default: return .other
        }
    }
}

// MARK: - Large files

struct LargeFile: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let name: String
    let size: Int64
    let modified: Date
    let lastUsed: Date?
    let kind: String?
    let category: FileCategory
    let isProtected: Bool
    var folder: String { Paths.parent(path) }

    /// Days since the file was last opened (or modified, if Spotlight never saw it opened).
    var idleDays: Int { Format.days(since: lastUsed ?? modified) ?? 0 }

    var smartNote: String? {
        if category == .installer && folder.hasPrefix(Paths.h("Downloads")) {
            return "Installer in Downloads. Safe to remove once the app is installed."
        }
        if category == .archive && folder.hasPrefix(Paths.h("Downloads")) {
            return "Archive in Downloads. Usually already extracted."
        }
        if idleDays > 365 { return "Not opened in over a year." }
        return nil
    }
}

// MARK: - Apps

struct AppInfo: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let name: String
    let bundleID: String?
    let size: Int64
    let lastUsed: Date?
    let canTrash: Bool
    var idleDays: Int? { Format.days(since: lastUsed) }
}

enum Scanners {
    /// Every file over 100 MB that Spotlight knows about in the home folder.
    static func largeFiles(minBytes: Int64 = 100_000_000) -> [LargeFile] {
        let result = Shell.run(["/usr/bin/mdfind", "-onlyin", Paths.home, "kMDItemFSSize > \(minBytes)"], timeout: 180)
        let fm = FileManager.default
        var files: [LargeFile] = []
        for p in result.stdout.split(separator: "\n").map(String.init) {
            var isDir: ObjCBool = false
            guard !p.hasPrefix(Paths.trash + "/"),
                  !p.contains("/Library/"),
                  !Safety.packageInterior(p),
                  fm.fileExists(atPath: p, isDirectory: &isDir), !isDir.boolValue,
                  let attrs = try? fm.attributesOfItem(atPath: p),
                  let size = (attrs[.size] as? NSNumber)?.int64Value,
                  size >= minBytes else { continue }
            files.append(LargeFile(path: p, name: Paths.name(p), size: size,
                                   modified: (attrs[.modificationDate] as? Date) ?? .distantPast,
                                   lastUsed: Spotlight.lastUsed(p),
                                   kind: Spotlight.kind(p),
                                   category: FileCategory.of(p),
                                   isProtected: Safety.isProtected(p)))
        }
        files.sort { $0.size > $1.size }
        return Array(files.prefix(400))
    }

    /// Apps in /Applications and ~/Applications with their size and when they were last opened.
    static func apps() -> [AppInfo] {
        let fm = FileManager.default
        var paths: [String] = []
        for dir in ["/Applications", Paths.h("Applications")] {
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for name in names where name.hasSuffix(".app") {
                paths.append(dir + "/" + name)
            }
        }
        let sizes = Shell.sizes(of: paths)
        var apps: [AppInfo] = []
        for p in paths {
            let bundle = Bundle(path: p)
            let id = bundle?.bundleIdentifier
            if id?.hasPrefix("com.apple.") == true { continue }
            let display = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? Paths.name(p).replacingOccurrences(of: ".app", with: "")
            apps.append(AppInfo(path: p, name: display, bundleID: id, size: sizes[p] ?? 0,
                                lastUsed: Spotlight.lastUsed(p),
                                canTrash: Safety.isTrashableApp(p)))
        }
        apps.sort { $0.size > $1.size }
        return apps
    }
}
