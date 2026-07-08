import Testing
import SwiftUI
@testable import VJTestKitchen

#if canImport(UIKit)
import UIKit
#endif

struct ThemeTests {
    /// Rounded 0...255 channels for exact-ish comparison without float noise.
    private func channels(_ color: PlatformColor) -> [Int] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a].map { Int(($0 * 255).rounded()) }
    }

    @Test func rgbInitDecodesEachChannel() {
        #expect(channels(PlatformColor(rgb: 0xE2603F)) == [226, 96, 63, 255])
        #expect(channels(PlatformColor(rgb: 0x000000)) == [0, 0, 0, 255])
        #expect(channels(PlatformColor(rgb: 0xFFFFFF)) == [255, 255, 255, 255])
    }

    // The dynamic light/dark resolution below rides UIKit's `UITraitCollection`,
    // which is iOS-only. On macOS the brand palette still resolves per
    // `NSAppearance`, but there's no equivalent synchronous "resolve for style X"
    // API to assert against, so these are iOS-scoped.
    #if canImport(UIKit)
    @Test func brandPrimaryResolvesLightAndDark() {
        let ui = UIColor(Color.brandPrimary)
        let light = ui.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let dark = ui.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        #expect(channels(light) == channels(PlatformColor(rgb: 0xE2603F)))
        #expect(channels(dark) == channels(PlatformColor(rgb: 0xF0764F)))
    }

    @Test func brandSaffronResolvesLightAndDark() {
        let ui = UIColor(Color.brandSaffron)
        #expect(channels(ui.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))) == channels(PlatformColor(rgb: 0xE8A13A)))
        #expect(channels(ui.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))) == channels(PlatformColor(rgb: 0xF0B255)))
    }

    @Test func brandSageResolvesLightAndDark() {
        let ui = UIColor(Color.brandSage)
        #expect(channels(ui.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))) == channels(PlatformColor(rgb: 0x6E8B5B)))
        #expect(channels(ui.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))) == channels(PlatformColor(rgb: 0x8AA876)))
    }
    #endif
}
