import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 214, ideal: 236, max: 300)
        } detail: {
            ZStack {
                AuroraBackground()
                page
                    .id(model.section ?? .overview)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
            .animation(.snappy(duration: 0.28), value: model.section)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.rescan()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .help("Measure everything again (⌘R)")
            }
        }
        .sheet(item: $model.pending) { action in
            ConfirmSheet(action: action)
        }
        .task {
            // Lets the screenshot step open a given page: RECLAIM_SECTION=map
            if let raw = ProcessInfo.processInfo.environment["RECLAIM_SECTION"],
               let section = AppSection(rawValue: raw) {
                model.section = section
                NSApp.activate()
            }
        }
        .overlay(alignment: .top) { BatchBanner() }
        .overlay(alignment: .bottom) { ToastOverlay() }
        .overlay { CelebrationOverlay() }
    }

    @ViewBuilder
    private var page: some View {
        switch model.section ?? .overview {
        case .overview: OverviewView()
        case .clean: SmartCleanView()
        case .map: SpaceMapView()
        case .projects: ProjectsView()
        case .files: LargeFilesView()
        case .duplicates: DuplicatesView()
        case .apps: AppsView()
        case .history: HistoryView()
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject var model: AppModel
    private var groups: [String] { ["Reclaim", "Discover", "Track"] }

    var body: some View {
        List(selection: $model.section) {
            ForEach(groups, id: \.self) { group in
                Section(group) {
                    ForEach(AppSection.allCases.filter { $0.group == group }) { section in
                        Label(section.title, systemImage: section.icon)
                            .badge(badge(for: section))
                            .tag(Optional(section))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarGauge()
                .padding(12)
        }
    }

    private func badge(for section: AppSection) -> Text? {
        switch section {
        case .clean:
            return model.recommendedBytes > 500_000_000 ? Text(Format.short(model.recommendedBytes)) : nil
        case .projects:
            let stale = model.staleProjects.count
            return model.projectsState == .loaded && stale > 0 ? Text("\(stale)") : nil
        case .duplicates:
            return model.dupesState == .loaded && !model.dupes.isEmpty ? Text("\(model.dupes.count)") : nil
        case .apps:
            let unused = model.unusedApps.count
            return unused > 0 ? Text("\(unused)") : nil
        default:
            return nil
        }
    }
}

struct SidebarGauge: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let d = model.disk {
            let reclaim = model.reclaimableBytes
            let trash = model.trashBytes
            HStack(spacing: 12) {
                TideGauge(total: d.total, other: max(0, d.used - reclaim - trash), reclaim: reclaim, trash: trash,
                          showTicks: false, cornerFraction: 0.32, animated: false)
                    .frame(width: 28, height: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(Format.short(d.free)) free")
                        .font(.display(15, .bold))
                        .monospacedDigit()
                        .foregroundStyle(model.fullness > 0.9 ? Palette.coral : Color.primary)
                    Text("of \(Format.short(d.total)) on \(model.computerName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
            .onTapGesture { model.section = .overview }
            .help("Open Overview")
        }
    }
}

// MARK: - Confirmation sheet

struct ConfirmSheet: View {
    @Environment(\.dismiss) var dismiss
    let action: PendingAction
    @State var typed = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                SymbolTile(symbol: action.destructive ? "exclamationmark.triangle.fill" : "trash",
                           tint: action.destructive ? Palette.coral : Palette.mint, size: 46)
                VStack(alignment: .leading, spacing: 6) {
                    Text(action.title)
                        .font(.display(20, .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(action.message)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !action.items.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(action.items.enumerated()), id: \.offset) { _, item in
                            HStack(spacing: 9) {
                                Circle()
                                    .fill(action.destructive ? Palette.coral : Palette.mint)
                                    .frame(width: 6, height: 6)
                                Text(item)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
                .frame(maxHeight: 190)
                .fixedSize(horizontal: false, vertical: true)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
            }

            if let command = action.command {
                Text(command)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
            }

            if let word = action.typeToConfirm {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Emptying the Trash can't be undone. Type “\(word)” to confirm.")
                        .font(.callout)
                    TextField(word, text: $typed)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(action.confirmLabel, role: action.destructive ? .destructive : nil) {
                    let perform = action.perform
                    dismiss()
                    Task { await perform() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(action.destructive ? Palette.coral : Palette.mint)
                .disabled(!canConfirm)
            }
        }
        .padding(26)
        .frame(width: 480)
    }

    private var canConfirm: Bool {
        guard let word = action.typeToConfirm else { return true }
        return typed.trimmingCharacters(in: .whitespaces).lowercased() == word
    }
}

// MARK: - Feedback overlays

struct ToastOverlay: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            if let toast = model.toast {
                HStack(spacing: 9) {
                    Image(systemName: toast.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(toast.ok ? Palette.mint : Palette.coral)
                    Text(toast.text)
                        .lineLimit(2)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .glassPanel(cornerRadius: 20)
                .padding(.bottom, 96)
                .padding(.horizontal, 60)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(toast.id)
            }
        }
        .animation(.snappy, value: model.toast)
    }
}

/// Progress for a one-click clean, visible from every page.
struct BatchBanner: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            if let run = model.batch {
                HStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.small)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(run.current.isEmpty ? "Getting ready…" : "Cleaning \(run.current)…")
                            .font(.headline)
                            .lineLimit(1)
                        ProgressView(value: Double(run.done), total: Double(max(run.total, 1)))
                            .tint(Palette.mint)
                            .frame(width: 240)
                    }
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(run.done) of \(run.total)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        if run.freed > 0 {
                            Text("\(Format.short(run.freed)) freed")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(Palette.mint)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassPanel(cornerRadius: 20)
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: model.batch)
    }
}

/// A short burst of bubbles and the amount freed, after a cleanup that actually freed space.
struct CelebrationOverlay: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            if let freed = model.celebration {
                ZStack {
                    BubbleBurst()
                        .allowsHitTesting(false)
                    VStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(Palette.mint)
                            .symbolEffect(.bounce, value: freed)
                        Text(Format.bytes(freed))
                            .font(.display(52, .heavy))
                            .monospacedDigit()
                        Text("is free again")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        if model.lifetimeFreed > freed {
                            Text("\(Format.short(model.lifetimeFreed)) reclaimed in total")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                                .padding(.top, 2)
                        }
                    }
                    .padding(.horizontal, 44)
                    .padding(.vertical, 28)
                    .glassPanel(cornerRadius: 28)
                    .onTapGesture { dismiss() }
                }
                .transition(.scale(scale: 0.85).combined(with: .opacity))
                .task(id: freed) {
                    try? await Task.sleep(nanoseconds: 2_800_000_000)
                    dismiss()
                }
                .sensoryFeedback(.success, trigger: freed)
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.3), value: model.celebration)
    }

    private func dismiss() {
        withAnimation(.snappy) { model.celebration = nil }
    }
}

