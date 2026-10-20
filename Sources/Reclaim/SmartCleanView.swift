import AppKit
import SwiftUI

struct SmartCleanView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                PageHeader(title: "Smart Clean", subtitle: subtitle)

                CleanHero()

                let safe = model.sortedTargets.filter { $0.risk == .safe }
                if !safe.isEmpty {
                    CleanGroup(title: "Rebuilds itself",
                               caption: "Caches and build files that tools recreate on their own. Ticked for you.",
                               targets: safe)
                }

                let review = model.sortedTargets.filter { $0.risk == .review }
                if !review.isEmpty {
                    CleanGroup(title: "Worth a look",
                               caption: "Big, but some of it may still matter to you. Nothing here is ticked unless you tick it.",
                               targets: review)
                }

                TrashCard()
            }
            .padding(.horizontal, 36)
            .padding(.top, 28)
            .padding(.bottom, 130)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .bottom) { CleanDock() }
        .navigationTitle("Smart Clean")
        .task {
            if model.ollamaModels == nil && model.targets.contains(where: { $0.id == "ollama" }) {
                model.loadOllama()
            }
        }
    }

    private var subtitle: String {
        if model.isMeasuring && model.recommendedBytes == 0 {
            return "Measuring caches, models and build folders…"
        }
        let count = model.recommendedTargets.count
        if count == 0 {
            return "Nothing big rebuilds itself right now. Check the items below that are worth a look."
        }
        return "\(count) item\(count == 1 ? "" : "s") that rebuild themselves add up to \(Format.short(model.recommendedBytes)). Untick anything you'd rather keep."
    }
}

// MARK: - Live total

/// The amount ticked, drawn as a bar of everything Smart Clean found. Ticking an item fills its segment.
struct CleanHero: View {
    @EnvironmentObject var model: AppModel

    private var items: [TargetDef] {
        model.sortedTargets.filter {
            $0.isBatchable && $0.isAvailable && $0.id != "trash" && (model.sizes[$0.id]?.bytes ?? 0) > 0
                // Homebrew's cache sits inside App caches; don't draw it twice.
                && !(!$0.inTotal && model.targets.contains { t in t.id == "caches" })
        }
    }

    var body: some View {
        let list = items
        let trash = model.emptyTrashAfterBatch ? model.trashBytes : 0
        let total = list.compactMap { model.sizes[$0.id]?.bytes }.reduce(0, +) + trash
        let ticked = model.checkedBytes

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Format.short(ticked))
                    .font(.display(56, .heavy))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(ticked > 0 ? AnyShapeStyle(LinearGradient(colors: [Palette.mint, Palette.sky],
                                                                              startPoint: .leading, endPoint: .trailing))
                                     : AnyShapeStyle(Color.secondary))
                VStack(alignment: .leading, spacing: 1) {
                    Text(ticked > 0 ? "ready to reclaim" : "nothing ticked yet")
                        .font(.title3.weight(.semibold))
                    Text("of \(Format.short(total)) Smart Clean found")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .animation(.snappy, value: ticked)

            GeometryReader { geo in
                let gaps = CGFloat(max(0, list.count - 1 + (trash > 0 ? 1 : 0))) * 3
                let usable = max(0, geo.size.width - gaps)
                HStack(spacing: 3) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, t in
                        let bytes = model.sizes[t.id]?.bytes ?? 0
                        let on = model.checked.contains(t.id)
                        let color = Palette.ring[index % Palette.ring.count]
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(on ? AnyShapeStyle(color.gradient) : AnyShapeStyle(color.opacity(0.16)))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(color.opacity(on ? 0 : 0.45), lineWidth: 1))
                            .frame(width: max(4, usable * CGFloat(Double(bytes) / Double(max(total, 1)))))
                            .help("\(t.name): \(Format.bytes(bytes))")
                            .onTapGesture { toggle(t) }
                    }
                    if trash > 0 {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Palette.coral.gradient)
                            .frame(width: max(4, usable * CGFloat(Double(trash) / Double(max(total, 1)))))
                            .help("Trash: \(Format.bytes(trash))")
                    }
                }
            }
            .frame(height: 30)
            .animation(.snappy(duration: 0.3), value: model.checked)

            let tickedItems = list.enumerated().filter { model.checked.contains($0.element.id) }
            if !tickedItems.isEmpty {
                FlowLegend(entries: tickedItems.map { (index, t) in
                    (t.name, model.sizes[t.id]?.bytes ?? 0, Palette.ring[index % Palette.ring.count])
                })
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LinearGradient(colors: [Palette.mint.opacity(0.10), Palette.sky.opacity(0.05)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.mint.opacity(0.22)))
    }

    private func toggle(_ t: TargetDef) {
        if model.checked.contains(t.id) { model.checked.remove(t.id) } else { model.checked.insert(t.id) }
    }
}

