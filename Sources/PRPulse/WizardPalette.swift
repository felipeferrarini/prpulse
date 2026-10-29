import SwiftUI

/// The wizard's own colors: cool navy surfaces and a blue accent, in a light and a dark flavor.
enum WizardPalette {
    static let bg = Palette.dynamic(light: 0xF3F5FB, dark: 0x0A0F1F)
    static let ink = Palette.dynamic(light: 0x0B1736, dark: 0xEEF1FB)
    static let ink2 = Palette.dynamic(light: 0x53607F, dark: 0xA2ACC9)
    static let ink3 = Palette.dynamic(light: 0x6A7595, dark: 0x8591B3)
    static let line = Palette.dynamic(light: 0xD9E0F2, dark: 0x232E52)
    static let card = Palette.dynamic(light: 0xFFFFFF, dark: 0x121A33)
    static let card2 = Palette.dynamic(light: 0xE9EEFB, dark: 0x1A2447)
    static let off = Palette.dynamic(light: 0xC8D1EA, dark: 0x38457A)
    static let accent = Palette.dynamic(light: 0x2F55FF, dark: 0x8EA6FF)
    static let soft = Palette.dynamic(light: 0xE3E9FF, dark: 0x1B2750)
    static let onAccent = Palette.dynamic(light: 0xFFFFFF, dark: 0x0A0F1F)
    static let danger = Palette.dynamic(light: 0xD7382B, dark: 0xFF8577)
    static let success = Palette.dynamic(light: 0x16784A, dark: 0x52CF92)

    static let stageBase = Color(nsColor: NSColor(hex: 0x0C0E1C))
    static let stageGlow = Color(nsColor: NSColor(hex: 0x2F55FF))
    static let stageIndigo = Color(nsColor: NSColor(hex: 0x5850FF))
    static let brandOrange = Color(nsColor: NSColor(hex: 0xFF8A3D))
}

/// Fades a view up into place, one after another.
struct Staggered: ViewModifier {
    let index: Int
    @LocalState private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onAppear {
                withAnimation(.easeOut(duration: 0.55).delay(Double(index) * 0.055)) { shown = true }
            }
    }
}

extension View {
    func staggered(_ index: Int) -> some View {
        modifier(Staggered(index: index))
    }
}

struct WizardPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(WizardPalette.onAccent)
            .frame(minWidth: 130)
            .frame(height: 40)
            .padding(.horizontal, 20)
            .background(WizardPalette.accent, in: RoundedRectangle(cornerRadius: 11))
            .opacity(isEnabled ? 1 : 0.35)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
