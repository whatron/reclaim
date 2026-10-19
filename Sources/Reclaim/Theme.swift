import AppKit
import SwiftUI

// MARK: - Palette ("tide": data is water, free space is air)

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension Color {
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

enum Palette {
    static let mint = Color.adaptive(light: 0x0E9C7F, dark: 0x5EE0C1)
    static let coral = Color.adaptive(light: 0xD33852, dark: 0xFF7A8A)
    static let sand = Color.adaptive(light: 0xB07F05, dark: 0xF2C14E)
    static let violet = Color.adaptive(light: 0x6E56CF, dark: 0xA594F9)
    static let sky = Color.adaptive(light: 0x2F7FD8, dark: 0x6CB4FF)
    static let deep = Color.adaptive(light: 0x3D6496, dark: 0x3B6AA0)
    static let abyss = Color.adaptive(light: 0x23426E, dark: 0x16294A)
    static let tile = Color.adaptive(light: 0x6E9BD3, dark: 0x4B7FBE)
    static let tileFile = Color.adaptive(light: 0x9F90E0, dark: 0x8A79D6)

    /// Hues for the rings of the space map, in order of size.
    static let ring: [Color] = [
        Color.adaptive(light: 0x2F7FD8, dark: 0x5AA2F0),
        Color.adaptive(light: 0x6E56CF, dark: 0x9D8CF6),
        Color.adaptive(light: 0x0F8F9E, dark: 0x45C6D6),
        Color.adaptive(light: 0xC0508A, dark: 0xF08DC0),
        Color.adaptive(light: 0x3E5FC9, dark: 0x7D95F2),
        Color.adaptive(light: 0xB07F05, dark: 0xEFC25A),
        Color.adaptive(light: 0x2E8F5E, dark: 0x6FD39C),
        Color.adaptive(light: 0xD0603A, dark: 0xF59A72),
    ]
}

extension Font {
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Surfaces

extension View {
    /// Liquid Glass on macOS 26, a material panel on earlier versions.
    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat = 18) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.materialPanel(cornerRadius: cornerRadius)
        }
        #else
        self.materialPanel(cornerRadius: cornerRadius)
        #endif
    }

    func materialPanel(cornerRadius: CGFloat) -> some View {
        self
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
    }

    /// A quiet content card.
    func card(cornerRadius: CGFloat = 16, padding: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72)))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07)))
    }
}

/// Soft ocean light behind every page.
struct AuroraBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(colors: [Palette.sky.opacity(0.16), .clear], center: .topLeading,
                           startRadius: 10, endRadius: 720)
            RadialGradient(colors: [Palette.mint.opacity(0.10), .clear], center: .bottomTrailing,
                           startRadius: 10, endRadius: 640)
            RadialGradient(colors: [Palette.violet.opacity(0.07), .clear], center: .topTrailing,
                           startRadius: 10, endRadius: 520)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Small pieces

/// Diagonal stripes, used for "can be cleaned" and "in the Trash".
struct Stripes: View {
    let color: Color
    var baseOpacity: Double = 0.72
    var spacing: CGFloat = 12

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color.opacity(baseOpacity)))
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                var line = Path()
                line.move(to: CGPoint(x: x, y: size.height))
                line.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(line, with: .color(color), lineWidth: spacing * 0.42)
                x += spacing
            }
        }
    }
}

struct SymbolTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 34

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.12)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .strokeBorder(tint.opacity(0.25)))
            .overlay(Image(systemName: symbol)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(tint))
            .frame(width: size, height: size)
    }
}

struct Pill: View {
    let text: String
    var tint: Color = .secondary
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.13)))
    }
}

/// A round selection mark, like picking photos.
struct RoundCheck: View {
    let isOn: Bool
    var tint: Color = Palette.mint

    var body: some View {
        ZStack {
            Circle().strokeBorder(isOn ? tint : Color.secondary.opacity(0.5), lineWidth: 1.5)
            if isOn {
                Circle().fill(tint).padding(0.5)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 20, height: 20)
        .animation(.snappy(duration: 0.18), value: isOn)
        .contentShape(Circle())
    }
}

struct Meter: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.07))
                Capsule().fill(LinearGradient(colors: [color.opacity(0.75), color],
                                              startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, geo.size.width * min(1, fraction)))
            }
        }
        .frame(height: height)
        .animation(.smooth(duration: 0.6), value: fraction)
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.display(30, .heavy))
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The floating bar at the bottom of a page that carries its main action.
struct ActionDock<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 14) { content }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassPanel(cornerRadius: 22)
            .padding(.horizontal, 28)
            .padding(.bottom, 18)
    }
}
