import Foundation
import Testing
@testable import VJTestKitchen

/// Records the filters each `fetchPage` was called with so tests can assert the
/// suggestion's keyword/prep-time actually reach the query, plus the empty-result
/// fallback to an unfiltered page.
final class FakeHomeRecipeService: RecipeServicing, @unchecked Sendable {
    /// Keyed by the `matching` term (nil → ""), so a test can return matches for
    /// the keyword query and/or the fallback independently.
    var pagesByKeyword: [String: [Recipe]] = [:]
    var countToReturn = 0
    private(set) var fetchedPages: [(offset: Int, limit: Int, search: String?, tag: String?, maxPrepTime: Int?)] = []

    func fetchPage(offset: Int, limit: Int, matching search: String?, tag: String?, maxPrepTime: Int?) async throws -> [Recipe] {
        fetchedPages.append((offset, limit, search, tag, maxPrepTime))
        return pagesByKeyword[search ?? "", default: []]
    }

    func totalCount() async throws -> Int { countToReturn }
    func fetchDetail(id: Int64) async throws -> RecipeDetail { fatalError("not used") }
    func create(_ draft: RecipeDraft) async throws -> Recipe { fatalError("not used") }
    func update(id: Int64, with draft: RecipeDraft) async throws { fatalError("not used") }
    func delete(id: Int64) async throws { fatalError("not used") }
}

final class FakeHomeMealPlanService: MealPlanServicing, @unchecked Sendable {
    var plansToReturn: [MealPlanWithRecipe] = []
    var errorToThrow: Error?

    func fetchAll() async throws -> [MealPlanWithRecipe] {
        if let errorToThrow { throw errorToThrow }
        return plansToReturn
    }
    func create(_ draft: MealPlanDraft) async throws {}
    func delete(id: Int64) async throws {}
}

final class FakeHomeGroceryService: GroceryItemServicing, @unchecked Sendable {
    var itemsToReturn: [GroceryItem] = []

    func fetchAll() async throws -> [GroceryItem] { itemsToReturn }
    func add(_ draft: GroceryItemDraft) async throws -> GroceryItem { fatalError("not used") }
    func addMany(_ drafts: [GroceryItemDraft]) async throws -> [GroceryItem] { fatalError("not used") }
    func setChecked(id: UUID, isChecked: Bool) async throws {}
    func setCategory(id: UUID, category: GroceryCategory) async throws {}
    func delete(id: UUID) async throws {}
    func clearAll() async throws {}
}

private func makeRecipe(_ id: Int64, _ title: String) -> Recipe {
    Recipe(id: id, userId: nil, title: title, description: nil, instructions: nil, imagePath: nil, prepTime: 25, servings: 4, createdAt: Date())
}

private func makePlan(id: Int64, date: String, title: String, mealType: String = "Dinner") -> MealPlanWithRecipe {
    MealPlanWithRecipe(id: id, userId: UUID(), date: date, mealType: mealType, recipeId: 1, createdAt: Date(), recipes: .init(title: title))
}

private func makeGroceryItem(_ name: String, checked: Bool) -> GroceryItem {
    GroceryItem(id: UUID(), userId: UUID(), name: name, amount: 1, unit: "", category: .other, isChecked: checked, sourceRecipeId: nil, sourceRecipeTitle: nil, createdAt: Date())
}

private struct TestError: Error, LocalizedError {
    var errorDescription: String? { "failed" }
}

@MainActor
struct HomeViewModelTests {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// A Tuesday in July → summer weeknight; week is 2026-07-07 … 2026-07-13.
    private var referenceDate: Date {
        utcCalendar.date(from: DateComponents(year: 2026, month: 7, day: 7))!
    }

    private func makeViewModel(
        recipes: FakeHomeRecipeService = FakeHomeRecipeService(),
        meals: FakeHomeMealPlanService = FakeHomeMealPlanService(),
        grocery: FakeHomeGroceryService = FakeHomeGroceryService()
    ) -> HomeViewModel {
        HomeViewModel(
            referenceDate: referenceDate, calendar: utcCalendar,
            recipeService: recipes, mealPlanService: meals, groceryService: grocery
        )
    }

