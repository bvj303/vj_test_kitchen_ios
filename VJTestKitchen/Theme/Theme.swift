import SwiftUI

/// VJ Test Kitchen "Warm Kitchen" brand palette.
///
/// Colors are defined in code (light + dark tuned) so they are usable from any
/// view without a `Bundle` lookup and are unit-testable outside the app process.
/// The asset catalog's `AccentColor` mirrors `primary`, so system chrome (tab-bar
/// selection, nav-bar buttons, `.glassProminent` buttons) picks up the same
/// terracotta automatically without every call site opting in.
///
/// `Color.dynamic(light:dark:)` (see `Platform/PlatformColor.swift`) is the
/// cross-platform primitive — it resolves per appearance on both iOS
/// (`UITraitCollection`) and macOS (`NSAppearance`).
enum BrandColor {
    /// Terracotta — the primary brand accent. Mirrors `AccentColor` in the asset catalog.
    static let primary = Color.dynamic(light: 0xE2603F, dark: 0xF0764F)
    /// Saffron — warm secondary accent (ratings, highlights).
    static let saffron = Color.dynamic(light: 0xE8A13A, dark: 0xF0B255)
    /// Sage green — cool tertiary accent (tags, "fresh" cues).
    static let sage = Color.dynamic(light: 0x6E8B5B, dark: 0x8AA876)
}

extension Color {
    static let brandPrimary = BrandColor.primary
    static let brandSaffron = BrandColor.saffron
    static let brandSage = BrandColor.sage
}
