import Foundation

/// The single-select "Minimum Rating" filter on the Recipes list, narrowing to
/// recipes with an ATK rating at or above the threshold. Highest-first order,
/// since that's the direction users actually browse ("show me the best ones").
enum MinRatingFilter: String, CaseIterable, Identifiable, Hashable {
    case fourPointFive
    case four
    case threePointFive
    case three

    var id: String { rawValue }

    /// Inclusive lower bound applied server-side (`.gte` on `atk_rating`).
    var minRating: Double {
        switch self {
        case .fourPointFive: return 4.5
        case .four: return 4.0
        case .threePointFive: return 3.5
        case .three: return 3.0
        }
    }

    /// Full label shown in the filter menu.
    var label: String {
        switch self {
        case .fourPointFive: return "4.5+ Stars"
        case .four: return "4.0+ Stars"
        case .threePointFive: return "3.5+ Stars"
        case .three: return "3.0+ Stars"
        }
    }

    /// Compact label shown on the closed filter chip once a value is picked.
    var chipLabel: String {
        String(format: "%.1f+ ★", minRating)
    }
}
