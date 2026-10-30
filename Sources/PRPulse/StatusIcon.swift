import AppKit
import PRPulseCore

/// Draws the menu bar icon: a pull request glyph that turns into one orange pill with the count when
/// something needs the viewer, rings out when a new item arrives, and turns red when it cannot update.
enum StatusIconRenderer {
    private static let height: CGFloat = 22
    private static let pillHeight = BrandIcon.Pill.height
    private static let glyphSize = BrandIcon.Pill.glyphSize
    private static let ripplePadding: CGFloat = 4

    private static let orangeTop = BrandIcon.orangeTop
    private static let orangeBottom = BrandIcon.orangeBottom
    private static let redTop = NSColor(hex: 0xFF6B5E)
    private static let redBottom = NSColor(hex: 0xE5382B)
    private static let ink = BrandIcon.ink

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
            .font: NSFont.monospacedDigitSystemFont(ofSize: BrandIcon.Pill.fontSize, weight: .bold),
            .foregroundColor: content,
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let pillWidth = BrandIcon.Pill.leading + glyphSize + BrandIcon.Pill.gap + ceil(textSize.width) + BrandIcon.Pill.trailing
        let size = NSSize(width: pillWidth + ripplePadding * 2, height: height)

        let image = NSImage(size: size, flipped: false) { _ in
            let pill = NSRect(x: ripplePadding, y: (size.height - pillHeight) / 2, width: pillWidth, height: pillHeight)
            if let ripple { drawRipple(around: pill, color: colors.1, phase: ripple) }
            drawPill(pill, colors: colors)
            content.set()
            drawGlyph(in: NSRect(x: pill.minX + BrandIcon.Pill.leading, y: pill.midY - glyphSize / 2, width: glyphSize, height: glyphSize))
            (text as NSString).draw(
                at: NSPoint(x: pill.minX + BrandIcon.Pill.leading + glyphSize + BrandIcon.Pill.gap, y: pill.midY - textSize.height / 2),
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

    /// The shared glyph, fitted into `rect`. Its grid has y pointing down, so it is flipped here.
    private static func drawGlyph(in rect: NSRect) {
        let scale = rect.width / 24
        var transform = AffineTransform(translationByX: rect.minX, byY: rect.maxY)
        transform.scale(x: scale, y: -scale)

        let path = BrandIcon.glyphPath()
        path.transform(using: transform)
        path.lineWidth = BrandIcon.lineWidth(forGlyphSize: rect.width)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }
}
