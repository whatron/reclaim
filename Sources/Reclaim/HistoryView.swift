import Charts
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PageHeader(title: "History", subtitle: subtitle)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Free space").font(.display(21, .bold))
                    if model.history.count >= 2, let d = model.disk {
                        FreeSpaceChart(history: model.history, forecast: model.forecast, total: d.total)
                            .frame(height: 280)
                            .card()
                    } else {
                        HStack(spacing: 14) {
                            SymbolTile(symbol: "chart.xyaxis.line", tint: Palette.sky, size: 44)
                            Text("Reclaim notes your free space every hour while it's running, including from the menu bar. The chart fills in from here, and after a couple of days it can tell you when your Mac will be full.")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                    }
                }

                HStack(spacing: 14) {
                    StatTile(value: Format.short(model.lifetimeFreed), label: "freed with Reclaim",
                             tint: Palette.mint, symbol: "sparkles")
                    if let change = weekChange {
                        StatTile(value: Format.signed(change),
                                 label: "free space since last week",
                                 tint: change >= 0 ? Palette.mint : Palette.coral,
                                 symbol: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                    }
                    if let f = model.forecast, let days = f.daysUntilFull {
                        StatTile(value: "\(days) days", label: "until full at this pace", tint: Palette.coral,
                                 symbol: "hourglass")
                    }
                }

                GrowthCard()
                ActivityCard()
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 28)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("History")
    }

    /// Change in free space compared with about a week ago.
    private var weekChange: Int64? {
        guard let d = model.disk,
              let base = model.history.last(where: { Date().timeIntervalSince($0.date) >= 6 * 86_400 }) else { return nil }
        return d.free - base.free
    }

    private var subtitle: String {
        guard model.history.count >= 3 else {
            return "How your free space changes over time, and what's growing."
        }
        guard let f = model.forecast else {
            return "Not enough of a trend yet. Check back in a day or two."
        }
        let perWeek = -f.slopePerDay * 7
        if let full = f.projectedFullDate, perWeek > 100_000_000 {
            return "You're using about \(Format.short(Int64(perWeek))) of free space a week. At that pace your Mac fills up around \(full.formatted(date: .abbreviated, time: .omitted))."
        }
        if perWeek < -100_000_000 {
            return "Free space has grown by about \(Format.short(Int64(-perWeek))) a week lately. Nice."
        }
        return "Free space has been steady over the last two weeks."
    }
}

struct FreeSpaceChart: View {
    let history: [Snapshot]
    let forecast: Forecast?
    let total: Int64
    @State var selected: Date?

    private func gb(_ bytes: Int64) -> Double { Double(bytes) / 1e9 }

    var body: some View {
        let points = history
        let maxFree = gb(points.map(\.free).max() ?? 0)
        let nearest = selected.flatMap { date in
            points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        }

        Chart {
            ForEach(points) { s in
                AreaMark(x: .value("Time", s.date), y: .value("Free", gb(s.free)))
                    .foregroundStyle(LinearGradient(colors: [Palette.sky.opacity(0.32), Palette.sky.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", s.date), y: .value("Free", gb(s.free)),
                         series: .value("Series", "Free space"))
                    .foregroundStyle(Palette.sky)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
            }

            if let f = forecast, let full = f.projectedFullDate, let last = points.last,
               let days = f.daysUntilFull, days <= 120 {
                LineMark(x: .value("Time", last.date), y: .value("Free", gb(last.free)),
                         series: .value("Series", "Forecast"))
                    .foregroundStyle(Palette.coral)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                LineMark(x: .value("Time", full), y: .value("Free", 0),
                         series: .value("Series", "Forecast"))
                    .foregroundStyle(Palette.coral)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                PointMark(x: .value("Time", full), y: .value("Free", 0))
                    .foregroundStyle(Palette.coral)
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Full around \(full.formatted(.dateTime.month().day()))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.coral)
                    }
            }

            if let s = nearest {
                RuleMark(x: .value("Time", s.date))
                    .foregroundStyle(Color.primary.opacity(0.25))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(spacing: 1) {
                            Text("\(Format.short(s.free)) free")
                                .font(.callout.weight(.semibold))
                            Text(s.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.regularMaterial))
                    }
                PointMark(x: .value("Time", s.date), y: .value("Free", gb(s.free)))
                    .foregroundStyle(Palette.sky)
                    .symbolSize(60)
            }
        }
        .chartYScale(domain: 0...max(1, maxFree * 1.15))
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text("\(Int(v)) GB") }
                }
            }
        }
        .chartXSelection(value: $selected)
    }
}

struct Growth: Identifiable {
    let target: TargetDef
    let delta: Int64
    var id: String { target.id }
}

struct GrowthCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let growers = model.targets.compactMap { t -> Growth? in
            guard let g = model.growth(of: t.id) else { return nil }
            return Growth(target: t, delta: g)
        }
        .sorted { $0.delta > $1.delta }

        VStack(alignment: .leading, spacing: 12) {
            Text("What changed this week").font(.display(21, .bold))
            if growers.isEmpty {
                Text("Nothing Reclaim tracks has grown or shrunk by more than 100 MB in the past week.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(growers) { item in
                        HStack(spacing: 12) {
                            SymbolTile(symbol: item.target.symbol, tint: item.delta > 0 ? Palette.coral : Palette.mint, size: 32)
                            Text(item.target.name).font(.headline)
                            Spacer()
                            Text(Format.signed(item.delta))
                                .font(.display(16, .bold))
                                .monospacedDigit()
                                .foregroundStyle(item.delta > 0 ? Palette.coral : Palette.mint)
                            Text("now \(Format.bytes(model.sizes[item.target.id]?.bytes))")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 110, alignment: .trailing)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                    }
                }
                .card(padding: 6)
            }
        }
    }
}

struct ActivityCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity").font(.display(21, .bold))
            if model.log.isEmpty {
                Text("Cleanups you run show up here, with the output of every command Reclaim ran for you.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.log.reversed())) { entry in
                        LogRow(entry: entry)
                        if entry.id != model.log.first?.id {
                            Divider().opacity(0.5)
                        }
                    }
                }
                .card(padding: 10)
            }
        }
    }
}

struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        if entry.output.isEmpty {
            header.padding(.vertical, 6)
        } else {
            DisclosureGroup {
                Text(entry.output)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            } label: {
                header
            }
            .padding(.vertical, 6)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: entry.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(entry.ok ? Palette.mint : Palette.coral)
            Text(entry.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if entry.freed > 0 {
                Text(Format.short(entry.freed))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Palette.mint)
                    .monospacedDigit()
            }
            Text(entry.date, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}
