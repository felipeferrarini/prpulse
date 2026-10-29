import AppKit
import PRPulseCore

enum StatusIconRenderer {
    private static let symbolName = "arrow.triangle.branch"
    private static let height: CGFloat = 18

    static func image(for state: IconState, phase: Double) -> NSImage {
        switch state {
        case .upToDate: templateSymbol()
        case .pending(let count): badged(.systemOrange, text: String(count), halo: nil)
        case .fresh(let count): badged(.systemOrange, text: String(count), halo: phase)
        case .error: badged(.systemRed, text: "!", halo: nil)
        }
    }

    private static func symbol() -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: "PRPulse")?
            .withSymbolConfiguration(configuration) ?? NSImage(size: NSSize(width: height, height: height))
    }

    private static func templateSymbol() -> NSImage {
        let image = symbol()
        image.isTemplate = true
        return image
    }

    private static func tinted(_ symbol: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    private static func badged(_ color: NSColor, text: String, halo: Double?) -> NSImage {
        let icon = tinted(symbol(), color)
        let badge = badgeAttributes()
        let textSize = (text as NSString).size(withAttributes: badge)
        let badgeWidth = max(textSize.width + 8, 14)
        let size = NSSize(width: icon.size.width + badgeWidth * 0.6 + 12, height: height + 8)

        let image = NSImage(size: size, flipped: false) { _ in
            let iconOrigin = NSPoint(x: 6, y: (size.height - icon.size.height) / 2 - 1)
            if let halo { drawHalo(around: NSRect(origin: iconOrigin, size: icon.size), color: color, phase: halo) }
            icon.draw(at: iconOrigin, from: .zero, operation: .sourceOver, fraction: 1)
            drawBadge(text, attributes: badge, textSize: textSize, width: badgeWidth, in: size)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func badgeAttributes() -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 9, weight: .bold), .foregroundColor: NSColor.white]
    }

    private static func drawBadge(
        _ text: String,
        attributes: [NSAttributedString.Key: Any],
        textSize: NSSize,
        width: CGFloat,
        in size: NSSize
    ) {
        let rect = NSRect(x: size.width - width, y: size.height - 13, width: width, height: 12)
        NSColor.systemRed.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        let origin = NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2)
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }

    private static func drawHalo(around rect: NSRect, color: NSColor, phase: Double) {
        let grow = CGFloat(phase) * 4
        let ring = rect.insetBy(dx: -1 - grow, dy: -1 - grow)
        color.withAlphaComponent(CGFloat(0.6 * (1 - phase))).setStroke()
        let path = NSBezierPath(ovalIn: ring)
        path.lineWidth = 1.5
        path.stroke()
    }
}