/// Small coloured name-and-size labels that wrap onto new lines.
struct FlowLegend: View {
    let entries: [(String, Int64, Color)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10, alignment: .leading)],
                  alignment: .leading, spacing: 6) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                HStack(spacing: 6) {
                    Circle().fill(entry.2).frame(width: 8, height: 8)
                    Text(entry.0).lineLimit(1)
                    Text(Format.short(entry.1))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .font(.callout)
            }
        }
    }
}

// MARK: - Groups and rows

struct CleanGroup: View {
    let title: String
    let caption: String
    let targets: [TargetDef]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.display(21, .bold))
                Text(caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 2) {
                ForEach(targets) { target in
                    CleanRow(target: target)
                }
            }
            .padding(6)
            .card(padding: 0)
        }
    }
}

struct CleanRow: View {
    @EnvironmentObject var model: AppModel
    let target: TargetDef
    @State var expanded = false
    @State var hovering = false

    private var size: TargetSize? { model.sizes[target.id] }
    private var bytes: Int64 { size?.bytes ?? 0 }
    private var checkable: Bool { target.isBatchable && target.isAvailable && bytes > 0 }
    private var isOn: Bool { checkable && model.checked.contains(target.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                if target.isBatchable {
                    RoundCheck(isOn: isOn, tint: target.risk.color)
                        .opacity(checkable ? 1 : 0.3)
                } else {
                    Color.clear.frame(width: 20, height: 20)
                }

                SymbolTile(symbol: target.symbol, tint: target.risk.color, size: 40)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(target.name).font(.headline)
                        if let growth = model.growth(of: target.id) {
                            Pill(text: "\(Format.signed(growth)) this week",
                                 tint: growth > 0 ? Palette.coral : Palette.mint,
                                 symbol: growth > 0 ? "arrow.up.right" : "arrow.down.right")
                        }
                        if !target.isAvailable, let tool = target.tool {
                            Pill(text: "\(tool) not installed", tint: .secondary)
                        }
                        if size?.limited == true {
                            Pill(text: "Partly hidden", tint: Palette.sand, symbol: "lock")
                                .help("Turn on Full Disk Access for an exact number.")
                        }
                    }
                    Text(target.about)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if bytes > 0 {
                        Meter(fraction: share, color: target.risk.color, height: 4)
                            .frame(maxWidth: 280)
                            .padding(.top, 3)
                    }
                }

                Spacer(minLength: 12)

                sizeLabel
                    .frame(minWidth: 86, alignment: .trailing)

                trailing
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
            .onTapGesture { tap() }

