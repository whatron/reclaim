import AppKit
import SwiftUI

struct CleanupView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HeroView()
                if !model.hasFullDiskAccess {
                    AccessBanner()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Clean up")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                    Text("Biggest first. Green items rebuild themselves; yellow ones are worth a look first.")
                        .foregroundStyle(.secondary)
                }
                Card {
                    VStack(spacing: 0) {
                        let list = model.sortedTargets
                        ForEach(list) { target in
                            if target.id != list.first?.id {
                                Divider().padding(.leading, 38)
                            }
                            TargetRow(target: target)
                        }
                    }
                }
                .animation(.snappy, value: model.sortedTargets.map(\.id))
            }
            .padding(32)
            .frame(maxWidth: 940, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Clean Up")
    }
}

// MARK: - Hero

struct HeroView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let d = model.disk {
            let reclaim = model.reclaimableBytes
            let trash = model.trashBytes
            let other = max(0, d.used - reclaim - trash)
            let big = Format.bigFree(d.free)
            let low = d.total > 0 && Double(d.free) / Double(d.total) < 0.1
            let percent = d.total > 0 ? Int((Double(d.used) / Double(d.total) * 100).rounded()) : 0

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(big.number)
                        .font(.system(size: 108, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(low ? Palette.careful : Color.primary)
                    Text(big.unit)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .animation(.snappy, value: big.number)

                Text("of \(Format.bytes(d.total)) on \(model.computerName). \(percent)% full.")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                CapacityBar(total: d.total, other: other, reclaim: reclaim, trash: trash)
                    .padding(.top, 6)

                HStack(spacing: 22) {
                    LegendItem(label: "Everything else", value: other) {
                        RoundedRectangle(cornerRadius: 3).fill(Palette.other)
                    }
                    LegendItem(label: "Can be cleaned", value: reclaim) {
                        Stripes(color: Palette.safe).clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    LegendItem(label: "In the Trash", value: trash) {
                        Stripes(color: Palette.careful).clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    LegendItem(label: "Free", value: d.free) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.07))
                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.primary.opacity(0.15)))
                    }
                }
                .font(.callout)

                summary(reclaim: reclaim, trash: trash)
                    .font(.title3)
                    .padding(.top, 4)
            }
        } else {
            ProgressView("Reading your disk…")
                .frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    private func summary(reclaim: Int64, trash: Int64) -> Text {
        var text: Text
        if reclaim > 0 {
            text = Text("You can free about ")
                + Text(Format.bytes(reclaim)).foregroundColor(Palette.safe).bold()
                + Text(model.isMeasuring ? " with the cleanups below, and still counting." : " with the cleanups below.")
        } else if model.isMeasuring {
            text = Text("Measuring caches, models and build data…")
        } else {
            text = Text("No big caches found. Use Explore to see what's taking space.")
        }
        if trash > 500_000_000 {
            text = text + Text(" Another ")
                + Text(Format.bytes(trash)).foregroundColor(Palette.careful).bold()
                + Text(" is waiting in the Trash.")
        }
        return text
    }
}

struct LegendItem<Swatch: View>: View {
    let label: String
    let value: Int64
    @ViewBuilder var swatch: Swatch

    var body: some View {
        HStack(spacing: 7) {
            swatch.frame(width: 12, height: 12)
            Text(label).foregroundStyle(.secondary)
            Text(Format.bytes(value)).fontWeight(.semibold).monospacedDigit()
        }
    }
}

struct AccessBanner: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "lock.shield")
                .font(.title)
                .foregroundStyle(Palette.review)
            VStack(alignment: .leading, spacing: 3) {
                Text("Reclaim can't see some folders yet")
                    .font(.headline)
                Text("Turn on Full Disk Access for Reclaim so it can measure Library, containers and the Trash accurately. Then come back and click Check Again.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button("Open Settings") { model.openFullDiskAccessSettings() }
            Button("Check Again") { model.rescan() }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.review.opacity(0.12))
        )
    }
}

// MARK: - Cleanup row

struct TargetRow: View {
    @EnvironmentObject private var model: AppModel
    let target: TargetDef
    @State private var showModels = false

    private var size: TargetSize? { model.sizes[target.id] }
    private var isBusy: Bool { model.busy.contains(target.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 11) {
                Circle()
                    .fill(target.risk.color)
                    .frame(width: 9, height: 9)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                Text(target.name)
                    .font(.headline)
                Spacer()
                sizeLabel
            }

            VStack(alignment: .leading, spacing: 10) {
                Meter(fraction: meterFraction, color: target.risk.color)

                Text(target.about)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 14) {
                    Text(target.risk.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if target.showsInMap {
                        Button("Show in Map") { model.openInExplorer(target.existingPaths.first ?? target.paths[0]) }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                    Spacer()
                    actionButton
                }

                if !target.isAvailable, let tool = target.tool {
                    Label("\(tool) isn't installed or isn't on your PATH.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(Palette.review)
                }
                if size?.limited == true {
                    Label("Some of this couldn't be read. Turn on Full Disk Access for an exact number.", systemImage: "lock")
                        .font(.caption)
                        .foregroundStyle(Palette.review)
                }
                if showModels {
                    OllamaModelsList()
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.leading, 20)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
    }

    private var meterFraction: Double {
        let maxBytes = model.targets.compactMap { model.sizes[$0.id]?.bytes }.max() ?? 0
        guard maxBytes > 0, let b = size?.bytes, b > 0 else { return 0 }
        return max(0.015, Double(b) / Double(maxBytes))
    }

    @ViewBuilder
    private var sizeLabel: some View {
        if let s = size, !(s.measuring && s.bytes == nil) {
            Text(Format.bytes(s.bytes))
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
        } else {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Measuring").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch target.kind {
        case .ollama:
            Button(showModels ? "Hide Models" : "Choose Models") {
                withAnimation(.snappy) { showModels.toggle() }
                if showModels { model.loadOllama() }
            }
            .disabled(!target.isAvailable)
        case .explore:
            Button("Explore") { model.openInExplorer(target.existingPaths.first ?? target.paths[0]) }
        default:
            Button(role: target.risk == .careful ? .destructive : nil) {
                model.requestRun(target)
            } label: {
                if isBusy {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Working…")
                    }
                } else {
                    Text(target.label)
                }
            }
            .disabled(!target.isAvailable || isBusy || (size?.bytes ?? 0) == 0)
        }
    }
}

struct Meter: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.07))
                Capsule().fill(color)
                    .frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 5)
        .animation(.smooth(duration: 0.6), value: fraction)
    }
}

struct OllamaModelsList: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.ollamaError {
                Text(error)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            } else if let models = model.ollamaModels {
                if models.isEmpty {
                    Text("No models installed.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                ForEach(models) { m in
                    if m.id != models.first?.id { Divider() }
                    HStack(spacing: 12) {
                        Text(m.name)
                            .font(.system(.callout, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(m.size)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                        Text(m.modified)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 110, alignment: .trailing)
                        Button("Remove", role: .destructive) { model.requestRemoveModel(m) }
                            .disabled(model.busy.contains("m:" + m.name))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                    .padding(14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }
}
