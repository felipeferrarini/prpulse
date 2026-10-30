import AppKit
import SwiftUI

/// What the menu bar icon, the setup wizard and the popover share: one glyph, one orange and one ink.
enum BrandIcon {
    static let orangeTop = NSColor(hex: 0xFFA766)
    static let orangeBottom = NSColor(hex: 0xFF7A2C)
    static let ink = NSColor(hex: 0x2A1204)

    /// The pull request mark on a 24 point grid with y pointing down: a node at the top left joined to one at
    /// the bottom, and a bent line that reaches the node at the bottom right.
    static func glyphPath() -> NSBezierPath {
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

    /// Strokes are a little heavier on small glyphs so they stay legible.
    static func lineWidth(forGlyphSize size: CGFloat) -> CGFloat {
        2.1 * size / 24 * (size < 14 ? 1.15 : 1)
    }

    /// The pill the menu bar draws when something needs the viewer, measured in points at its natural size.
    enum Pill {
        static let height: CGFloat = 18
        static let glyphSize: CGFloat = 12
        static let leading: CGFloat = 6
        static let gap: CGFloat = 3
        static let trailing: CGFloat = 7
        static let fontSize: CGFloat = 11
    }
}

/// The glyph as a SwiftUI shape; stroke it with `BrandIcon.lineWidth(forGlyphSize:)`.
struct PullRequestGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let transform = CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: scale, y: scale)
        return Path(BrandIcon.glyphPath().cgPath).applying(transform)
    }
}

/// The glyph at a given size, drawn the way the menu bar draws it.
struct BrandGlyph: View {
    let size: CGFloat
    var color: Color = Color(nsColor: BrandIcon.ink)

    var body: some View {
        PullRequestGlyph()
            .stroke(color, style: StrokeStyle(lineWidth: BrandIcon.lineWidth(forGlyphSize: size), lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The menu bar pill, scaled: the same proportions, orange and ink as `StatusIconRenderer`.
struct BrandPill: View {
    let count: Int
    var height: CGFloat = BrandIcon.Pill.height

    var body: some View {
        let scale = height / BrandIcon.Pill.height
        HStack(spacing: BrandIcon.Pill.gap * scale) {
            BrandGlyph(size: BrandIcon.Pill.glyphSize * scale)
            Text(StatusIconRenderer.label(count))
                .font(.system(size: BrandIcon.Pill.fontSize * scale, weight: .bold).monospacedDigit())
                .foregroundStyle(Color(nsColor: BrandIcon.ink))
        }
        .padding(.leading, BrandIcon.Pill.leading * scale)
        .padding(.trailing, BrandIcon.Pill.trailing * scale)
        .frame(height: height)
        .background(
            LinearGradient(
                colors: [Color(nsColor: BrandIcon.orangeTop), Color(nsColor: BrandIcon.orangeBottom)],
                startPoint: .top, endPoint: .bottom
            ),
            in: Capsule(style: .circular)
        )
        .overlay(Capsule(style: .circular).inset(by: 0.25 * scale).stroke(Color.white.opacity(0.35), lineWidth: 0.5 * scale))
    }
}
