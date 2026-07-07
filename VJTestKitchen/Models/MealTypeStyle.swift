import SwiftUI

/// Visual treatment for a meal type (Breakfast/Lunch/Dinner/Snack) used by the
/// calendar's meal rows so meals are scannable at a glance — an SF Symbol plus a
/// brand tint per type. Matching is case-insensitive; any unknown/custom string
/// falls back to a neutral fork-and-knife icon in the primary brand color, so a
/// stray meal type can never render blank.
enum MealTypeStyle {
    /// SF Symbol name for the given meal type.
    static func icon(for mealType: String) -> String {
        switch mealType.lowercased() {
        case "breakfast": return "sunrise.fill"
        case "lunch": return "sun.max.fill"
        case "dinner": return "moon.stars.fill"
        case "snack": return "carrot.fill"
        default: return "fork.knife"
        }
    }

    /// Brand tint for the given meal type — mirrors the "Warm Kitchen" palette's
    /// role assignments (see Theme.swift).
    static func tint(for mealType: String) -> Color {
        switch mealType.lowercased() {
        case "breakfast": return .brandSaffron
        case "lunch": return .brandPrimary
        case "dinner": return .brandSage
        default: return .brandPrimary
        }
    }
}
