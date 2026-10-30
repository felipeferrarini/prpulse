import AppKit

// Draws the app icon into an .iconset folder: the orange of the menu bar pill, with its ink pull request glyph.
// The orange, the ink and the glyph come from Sources/PRPulse/BrandMark.swift; keep the two in step.
// Usage: swift scripts/make-icon.swift <output.iconset>

let outputPath = CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset"

func hex(_ value: Int) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: 1
    )
}

/// The glyph on a 24 point grid with y pointing down.
func glyphPath() -> NSBezierPath {
    let path = NSBezierPath()
    path.appendOval(in: NSRect(x: 15, y: 15, width: 6, height: 6))
    path.appendOval(in: NSRect(x: 3, y: 3, width: 6, height: 6))
    path.move(to: NSPoint(x: 6, y: 9))
    path.line(to: NSPoint(x: 6, y: 21))
    path.move(to: NSPoint(x: 13, y: 6))
    path.line(to: NSPoint(x: 16, y: 6))
    path.curve(to: NSPoint(x: 18, y: 8), controlPoint1: NSPoint(x: 17.1, y: 6), controlPoint2: NSPoint(x: 18, y: 6.9))
    path.line(to: NSPoint(x: 18, y: 15))
    return path
}

func render(pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let size = CGFloat(pixels)
    let body = NSRect(x: size * 0.05, y: size * 0.05, width: size * 0.9, height: size * 0.9)
    let path = NSBezierPath(roundedRect: body, xRadius: size * 0.2, yRadius: size * 0.2)
    NSGradient(starting: hex(0xFFA766), ending: hex(0xFF7A2C))?.draw(in: path, angle: -90)

    let glyphSize = size * 0.5
    let scale = glyphSize / 24
    var transform = AffineTransform(translationByX: (size - glyphSize) / 2, byY: (size + glyphSize) / 2)
    transform.scale(x: scale, y: -scale)
    let glyph = glyphPath()
    glyph.transform(using: transform)
    glyph.lineWidth = 2.3 * scale
    glyph.lineCapStyle = .round
    glyph.lineJoinStyle = .round
    hex(0x2A1204).setStroke()
    glyph.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let entries: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

try? FileManager.default.createDirectory(atPath: outputPath, withIntermediateDirectories: true)
for entry in entries {
    guard let png = render(pixels: entry.pixels) else { fatalError("cannot render \(entry.name)") }
    try png.write(to: URL(fileURLWithPath: outputPath).appendingPathComponent("\(entry.name).png"))
}
