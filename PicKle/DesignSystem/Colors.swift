import SwiftUI
import AppKit

/// PICkle brand palette — the pickle-green sibling of pizzaClip's brick-red set.
///
/// We inherit pizzaClip's *color-role structure* (accent / amber / amberFill /
/// inkOnAmber) and its adaptive light/dark pairing, swapping only the hex values
/// to a pickle theme. Light mode uses richer/darker greens (legible on bright
/// glass); Dark mode uses brighter greens (vivid on dark glass).
enum AppColors {
    /// Primary brand accent — pickle green. Drives selection, the app tint, and
    /// the footer action words. Brightened to a fresh dill green in Dark mode.
    static let accent = Color(light: 0x3B6B2F, dark: 0x6FAE4E)

    /// Secondary pop — dijon mustard yellow. Used as *text / stroke* for badges
    /// and markers, so it's deepened on light glass and kept bright on dark.
    static let amber = Color(light: 0xB57500, dark: 0xE9C046)

    /// Bright fill for *filled* chips (e.g. count badges). Stays bright in both
    /// modes since dark ink sits on top of it.
    static let amberFill = Color(light: 0xE9C046, dark: 0xF2D35B)

    /// Deep green-black ink — used as the label *on* the bright chip.
    static let inkOnAmber = Color(hex: 0x10261A)

    // System-derived neutrals — already adapt to light/dark on their own.
    static let separator = Color(NSColor.separatorColor)
    static let secondaryLabel = Color(NSColor.secondaryLabelColor)
    static let tertiaryLabel = Color(NSColor.tertiaryLabelColor)
}

extension Color {
    /// Solid color from a `0xRRGGBB` literal.
    init(hex: Int) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// Appearance-adaptive color: `light` under Aqua, `dark` under Dark Aqua.
    /// Re-resolves whenever the rendering view's effective appearance flips, so a
    /// single declaration covers both day and night mode.
    init(light: Int, dark: Int) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}
