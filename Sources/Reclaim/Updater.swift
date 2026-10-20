import AppKit
import Foundation
import SwiftUI

/// Checks GitHub releases for a newer Reclaim and installs it in place.
///
/// It asks GitHub's API directly, which works while the repository is public. If that fails (for
/// example, if the repository is made private), it falls back to the GitHub CLI (`gh`) and your
/// sign-in. Either way, the download isn't marked by macOS, so the new version opens without the
/// "unsafe app" warning.
@MainActor
final class Updater: ObservableObject {
    nonisolated static let repo = "whatron/reclaim"

    struct Release: Equatable {
        let tag: String
        let version: String
        let notes: String
        let pageURL: URL
        let published: Date?
        let assetName: String
        let assetURL: URL?
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate(latest: String)
        case available(Release)
        case downloading(Release)
        case installing(Release)
        case failed(String)
    }

    @Published var state: State = .idle
    @Published var showSheet = false
    @Published var lastChecked: Date?

    /// The release a person can install right now, if any.
    var available: Release? {
        switch state {
        case .available(let r), .downloading(let r), .installing(let r): return r
        default: return nil
        }
    }

    private var usedCLI = false
    private var started = false

    /// Checks shortly after launch and then once a day, if automatic checks are on.
    func start() {
        guard !started, Tour.folder == nil,
              ProcessInfo.processInfo.environment["RECLAIM_TEST_UPDATE"] == nil else { return }
        started = true
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            while !Task.isCancelled {
                if UserDefaults.standard.object(forKey: "autoCheckUpdates") as? Bool ?? true {
                    await check(userInitiated: false)
                }
                try? await Task.sleep(nanoseconds: 24 * 3600 * 1_000_000_000)
            }
        }
    }

    func check(userInitiated: Bool) async {
        if case .downloading = state { return }
        if case .installing = state { return }
        if userInitiated { showSheet = true }
        state = .checking
        do {
            let release = try await fetchLatest()
            lastChecked = Date()
            let skipped = UserDefaults.standard.string(forKey: "skippedUpdate")
            if Self.isNewer(release.version, than: AppVersion.version) {
                state = .available(release)
                if !userInitiated && skipped == release.version {
                    state = .upToDate(latest: release.version)
                }
            } else {
                state = .upToDate(latest: release.version)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Build-check only (RECLAIM_TEST_UPDATE): installs the latest release over this copy with the
    /// update sheet open, exactly as a person would, so the build can confirm the swap and relaunch.
    func testInstallLatest() async {
        guard let release = try? await fetchLatest() else {
            state = .failed("Test: couldn't find the latest release.")
            return
        }
        state = .available(release)
        showSheet = true
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await install(release)
    }

    /// Screenshot tour only: checks for real, then shows the latest release as if it were new.
    func tourShowLatest() async -> String {
        await check(userInitiated: false)
        let outcome: String
        switch state {
        case .upToDate(let latest): outcome = "up to date, latest release \(latest)"
        case .available(let r): outcome = "update available: \(r.version)"
        case .failed(let message): outcome = "failed: \(message)"
        default: outcome = "\(state)"
        }
        if let release = try? await fetchLatest() { state = .available(release) }
        return "Update check (via \(usedCLI ? "GitHub CLI" : "anonymous request")): \(outcome)"
    }

    func skip(_ release: Release) {
        UserDefaults.standard.set(release.version, forKey: "skippedUpdate")
        state = .upToDate(latest: release.version)
        showSheet = false
    }

    // MARK: Finding the latest release

    private struct APIRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL?
        }
        let tag_name: String
        let name: String?
        let body: String?
        let html_url: URL
        let published_at: String?
        let assets: [Asset]
    }

    private func fetchLatest() async throws -> Release {
        let api = "repos/\(Self.repo)/releases/latest"
        var data: Data?
        // 1. Anonymous request: works if the repository is public.
        if let url = URL(string: "https://api.github.com/\(api)") {
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            if let answer = try? await URLSession.shared.data(for: request),
               (answer.1 as? HTTPURLResponse)?.statusCode == 200 {
                data = answer.0
                usedCLI = false
            }
        }
        // 2. The GitHub CLI, signed in as you: works for the private repository.
        if data == nil {
            guard Shell.which("gh") != nil else {
                throw UpdateError("Couldn't reach GitHub's releases directly. To check through the GitHub CLI instead, Install it with “brew install gh”, then run “gh auth login”.")
            }
            let result = await background { Shell.run(["gh", "api", api], timeout: 30) }
            guard result.ok else {
                if result.output.contains("auth login") || result.output.contains("401") {
                    throw UpdateError("The GitHub CLI isn't signed in. Run “gh auth login” in Terminal, then check again.")
                }
                throw UpdateError("Couldn't reach GitHub. \(result.output.prefix(200))")
            }
            data = Data(result.stdout.utf8)
            usedCLI = true
        }
        guard let data, let release = try? JSONDecoder().decode(APIRelease.self, from: data) else {
            throw UpdateError("GitHub's answer didn't include a release.")
        }
        guard let asset = release.assets.first(where: { $0.name.hasPrefix("Reclaim-") && $0.name.hasSuffix(".zip") }) else {
            throw UpdateError("The latest release, \(release.tag_name), has no app attached.")
        }
        let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        return Release(tag: release.tag_name, version: version, notes: release.body ?? "",
                       pageURL: release.html_url,
                       published: release.published_at.flatMap { ISO8601DateFormatter().date(from: $0) },
                       assetName: asset.name, assetURL: asset.browser_download_url)
    }

    // MARK: Installing

    func install(_ release: Release) async {
        let appPath = Bundle.main.bundlePath
        let folder = Paths.parent(appPath)
        guard !appPath.contains("/AppTranslocation/") else {
            state = .failed("Reclaim is running from a temporary location macOS made for it. Move Reclaim into Applications, open it from there, and try again.")
            return
        }
        guard FileManager.default.isWritableFile(atPath: folder) else {
            state = .failed("Reclaim can't replace itself in \(Paths.tilde(folder)). Use install.sh, or download the update from the release page.")
            return
        }

        state = .downloading(release)
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("reclaim-update-\(UUID().uuidString)", isDirectory: true)
        let zip = work.appendingPathComponent(release.assetName)
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            if usedCLI || release.assetURL == nil {
                let tag = release.tag
                let dir = work.path
                let repo = Updater.repo
                let r = await background {
                    Shell.run(["gh", "release", "download", tag, "--repo", repo,
                               "--pattern", "Reclaim-*.zip", "--dir", dir, "--clobber"], timeout: 600)
                }
                guard r.ok else { throw UpdateError("The download didn't finish. \(r.output.prefix(200))") }
            } else if let url = release.assetURL {
                let (temp, response) = try await URLSession.shared.download(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("The download didn't finish.") }
                try FileManager.default.moveItem(at: temp, to: zip)
            }

            state = .installing(release)
            let unpacked = work.appendingPathComponent("unpacked").path
            let zipPath = zip.path
            let r = await background { Shell.run(["/usr/bin/ditto", "-x", "-k", zipPath, unpacked]) }
            let newApp = unpacked + "/Reclaim.app"
            guard r.ok, FileManager.default.fileExists(atPath: newApp + "/Contents/MacOS/Reclaim") else {
                throw UpdateError("The download didn't contain Reclaim.app.")
            }

            // Swap the app once this copy has quit, then open the new one. The old copy is kept
            // until the new one is in place, and every step is logged.
            let script = """
            log="$HOME/Library/Logs/Reclaim/update.log"
            mkdir -p "$(dirname "$log")"
            {
              echo "$(date): installing $3 over $2; waiting for process $1 to quit"
              i=0
              while kill -0 "$1" 2>/dev/null && [ $i -lt 100 ]; do sleep 0.2; i=$((i + 1)); done
              if kill -0 "$1" 2>/dev/null; then
                echo "Still running after 20 seconds; stopping it."
                kill -9 "$1"; sleep 0.5
              fi
              backup="$2.old-$$"
              if mv "$2" "$backup"; then
                if /usr/bin/ditto "$3" "$2"; then
                  rm -rf "$backup"
                  /usr/bin/xattr -dr com.apple.quarantine "$2" 2>/dev/null
                  echo "Installed."
                else
                  echo "Copying the new version failed; putting the old one back."
                  rm -rf "$2"; mv "$backup" "$2"
                fi
              else
                echo "Couldn't move the old version aside; leaving it as it was."
              fi
              /usr/bin/open "$2"
              rm -rf "$4"
            } >> "$log" 2>&1
            """
            let swap = Process()
            swap.executableURL = URL(fileURLWithPath: "/bin/sh")
            swap.arguments = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier),
                              appPath, newApp, work.path]
            try swap.run()
            UserDefaults.standard.removeObject(forKey: "skippedUpdate")
            showSheet = false
            AppQuit.now()
        } catch {
            try? FileManager.default.removeItem(at: work)
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: Versions

    /// Whether `remote` (e.g. 0.1.1) comes after `local` (e.g. 0.1.0 or 0.1.0-build.31).
    /// A build label on the same number counts as that release or later, so it isn't offered again.
    nonisolated static func isNewer(_ remote: String, than local: String) -> Bool {
        func numbers(_ v: String) -> [Int] {
            let trimmed = v.hasPrefix("v") ? String(v.dropFirst()) : v
            let core = trimmed.split(separator: "-", maxSplits: 1).first.map(String.init) ?? trimmed
            return core.split(separator: ".").map { Int($0) ?? 0 }
        }
        let a = numbers(remote), b = numbers(local)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

struct UpdateError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: - The update sheet

struct UpdateSheet: View {
    @EnvironmentObject var updater: Updater
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch updater.state {
            case .idle, .checking:
                header(symbol: "arrow.triangle.2.circlepath", tint: Palette.sky,
                       title: "Checking for updates…", detail: "Asking GitHub for the latest release.")
                ProgressView().frame(maxWidth: .infinity)
            case .upToDate(let latest):
                header(symbol: "checkmark.seal.fill", tint: Palette.mint, title: "You're up to date",
                       detail: "Reclaim \(AppVersion.version) is the newest version (latest release: \(latest)).")
            case .failed(let message):
                header(symbol: "exclamationmark.triangle.fill", tint: Palette.sand, title: "Couldn't check for updates",
                       detail: message)
            case .available(let r):
                header(symbol: "sparkles", tint: Palette.mint, title: "Reclaim \(r.version) is available",
                       detail: "You have \(AppVersion.version). Reclaim installs the update and reopens in a few seconds."
                               + (r.published.map { " Released \(Format.ago($0))." } ?? ""))
                notes(r)
            case .downloading(let r):
                header(symbol: "arrow.down.circle", tint: Palette.sky, title: "Downloading Reclaim \(r.version)…",
                       detail: "This only takes a moment.")
                ProgressView().frame(maxWidth: .infinity)
            case .installing(let r):
                header(symbol: "shippingbox", tint: Palette.sky, title: "Installing Reclaim \(r.version)…",
                       detail: "Reclaim will quit and reopen.")
                ProgressView().frame(maxWidth: .infinity)
            }

            HStack {
                if case .available(let r) = updater.state {
                    Button("Skip This Version") { updater.skip(r) }
                    Link("Release Page", destination: r.pageURL)
                        .padding(.leading, 6)
                }
                Spacer()
                switch updater.state {
                case .available(let r):
                    Button("Later") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Install and Relaunch") { Task { await updater.install(r) } }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.mint)
                case .downloading, .installing:
                    EmptyView()
                case .failed:
                    Button("Try Again") { Task { await updater.check(userInitiated: true) } }
                    Button("Close") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                default:
                    Button("Close") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(26)
        .frame(width: 520)
        .animation(.snappy, value: updater.state)
    }

    private func header(symbol: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            SymbolTile(symbol: symbol, tint: tint, size: 50)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.display(21, .bold))
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func notes(_ r: Updater.Release) -> some View {
        let text = Self.renderNotes(r.notes)
        if !text.characters.isEmpty {
            ScrollView {
                Text(text)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 220)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
        }
    }

    /// Release notes are Markdown; headings become bold lines and the install steps are left out.
    static func renderNotes(_ markdown: String) -> AttributedString {
        var lines: [String] = []
        var skipping = false
        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") {
                let title = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                skipping = title.lowercased() == "install"
                if !skipping { lines.append("**\(title)**") }
                continue
            }
            guard !skipping else { continue }
            if line.hasPrefix("* ") || line.hasPrefix("- ") {
                lines.append("•  " + line.dropFirst(2))
            } else {
                lines.append(raw)
            }
        }
        let cleaned = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: cleaned, options: options)) ?? AttributedString(cleaned)
    }
}

/// A small call to action, used in the sidebar.
struct UpdatePill: View {
    @EnvironmentObject var updater: Updater

    var body: some View {
        if let r = updater.available {
            Button {
                updater.showSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(Palette.mint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Update available").font(.callout.weight(.semibold))
                        Text("Reclaim \(r.version)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.mint.opacity(0.14)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.mint.opacity(0.3)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// Quitting reliably. AppKit refuses to quit while a sheet is open on a window, which left the
/// update stuck on "Reclaim will quit and reopen", so sheets are closed first, and the app exits
/// anyway if something still holds it open.
@MainActor
enum AppQuit {
    static func now() {
        for window in NSApp.windows {
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NSApp.terminate(nil) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { exit(0) }
    }
}
