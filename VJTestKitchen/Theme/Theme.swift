import SwiftUI
import UIKit

/// VJ Test Kitchen "Warm Kitchen" brand palette.
///
/// Colors are defined in code (light + dark tuned) so they are usable from any
/// view without a `Bundle` lookup and are unit-testable outside the app process.
/// The asset catalog's `AccentColor` mirrors `primary`, so system chrome (tab-bar
/// selection, nav-bar buttons, `.glassProminent` buttons) picks up the same
/// terracotta automatically without every call site opting in.
enum BrandColor {
    /// Terracotta — the primary brand accent. Mirrors `AccentColor` in the asset catalog.
    static let primary = dynamic(light: 0xE2603F, dark: 0xF0764F)
    /// Saffron — warm secondary accent (ratings, highlights).
    static let saffron = dynamic(light: 0xE8A13A, dark: 0xF0B255)
    /// Sage green — cool tertiary accent (tags, "fresh" cues).
    static let sage = dynamic(light: 0x6E8B5B, dark: 0x8AA876)

    /// A `Color` that resolves to the `light` or `dark` hex per the current appearance.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension Color {
    static let brandPrimary = BrandColor.primary
    static let brandSaffron = BrandColor.saffron
    static let brandSage = BrandColor.sage
}

extension UIColor {
    /// Builds an opaque color from a 24-bit `0xRRGGBB` value.
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
