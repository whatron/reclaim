import AppKit
import SwiftUI

struct AppsView: View {
    @EnvironmentObject var model: AppModel
    @State var unusedOnly = false
    @State var sortByIdle = false
    @State var picked: Set<String> = []

    var body: some View {
        Group {
            switch model.appsState {
            case .idle, .loading:
                ScanningState(symbol: "square.grid.3x3", tint: Palette.sky, title: "Measuring your apps",
                              status: "Checking each app's size and when you last opened it…")
            case .loaded:
                if model.apps.isEmpty {
                    ContentUnavailableView("No third-party apps found", systemImage: "square.grid.3x3",
                                           description: Text("Reclaim looks in /Applications and ~/Applications."))
                } else {
                    loaded
                }
            }
        }
        .navigationTitle("Apps")
        .task { model.loadAppsIfNeeded() }
    }

    private var visible: [AppInfo] {
        let list = unusedOnly ? model.unusedApps : model.apps
        if sortByIdle {
            return list.sorted { ($0.idleDays ?? Int.max) > ($1.idleDays ?? Int.max) }
        }
        return list
    }

    private var subtitle: String {
        let unused = model.unusedApps
        let bytes = unused.reduce(Int64(0)) { $0 + $1.size }
        if unused.isEmpty {
            return "Your apps, biggest first. Everything big has been opened in the last three months."
        }
        return "Your apps, biggest first. \(unused.count) big app\(unused.count == 1 ? " hasn't" : "s haven't") been opened in three months and take \(Format.short(bytes)). Settings stay in Library, so reinstalling picks up where you left off."
    }

    private var loaded: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "Apps", subtitle: subtitle)

                HStack {
                    Picker("Show", selection: $unusedOnly) {
                        Text("All apps").tag(false)
                        Text("Unused for 3 months").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 300)
                    Spacer()
                    Picker("Sort", selection: $sortByIdle) {
                        Text("Biggest first").tag(false)
                        Text("Least recently opened").tag(true)
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
                    ForEach(visible) { app in
                        AppCard(app: app, isOn: picked.contains(app.path)) {
                            if picked.contains(app.path) { picked.remove(app.path) } else { picked.insert(app.path) }
                        }
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 28)
            .padding(.bottom, 130)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .bottom) { dock }
        .onChange(of: model.apps) { _, newValue in
            picked.formIntersection(Set(newValue.map(\.path)))
        }
    }

    private var dock: some View {
        let chosen = model.apps.filter { picked.contains($0.path) && $0.canTrash }
        let bytes = chosen.reduce(Int64(0)) { $0 + $1.size }
        return ActionDock {
            VStack(alignment: .leading, spacing: 2) {
                Text(chosen.isEmpty ? "Tick apps you no longer use" : "\(chosen.count) app\(chosen.count == 1 ? "" : "s") ticked")
                    .font(.headline)
                Text("Quit an app before moving it to the Trash.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 20)
            Button("Tick Unused") {
                withAnimation(.snappy) { picked = Set(model.unusedApps.map(\.path)) }
            }
            .disabled(model.unusedApps.isEmpty)
            Button {
                model.requestTrashApps(chosen)
            } label: {
                Label(bytes > 0 ? "Move \(Format.short(bytes)) to Trash" : "Move to Trash", systemImage: "trash")
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.sky)
            .controlSize(.large)
            .disabled(chosen.isEmpty)
        }
    }
}

struct AppCard: View {
    @EnvironmentObject var model: AppModel
    let app: AppInfo
    let isOn: Bool
    let toggle: () -> Void
    @State var hovering = false

    private var unused: Bool { (app.idleDays ?? 9999) >= 90 && app.size > 100_000_000 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(nsImage: Icons.icon(app.path))
                    .resizable()
                    .frame(width: 54, height: 54)
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                Spacer()
                if app.canTrash {
                    RoundCheck(isOn: isOn, tint: Palette.sky)
                        .opacity(isOn || hovering ? 1 : 0.35)
                } else {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.tertiary)
                        .help("Reclaim can't move this app.")
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(Format.bytes(app.size))
                    .font(.display(20, .heavy))
                    .monospacedDigit()
            }
            HStack(spacing: 5) {
                Image(systemName: unused ? "moon.zzz.fill" : "clock")
                Text(openedText)
                    .lineLimit(1)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(unused ? Palette.sand : Color.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(isOn ? 0.95 : 0.7)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(isOn ? Palette.sky : Color.primary.opacity(0.07), lineWidth: isOn ? 2 : 1))
        .scaleEffect(hovering ? 1.015 : 1)
        .animation(.snappy(duration: 0.18), value: hovering)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture { if app.canTrash { toggle() } }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(URL(fileURLWithPath: app.path)) }
            Button("Show in Finder") { model.reveal(app.path) }
            if app.canTrash {
                Divider()
                Button("Move to Trash…") { model.requestTrashApps([app]) }
            }
        }
        .help(Paths.tilde(app.path))
    }

    private var openedText: String {
        guard let days = app.idleDays else { return "Never opened" }
        if days == 0 { return "Opened today" }
        if days < 60 { return "Opened \(Format.ago(app.lastUsed))" }
        if days < 730 { return "Not opened in \(days / 30) months" }
        return "Not opened in \(days / 365) years"
    }
}
