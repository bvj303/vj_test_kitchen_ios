import Foundation

/// The denormalized payloads the app publishes for the home-screen / desktop
/// widgets. Deliberately **plain primitive value types with no app-layer
/// dependencies** (no `MealTypeStyle`, `Theme`, etc.) so this file can compile
/// into the lightweight widget-extension module unchanged — the widget only
/// *decodes* these, while the app *builds* them (see `WidgetSnapshotBuilder`,
/// which owns the domain→snapshot mapping that does depend on app types).
///
/// Each maps to one widget in the bundle. All are `Codable` so `WidgetDataStore`
/// can round-trip them through the shared App Group container as JSON.

/// Backs the **Cook's Idea** widget — the calendar/weather-derived suggestion
/// from `RecipeSuggester`, plus a few matching recipe titles.
struct CooksIdeaSnapshot: Codable, Equatable, Sendable {
    struct Recipe: Codable, Equatable, Sendable {
        var id: Int64
        var title: String
    }
    /// Suggestion headline, e.g. "Quick Winter Warmers".
    var title: String
    /// One-line rationale, e.g. "Fast, cozy dinners for a chilly weeknight".
    var subtitle: String
    /// SF Symbol summarizing the vibe.
    var symbol: String
    /// A handful of matching recipes to feature.
    var recipes: [Recipe]
}

/// Backs the **Today's Meals** widget — the current day's planned meals.
struct TodaysMealsSnapshot: Codable, Equatable, Sendable {
    struct Meal: Codable, Equatable, Sendable {
        /// Display label, e.g. "Dinner".
        var mealType: String
        var recipeTitle: String
        var recipeId: Int64
        /// SF Symbol for the meal type, resolved app-side via `MealTypeStyle`
        /// and carried here so the widget needn't depend on that app type.
        var iconSymbol: String
    }
    /// The "yyyy-MM-dd" day (UTC, matching `meal_plans.date`) these meals cover,
    /// so the widget can tell a stale snapshot from an empty day.
    var date: String
    var meals: [Meal]
}

/// Backs the **Grocery List** widget — how much is left to buy, plus a preview.
struct GrocerySnapshot: Codable, Equatable, Sendable {
    /// Unchecked (still-to-buy) item count — the headline number.
    var toBuyCount: Int
    /// Checked-off item count.
    var checkedCount: Int
    /// Total items on the list (`toBuyCount + checkedCount`).
    var totalCount: Int
    /// Names of the first few still-to-buy items, for the medium/large layouts.
    var preview: [String]
}
