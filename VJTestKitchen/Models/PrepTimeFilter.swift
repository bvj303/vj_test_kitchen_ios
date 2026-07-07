import Foundation

/// The single-select Prep Time filter on the Recipes list. Most options are
/// upper bounds ("30 min or less"); "Long Cooks" and "Overnight" are *lower*
/// bounds for finding slow / make-ahead recipes. Each option decomposes to an
/// inclusive `(minMinutes, maxMinutes)` range that `RecipeService.fetchPage`
/// applies server-side (`.gte` / `.lte` on `prep_time`).
enum PrepTimeFilter: String, CaseIterable, Identifiable, Hashable {
    case under30
    case under45
    case under60
    case longCooks
    case overnight

    var id: String { rawValue }

    /// Inclusive lower bound in minutes, or nil for no lower bound.
    var minMinutes: Int? {
        switch self {
        case .under30, .under45, .under60: return nil
        case .longCooks: return 120   // 2 hr+
        case .overnight: return 480    // 8 hr+
        }
    }

    /// Inclusive upper bound in minutes, or nil for no upper bound.
    var maxMinutes: Int? {
        switch self {
        case .under30: return 30
        case .under45: return 45
        case .under60: return 60
        case .longCooks, .overnight: return nil
        }
    }

    /// Full label shown in the Prep Time menu.
    var label: String {
        switch self {
        case .under30: return "30 min or less"
        case .under45: return "45 min or less"
        case .under60: return "1 hr or less"
        case .longCooks: return "Long Cooks (2 hr+)"
        case .overnight: return "Overnight (8 hr+)"
        }
    }

    /// Compact label shown on the closed filter chip once a value is picked.
    var chipLabel: String {
        switch self {
        case .under30: return "≤ 30 min"
        case .under45: return "≤ 45 min"
        case .under60: return "≤ 1 hr"
        case .longCooks: return "Long Cooks"
        case .overnight: return "Overnight"
        }
    }
}
