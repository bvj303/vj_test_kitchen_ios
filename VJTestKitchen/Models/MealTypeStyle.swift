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

    /// Sort rank for the given meal type so a day's meals read in the order they'd
    /// actually be eaten — Breakfast, Lunch, Dinner, then Snack last. Matching is
    /// case-insensitive; any unknown/custom type sorts after Snack (so a stray type
    /// never jumps ahead of the real meals). See `MealCalendarViewModel.mealPlans`.
    static func sortOrder(for mealType: String) -> Int {
        switch mealType.lowercased() {
        case "breakfast": return 0
        case "lunch": return 1
        case "dinner": return 2
        case "snack": return 3
        default: return 4
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
