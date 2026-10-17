import AppKit
import SwiftUI

@main
struct ReclaimApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @AppStorage("showInMenuBar") private var showInMenuBar = true

    var body: some Scene {
        Window("Reclaim", id: "main") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 940, minHeight: 640)
        }
        .defaultSize(width: 1200, height: 840)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Rescan") { model.rescan() }
                    .keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(after: .sidebar) {
                ForEach(Array(AppSection.allCases.enumerated()), id: \.element.id) { index, section in
                    Button(section.title) { model.section = section }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
            }
        }

        MenuBarExtra(isInserted: $showInMenuBar) {
            MenuBarContent()
                .environmentObject(model)
        } label: {
            Text(model.menuBarTitle)
        }

        Settings {
            SettingsView()
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

struct MenuBarContent: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let d = model.disk {
            Text("\(Format.bytes(d.free)) free of \(Format.bytes(d.total))")
        }
        if model.reclaimableBytes > 0 {
            Text("About \(Format.bytes(model.reclaimableBytes)) can be cleaned")
        }
        if model.trashBytes > 0 {
            Text("\(Format.bytes(model.trashBytes)) in the Trash")
        }
        Divider()
        Button("Open Reclaim") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Rescan") { model.rescan() }
        Divider()
        Button("Quit Reclaim") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

struct SettingsView: View {
    @AppStorage("showInMenuBar") private var showInMenuBar = true

    var body: some View {
        Form {
            Toggle("Show free space in the menu bar", isOn: $showInMenuBar)
            Text("When this is on, Reclaim keeps running in the menu bar after you close its window.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 420)
    }
}
