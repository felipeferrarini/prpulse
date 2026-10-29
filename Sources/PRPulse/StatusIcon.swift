import AppKit
import PRPulseCore

/// Draws the menu bar icon: a pull request glyph that turns into one orange pill with the count when
/// something needs the viewer, rings out when a new item arrives, and turns red when it cannot update.
enum StatusIconRenderer {
    private static let height: CGFloat = 22
    private static let pillHeight: CGFloat = 18
    private static let glyphSize: CGFloat = 12
    private static let ripplePadding: CGFloat = 4

    private static let orangeTop = NSColor(hex: 0xFFA766)
    private static let orangeBottom = NSColor(hex: 0xFF7A2C)
    private static let redTop = NSColor(hex: 0xFF6B5E)
    private static let redBottom = NSColor(hex: 0xE5382B)
    private static let ink = NSColor(hex: 0x2A1204)

    static func image(for state: IconState, phase: Double) -> NSImage {
        switch state {
        case .upToDate: idle()
        case .pending(let count): pill(text: label(count), colors: (orangeTop, orangeBottom), content: ink, ripple: nil)
        case .fresh(let count): pill(text: label(count), colors: (orangeTop, orangeBottom), content: ink, ripple: phase)
        case .error: pill(text: "!", colors: (redTop, redBottom), content: .white, ripple: nil)
        }
    }

    static func label(_ count: Int) -> String {
        count > 99 ? "99+" : String(count)
    }

    // MARK: Idle

    private static func idle() -> NSImage {
        let size = NSSize(width: 22, height: height)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.set()
            drawGlyph(in: NSRect(x: (size.width - 16) / 2, y: (size.height - 16) / 2, width: 16, height: 16))
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: Pill

    private static func pill(text: String, colors: (NSColor, NSColor), content: NSColor, ripple: Double?) -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: content,
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let pillWidth = 6 + glyphSize + 3 + ceil(textSize.width) + 7
        let size = NSSize(width: pillWidth + ripplePadding * 2, height: height)

        let image = NSImage(size: size, flipped: false) { _ in
            let pill = NSRect(x: ripplePadding, y: (size.height - pillHeight) / 2, width: pillWidth, height: pillHeight)
            if let ripple { drawRipple(around: pill, color: colors.1, phase: ripple) }
            drawPill(pill, colors: colors)
            content.set()
            drawGlyph(in: NSRect(x: pill.minX + 6, y: pill.midY - glyphSize / 2, width: glyphSize, height: glyphSize))
            (text as NSString).draw(
                at: NSPoint(x: pill.minX + 6 + glyphSize + 3, y: pill.midY - textSize.height / 2),
                withAttributes: attributes
            )
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func drawPill(_ rect: NSRect, colors: (NSColor, NSColor)) {
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        NSGradient(starting: colors.0, ending: colors.1)?.draw(in: path, angle: -90)
        NSColor.white.withAlphaComponent(0.35).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    private static func drawRipple(around rect: NSRect, color: NSColor, phase: Double) {
        let grow = CGFloat(phase) * ripplePadding
        let ring = rect.insetBy(dx: -grow, dy: -grow)
        color.withAlphaComponent(CGFloat(0.7 * (1 - phase))).setStroke()
        let path = NSBezierPath(roundedRect: ring, xRadius: ring.height / 2, yRadius: ring.height / 2)
        path.lineWidth = 1.5
        path.stroke()
    }

    // MARK: Glyph

    /// The pull request mark: a node at the top left joined to one at the bottom, and a bent line that
    /// reaches the node at the bottom right. Drawn on a 24 point grid, y down, then fitted into `rect`.
    private static func drawGlyph(in rect: NSRect) {
        let scale = rect.width / 24
        var transform = AffineTransform(translationByX: rect.minX, byY: rect.maxY)
        transform.scale(x: scale, y: -scale)

        let path = NSBezierPath()
        path.appendOval(in: NSRect(x: 15, y: 15, width: 6, height: 6))
        path.appendOval(in: NSRect(x: 3, y: 3, width: 6, height: 6))
        path.move(to: NSPoint(x: 6, y: 9))
        path.line(to: NSPoint(x: 6, y: 21))
        path.move(to: NSPoint(x: 13, y: 6))
        path.line(to: NSPoint(x: 16, y: 6))
        path.curve(to: NSPoint(x: 18, y: 8), controlPoint1: NSPoint(x: 17.1, y: 6), controlPoint2: NSPoint(x: 18, y: 6.9))
        path.line(to: NSPoint(x: 18, y: 15))
        path.transform(using: transform)
        path.lineWidth = 2.1 * scale * (rect.width < 14 ? 1.15 : 1)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }
}