struct BubbleBurst: View {
    @State var start = Date()
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start)
            Canvas { context, size in
                guard !reduceMotion else { return }
                for i in 0..<46 {
                    // Cheap deterministic "random" numbers per bubble.
                    let seed = Double(i) * 12.9898
                    let r1 = abs(sin(seed) * 43758.5453).truncatingRemainder(dividingBy: 1)
                    let r2 = abs(sin(seed * 1.7) * 23421.631).truncatingRemainder(dividingBy: 1)
                    let r3 = abs(sin(seed * 2.3) * 9813.17).truncatingRemainder(dividingBy: 1)
                    let delay = r3 * 0.6
                    let t = max(0, elapsed - delay)
                    guard t > 0 else { continue }
                    let rise = CGFloat(t * (160 + r2 * 240))
                    let x = size.width * CGFloat(0.2 + 0.6 * r1) + CGFloat(sin(t * 3 + seed)) * 10
                    let y = size.height * 0.62 - rise
                    let d = CGFloat(4 + r2 * 12)
                    let alpha = max(0, 0.55 - t * 0.22)
                    let color: Color = i % 3 == 0 ? Palette.sky : Palette.mint
                    let rect = CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)
                    context.stroke(Path(ellipseIn: rect), with: .color(color.opacity(alpha)), lineWidth: 1.5)
                    context.fill(Path(ellipseIn: rect.insetBy(dx: d * 0.3, dy: d * 0.3)),
                                 with: .color(color.opacity(alpha * 0.35)))
                }
            }
        }
        .onAppear { start = Date() }
    }
}
