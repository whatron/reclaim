import AppKit
import SwiftUI

/// Full Disk Access: one switch in System Settings that replaces the separate prompts for
/// Documents, Desktop, Downloads, iCloud Drive and the rest, and also opens up Library and the Trash.
enum Access {
    /// True when Reclaim can read places only Full Disk Access unlocks.
    static func hasFullDiskAccess() -> Bool {
        let fm = FileManager.default
        let probes = [
            Paths.h("Library/Application Support/com.apple.TCC/TCC.db"),
            Paths.h("Library/Safari/Bookmarks.plist"),
            Paths.h("Library/Safari"),
            Paths.h("Library/Mail"),
        ]
        for probe in probes {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: probe, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                return (try? fm.contentsOfDirectory(atPath: probe)) != nil
            }
            let fd = open(probe, O_RDONLY)
            if fd >= 0 {
                close(fd)
                return true
            }
            return false
        }
        // Nothing protected to test against, so nothing is being hidden.
        return true
    }

    static func openSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    /// macOS sometimes only applies Full Disk Access after the app restarts.
    @MainActor static func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"",
                             Bundle.main.bundlePath, String(ProcessInfo.processInfo.processIdentifier)]
        try? process.run()
        AppQuit.now()
    }
}

struct AccessSheet: View {
    @EnvironmentObject var model: AppModel
    @State var granted = false
    @State var openedSettings = false
    @State var waitedLong = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 16) {
                SymbolTile(symbol: granted ? "checkmark.shield.fill" : "lock.open.fill",
                           tint: granted ? Palette.mint : Palette.sky, size: 58)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 6) {
                    Text(granted ? "You're all set" : "One switch, and Reclaim sees everything")
                        .font(.display(24, .bold))
                    Text(granted
                         ? "Reclaim can now measure every corner of your disk. Starting the scan…"
                         : "Turn on Full Disk Access once instead of answering a prompt for every folder. It lets Reclaim measure Library, the Trash, Mail and app data, which is usually where the most space hides.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !granted {
                VStack(alignment: .leading, spacing: 14) {
                    StepRow(number: 1, title: "Open Privacy & Security",
                            detail: "Reclaim takes you straight to the Full Disk Access list.") {
                        Button {
                            Access.openSettings()
                            openedSettings = true
                        } label: {
                            Label("Open System Settings", systemImage: "gearshape")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.sky)
                    }
                    StepRow(number: 2, title: "Switch on Reclaim",
                            detail: "Not in the list? Drag this icon into it, then flip its switch.") {
                        AppDragTile()
                    }
                    StepRow(number: 3, title: "Come back here",
                            detail: "Reclaim notices on its own and starts scanning.") {
                        EmptyView()
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.04)))
            }

            HStack(spacing: 10) {
                if granted {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.mint)
                    Text("Full Disk Access is on").font(.headline)
                } else {
                    ProgressView().controlSize(.small)
                    Text(openedSettings ? "Waiting for the switch…" : "Waiting for Full Disk Access")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 18) {
                Promise(symbol: "lock.laptopcomputer", text: "Everything stays on your Mac")
                Promise(symbol: "hand.raised", text: "Nothing is removed without asking")
                Promise(symbol: "switch.2", text: "Turn it off any time")
            }

            Divider()

            HStack {
                if !granted {
                    Button("Continue with Limited Access") { model.continueWithLimitedAccess() }
                        .buttonStyle(.link)
                        .help("macOS will ask about Documents, Desktop and Downloads separately, and Library and the Trash stay partly hidden.")
                }
                Spacer()
                if !granted && waitedLong {
                    Text("Switched it on already?")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Restart Reclaim") { Access.relaunch() }
                }
            }
        }
        .padding(28)
        .frame(width: 580)
        .animation(.snappy, value: granted)
        .animation(.snappy, value: waitedLong)
        .interactiveDismissDisabled()
        .task {
            // Check once a second; most changes apply right away.
            guard Tour.folder == nil else { return }
            var seconds = 0
            while !Task.isCancelled && !granted {
                if Access.hasFullDiskAccess() {
                    granted = true
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    model.fullDiskAccessGranted()
                    return
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if openedSettings { seconds += 1 }
                if seconds >= 12 { waitedLong = true }
            }
        }
    }
}

struct StepRow<Accessory: View>: View {
    let number: Int
    let title: String
    let detail: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text("\(number)")
                .font(.display(15, .bold))
                .foregroundStyle(Palette.sky)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Palette.sky.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            accessory
        }
    }
}

/// Reclaim's own icon, which can be dragged into the Full Disk Access list.
struct AppDragTile: View {
    @State var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                .resizable()
                .frame(width: 30, height: 30)
            Text("Reclaim")
                .font(.callout.weight(.semibold))
            Image(systemName: "hand.draw")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(hovering ? 0.1 : 0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .foregroundStyle(Color.secondary.opacity(0.6)))
        .onHover { hovering = $0 }
        .onDrag { NSItemProvider(contentsOf: Bundle.main.bundleURL) ?? NSItemProvider() }
        .help("Drag into the Full Disk Access list in System Settings")
    }
}

struct Promise: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(Palette.mint)
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
