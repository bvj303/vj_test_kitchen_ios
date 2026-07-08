import SwiftUI

#if canImport(UIKit)
import UIKit
/// The platform's concrete color type (`UIColor` on iOS, `NSColor` on macOS).
typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
typealias PlatformColor = NSColor
#endif

extension PlatformColor {
    /// Builds an opaque sRGB color from a 24-bit `0xRRGGBB` value.
    convenience init(rgb: UInt32) {
        let red = CGFloat((rgb >> 16) & 0xFF) / 255
        let green = CGFloat((rgb >> 8) & 0xFF) / 255
        let blue = CGFloat(rgb & 0xFF) / 255
        #if canImport(UIKit)
        self.init(red: red, green: green, blue: blue, alpha: 1)
        #else
        self.init(srgbRed: red, green: green, blue: blue, alpha: 1)
        #endif
    }
}

extension Color {
    /// A `Color` that resolves to the `light` or `dark` hex per the current
    /// system appearance — the cross-platform primitive the brand palette is
    /// built on (see `Theme.swift`). On iOS this rides `UITraitCollection`; on
    /// macOS it rides `NSAppearance`'s dynamic provider.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { traits in
            PlatformColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
        #elseif canImport(AppKit)
        return Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return PlatformColor(rgb: isDark ? dark : light)
        })
        #endif
    }

    /// The primary window/content background: `systemBackground` on iOS,
    /// `windowBackgroundColor` on macOS.
    static var platformBackground: Color {
        #if canImport(UIKit)
        return Color(uiColor: .systemBackground)
        #elseif canImport(AppKit)
        return Color(nsColor: .windowBackgroundColor)
        #endif
    }

    /// The grouped-content background: `systemGroupedBackground` on iOS,
    /// `underPageBackgroundColor` on macOS (the closest neutral grouped fill).
    static var platformGroupedBackground: Color {
        #if canImport(UIKit)
        return Color(uiColor: .systemGroupedBackground)
        #elseif canImport(AppKit)
        return Color(nsColor: .underPageBackgroundColor)
        #endif
    }
}
