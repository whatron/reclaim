import AppKit
import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                OverviewHero()
                InsightsSection()
                SpaceBreakdown()
                LifetimeStrip()
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 30)
            .frame(maxWidth: 1080, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Overview")
    }
}

// MARK: - Hero

struct OverviewHero: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let d = model.disk {
            let reclaim = model.reclaimableBytes
            let trash = model.trashBytes
            let other = max(0, d.used - reclaim - trash)
            let big = Format.bigFree(d.free)
            let low = model.fullness > 0.9

            HStack(alignment: .center, spacing: 40) {
                TideGauge(total: d.total, other: other, reclaim: reclaim, trash: trash)
                    .frame(width: 210, height: 300)
                    .shadow(color: Palette.sky.opacity(0.25), radius: 30, y: 12)

                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(big.number)
                            .font(.display(118, .heavy))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(low ? AnyShapeStyle(Palette.coral)
                                : AnyShapeStyle(LinearGradient(colors: [.primary, .primary.opacity(0.72)],
                                                               startPoint: .top, endPoint: .bottom)))
                        Text(big.unit)
                            .font(.display(30, .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .animation(.snappy, value: big.number)

                    Text(model.summary)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 520, alignment: .leading)
                        .animation(.smooth, value: model.summary)

                    GaugeLegend(other: other, reclaim: reclaim, trash: trash, free: d.free)

                    HStack(spacing: 12) {
                        Button {
                            model.perform(.quickClean)
                        } label: {
                            Label(model.recommendedBytes > 0 ? "Clean \(Format.short(model.recommendedBytes)) Safely"
                                      : "Nothing Safe to Clean Yet",
                                  systemImage: "sparkles")
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.mint)
                        .controlSize(.large)
                        .disabled(model.recommendedBytes == 0 || model.batch != nil)

                        Button("Review Everything") { model.section = .clean }
                            .controlSize(.large)
                    }
                    .padding(.top, 4)
                }
            }
        } else {
            ProgressView("Reading your disk…")
                .frame(maxWidth: .infinity, minHeight: 300)
        }
    }
}

struct GaugeLegend: View {
    let other: Int64
    let reclaim: Int64
    let trash: Int64
    let free: Int64

    var body: some View {
        HStack(spacing: 20) {
            item("Your data", other) { RoundedRectangle(cornerRadius: 3).fill(Palette.deep) }
            item("Cleanable", reclaim) { Stripes(color: Palette.mint, spacing: 6).clipShape(RoundedRectangle(cornerRadius: 3)) }
            if trash > 0 {
                item("Trash", trash) { RoundedRectangle(cornerRadius: 3).fill(Palette.coral) }
            }
            item("Free", free) {
                RoundedRectangle(cornerRadius: 3).strokeBorder(Color.primary.opacity(0.3), lineWidth: 1)
            }
        }
        .font(.callout)
    }

    private func item<S: View>(_ label: String, _ bytes: Int64, @ViewBuilder swatch: () -> S) -> some View {
        HStack(spacing: 7) {
            swatch().frame(width: 12, height: 12)
            Text(label).foregroundStyle(.secondary)
            Text(Format.bytes(bytes)).fontWeight(.semibold).monospacedDigit()
        }
    }
}

// MARK: - Insights

struct InsightsSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let list = model.insights
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Recommended for you")
                    .font(.display(22, .bold))
                if let first = list.first {
                    FeaturedInsight(insight: first)
                }
                if list.count > 1 {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                        ForEach(list.dropFirst().prefix(6)) { insight in
                            InsightCard(insight: insight)
                        }
                    }
                }
            }
            .animation(.snappy, value: list.map(\.id))
        }
    }
}

struct FeaturedInsight: View {
    @EnvironmentObject var model: AppModel
    let insight: Insight

