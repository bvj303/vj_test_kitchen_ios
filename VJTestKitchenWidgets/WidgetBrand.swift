import SwiftUI

/// Brand palette + shared chrome for the widgets. The colors mirror
/// `BrandColor` (Theme.swift), but are redefined here as plain literals so the
/// lightweight widget module needn't pull in the app's `Color.dynamic` /
/// `Platform` shims. If the brand palette changes, update both places.
enum WidgetBrand {
    /// Terracotta — the primary brand accent.
    static let primary = Color(red: 0xE2 / 255, green: 0x60 / 255, blue: 0x3F / 255)
    /// Saffron — warm secondary accent.
    static let saffron = Color(red: 0xE8 / 255, green: 0xA1 / 255, blue: 0x3A / 255)
    /// Sage green — cool tertiary accent.
    static let sage = Color(red: 0x6E / 255, green: 0x8B / 255, blue: 0x5B / 255)

    /// A soft brand-tinted gradient used as a widget's `containerBackground`, so
    /// the widgets read as part of the same "Warm Kitchen" identity as the app.
    static func gradient(_ tint: Color) -> LinearGradient {
        LinearGradient(
            colors: [tint.opacity(0.28), tint.opacity(0.06)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
