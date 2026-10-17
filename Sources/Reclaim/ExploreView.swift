import AppKit
import SwiftUI

struct ExploreView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Breadcrumbs()
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            Divider()
            ZStack {
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(14)
            Divider()
            InspectorBar()
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
        }
        .navigationTitle("Explore")
        .task { model.startExploringIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        if model.scanning {
            VStack(spacing: 10) {
                ProgressView()
                Text("Measuring \(Paths.tilde(model.explorePath))")
                    .font(.headline)
                Text("Big folders like Library can take a minute.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
                TreemapView(scan: scan)
                    .id(scan.path)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
        }
    }
}

// MARK: - Breadcrumbs

struct Breadcrumbs: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            Button {
                model.goUp()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .disabled(model.explorePath == Paths.home)
            .help("Enclosing folder")
            .keyboardShortcut(.upArrow, modifiers: .command)

            let crumbs = model.crumbs
            ForEach(crumbs, id: \.path) { crumb in
                if crumb.path != Paths.home {
                    Image(systemName: "chevron.compact.right")
                        .foregroundStyle(.tertiary)
                }
                let isCurrent = crumb.path == model.explorePath
                Button(crumb.label) { model.explore(crumb.path) }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .foregroundStyle(isCurrent ? .primary : .secondary)
                    .disabled(isCurrent)
            }
            Spacer()
            if let scan = model.scan, !model.scanning {
                Text(Format.bytes(scan.size))
                    .font(.system(.headline, design: .rounded))
                    .monospacedDigit()
            }
        }
        .lineLimit(1)
    }
}

// MARK: - Treemap

struct TreemapRect: Identifiable {
    let node: DiskNode
    let rect: CGRect
    let rank: Int
    var id: String { node.id }
}

enum Treemap {
    /// Keeps the 70 biggest children and groups the rest, then lays them out.
    static func layout(scan: FolderScan, size: CGSize) -> [TreemapRect] {
        let kids = scan.children.filter { $0.size > 0 }
        let total = kids.reduce(Int64(0)) { $0 + $1.size }
        guard total > 0 else { return [] }
        let minSize = Int64(Double(total) * 0.004)
        var nodes: [DiskNode] = []
        for kid in kids where kid.size >= minSize && nodes.count < 70 {
            nodes.append(kid)
        }
        let rest = kids.dropFirst(nodes.count)
        if !rest.isEmpty {
            nodes.append(DiskNode(name: "\(rest.count) smaller items",
                                  path: scan.path + "/\u{0}smaller",
                                  size: rest.reduce(Int64(0)) { $0 + $1.size },
                                  isDir: false, isProtected: true, isGroup: true))
        }
        return squarify(nodes, in: size)
    }

    /// Squarified treemap (Bruls, Huizing and van Wijk).
    static func squarify(_ nodes: [DiskNode], in size: CGSize) -> [TreemapRect] {
        let total = nodes.reduce(Int64(0)) { $0 + $1.size }
        guard total > 0, size.width > 1, size.height > 1 else { return [] }
        let scale = Double(size.width * size.height) / Double(total)
        let items: [(node: DiskNode, area: Double)] = nodes.map { ($0, Double($0.size) * scale) }

        var out: [TreemapRect] = []
        var x = 0.0, y = 0.0
        var w = Double(size.width), h = Double(size.height)
        var row: [(node: DiskNode, area: Double)] = []

        func worst(_ r: [(node: DiskNode, area: Double)], _ side: Double) -> Double {
            var sum = 0.0, maxA = 0.0, minA = Double.infinity
            for item in r {
                sum += item.area
                maxA = max(maxA, item.area)
                minA = min(minA, item.area)
            }
            return max(side * side * maxA / (sum * sum), (sum * sum) / (side * side * minA))
        }

        func place(_ r: [(node: DiskNode, area: Double)]) {
            let sum = r.reduce(0.0) { $0 + $1.area }
            if w >= h {
                let colW = sum / h
                var cy = y
                for item in r {
                    let itemH = item.area / colW
                    out.append(TreemapRect(node: item.node, rect: CGRect(x: x, y: cy, width: colW, height: itemH), rank: out.count))
                    cy += itemH
                }
                x += colW
                w -= colW
            } else {
                let rowH = sum / w
                var cx = x
                for item in r {
                    let itemW = item.area / rowH
                    out.append(TreemapRect(node: item.node, rect: CGRect(x: cx, y: y, width: itemW, height: rowH), rank: out.count))
                    cx += itemW
                }
                y += rowH
                h -= rowH
            }
        }

        var i = 0
        while i < items.count {
            let side = min(w, h)
            if side <= 0.5 { break }
            let item = items[i]
            if row.isEmpty || worst(row + [item], side) <= worst(row, side) {
                row.append(item)
                i += 1
            } else {
                place(row)
                row.removeAll()
            }
        }
        if !row.isEmpty { place(row) }
        return out
    }
}

