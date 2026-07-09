import Foundation
import Testing
@testable import VJTestKitchen

/// Covers the domain→snapshot mapping (`WidgetSnapshotBuilder`), the App Group
/// store round-trip (`WidgetDataStore`), and the widget deep-link routing
/// (`AppTab(deepLinkHost:)`). The widget *views* aren't unit-tested (SwiftUI
/// layout), but everything feeding them is.
struct WidgetSnapshotTests {

    // MARK: Fixtures

    private func meal(_ id: Int64, _ date: String, _ type: String, _ title: String) -> MealPlanWithRecipe {
        MealPlanWithRecipe(id: id, userId: UUID(), date: date, mealType: type, recipeId: id, createdAt: Date(), recipes: .init(title: title))
    }

    private func recipe(_ id: Int64, _ title: String) -> Recipe {
        Recipe(id: id, userId: nil, title: title, description: nil, instructions: nil, imagePath: nil, prepTime: nil, servings: nil, createdAt: Date())
    }

    private func groceryItem(_ name: String, checked: Bool) -> GroceryItem {
        GroceryItem(id: UUID(), userId: UUID(), name: name, amount: 1, unit: "", category: .other, isChecked: checked, sourceRecipeId: nil, sourceRecipeTitle: nil, createdAt: Date())
    }

    // MARK: Today's meals

    @Test func todaysMealsFiltersToTodayAndOrdersByMealType() {
        let plans = [
            meal(1, "2026-07-08", "Dinner", "Roast Chicken"),
            meal(2, "2026-07-08", "Breakfast", "Oatmeal"),
            meal(3, "2026-07-09", "Lunch", "Tomorrow's Lunch"), // other day, excluded
            meal(4, "2026-07-08", "Lunch", "Caesar Salad"),
        ]
        let snapshot = WidgetSnapshotBuilder.todaysMeals(from: plans, today: "2026-07-08")

        #expect(snapshot.date == "2026-07-08")
        // Ordered Breakfast → Lunch → Dinner, tomorrow's meal dropped.
        #expect(snapshot.meals.map(\.recipeTitle) == ["Oatmeal", "Caesar Salad", "Roast Chicken"])
    }

    @Test func todaysMealsResolvesIconAndCaps() {
        let plans = (0..<10).map { meal(Int64($0), "2026-07-08", "Snack", "Snack \($0)") }
        let snapshot = WidgetSnapshotBuilder.todaysMeals(from: plans, today: "2026-07-08", limit: 3)

        #expect(snapshot.meals.count == 3)
        #expect(snapshot.meals.first?.iconSymbol == MealTypeStyle.icon(for: "Snack"))
    }

    @Test func todaysMealsEmptyWhenNoneToday() {
        let snapshot = WidgetSnapshotBuilder.todaysMeals(from: [meal(1, "2026-07-01", "Dinner", "X")], today: "2026-07-08")
        #expect(snapshot.meals.isEmpty)
        #expect(snapshot.date == "2026-07-08")
    }

    // MARK: Cook's idea

    @Test func cooksIdeaMapsSuggestionAndCapsRecipes() {
        let suggestion = RecipeSuggestion(title: "Quick Winter Warmers", subtitle: "Cozy", symbol: "snowflake", keyword: "soup", maxPrepTime: 30)
        let recipes = (1...5).map { recipe(Int64($0), "Soup \($0)") }
        let snapshot = WidgetSnapshotBuilder.cooksIdea(suggestion: suggestion, recipes: recipes, limit: 3)

        #expect(snapshot.title == "Quick Winter Warmers")
        #expect(snapshot.subtitle == "Cozy")
        #expect(snapshot.symbol == "snowflake")
        #expect(snapshot.recipes.map(\.title) == ["Soup 1", "Soup 2", "Soup 3"])
        #expect(snapshot.recipes.first?.id == 1)
    }

    // MARK: Grocery

    @Test func groceryCountsUncheckedCheckedAndPreview() {
        let items = [
            groceryItem("Milk", checked: false),
            groceryItem("Eggs", checked: true),
            groceryItem("Spinach", checked: false),
            groceryItem("Butter", checked: false),
        ]
        let snapshot = WidgetSnapshotBuilder.grocery(from: items, previewLimit: 2)

        #expect(snapshot.toBuyCount == 3)
        #expect(snapshot.checkedCount == 1)
        #expect(snapshot.totalCount == 4)
        // Preview lists only unchecked names, capped.
        #expect(snapshot.preview == ["Milk", "Spinach"])
    }

    @Test func groceryEmptyList() {
        let snapshot = WidgetSnapshotBuilder.grocery(from: [])
        #expect(snapshot.toBuyCount == 0)
        #expect(snapshot.totalCount == 0)
        #expect(snapshot.preview.isEmpty)
    }

    // MARK: Store round-trip

    @Test func storeRoundTripsEachSnapshot() throws {
        let suiteName = "test.widget.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WidgetDataStore(defaults: defaults)

        // Starts empty.
        #expect(store.cooksIdea == nil)
        #expect(store.todaysMeals == nil)
        #expect(store.grocery == nil)

        let idea = CooksIdeaSnapshot(title: "T", subtitle: "S", symbol: "star", recipes: [.init(id: 7, title: "R")])
        let meals = TodaysMealsSnapshot(date: "2026-07-08", meals: [.init(mealType: "Dinner", recipeTitle: "R", recipeId: 7, iconSymbol: "moon.stars.fill")])
        let grocery = GrocerySnapshot(toBuyCount: 2, checkedCount: 1, totalCount: 3, preview: ["Milk"])

        store.cooksIdea = idea
        store.todaysMeals = meals
        store.grocery = grocery

        #expect(store.cooksIdea == idea)
        #expect(store.todaysMeals == meals)
        #expect(store.grocery == grocery)
    }

    @Test func storeClearsOnNil() throws {
        let suiteName = "test.widget.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WidgetDataStore(defaults: defaults)

        store.grocery = GrocerySnapshot(toBuyCount: 1, checkedCount: 0, totalCount: 1, preview: [])
        #expect(store.grocery != nil)
        store.grocery = nil
        #expect(store.grocery == nil)
    }

    // MARK: Deep-link routing

    @Test func deepLinkHostMapsToTab() {
        #expect(AppTab(deepLinkHost: "home") == .home)
        #expect(AppTab(deepLinkHost: "recipes") == .recipes)
        #expect(AppTab(deepLinkHost: "recipe") == .recipes)
        #expect(AppTab(deepLinkHost: "grocery") == .grocery)
        #expect(AppTab(deepLinkHost: "planner") == .planner)
        #expect(AppTab(deepLinkHost: "calendar") == .calendar)
    }

    @Test func deepLinkHostIgnoresNonNavigationURLs() {
        // The auth redirect (vjtestkitchen://login-callback) must NOT resolve to
        // a tab, so onOpenURL falls through to the auth handler.
        #expect(AppTab(deepLinkHost: "login-callback") == nil)
        #expect(AppTab(deepLinkHost: nil) == nil)
    }

    @Test func publishedDeepLinkURLsMatchHosts() {
        #expect(AppTab(deepLinkHost: WidgetSharedConfig.DeepLink.home.host) == .home)
        #expect(AppTab(deepLinkHost: WidgetSharedConfig.DeepLink.grocery.host) == .grocery)
        #expect(AppTab(deepLinkHost: WidgetSharedConfig.DeepLink.calendar.host) == .calendar)
        #expect(AppTab(deepLinkHost: WidgetSharedConfig.DeepLink.recipes.host) == .recipes)
    }
}
