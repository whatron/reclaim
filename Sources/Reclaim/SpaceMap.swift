import AppKit
import SwiftUI

// MARK: - Sunburst geometry

/// One arc of the space map. Angles run clockwise from 12 o'clock, in radians.
struct RingSegment: Identifiable {
    var id: String { node.path }
    let node: DiskNode
    let level: Int
    let start: Double
    let end: Double
    let colorIndex: Int
}

enum Sunburst {
    static let holeFraction: CGFloat = 0.38
    static let innerOuterFraction: CGFloat = 0.69

    static func segments(for scan: FolderScan) -> [RingSegment] {
        let childTotal = scan.children.reduce(Int64(0)) { $0 + $1.size }
        let total = Double(max(scan.size, childTotal))
        guard total > 0 else { return [] }
        let fullTurn = 2 * Double.pi
        let minSweep = fullTurn * 0.006

        var out: [RingSegment] = []
        var angle = 0.0
        var color = 0
        var smallBytes: Int64 = 0
        var smallCount = 0

        for child in scan.children where child.size > 0 {
            let sweep = fullTurn * Double(child.size) / total
            if sweep < minSweep {
                smallBytes += child.size
                smallCount += 1
                continue
            }
            out.append(RingSegment(node: child, level: 1, start: angle, end: angle + sweep, colorIndex: color))
            var inner = angle
            for grand in child.children where grand.size > 0 {
                let gs = fullTurn * Double(grand.size) / total
                if gs >= minSweep * 0.6 {
                    out.append(RingSegment(node: grand, level: 2, start: inner, end: inner + gs, colorIndex: color))
                }
                inner += gs
            }
            angle += sweep
            color += 1
        }
        if smallBytes > 0 {
            let group = DiskNode(name: "\(smallCount) smaller items", path: scan.path + "/\u{0}smaller",
                                 size: smallBytes, isDir: false, isProtected: true, isGroup: true)
            out.append(RingSegment(node: group, level: 1, start: angle,
                                   end: angle + fullTurn * Double(smallBytes) / total, colorIndex: -1))
        }
        return out
    }

    /// Radii for a ring level, as fractions of the outer radius.
    static func band(_ level: Int) -> (inner: CGFloat, outer: CGFloat) {
        level == 1 ? (holeFraction + 0.015, innerOuterFraction) : (innerOuterFraction + 0.015, 1)
    }

    /// Finds the segment under a point, or nil for the hole and the empty space around the rings.
    static func hit(_ point: CGPoint, in size: CGSize, segments: [RingSegment]) -> RingSegment? {
        let radius = min(size.width, size.height) / 2
        let dx = point.x - size.width / 2
        let dy = point.y - size.height / 2
        let r = sqrt(dx * dx + dy * dy) / radius
        guard r > holeFraction, r <= 1 else { return nil }
        var theta = atan2(Double(dx), Double(-dy))
        if theta < 0 { theta += 2 * .pi }
        let level = r <= innerOuterFraction + 0.0075 ? 1 : 2
        return segments.first { $0.level == level && theta >= $0.start && theta < $0.end }
    }

    static func isInHole(_ point: CGPoint, in size: CGSize) -> Bool {
        let radius = min(size.width, size.height) / 2
        let dx = point.x - size.width / 2
        let dy = point.y - size.height / 2
        return sqrt(dx * dx + dy * dy) / radius <= holeFraction
    }

    static func sector(center: CGPoint, inner: CGFloat, outer: CGFloat, start: Double, end: Double) -> Path {
        // Our angles start at 12 o'clock; SwiftUI's start at 3 o'clock.
        let a0 = Angle.radians(start - .pi / 2)
        let a1 = Angle.radians(end - .pi / 2)
        var path = Path()
        path.addArc(center: center, radius: outer, startAngle: a0, endAngle: a1, clockwise: false)
        path.addArc(center: center, radius: inner, startAngle: a1, endAngle: a0, clockwise: true)
        path.closeSubpath()
        return path
    }
}

/// Draws the rings. Animatable so the rings sweep in when a folder opens.
struct SunburstCanvas: View, Animatable {
    var progress: Double
    let segments: [RingSegment]
    let hovered: String?
    let selected: String?
    let reclaimPaths: [String]

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let gap = 0.0045

            for seg in segments {
                let start = seg.start * progress
                let end = seg.end * progress
                guard end - start > gap * 1.5 else { continue }
                let band = Sunburst.band(seg.level)
                let path = Sunburst.sector(center: center, inner: radius * band.inner, outer: radius * band.outer,
                                           start: start + gap / 2, end: end - gap / 2)
                let isHovered = hovered == seg.id
                let isSelected = selected == seg.id
                context.fill(path, with: .color(color(for: seg, highlighted: isHovered || isSelected)))
                if isSelected {
                    context.stroke(path, with: .color(.primary), lineWidth: 2)
                }
            }
        }
    }

    private func color(for seg: RingSegment, highlighted: Bool) -> Color {
        if seg.node.isGroup {
            return Color.secondary.opacity(highlighted ? 0.35 : 0.2)
        }
        let reclaimable = reclaimPaths.contains { seg.node.path == $0 || seg.node.path.hasPrefix($0 + "/") }
        let base = reclaimable ? Palette.mint : Palette.ring[seg.colorIndex % Palette.ring.count]
        let strength: Double = seg.level == 1 ? 0.92 : 0.55
        return base.opacity(highlighted ? 1 : strength)
    }
}

struct SunburstView: View {
    @EnvironmentObject var model: AppModel
    let scan: FolderScan
    @State var progress: Double = 0

