import AppKit
import SwiftUI

@main
struct ReclaimApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject var model = AppModel()
    @AppStorage("showInMenuBar") var showInMenuBar = true

    var body: some Scene {
        Window("Reclaim", id: "main") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 680)
        }
        .defaultSize(width: 1280, height: 880)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Rescan") { model.rescan() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Clean Recommended…") { model.perform(.quickClean) }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                    .disabled(model.recommendedBytes == 0 || model.batch != nil)
            }
            CommandGroup(after: .sidebar) {
                ForEach(Array(AppSection.allCases.enumerated()), id: \.element.id) { index, section in
                    Button(section.title) { model.section = section }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
            }
        }

        MenuBarExtra(isInserted: $showInMenuBar) {
            MenuBarPanel()
                .environmentObject(model)
        } label: {
            Text(model.menuBarTitle)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in the menu bar if that's turned on.
        let showInMenuBar = UserDefaults.standard.object(forKey: "showInMenuBar") as? Bool ?? true
        return !showInMenuBar
    }
}

// MARK: - Menu bar

struct MenuBarPanel: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let d = model.disk {
                let reclaim = model.reclaimableBytes
                let trash = model.trashBytes
                let big = Format.bigFree(d.free)
                HStack(spacing: 14) {
                    TideGauge(total: d.total, other: max(0, d.used - reclaim - trash), reclaim: reclaim, trash: trash,
                              showTicks: false, cornerFraction: 0.3, animated: false)
                        .frame(width: 42, height: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(big.number)
                                .font(.display(30, .heavy))
                                .monospacedDigit()
                                .foregroundStyle(model.fullness > 0.9 ? Palette.coral : Color.primary)
                            Text(big.unit)
                                .font(.display(15, .semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text("of \(Format.bytes(d.total)) on \(model.computerName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                ProgressView("Reading your disk…")
            }

            if let insight = model.insights.first {
                HStack(spacing: 10) {
                    SymbolTile(symbol: insight.symbol, tint: insight.tint, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(insight.headline)
                            .font(.callout.weight(.semibold))
                            .lineLimit(2)
                        Text(insight.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Button {
                    openMain()
                    model.perform(insight.action)
                } label: {
                    Text(insight.actionTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(insight.tint)
                .controlSize(.large)
            }

            Divider()

            HStack {
                Button("Open Reclaim") { openMain() }
                Spacer()
                Button {
                    model.rescan()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Rescan")
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.borderless)
                .help("Quit Reclaim")
            }
        }
        .padding(16)
        .frame(width: 310)
    }

    private func openMain() {
        openWindow(id: "main")
        NSApp.activate()
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) var openWindow
    @AppStorage("showInMenuBar") var showInMenuBar = true
    @AppStorage("lowSpaceAlerts") var lowSpaceAlerts = true

    var body: some View {
        Form {
            Section("Access") {
                HStack(spacing: 10) {
                    Image(systemName: model.hasFullDiskAccess ? "checkmark.shield.fill" : "exclamationmark.shield")
                        .foregroundStyle(model.hasFullDiskAccess ? Palette.mint : Palette.sand)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.hasFullDiskAccess ? "Full Disk Access is on" : "Full Disk Access is off")
                        Text(model.hasFullDiskAccess ? "Reclaim can measure every folder."
                             : "Library, the Trash and some app data are only partly measured.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !model.hasFullDiskAccess {
                        Button("Set Up…") {
                            openWindow(id: "main")
                            NSApp.activate()
                            model.showAccessSheet = true
                        }
                    }
                }
            }
            Section {
                Toggle("Show free space in the menu bar", isOn: $showInMenuBar)
                Toggle("Warn me when my Mac is nearly full", isOn: $lowSpaceAlerts)
            } footer: {
                Text("With the menu bar item on, Reclaim keeps watching free space after you close its window, records a reading every hour for History, and warns you when space runs low.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 470)
        .fixedSize()
    }
}
