import AppKit
import PRPulseCore
import SwiftUI

enum Palette {
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }

    static let review = dynamic(light: 0x3552D6, dark: 0x8AA4FF)
    static let changes = dynamic(light: 0xC13A2D, dark: 0xFF8577)
    static let respond = dynamic(light: 0x6D3FD0, dark: 0xBB99FF)
    static let ci = dynamic(light: 0xB0450C, dark: 0xFF9A62)
    static let conflict = dynamic(light: 0x865F00, dark: 0xF0C14B)
    static let merge = dynamic(light: 0x16784A, dark: 0x52CF92)

    static let thumb = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.14) : .white
    })
    static let surface = Color.primary.opacity(0.05)
    static let line = Color.primary.opacity(0.1)

    static func tone(_ tone: Waiting.Tone) -> Color? {
        switch tone {
        case .normal: nil
        case .warm: conflict
        case .hot: changes
        }
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension ActionLane {
    var tone: Color {
        switch self {
        case .review: Palette.review
        case .changes: Palette.changes
        case .respond: Palette.respond
        case .ci: Palette.ci
        case .conflict: Palette.conflict
        case .merge: Palette.merge
        }
    }

    var symbol: String {
        switch self {
        case .review: "eye"
        case .changes: "pencil"
        case .respond: "bubble.left"
        case .ci: "xmark.circle"
        case .conflict: "exclamationmark.triangle"
        case .merge: "arrow.triangle.merge"
        }
    }

    var filterTitle: String {
        switch self {
        case .review: tr("lane.review")
        case .changes: tr("lane.changes")
        case .respond: tr("lane.respond")
        case .ci: tr("lane.ci")
        case .conflict: tr("lane.conflict")
        case .merge: tr("lane.merge")
        }
    }

    var chipTitle: String {
        switch self {
        case .review: tr("chip.review")
        case .changes: tr("chip.changes")
        case .respond: tr("chip.respond")
        case .ci: tr("chip.ci")
        case .conflict: tr("chip.conflict")
        case .merge: tr("chip.merge")
        }
    }
}
