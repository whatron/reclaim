import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.section) {
                ForEach(AppSection.allCases) { section in
                    sidebarRow(section)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
            .safeAreaInset(edge: .bottom) {
                SidebarDiskSummary()
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        } detail: {
            detail
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
        .overlay(alignment: .bottom) {
            ToastOverlay()
        }
    }

    @ViewBuilder
    private func sidebarRow(_ section: AppSection) -> some View {
        switch section {
        case .large:
            Label(section.title, systemImage: section.icon)
                .badge(model.largeState == .loaded ? model.large.count : 0)
        case .activity:
            Label(section.title, systemImage: section.icon)
                .badge(model.log.filter { !$0.ok }.count)
        default:
            Label(section.title, systemImage: section.icon)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.section ?? .cleanup {
        case .cleanup: CleanupView()
        case .explore: ExploreView()
        case .large: LargeFilesView()
        case .activity: ActivityView()
        }
    }
}

// MARK: - Sidebar summary

struct SidebarDiskSummary: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let d = model.disk {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(Format.short(d.free)) free")
                    .font(.system(.headline, design: .rounded))
                    .monospacedDigit()
                CapacityBar(total: d.total,
                            other: max(0, d.used - model.reclaimableBytes - model.trashBytes),
                            reclaim: model.reclaimableBytes,
                            trash: model.trashBytes,
                            height: 7, radius: 3.5)
                Text("of \(Format.bytes(d.total))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Shared pieces

/// Diagonal stripes, used for "can be cleaned" and "in the Trash".
struct Stripes: View {
    let color: Color
    var baseOpacity: Double = 0.72

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color.opacity(baseOpacity)))
            let step: CGFloat = 12
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                var line = Path()
                line.move(to: CGPoint(x: x, y: size.height))
                line.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(line, with: .color(color), lineWidth: 5)
                x += step
            }
        }
    }
}

struct CapacityBar: View {
    let total: Int64
    let other: Int64
    let reclaim: Int64
    let trash: Int64
    var height: CGFloat = 44
    var radius: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Rectangle().fill(Palette.other)
                    .frame(width: geo.size.width * fraction(other))
                Stripes(color: Palette.safe)
                    .frame(width: geo.size.width * fraction(reclaim))
                Stripes(color: Palette.careful)
                    .frame(width: geo.size.width * fraction(trash))
                Spacer(minLength: 0)
            }
        }
        .frame(height: height)
        .background(Color.primary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .animation(.smooth(duration: 0.9), value: other)
        .animation(.smooth(duration: 0.9), value: reclaim)
        .animation(.smooth(duration: 0.9), value: trash)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Format.bytes(max(0, total - other - reclaim - trash))) free of \(Format.bytes(total))")
    }

    private func fraction(_ v: Int64) -> CGFloat {
        total > 0 ? CGFloat(max(0, v)) / CGFloat(total) : 0
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
    }
}

// MARK: - Confirmation sheet

struct ConfirmSheet: View {
    @Environment(\.dismiss) private var dismiss
    let action: PendingAction
    @State private var typed = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: action.destructive ? "exclamationmark.triangle.fill" : "trash.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(action.destructive ? Palette.careful : Palette.safe)
                VStack(alignment: .leading, spacing: 6) {
                    Text(action.title)
                        .font(.title3.weight(.semibold))
                    Text(action.message)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let command = action.command {
                Text(command)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            }
            if let word = action.typeToConfirm {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Type “\(word)” to confirm.")
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
                .disabled(!canConfirm)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private var canConfirm: Bool {
        guard let word = action.typeToConfirm else { return true }
        return typed.trimmingCharacters(in: .whitespaces).lowercased() == word
    }
}

// MARK: - Toast

struct ToastOverlay: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let toast = model.toast {
            HStack(spacing: 8) {
                Image(systemName: toast.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(toast.ok ? Palette.safe : Palette.careful)
                Text(toast.text)
                    .lineLimit(2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
            .padding(.bottom, 24)
            .padding(.horizontal, 40)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(toast.id)
        }
    }
}
