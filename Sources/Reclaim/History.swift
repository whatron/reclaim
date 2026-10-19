import Foundation

/// One reading of the disk, saved about once an hour.
struct Snapshot: Codable, Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let free: Int64
    let total: Int64
    var targets: [String: Int64]
}

struct Forecast {
    /// Bytes per day; negative means the disk is filling up.
    let slopePerDay: Double
    let daysUntilFull: Int?
    let projectedFullDate: Date?
}

enum HistoryStore {
    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: Paths.h("Library/Application Support"))
        return base.appendingPathComponent("Reclaim", isDirectory: true).appendingPathComponent("history.json")
    }

    static func load() -> [Snapshot] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Snapshot].self, from: data)) ?? []
    }

    static func save(_ snapshots: [Snapshot]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshots) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Keeps hourly detail for two weeks and one reading per day before that, up to a year.
    static func compact(_ snapshots: [Snapshot]) -> [Snapshot] {
        let now = Date()
        var out: [Snapshot] = []
        var seenDays = Set<String>()
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        for s in snapshots.sorted(by: { $0.date > $1.date }) {
            let age = now.timeIntervalSince(s.date)
            if age > 365 * 86_400 { continue }
            if age < 14 * 86_400 {
                out.append(s)
            } else if seenDays.insert(day.string(from: s.date)).inserted {
                out.append(s)
            }
        }
        return out.sorted { $0.date < $1.date }
    }

    /// Least-squares trend of free space over the last 14 days.
    static func forecast(_ snapshots: [Snapshot], currentFree: Int64) -> Forecast? {
        let cutoff = Date().addingTimeInterval(-14 * 86_400)
        let recent = snapshots.filter { $0.date >= cutoff }
        guard recent.count >= 3,
              let first = recent.first?.date, let last = recent.last?.date,
              last.timeIntervalSince(first) >= 12 * 3600 else { return nil }
        let xs = recent.map { $0.date.timeIntervalSince(first) / 86_400 }
        let ys = recent.map { Double($0.free) }
        let n = Double(xs.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        var num = 0.0
        var den = 0.0
        for i in 0..<xs.count {
            num += (xs[i] - meanX) * (ys[i] - meanY)
            den += (xs[i] - meanX) * (xs[i] - meanX)
        }
        guard den > 0 else { return nil }
        let slope = num / den
        guard slope < -50_000_000 else {
            return Forecast(slopePerDay: slope, daysUntilFull: nil, projectedFullDate: nil)
        }
        let days = Int((Double(currentFree) / -slope).rounded())
        return Forecast(slopePerDay: slope, daysUntilFull: days,
                        projectedFullDate: Date().addingTimeInterval(Double(days) * 86_400))
    }

    /// The reading closest to `days` ago (at least one day old), for "grew by" comparisons.
    static func baseline(_ snapshots: [Snapshot], daysAgo days: Double) -> Snapshot? {
        let target = Date().addingTimeInterval(-days * 86_400)
        let older = snapshots.filter { Date().timeIntervalSince($0.date) >= 86_400 && !$0.targets.isEmpty }
        return older.min { abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target)) }
    }
}
