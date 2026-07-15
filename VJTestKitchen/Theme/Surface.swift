import SwiftUI

/// The app-wide surface / elevation system.
///
/// Before this existed, container surfaces were applied ad hoc and drifted apart:
/// neutral glass cards on some screens, brand-tinted ("brown") glass at a grab
/// bag of opacities (0.12 / 0.18 / 0.22) on others, `.regularMaterial` on the
/// grocery list, and corner radii of 10 / 16 / 20 with no rationale. That
/// inconsistency was the visual half of a recurring problem.
///
/// This defines a single vocabulary — **two container tiers**, **one radius
/// scale**, **one spacing scale** — so every screen's containers read as one
/// material system. Tiers are built from the existing Liquid Glass mechanism and
/// the existing brand palette (see `Theme.swift`); **no new colors are
/// introduced.** Everything resolves correctly in light and dark because
/// `.glassEffect` and `platformGroupedBackground` are both appearance-aware
/// (Settings exposes the light/dark override).
///
/// Scope: this governs *container* surfaces (screen backgrounds, cards, hero
/// panels). It deliberately does **not** touch semantic accent chips — sage tag
/// pills, saffron rating badges, filter pills — those stay brand-coded per the
/// theming conventions; they're accents, not surface tiers.
enum Surface {
    /// Corner-radius ramp. One scale, used everywhere a surface is rounded.
    enum Radius {
        /// Compact tiles / small chips.
        static let small: CGFloat = 12
        /// Standard cards — the default.
        static let medium: CGFloat = 16
        /// Hero / full-width panels.
        static let large: CGFloat = 20
    }

    /// Spacing ramp for surface interiors and the gaps between them. One scale,
    /// so padding is picked from a fixed set rather than an arbitrary number.
    enum Space {
        static let xSmall: CGFloat = 8
        static let small: CGFloat = 12
        static let medium: CGFloat = 16
        static let large: CGFloat = 20
        static let xLarge: CGFloat = 24
    }
}

/// The container tiers. `background` is applied with `.screenBackground()`; the
/// two elevated tiers with `.surface(_:radius:)`.
enum SurfaceTier {
    /// A resting surface — a neutral glass card. The default for grouped content.
    case card
    /// A primary / hero surface — one consistent, subtle brand tint, so a
    /// screen's headline panel reads as elevated without every screen inventing
    /// its own tint opacity.
    case elevated
}

extension Color {
    /// The single screen-base fill behind all content (system grouped
    /// background: near-black in dark, off-white in light).
    static var surfaceBackground: Color { .platformGroupedBackground }
}

private struct SurfaceModifier: ViewModifier {
    let tier: SurfaceTier
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        switch tier {
        case .card:
            content.glassEffect(.regular, in: shape)
        case .elevated:
            content.glassEffect(.regular.tint(BrandColor.primary.opacity(0.14)), in: shape)
        }
    }
}

extension View {
    /// Wrap a container in one of the app's surface tiers at a chosen radius
    /// (defaults to the standard card radius). Use `.card` for resting grouped
    /// content and `.elevated` for a screen's single hero/headline panel.
    func surface(_ tier: SurfaceTier, radius: CGFloat = Surface.Radius.medium) -> some View {
        modifier(SurfaceModifier(tier: tier, radius: radius))
    }

    /// The app-standard screen background, extended under the safe area. Use on
    /// the root scrollable of every screen so the page base is identical
    /// app-wide. For `List`-based screens, pair with
    /// `.scrollContentBackground(.hidden)`.
    func screenBackground() -> some View {
        background(Color.surfaceBackground.ignoresSafeArea())
    }
}
