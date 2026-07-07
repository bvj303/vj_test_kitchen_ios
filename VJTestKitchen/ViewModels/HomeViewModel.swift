import Foundation
import Observation

/// Backs the Home tab: a context-aware suggested-recipes shelf plus a few
/// glanceable numbers (catalog size, meals planned this week, grocery items
/// left). Follows the Service/`@Observable` pattern used across the app — all
/// data comes through injected services so the whole thing is unit-testable
/// without a network or a session.
@MainActor
@Observable
final class HomeViewModel {
    /// The calendar-derived cooking suggestion (weeknight/weekend + season).
    /// Computed once from the reference date, since the Home screen is
    /// re-created on tab switch anyway.
    let suggestion: RecipeSuggestion

    private(set) var suggestedRecipes: [Recipe] = []
    /// This week's planned meals (the 7 days from the reference date), ordered
    /// by day then meal type — a compact preview of the Calendar.
    private(set) var weekMeals: [MealPlanWithRecipe] = []
    /// Total recipes in the catalog. Nil until loaded (or if the count fails —
    /// a missing stat just hides, it never errors the screen).
    private(set) var totalRecipeCount: Int?
    private(set) var uncheckedGroceryCount = 0
    private(set) var isLoading = false
    var errorMessage: String?

    /// The 7 "yyyy-MM-dd" strings of the reference week (UTC), matching how the
    /// Calendar computes its week so day membership lines up exactly.
    let weekDates: [String]

    private let recipeService: RecipeServicing
    private let mealPlanService: MealPlanServicing
    private let groceryService: GroceryItemServicing

    /// How many recipes the suggested shelf pulls.
    private static let suggestedLimit = 10

    init(
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        recipeService: RecipeServicing = RecipeService(),
        mealPlanService: MealPlanServicing = MealPlanService(),
        groceryService: GroceryItemServicing = GroceryItemService()
    ) {
        self.recipeService = recipeService
        self.mealPlanService = mealPlanService
        self.groceryService = groceryService
        self.suggestion = RecipeSuggester.suggestion(for: referenceDate, calendar: calendar)
        self.weekDates = Self.computeWeekDates(from: referenceDate)
    }

    /// Number of meals planned across the reference week — drives a stat tile.
    var mealsThisWeekCount: Int { weekMeals.count }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        // Loaded independently so one failing section (e.g. an empty grocery
        // table) never blanks the others; the primary loads surface an error.
        await loadSuggestedRecipes()
        await loadWeekMeals()
        await loadTotalCount()
        await loadGrocery()
    }

    private func loadSuggestedRecipes() async {
        do {
            var recipes = try await recipeService.fetchPage(
                offset: 0, limit: Self.suggestedLimit,
                matching: suggestion.keyword, tag: nil, maxPrepTime: suggestion.maxPrepTime
            )
            // The seasonal keyword might match nothing in a small/partial
            // catalog — fall back to a plain page so the shelf is never empty
            // just because "grilled" isn't in the imported subset.
            if recipes.isEmpty {
                recipes = try await recipeService.fetchPage(offset: 0, limit: Self.suggestedLimit, matching: nil)
            }
            suggestedRecipes = recipes
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    private func loadWeekMeals() async {
        do {
            let all = try await mealPlanService.fetchAll()
            let weekSet = Set(weekDates)
            weekMeals = all
                .filter { weekSet.contains($0.date) }
                .sorted { lhs, rhs in
                    if lhs.date != rhs.date { return lhs.date < rhs.date }
                    let lhsOrder = MealTypeStyle.sortOrder(for: lhs.mealType)
                    let rhsOrder = MealTypeStyle.sortOrder(for: rhs.mealType)
                    if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
                    return lhs.id < rhs.id
                }
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    private func loadTotalCount() async {
        // A count failure shouldn't error the whole screen — the tile just hides.
        totalRecipeCount = try? await recipeService.totalCount()
    }

    private func loadGrocery() async {
        if let items = try? await groceryService.fetchAll() {
            uncheckedGroceryCount = items.filter { !$0.isChecked }.count
        }
    }

    private static func computeWeekDates(from date: Date) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return (0..<7).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: date)!
            return MealPlan.dateFormatter.string(from: day)
        }
    }
}
