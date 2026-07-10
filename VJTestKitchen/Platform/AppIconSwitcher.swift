import Foundation
#if os(iOS)
import UIKit
#endif

/// Switching the app's icon between `AppIconOption` looks. Main-actor because
/// the real implementation talks to UIApplication; abstracted (like
/// `AuthServicing`) so `SettingsViewModel` stays unit-testable and UIKit-free.
@MainActor
protocol AppIconSwitching {
    /// Whether this platform/device can switch icons at all — macOS has no
    /// alternate-icon API, so the mac app hides the picker entirely.
    var supportsAlternateIcons: Bool { get }
    /// The system's currently applied alternate icon set name (nil = primary).
    var currentAlternateIconName: String? { get }
    /// Applies an alternate icon set by name, or the primary icon for nil.
    func setAlternateIcon(named name: String?) async throws
}

/// The real switcher: UIApplication-backed on iOS/iPadOS, a "not supported"
/// stub on macOS. Lives in Platform/ per the one-shim-layer convention —
/// this is the only file that knows icon switching is an iOS-only concept.
struct AppIconSwitcher: AppIconSwitching {
    #if os(iOS)
    var supportsAlternateIcons: Bool {
        UIApplication.shared.supportsAlternateIcons
    }

    var currentAlternateIconName: String? {
        UIApplication.shared.alternateIconName
    }

    func setAlternateIcon(named name: String?) async throws {
        try await UIApplication.shared.setAlternateIconName(name)
    }
    #else
    var supportsAlternateIcons: Bool { false }
    var currentAlternateIconName: String? { nil }
    func setAlternateIcon(named name: String?) async throws {}
    #endif
}
