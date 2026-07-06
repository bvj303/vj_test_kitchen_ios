import Foundation

/// Note: `date` is kept as a plain "yyyy-MM-dd" string matching Postgres's
/// `date` column, rather than `Date` — the shared SupabaseDecoding strategy
/// is timestamp-oriented (ISO8601 with time), so a date-only column needs
/// its own formatter (`MealPlan.dateFormatter`) rather than sharing that one.
struct MealPlan: Codable, Identifiable, Sendable, Hashable {
    let id: Int64
    var userId: UUID
    var date: String
    var mealType: String
    var recipeId: Int64
    let createdAt: Date

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}

struct MealPlanInsert: Codable, Sendable {
    var userId: UUID
    var date: String
    var mealType: String
    var recipeId: Int64
}

/// User-facing fields — no `id`/`userId`/`createdAt`. `MealPlanService`
/// resolves the current user internally, same pattern as `RecipeDraft`.
struct MealPlanDraft: Sendable {
    var date: String
    var mealType: String
    var recipeId: Int64
}

/// Meal plan joined with its recipe's title, matching
/// `meal_plans.select("*, recipes(title)")`.
struct MealPlanWithRecipe: Codable, Identifiable, Sendable, Hashable {
    let id: Int64
    var userId: UUID
    var date: String
    var mealType: String
    var recipeId: Int64
    let createdAt: Date
    var recipes: RecipeTitle

    var recipeTitle: String { recipes.title }

    struct RecipeTitle: Codable, Sendable, Hashable {
        var title: String
    }
}
