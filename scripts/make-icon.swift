import AppKit

// Draws the app icon (orange rounded square with the branch symbol) into an .iconset folder.
// Usage: swift scripts/make-icon.swift <output.iconset>

let outputPath = CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset"

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
    NSGradient(
        starting: NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.26, alpha: 1),
        ending: NSColor(calibratedRed: 0.91, green: 0.35, blue: 0.05, alpha: 1)
    )?.draw(in: path, angle: -90)

    let configuration = NSImage.SymbolConfiguration(pointSize: size * 0.5, weight: .semibold)
    if let symbol = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) {
        let tinted = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            NSColor.white.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        let origin = NSPoint(x: (size - tinted.size.width) / 2, y: (size - tinted.size.height) / 2)
        tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
    }
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
