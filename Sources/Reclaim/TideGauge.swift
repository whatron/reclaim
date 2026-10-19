import SwiftUI

/// A water surface at `level` (0 = empty, 1 = full). Only the level animates; the phase moves with time.
struct WaveShape: Shape {
    var level: Double
    var phase: Double
    var amplitude: CGFloat

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let clamped = min(1, max(0, level))
        guard clamped > 0.0005 else { return path }
        let baseY = rect.maxY - rect.height * CGFloat(clamped)
        let amp = clamped > 0.995 ? 0 : amplitude
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        let steps = 56
        for i in 0...steps {
            let rel = Double(i) / Double(steps)
            let x = rect.minX + rect.width * CGFloat(rel)
            let wave = sin(rel * 2 * .pi * 1.25 + phase) + 0.35 * sin(rel * 2 * .pi * 2.6 - phase * 1.4)
            path.addLine(to: CGPoint(x: x, y: baseY + amp * CGFloat(wave)))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The disk as a glass vessel: deep water is your data, the glowing shallows are what can be
/// cleaned, coral is the Trash, and the air above is free space.
struct TideGauge: View {
    let total: Int64
    let other: Int64
    let reclaim: Int64
    let trash: Int64
    var showTicks = true
    var cornerFraction: CGFloat = 0.26
    /// Small gauges (sidebar, menu bar) stay still to save battery.
    var animated = true

    @Environment(\.accessibilityReduceMotion) var reduceMotion

    private func fraction(_ v: Int64) -> Double {
        total > 0 ? Double(max(0, v)) / Double(total) : 0
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let radius = min(size.width, size.height) * cornerFraction
            let vessel = RoundedRectangle(cornerRadius: radius, style: .continuous)
            let levelOther = fraction(other)
            let levelReclaim = levelOther + fraction(reclaim)
            let levelAll = levelReclaim + fraction(trash)
            let amp = max(2.5, size.height * 0.018)

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !animated)) { timeline in
                let t = (reduceMotion || !animated) ? 0 : timeline.date.timeIntervalSinceReferenceDate

                ZStack {
                    vessel.fill(Color.primary.opacity(0.045))

                    ZStack {
                        WaveShape(level: levelAll, phase: t * 1.15, amplitude: amp)
                            .fill(LinearGradient(colors: [Palette.coral.opacity(0.95), Palette.coral.opacity(0.7)],
                                                 startPoint: .top, endPoint: .bottom))
                            .animation(.spring(duration: 1.4, bounce: 0.15), value: levelAll)

                        WaveShape(level: levelReclaim, phase: t * 0.95 + 1.7, amplitude: amp * 0.85)
                            .fill(LinearGradient(colors: [Palette.mint, Palette.mint.opacity(0.7)],
                                                 startPoint: .top, endPoint: .bottom))
                            .animation(.spring(duration: 1.4, bounce: 0.15), value: levelReclaim)

                        Stripes(color: .white, baseOpacity: 0, spacing: 14)
                            .opacity(0.16)
                            .mask(WaveShape(level: levelReclaim, phase: t * 0.95 + 1.7, amplitude: amp * 0.85)
                                .animation(.spring(duration: 1.4, bounce: 0.15), value: levelReclaim))

                        WaveShape(level: levelOther, phase: t * 0.75 + 3.1, amplitude: amp * 0.7)
                            .fill(LinearGradient(colors: [Palette.deep, Palette.abyss],
                                                 startPoint: .top, endPoint: .bottom))
                            .animation(.spring(duration: 1.4, bounce: 0.15), value: levelOther)

                        bubbles(time: t, height: size.height, width: size.width, level: levelOther)
                    }
                    .clipShape(vessel)

                    // Glass: a soft highlight down the left side and a bright rim.
                    vessel
                        .fill(LinearGradient(colors: [.white.opacity(0.22), .clear],
                                             startPoint: .leading, endPoint: UnitPoint(x: 0.35, y: 0.5)))
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                    vessel
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.08),
                                                              Palette.sky.opacity(0.35)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing),
                                      lineWidth: 1.5)

                    if showTicks { ticks(height: size.height) }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Disk \(Int((fraction(other + reclaim + trash) * 100).rounded())) percent full")
    }

    private func bubbles(time t: Double, height: CGFloat, width: CGFloat, level: Double) -> some View {
        Canvas { context, size in
            let travel = size.height * CGFloat(level)
            guard travel > 30 else { return }
            for i in 0..<8 {
                let speed = 14.0 + Double(i) * 4.5
                let offset = CGFloat((t * speed + Double(i) * 53).truncatingRemainder(dividingBy: Double(travel)))
                let x = size.width * (0.14 + 0.1 * CGFloat(i)) + CGFloat(sin(t * 1.3 + Double(i))) * 4
                let d = CGFloat(2 + i % 3)
                let fade = 0.3 * (1 - offset / travel)
                context.fill(Path(ellipseIn: CGRect(x: x, y: size.height - offset, width: d, height: d)),
                             with: .color(.white.opacity(Double(fade))))
            }
        }
        .allowsHitTesting(false)
    }

    private func ticks(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach([75, 50, 25], id: \.self) { pct in
                Spacer()
                HStack(spacing: 4) {
                    Spacer()
                    Text("\(pct)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                    Rectangle().fill(.white.opacity(0.55)).frame(width: 9, height: 1)
                }
                .frame(height: 0)
            }
            Spacer()
        }
        .padding(.trailing, 8)
        .shadow(color: .black.opacity(0.45), radius: 1.5)
        .allowsHitTesting(false)
    }
}