    var body: some View {
        let segments = Sunburst.segments(for: scan)
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                SunburstCanvas(progress: progress, segments: segments, hovered: model.hovered?.path,
                               selected: model.selection?.path, reclaimPaths: model.reclaimPaths)
                    .frame(width: side, height: side)
                    .contentShape(Circle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let hit = Sunburst.hit(location, in: CGSize(width: side, height: side), segments: segments)
                            if hit?.node.path != model.hovered?.path {
                                model.hovered = hit?.node
                            }
                        case .ended:
                            model.hovered = nil
                        }
                    }
                    .onTapGesture(count: 2) { location in
                        let area = CGSize(width: side, height: side)
                        if let seg = Sunburst.hit(location, in: area, segments: segments),
                           seg.node.isDir, !seg.node.isGroup {
                            model.explore(seg.node.path)
                        }
                    }
                    .onTapGesture { location in
                        let area = CGSize(width: side, height: side)
                        if let seg = Sunburst.hit(location, in: area, segments: segments) {
                            if !seg.node.isGroup { model.select(seg.node) }
                        } else if Sunburst.isInHole(location, in: area) {
                            model.goUp()
                        } else {
                            model.select(nil)
                        }
                    }

                CenterLabel(scan: scan)
                    .frame(width: side * Sunburst.holeFraction * 1.6)
                    .allowsHitTesting(false)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear {
            progress = 0
            withAnimation(.spring(duration: 0.9, bounce: 0.12)) { progress = 1 }
        }
    }
}

struct CenterLabel: View {
    @EnvironmentObject var model: AppModel
    let scan: FolderScan

    var body: some View {
        let node = model.hovered ?? model.selection
        VStack(spacing: 3) {
            if let node {
                Text(Knowledge.explain(node.path)?.title ?? node.name)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(Format.bytes(node.size))
                    .font(.display(24, .heavy))
                    .monospacedDigit()
                Text("\(percent(node.size))% of \(scan.path == Paths.home ? "Home" : Paths.name(scan.path))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(scan.path == Paths.home ? "Home" : Paths.name(scan.path))
                    .font(.headline)
                    .lineLimit(1)
                Text(Format.bytes(scan.size))
                    .font(.display(26, .heavy))
                    .monospacedDigit()
                if scan.path != Paths.home {
                    Label("Click to go up", systemImage: "arrow.up.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .animation(.snappy(duration: 0.15), value: node?.path)
    }

    private func percent(_ bytes: Int64) -> Int {
        scan.size > 0 ? Int((Double(bytes) / Double(scan.size) * 100).rounded()) : 0
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
    /// Keeps the 60 biggest children and groups the rest, then lays them out.
    static func layout(scan: FolderScan, size: CGSize) -> [TreemapRect] {
        let kids = scan.children.filter { $0.size > 0 }
        let total = kids.reduce(Int64(0)) { $0 + $1.size }
        guard total > 0 else { return [] }
        let minSize = Int64(Double(total) * 0.004)
        var nodes: [DiskNode] = []
        for kid in kids where kid.size >= minSize && nodes.count < 60 {
            nodes.append(kid)
        }
        let rest = kids.dropFirst(nodes.count)
        if !rest.isEmpty {
            nodes.append(DiskNode(name: "\(rest.count) smaller items", path: scan.path + "/\u{0}smaller",
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
                    out.append(TreemapRect(node: item.node, rect: CGRect(x: x, y: cy, width: colW, height: itemH),
                                           rank: out.count))
                    cy += itemH
                }
                x += colW
                w -= colW
            } else {
                let rowH = sum / w
                var cx = x
                for item in r {
                    let itemW = item.area / rowH
                    out.append(TreemapRect(node: item.node, rect: CGRect(x: cx, y: y, width: itemW, height: rowH),
                                           rank: out.count))
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
    @EnvironmentObject var model: AppModel
    let scan: FolderScan

    var body: some View {
        GeometryReader { geo in
            let rects = Treemap.layout(scan: scan, size: geo.size)
            let reclaimPaths = model.reclaimPaths
            ZStack(alignment: .topLeading) {
                ForEach(rects) { r in
                    TreemapTile(item: r,
                                isReclaim: reclaimPaths.contains { r.node.path == $0 || r.node.path.hasPrefix($0 + "/") },
                                isSelected: model.selection?.path == r.node.path)
                        .frame(width: max(0, r.rect.width - 4), height: max(0, r.rect.height - 4))
                        .offset(x: r.rect.minX + 2, y: r.rect.minY + 2)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }
}

struct TreemapTile: View {
    @EnvironmentObject var model: AppModel
    let item: TreemapRect
    let isReclaim: Bool
    let isSelected: Bool
    @State var hovering = false

    private var node: DiskNode { item.node }
    private var isBig: Bool { item.rect.width > 190 && item.rect.height > 90 }
    private var showsLabel: Bool { item.rect.width > 64 && item.rect.height > 36 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            fill
            if showsLabel {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
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
                .foregroundStyle(node.isGroup ? Color.secondary : Color.white)
                .padding(isBig ? 10 : 7)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary, lineWidth: 2)
            }
        }
        .brightness(hovering && !node.isGroup ? 0.07 : 0)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { inside in
            hovering = inside
            if !node.isGroup { model.hovered = inside ? node : nil }
        }
        .onTapGesture(count: 2) {
            if node.isDir && !node.isGroup { model.explore(node.path) }
        }
        .onTapGesture {
            if !node.isGroup { model.select(node) }
        }
    }

    @ViewBuilder
    private var fill: some View {
        if node.isGroup {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(.tertiary)
        } else if isReclaim {
            Stripes(color: Palette.mint, baseOpacity: 0.6)
        } else {
            let color = Palette.ring[item.rank % Palette.ring.count]
            LinearGradient(colors: [color.opacity(0.95), color.opacity(0.72)], startPoint: .topLeading,
                           endPoint: .bottomTrailing)
        }
    }
}