struct TreemapView: View {
    @EnvironmentObject private var model: AppModel
    let scan: FolderScan

    var body: some View {
        GeometryReader { geo in
            let rects = Treemap.layout(scan: scan, size: geo.size)
            let reclaimPaths = model.reclaimPaths
            ZStack(alignment: .topLeading) {
                ForEach(rects) { r in
                    TileView(item: r,
                             total: scan.size,
                             isReclaim: reclaimPaths.contains { r.node.path == $0 || r.node.path.hasPrefix($0 + "/") },
                             isSelected: model.selection?.path == r.node.path)
                        .frame(width: max(0, r.rect.width - 3), height: max(0, r.rect.height - 3))
                        .offset(x: r.rect.minX + 1.5, y: r.rect.minY + 1.5)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }
}

struct TileView: View {
    @EnvironmentObject private var model: AppModel
    let item: TreemapRect
    let total: Int64
    let isReclaim: Bool
    let isSelected: Bool
    @State private var hovering = false

    private var node: DiskNode { item.node }
    private var isBig: Bool { item.rect.width > 200 && item.rect.height > 90 }
    private var showsLabel: Bool { item.rect.width > 62 && item.rect.height > 34 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            fill
            if showsLabel {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        if isBig && !node.isGroup {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: node.path))
                                .resizable()
                                .frame(width: 18, height: 18)
                        }
                        Text(node.name)
                            .font(.system(size: isBig ? 14 : 12, weight: .semibold))
                            .lineLimit(1)
                    }
                    Text(Format.bytes(node.size))
                        .font(.system(size: isBig ? 13 : 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .opacity(0.8)
                }
                .foregroundStyle(node.isGroup ? Color.secondary : Color.primary)
                .padding(isBig ? 10 : 7)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary, lineWidth: 2)
            }
        }
        .brightness(hovering && !node.isGroup ? 0.06 : 0)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering = $0 }
        .help(helpText)
        .onTapGesture(count: 2) {
            if node.isDir && !node.isGroup { model.explore(node.path) }
        }
        .onTapGesture {
            if !node.isGroup { model.select(node) }
        }
        .contextMenu {
            if !node.isGroup {
                if node.isDir {
                    Button("Open Folder") { model.explore(node.path) }
                }
                Button("Show in Finder") { model.reveal(node.path) }
                if !node.isProtected {
                    Divider()
                    Button("Move to Trash") {
                        model.requestTrash([TrashItem(path: node.path, name: node.name, size: node.size)])
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var fill: some View {
        if node.isGroup {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(.tertiary)
        } else if isReclaim {
            Stripes(color: Palette.safe, baseOpacity: 0.55)
        } else {
            (node.isDir ? Palette.tile : Palette.tileFile)
                .opacity(max(0.32, 0.95 - Double(item.rank) * 0.04))
        }
    }

    private var helpText: String {
        let pct = total > 0 ? Double(node.size) / Double(total) * 100 : 0
        var text = "\(node.name)\n\(Format.bytes(node.size)), \(String(format: "%.1f", pct))% of this folder"
        if node.isDir && !node.isGroup { text += "\nDouble-click to open" }
        if isReclaim { text += "\nCovered by a cleanup in Clean Up" }
        return text
    }
}

// MARK: - Inspector

struct InspectorBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            if let node = model.selection {
                Image(nsImage: NSWorkspace.shared.icon(forFile: node.path))
                    .resizable()
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(Format.bytes(node.size)), \(percent(node))% of this folder")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(Paths.tilde(node.path))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer()
                if node.isDir {
                    Button("Open Folder") { model.explore(node.path) }
                }
                Button("Show in Finder") { model.reveal(node.path) }
                if !node.isProtected {
                    Button("Move to Trash", role: .destructive) {
                        model.requestTrash([TrashItem(path: node.path, name: node.name, size: node.size)])
                    }
                    .keyboardShortcut(.delete, modifiers: .command)
                }
            } else if let scan = model.scan, !model.scanning {
                Text("\(Paths.tilde(scan.path)) uses \(Format.bytes(scan.size)). Click a block to select it; double-click a folder to open it."
                     + (scan.limited ? " Some items couldn't be read." : ""))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                Spacer()
            }
        }
        .frame(minHeight: 44)
    }

    private func percent(_ node: DiskNode) -> Int {
        guard let total = model.scan?.size, total > 0 else { return 0 }
        return Int((Double(node.size) / Double(total) * 100).rounded())
    }
}