            if expanded && target.kind.isOllama {
                OllamaPanel()
                    .padding(.leading, 88)
                    .padding(.trailing, 14)
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.primary.opacity(hovering || isOn ? (isOn ? 0.055 : 0.035) : 0)))
        .onHover { hovering = $0 }
        .contextMenu { menuItems }
        .animation(.snappy(duration: 0.22), value: expanded)
    }

    private var share: Double {
        let biggest = model.targets.filter { $0.id != "trash" }.compactMap { model.sizes[$0.id]?.bytes }.max() ?? 0
        return biggest > 0 ? max(0.02, Double(bytes) / Double(biggest)) : 0
    }

    private func tap() {
        if target.kind.isOllama {
            expanded.toggle()
        } else if target.kind.isExplore {
            model.openInMap(target.existingPaths.first ?? target.paths[0])
        } else if checkable {
            if model.checked.contains(target.id) {
                model.checked.remove(target.id)
            } else {
                model.checked.insert(target.id)
            }
        }
    }

    @ViewBuilder
    private var sizeLabel: some View {
        if let s = size, !(s.measuring && s.bytes == nil) {
            Text(Format.bytes(s.bytes))
                .font(.display(17, .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(bytes > 0 ? Color.primary : Color.secondary)
        } else {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Measuring").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if model.busy.contains(target.id) {
            ProgressView().controlSize(.small).frame(width: 28)
        } else if target.kind.isOllama {
            Button(expanded ? "Done" : "Choose") { expanded.toggle() }
                .disabled(!target.isAvailable)
        } else if target.kind.isExplore {
            Button("Open") { model.openInMap(target.existingPaths.first ?? target.paths[0]) }
        } else {
            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(hovering ? 1 : 0.45)
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        if target.isBatchable {
            Button("\(target.label) Now…") { model.requestRun(target) }
                .disabled(!checkable || model.batch != nil)
        }
        if target.showsInMap, let path = target.existingPaths.first {
            Button("Show in Space Map") { model.openInMap(path) }
            Button("Show in Finder") { model.reveal(path) }
        }
        if let command = target.commandText {
            Divider()
            Text("Runs: \(command)")
        }
    }
}

// MARK: - Ollama models

struct OllamaPanel: View {
    @EnvironmentObject var model: AppModel
    @State var picked: Set<String> = []
    @State var didPreselect = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = model.ollamaError {
                Text(error)
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else if let models = model.ollamaModels {
                if models.isEmpty {
                    Text("No models installed.")
                        .foregroundStyle(.secondary)
                        .padding(12)
                }
                ForEach(models) { m in
                    HStack(spacing: 12) {
                        RoundCheck(isOn: picked.contains(m.name), tint: Palette.coral)
                        Text(m.name)
                            .font(.system(.callout, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if (m.ageDays ?? 0) >= 60 {
                            Pill(text: "Unused \(m.modified)", tint: Palette.sand, symbol: "moon.zzz")
                        }
                        Spacer()
                        Text(m.size)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if picked.contains(m.name) { picked.remove(m.name) } else { picked.insert(m.name) }
                    }
                    Divider().opacity(0.5)
                }
                HStack {
                    Button("Select Unused") { picked = Set(model.unusedModels.map(\.name)) }
                        .disabled(model.unusedModels.isEmpty)
                    Spacer()
                    Button(picked.count > 1 ? "Remove \(picked.count) Models…" : "Remove Model…", role: .destructive) {
                        model.requestRemoveModels(models.filter { picked.contains($0.name) })
                    }
                    .disabled(picked.isEmpty)
                }
                .padding(12)
                .onAppear {
                    if !didPreselect {
                        didPreselect = true
                        picked = Set(model.unusedModels.map(\.name))
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Asking Ollama for your models…").foregroundStyle(.secondary)
                }
                .padding(12)
            }
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
        .onAppear {
            if model.ollamaModels == nil { model.loadOllama() }
        }
    }
}

// MARK: - Trash

struct TrashCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let bytes = model.trashBytes
        HStack(spacing: 16) {
            SymbolTile(symbol: bytes > 0 ? "trash.fill" : "trash", tint: Palette.coral, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(bytes > 0 ? "\(Format.bytes(bytes)) in the Trash" : "The Trash is empty")
                    .font(.headline)
                Text("Everything Reclaim removes goes to the Trash first, so you can put it back. The space only returns once the Trash is emptied.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Empty the Trash after cleaning", isOn: $model.emptyTrashAfterBatch)
                    .toggleStyle(.checkbox)
                    .padding(.top, 4)
            }
            Spacer(minLength: 12)
            Button("Empty Trash…", role: .destructive) {
                if let t = model.targets.first(where: { $0.id == "trash" }) { model.requestRun(t) }
            }
            .disabled(bytes == 0 || model.busy.contains("trash"))
        }
        .card()
    }
}

// MARK: - Dock

struct CleanDock: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let count = model.checkedTargets.count
        let bytes = model.checkedBytes
        let emptying = model.emptyTrashAfterBatch
        ActionDock {
            SymbolTile(symbol: "sparkles", tint: emptying ? Palette.coral : Palette.mint, size: 32)
                .opacity(count > 0 ? 1 : 0.45)

            VStack(alignment: .leading, spacing: 2) {
                Text(count == 0 ? "Nothing ticked" : "\(count) item\(count == 1 ? "" : "s") ticked")
                    .font(.headline)
                Text(emptying ? "Moved to the Trash, then the Trash is emptied."
                     : "Everything goes to the Trash, so you can put it back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 20)

            Button("Tick Recommended") {
                withAnimation(.snappy) { model.checked = Set(model.recommendedTargets.map(\.id)) }
            }
            .disabled(model.recommendedTargets.isEmpty)

            Button {
                model.requestBatchClean()
            } label: {
                Label(bytes > 0 ? "Clean \(Format.short(bytes))" : "Clean", systemImage: "sparkles")
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.borderedProminent)
            .tint(emptying ? Palette.coral : Palette.mint)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled((count == 0 && !(emptying && model.trashBytes > 0)) || model.batch != nil)
        }
    }
}
