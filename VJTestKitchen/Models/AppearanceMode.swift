import SwiftUI

/// User-facing appearance override for the app. `system` defers to the
/// device's Light/Dark Mode setting; `light`/`dark` pin the app regardless
/// of the device setting.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// `nil` tells SwiftUI's `.preferredColorScheme` to defer to the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