    @Test func suggestionReflectsReferenceDate() {
        let viewModel = makeViewModel()
        #expect(viewModel.suggestion.title == "Light Summer Suppers")
        #expect(viewModel.suggestion.keyword == "salad")
        #expect(viewModel.suggestion.maxPrepTime == 30)
    }

    @Test func weekDatesSpanReferenceWeek() {
        let viewModel = makeViewModel()
        #expect(viewModel.weekDates == ["2026-07-07", "2026-07-08", "2026-07-09", "2026-07-10", "2026-07-11", "2026-07-12", "2026-07-13"])
    }

    @Test func loadPassesSuggestionFiltersToQuery() async {
        let recipes = FakeHomeRecipeService()
        recipes.pagesByKeyword = ["salad": [makeRecipe(1, "Greek Salad")]]
        let viewModel = makeViewModel(recipes: recipes)

        await viewModel.load()

        #expect(viewModel.suggestedRecipes.map(\.title) == ["Greek Salad"])
        let first = recipes.fetchedPages.first
        #expect(first?.search == "salad")
        #expect(first?.maxPrepTime == 30)
    }

    @Test func loadFallsBackToUnfilteredPageWhenKeywordMatchesNothing() async {
        let recipes = FakeHomeRecipeService()
        // Keyword ("salad") returns nothing; the unfiltered fallback (nil) does.
        recipes.pagesByKeyword = ["": [makeRecipe(9, "Anything")]]
        let viewModel = makeViewModel(recipes: recipes)

        await viewModel.load()

        #expect(viewModel.suggestedRecipes.map(\.title) == ["Anything"])
        // Two calls: the keyword query, then the unfiltered fallback.
        #expect(recipes.fetchedPages.count == 2)
        #expect(recipes.fetchedPages.last?.search == nil)
    }

    @Test func loadKeepsOnlyThisWeeksMealsSortedByDayThenMealType() async {
        let meals = FakeHomeMealPlanService()
        meals.plansToReturn = [
            makePlan(id: 1, date: "2026-07-08", title: "Tacos", mealType: "Dinner"),
            makePlan(id: 2, date: "2026-07-08", title: "Eggs", mealType: "Breakfast"),
            makePlan(id: 3, date: "2026-07-07", title: "Soup", mealType: "Dinner"),
            makePlan(id: 4, date: "2026-06-30", title: "Old Meal"),        // before the week
            makePlan(id: 5, date: "2026-07-20", title: "Future Meal"),     // after the week
        ]
        let viewModel = makeViewModel(meals: meals)

        await viewModel.load()

        // Only in-week meals, ordered by date then meal type (Breakfast before Dinner).
        #expect(viewModel.weekMeals.map(\.recipeTitle) == ["Soup", "Eggs", "Tacos"])
        #expect(viewModel.mealsThisWeekCount == 3)
    }

    @Test func loadPopulatesCountAndUncheckedGrocery() async {
        let recipes = FakeHomeRecipeService()
        recipes.countToReturn = 14_601
        let grocery = FakeHomeGroceryService()
        grocery.itemsToReturn = [
            makeGroceryItem("Milk", checked: false),
            makeGroceryItem("Eggs", checked: true),
            makeGroceryItem("Bread", checked: false),
        ]
        let viewModel = makeViewModel(recipes: recipes, grocery: grocery)

        await viewModel.load()

        #expect(viewModel.totalRecipeCount == 14_601)
        #expect(viewModel.uncheckedGroceryCount == 2)
    }

    @Test func loadSurfacesMealPlanError() async {
        let meals = FakeHomeMealPlanService()
        meals.errorToThrow = TestError()
        let viewModel = makeViewModel(meals: meals)

        await viewModel.load()

        #expect(viewModel.errorMessage == "failed")
    }
}
