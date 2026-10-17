// Draws Reclaim's app icon into an .iconset folder.
// Usage: swift Scripts/make_icon.swift build/AppIcon.iconset
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

func render(_ px: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    let s = CGFloat(px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Squircle-ish base, macOS icon grid (about 10% margin).
    let inset = s * 0.098
    let base = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let shape = NSBezierPath(roundedRect: base, xRadius: base.width * 0.225, yRadius: base.width * 0.225)
    NSGradient(starting: color(0x1D3B63), ending: color(0x0C1828))?.draw(in: shape, angle: -90)

    // Capacity bar.
    let barH = base.height * 0.17
    let bar = NSRect(x: base.minX + base.width * 0.14, y: base.midY - barH / 2,
                     width: base.width * 0.72, height: barH)
    let barPath = NSBezierPath(roundedRect: bar, xRadius: barH * 0.32, yRadius: barH * 0.32)
    color(0xFFFFFF, 0.12).setFill()
    barPath.fill()

    NSGraphicsContext.saveGraphicsState()
    barPath.addClip()
    color(0x4A6B93).setFill()
    NSBezierPath(rect: NSRect(x: bar.minX, y: bar.minY, width: bar.width * 0.42, height: barH)).fill()

    let mint = NSRect(x: bar.minX + bar.width * 0.42, y: bar.minY, width: bar.width * 0.33, height: barH)
    color(0x5EE0C1).setFill()
    NSBezierPath(rect: mint).fill()
    NSBezierPath(rect: mint).addClip()
    color(0x2FA98C).setStroke()
    let step = barH * 0.42
    var x = mint.minX - barH
    while x < mint.maxX {
        let stripe = NSBezierPath()
        stripe.move(to: NSPoint(x: x, y: mint.minY))
        stripe.line(to: NSPoint(x: x + barH, y: mint.maxY))
        stripe.lineWidth = step * 0.42
        stripe.stroke()
        x += step
    }
    NSGraphicsContext.restoreGraphicsState()

    // Small "free" tick under the bar.
    color(0x5EE0C1).setFill()
    let dot = base.width * 0.05
    NSBezierPath(ovalIn: NSRect(x: bar.minX, y: bar.minY - dot * 2.4, width: dot, height: dot)).fill()
    color(0xFFFFFF, 0.35).setFill()
    NSBezierPath(roundedRect: NSRect(x: bar.minX + dot * 1.6, y: bar.minY - dot * 2.15,
                                     width: bar.width * 0.38, height: dot * 0.5),
                 xRadius: dot * 0.25, yRadius: dot * 0.25).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let sizes: [(String, Int)] = [
    ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
    ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
    ("512x512", 512), ("512x512@2x", 1024),
]
for (name, px) in sizes {
    if let data = render(px) {
        try? data.write(to: URL(fileURLWithPath: "\(outDir)/icon_\(name).png"))
    }
}
