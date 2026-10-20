import AppKit
import SwiftUI

struct SpaceMapView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            MapHeader()
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 10)
            HStack(alignment: .top, spacing: 20) {
                ZStack { chart }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                MapInspector()
                    .frame(width: 320)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .environmentObject(model.mapHover)
        .navigationTitle("Space Map")
        .task { model.startExploringIfNeeded() }
    }

    @ViewBuilder
    private var chart: some View {
        if model.scanning {
            VStack(spacing: 12) {
                if model.homeWalk != nil && !DiskIndex.shared.canShow(Paths.home) && model.mapTotal > 0 {
                    ProgressView(value: Double(model.mapDone), total: Double(model.mapTotal))
                        .tint(Palette.sky)
                        .frame(width: 260)
                    Text("Measuring your home folder")
                        .font(.headline)
                    Text("\(model.mapDone) of \(model.mapTotal) folders done. After this, every folder opens instantly.")
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.large)
                    Text("Measuring \(Paths.tilde(model.explorePath))")
                        .font(.headline)
                    Text("Big folders can take a moment.")
                        .foregroundStyle(.secondary)
                }
            }
        } else if let error = model.scanError {
            ContentUnavailableView {
                Label("Can't open this folder", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Go to Home") { model.explore(Paths.home) }
            }
        } else if let scan = model.scan {
            if scan.children.allSatisfy({ $0.size == 0 }) {
                ContentUnavailableView("This folder is empty", systemImage: "folder")
            } else {
                Group {
                    switch model.mapStyle {
                    case .rings: SunburstView(scan: scan)
                    case .blocks: TreemapView(scan: scan)
                    }
                }
                .id(scan.path + model.mapStyle.rawValue)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        } else {
            ProgressView()
        }
    }
}

// MARK: - Header

struct MapHeader: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            Button {
                model.goUp()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .disabled(model.explorePath == Paths.home)
            .keyboardShortcut(.upArrow, modifiers: .command)
            .help("Enclosing folder (⌘↑)")

            ForEach(model.crumbs, id: \.path) { crumb in
                if crumb.path != Paths.home {
                    Image(systemName: "chevron.compact.right")
                        .foregroundStyle(.tertiary)
                }
                Button(crumb.label) { model.explore(crumb.path) }
                    .buttonStyle(.plain)
                    .font(crumb.path == model.explorePath ? .headline : .body)
                    .foregroundStyle(crumb.path == model.explorePath ? Color.primary : Color.secondary)
                    .disabled(crumb.path == model.explorePath)
            }

            Spacer(minLength: 16)

            if let scan = model.scan, !model.scanning {
                Text(Format.bytes(scan.size))
                    .font(.display(17, .bold))
                    .monospacedDigit()
                    .padding(.trailing, 6)
            }

            Picker("Style", selection: $model.mapStyle) {
                Label("Rings", systemImage: "circle.circle").tag(MapStyle.rings)
                Label("Blocks", systemImage: "square.grid.2x2").tag(MapStyle.blocks)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 170)
        }
        .lineLimit(1)
    }
}

// MARK: - Inspector

struct MapInspector: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var hover: MapHover

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let node = model.selection ?? hover.node {
                    NodeDetail(node: node, isSelected: model.selection?.path == node.path)
                        .id(node.path)
                } else if let scan = model.scan {
                    FolderSummary(scan: scan)
                } else {
                    Text("Measuring…").foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .glassPanel(cornerRadius: 20)
    }
}

struct AdviceCard: View {
    let info: Explanation

    private var tint: Color {
        switch info.advice {
        case .safe: return Palette.mint
        case .review: return Palette.sand
        case .keep: return Palette.sky
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: info.symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 6) {
                Pill(text: info.advice.label, tint: tint)
                Text(info.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.1)))
    }
}

struct NodeDetail: View {
    @EnvironmentObject var model: AppModel
    let node: DiskNode
    let isSelected: Bool

    var body: some View {
        let info = Knowledge.explain(node.path)
        let covering = model.targets.first { t in
            t.showsInMap && t.paths.contains { node.path == $0 || node.path.hasPrefix($0 + "/") }
        }
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: Icons.icon(node.path))
                    .resizable()
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(info?.title ?? node.name)
                        .font(.display(18, .bold))
                        .lineLimit(2)
                    Text(Paths.tilde(node.path))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Format.bytes(node.size))
                    .font(.display(30, .heavy))
                    .monospacedDigit()
                if let scan = model.scan, scan.size > 0 {
                    Text("\(Int((Double(node.size) / Double(scan.size) * 100).rounded()))% of this folder")
                        .foregroundStyle(.secondary)
                }
            }

            if let info {
                AdviceCard(info: info)
            }

            if let covering {
                Button {
                    model.section = .clean
                } label: {
                    Label("Smart Clean handles this: \(covering.name)", systemImage: "sparkles")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .tint(Palette.mint)
            }

            if node.isDir && !node.children.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Biggest inside").font(.headline)
                    let top = Array(node.children.prefix(6))
                    let biggest = max(1, top.first?.size ?? 1)
                    ForEach(top) { child in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(child.name).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(Format.bytes(child.size))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .font(.callout)
                            Meter(fraction: Double(child.size) / Double(biggest), color: Palette.sky, height: 4)
                        }
                    }
                }
            }

            if isSelected {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if node.isDir {
                            Button("Open") { model.explore(node.path) }
                        }
                        Button("Show in Finder") { model.reveal(node.path) }
                    }
                    if Safety.canTrash(node.path) {
                        Button("Move to Trash…", role: .destructive) {
                            model.requestTrash([TrashItem(path: node.path, name: node.name, size: node.size)])
                        }
                        .keyboardShortcut(.delete, modifiers: .command)
                    } else {
                        Label("Reclaim protects this, so it can't be trashed from here.", systemImage: "lock.shield")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(node.isDir ? "Click to select. Double-click to open." : "Click to select.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct FolderSummary: View {
    @EnvironmentObject var model: AppModel
    let scan: FolderScan

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(scan.path == Paths.home ? "Home" : Paths.name(scan.path))
                    .font(.display(20, .bold))
                Text("\(Format.bytes(scan.size)) across \(scan.children.count) items")
                    .foregroundStyle(.secondary)
            }

            if let info = Knowledge.explain(scan.path) {
                AdviceCard(info: info)
            }

            VStack(alignment: .leading, spacing: 9) {
                Text("Biggest here").font(.headline)
                let reclaimPaths = model.reclaimPaths
                ForEach(Array(scan.children.prefix(9).enumerated()), id: \.element.id) { index, child in
                    let reclaimable = reclaimPaths.contains { child.path == $0 || child.path.hasPrefix($0 + "/") }
                    Button {
                        model.select(child)
                    } label: {
                        HStack(spacing: 9) {
                            Circle()
                                .fill(reclaimable ? Palette.mint : Palette.ring[index % Palette.ring.count])
                                .frame(width: 9, height: 9)
                            Text(Knowledge.explain(child.path)?.title ?? child.name)
                                .lineLimit(1)
                            Spacer()
                            Text(Format.bytes(child.size))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Hover a ring to see what it is. Click to select, double-click a folder to open it, and click the middle to go back up. Mint means Smart Clean can clear it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if scan.limited {
                Label("Some folders couldn't be read. Turn on Full Disk Access for the full picture.", systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(Palette.sand)
            }
        }
    }
}