    var body: some View {
        HStack(spacing: 18) {
            SymbolTile(symbol: insight.symbol, tint: insight.tint, size: 54)
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.headline).font(.display(21, .bold))
                Text(insight.detail).foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            Button(insight.actionTitle) { model.perform(insight.action) }
                .buttonStyle(.borderedProminent)
                .tint(insight.tint)
                .controlSize(.large)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [insight.tint.opacity(0.18), insight.tint.opacity(0.05)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(insight.tint.opacity(0.28)))
    }
}

struct InsightCard: View {
    @EnvironmentObject var model: AppModel
    let insight: Insight
    @State var hovering = false

    var body: some View {
        Button {
            model.perform(insight.action)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                SymbolTile(symbol: insight.symbol, tint: insight.tint, size: 38)
                VStack(alignment: .leading, spacing: 4) {
                    Text(insight.headline)
                        .font(.headline)
                        .multilineTextAlignment(.leading)
                    Text(insight.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(insight.actionTitle)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(insight.tint)
                        .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 16)
            .scaleEffect(hovering ? 1.012 : 1)
            .animation(.snappy(duration: 0.2), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Where your space goes

struct SpaceBreakdown: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Where your space goes").font(.display(22, .bold))
                Spacer()
                Button("Open Space Map") { model.openInMap(Paths.home) }
                    .buttonStyle(.link)
            }
            if let scan = model.homeScan {
                let top = Array(scan.children.prefix(7))
                let maxSize = max(1, top.first?.size ?? 1)
                VStack(spacing: 0) {
                    ForEach(Array(top.enumerated()), id: \.element.id) { index, node in
                        if index > 0 { Divider().padding(.leading, 58) }
                        BreakdownRow(node: node, fraction: Double(node.size) / Double(maxSize),
                                     share: scan.size > 0 ? Double(node.size) / Double(scan.size) : 0,
                                     color: Palette.ring[index % Palette.ring.count])
                    }
                }
                .card(padding: 6)
            } else {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Measuring your home folder…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .card()
            }
        }
    }
}

struct BreakdownRow: View {
    @EnvironmentObject var model: AppModel
    let node: DiskNode
    let fraction: Double
    let share: Double
    let color: Color
    @State var hovering = false

    var body: some View {
        let info = Knowledge.explain(node.path)
        Button {
            if node.isDir { model.openInMap(node.path) } else { model.reveal(node.path) }
        } label: {
            HStack(spacing: 14) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: node.path))
                    .resizable()
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(info?.title ?? node.name).font(.headline)
                        if info != nil && info?.title != node.name {
                            Text(node.name).font(.caption).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text("\(Int((share * 100).rounded()))%")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text(Format.bytes(node.size))
                            .font(.display(15, .bold))
                            .monospacedDigit()
                            .frame(minWidth: 70, alignment: .trailing)
                    }
                    Meter(fraction: fraction, color: color, height: 6)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .opacity(hovering ? 1 : 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(hovering ? 0.05 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(info?.detail ?? Paths.tilde(node.path))
    }
}

// MARK: - Lifetime

struct LifetimeStrip: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if model.lifetimeFreed > 0 || model.forecast != nil {
            HStack(spacing: 28) {
                if model.lifetimeFreed > 0 {
                    stat(Format.short(model.lifetimeFreed), "freed with Reclaim so far", Palette.mint)
                }
                if let f = model.forecast {
                    let perWeek = Int64(-f.slopePerDay * 7)
                    if perWeek > 100_000_000 {
                        stat(Format.short(perWeek), "of free space used each week", Palette.coral)
                    } else if perWeek < -100_000_000 {
                        stat(Format.short(-perWeek), "freed up each week on average", Palette.mint)
                    } else {
                        stat("Steady", "free space has barely changed lately", Palette.sky)
                    }
                }
                Spacer()
                Button("See History") { model.section = .history }
            }
            .card()
        }
    }

    private func stat(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.display(26, .heavy)).foregroundStyle(tint).monospacedDigit()
            Text(label).font(.callout).foregroundStyle(.secondary)
        }
    }
}
