import Foundation

/// The selectable app-icon looks — classic Spatch plus a few of his stunt
/// alter egos. Each case maps to an alternate icon set in Assets.xcassets
/// (regenerate them with `scripts/render_app_icon.swift` after art changes)
/// and a small preview imageset for the Settings picker. Pure and stateless,
/// same shape as `SpatchMood`/`MealTypeStyle`.
enum AppIconOption: String, CaseIterable, Identifiable, Sendable {
    case classic
    case pizzaSurf
    case rocketRide
    case balloonRide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: "Classic Spatch"
        case .pizzaSurf: "Pizza Surf"
        case .rocketRide: "Rocket Ride"
        case .balloonRide: "Balloon Ride"
        }
    }

    var subtitle: String {
        switch self {
        case .classic: "Front and center, spoon in hand"
        case .pizzaSurf: "Carving waves on a pepperoni pie"
        case .rocketRide: "Full thrust, straight off the shelf"
        case .balloonRide: "Drifting by on party balloons"
        }
    }

    /// The asset-catalog icon set passed to the system icon switcher — nil
    /// means the primary `AppIcon`. These names must match both the
    /// `.appiconset` folders and `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`
    /// in project.yml.
    var alternateIconName: String? {
        switch self {
        case .classic: nil
        case .pizzaSurf: "AppIconPizza"
        case .rocketRide: "AppIconRocket"
        case .balloonRide: "AppIconBalloon"
        }
    }

    /// The imageset shown as this option's thumbnail in the Settings picker
    /// (alternate `.appiconset`s aren't loadable via `Image(_:)`, so each look
    /// ships a small preview render too).
    var previewImageName: String {
        switch self {
        case .classic: "IconPreviewClassic"
        case .pizzaSurf: "IconPreviewPizza"
        case .rocketRide: "IconPreviewRocket"
        case .balloonRide: "IconPreviewBalloon"
        }
    }

    /// Maps the system's reported alternate-icon name back to an option.
    /// nil (primary) — or a name from a build that no longer ships — reads as
    /// classic.
    static func option(forAlternateIconName name: String?) -> AppIconOption {
        allCases.first { $0.alternateIconName == name } ?? .classic
    }
}
