import AppKit

/// The outline of the popover: a rounded rectangle with a small arrow on top that points at the menu bar icon.
enum PopoverShape {
    static let arrowHeight: CGFloat = 9
    static let arrowWidth: CGFloat = 22

    /// The outline in a view that is not flipped, `size` being the whole panel, arrow included, and `caretX` where the arrow sits.
    static func path(size: CGSize, caretX: CGFloat, radius: CGFloat) -> CGPath {
        let half = arrowWidth / 2
        let center = min(max(caretX, radius + half + 2), size.width - radius - half - 2)
        let width = size.width
        let top = size.height - arrowHeight
        let path = CGMutablePath()
        path.move(to: CGPoint(x: radius, y: 0))
        path.addLine(to: CGPoint(x: width - radius, y: 0))
        path.addArc(tangent1End: CGPoint(x: width, y: 0), tangent2End: CGPoint(x: width, y: radius), radius: radius)
        path.addLine(to: CGPoint(x: width, y: top - radius))
        path.addArc(tangent1End: CGPoint(x: width, y: top), tangent2End: CGPoint(x: width - radius, y: top), radius: radius)
        path.addLine(to: CGPoint(x: center + half, y: top))
        path.addLine(to: CGPoint(x: center + 2.6, y: size.height - 1.6))
        path.addQuadCurve(to: CGPoint(x: center - 2.6, y: size.height - 1.6), control: CGPoint(x: center, y: size.height + 1.2))
        path.addLine(to: CGPoint(x: center - half, y: top))
        path.addLine(to: CGPoint(x: radius, y: top))
        path.addArc(tangent1End: CGPoint(x: 0, y: top), tangent2End: CGPoint(x: 0, y: top - radius), radius: radius)
        path.addLine(to: CGPoint(x: 0, y: radius))
        path.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: radius, y: 0), radius: radius)
        path.closeSubpath()
        return path
    }

    /// What the blurred background is cut to.
    static func mask(size: CGSize, caretX: CGFloat, radius: CGFloat) -> NSImage {
        NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill()
            NSBezierPath(cgPath: path(size: size, caretX: caretX, radius: radius)).fill()
            return true
        }
    }
}

/// A hairline along the whole outline, arrow included, above the content. It never takes a click.
final class PopoverBorderView: NSView {
    var caretX: CGFloat = 0 {
        didSet { if caretX != oldValue { needsDisplay = true } }
    }
    var radius: CGFloat = 12

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let inset: CGFloat = 0.5
        let size = CGSize(width: bounds.width - inset * 2, height: bounds.height - inset * 2)
        guard size.width > 0, size.height > 0 else { return }
        var move = CGAffineTransform(translationX: inset, y: inset)
        guard let outline = PopoverShape.path(size: size, caretX: caretX - inset, radius: radius).copy(using: &move) else { return }
        let line = NSBezierPath(cgPath: outline)
        line.lineWidth = 1
        NSColor.labelColor.withAlphaComponent(0.1).setStroke()
        line.stroke()
    }
}
