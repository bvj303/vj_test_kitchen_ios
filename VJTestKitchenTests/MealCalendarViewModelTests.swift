import Foundation
import Testing
@testable import VJTestKitchen

final class FakeMealPlanService: MealPlanServicing, @unchecked Sendable {
    var plansToReturn: [MealPlanWithRecipe] = []
    var errorToThrow: Error?
    private(set) var createdDrafts: [MealPlanDraft] = []
    private(set) var deletedIds: [Int64] = []

    func fetchAll() async throws -> [MealPlanWithRecipe] {
        if let errorToThrow { throw errorToThrow }
        return plansToReturn
    }

    func create(_ draft: MealPlanDraft) async throws {
        if let errorToThrow { throw errorToThrow }
        createdDrafts.append(draft)
    }

    func delete(id: Int64) async throws {
        if let errorToThrow { throw errorToThrow }
        deletedIds.append(id)
    }
}

final class FakeMealPlanRecipeService: RecipeServicing, @unchecked Sendable {
    var recipesToReturn: [Recipe] = []
    private(set) var fetchedPages: [(offset: Int, limit: Int, search: String?)] = []

    func fetchPage(offset: Int, limit: Int, matching search: String?) async throws -> [Recipe] {
        fetchedPages.append((offset, limit, search))
        let filtered = search.map { term in
            recipesToReturn.filter { $0.title.localizedCaseInsensitiveContains(term) }
        } ?? recipesToReturn
        let start = min(offset, filtered.count)
        let end = min(offset + limit, filtered.count)
        return Array(filtered[start..<end])
    }

    func fetchDetail(id: Int64) async throws -> RecipeDetail { fatalError("not used") }
    func create(_ draft: RecipeDraft) async throws -> Recipe { fatalError("not used") }
    func update(id: Int64, with draft: RecipeDraft) async throws { fatalError("not used") }
    func delete(id: Int64) async throws { fatalError("not used") }
}

private func makePlan(id: Int64, date: String, title: String, mealType: String = "Dinner") -> MealPlanWithRecipe {
    MealPlanWithRecipe(id: id, userId: UUID(), date: date, mealType: mealType, recipeId: 1, createdAt: Date(), recipes: .init(title: title))
}

private struct TestError: Error, LocalizedError {
    var errorDescription: String? { "failed" }
}

@MainActor
struct MealCalendarViewModelTests {
    @Test func weekDatesStartsAtReferenceDateAndSpansSevenDays() {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 5
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let referenceDate = calendar.date(from: components)!

        let viewModel = MealCalendarViewModel(referenceDate: referenceDate, mealPlanService: FakeMealPlanService(), recipeService: FakeMealPlanRecipeService())

        #expect(viewModel.weekDates == ["2026-07-05", "2026-07-06", "2026-07-07", "2026-07-08", "2026-07-09", "2026-07-10", "2026-07-11"])
    }

    @Test func isTodayMatchesFirstWeekDateOnly() {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 5
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let referenceDate = calendar.date(from: components)!

        let viewModel = MealCalendarViewModel(referenceDate: referenceDate, mealPlanService: FakeMealPlanService(), recipeService: FakeMealPlanRecipeService())

        #expect(viewModel.todayDate == "2026-07-05")
        #expect(viewModel.isToday("2026-07-05"))
        #expect(!viewModel.isToday("2026-07-06"))
    }

    @Test func holidayPassesThroughToHolidayProvider() {
        let viewModel = MealCalendarViewModel(mealPlanService: FakeMealPlanService(), recipeService: FakeMealPlanRecipeService())

        #expect(viewModel.holiday(for: "2026-07-04")?.name == "Independence Day")
        #expect(viewModel.holiday(for: "2026-07-07") == nil)
    }

    @Test func selectedPlanningDateDefaultsToFirstDayOfWeek() {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 5
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let referenceDate = calendar.date(from: components)!

        let viewModel = MealCalendarViewModel(referenceDate: referenceDate, mealPlanService: FakeMealPlanService(), recipeService: FakeMealPlanRecipeService())

        #expect(viewModel.selectedPlanningDate == "2026-07-05")
        #expect(viewModel.selectedPlanningDate == viewModel.weekDates.first)
    }

    @Test func loadGroupsMealPlansByDate() async {
        let plans = FakeMealPlanService()
        plans.plansToReturn = [
            makePlan(id: 1, date: "2026-07-05", title: "Tacos"),
            makePlan(id: 2, date: "2026-07-05", title: "Salad"),
            makePlan(id: 3, date: "2026-07-06", title: "Pasta"),
        ]
        let viewModel = MealCalendarViewModel(mealPlanService: plans, recipeService: FakeMealPlanRecipeService())

        await viewModel.load()

        #expect(viewModel.mealPlans(for: "2026-07-05").count == 2)
        #expect(viewModel.mealPlans(for: "2026-07-06").count == 1)
        #expect(viewModel.mealPlans(for: "2026-07-07").isEmpty)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func mealPlansAreOrderedByMealTypeWithSnackLast() async {
        let plans = FakeMealPlanService()
        // Intentionally out of order (and snack not last) as returned by the DB.
        plans.plansToReturn = [
            makePlan(id: 1, date: "2026-07-05", title: "Trail Mix", mealType: "Snack"),
            makePlan(id: 2, date: "2026-07-05", title: "Steak", mealType: "Dinner"),
            makePlan(id: 3, date: "2026-07-05", title: "Pancakes", mealType: "Breakfast"),
            makePlan(id: 4, date: "2026-07-05", title: "Sandwich", mealType: "Lunch"),
        ]
        let viewModel = MealCalendarViewModel(mealPlanService: plans, recipeService: FakeMealPlanRecipeService())

        await viewModel.load()

        #expect(viewModel.mealPlans(for: "2026-07-05").map(\.mealType) == ["Breakfast", "Lunch", "Dinner", "Snack"])
    }

    @Test func mealPlansOrderIsStableForSameMealType() async {
        let plans = FakeMealPlanService()
        plans.plansToReturn = [
            makePlan(id: 3, date: "2026-07-05", title: "Late Dinner", mealType: "Dinner"),
            makePlan(id: 1, date: "2026-07-05", title: "Early Dinner", mealType: "Dinner"),
            makePlan(id: 2, date: "2026-07-05", title: "Mid Dinner", mealType: "Dinner"),
        ]
        let viewModel = MealCalendarViewModel(mealPlanService: plans, recipeService: FakeMealPlanRecipeService())

        await viewModel.load()

        // Same meal type keeps a deterministic order (by id) rather than DB order.
        #expect(viewModel.mealPlans(for: "2026-07-05").map(\.id) == [1, 2, 3])
    }

    @Test func loadSurfacesErrorMessage() async {
        let plans = FakeMealPlanService()
        plans.errorToThrow = TestError()
        let viewModel = MealCalendarViewModel(mealPlanService: plans, recipeService: FakeMealPlanRecipeService())

        await viewModel.load()

        #expect(viewModel.errorMessage == "failed")
    }

    @Test func matchingRecipesFiltersBySearchTextCaseInsensitivelyViaServerSideSearch() async {
        let recipes = FakeMealPlanRecipeService()
        recipes.recipesToReturn = [
            Recipe(id: 1, userId: nil, title: "Carbonara", description: nil, instructions: nil, imagePath: nil, prepTime: nil, servings: nil, createdAt: Date()),
            Recipe(id: 2, userId: nil, title: "Beef Tacos", description: nil, instructions: nil, imagePath: nil, prepTime: nil, servings: nil, createdAt: Date()),
        ]
        let viewModel = MealCalendarViewModel(mealPlanService: FakeMealPlanService(), recipeService: recipes, debounceDelay: .zero)
        await viewModel.load()

        #expect(viewModel.matchingRecipes.isEmpty)

        viewModel.recipeSearchText = "taco"
        try? await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.matchingRecipes.map(\.title) == ["Beef Tacos"])
        #expect(recipes.fetchedPages.last?.search == "taco")
        #expect(recipes.fetchedPages.last?.limit == 5)
    }

    @Test func addMealPlanCallsServiceThenReloads() async {
        let plans = FakeMealPlanService()
        let viewModel = MealCalendarViewModel(mealPlanService: plans, recipeService: FakeMealPlanRecipeService())
        viewModel.selectedMealType = "Lunch"

        await viewModel.addMealPlan(date: "2026-07-05", recipeId: 9)

        #expect(plans.createdDrafts.count == 1)
        #expect(plans.createdDrafts.first?.date == "2026-07-05")
        #expect(plans.createdDrafts.first?.mealType == "Lunch")
        #expect(plans.createdDrafts.first?.recipeId == 9)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func deleteMealPlanCallsServiceThenReloads() async {
        let plans = FakeMealPlanService()
        let viewModel = MealCalendarViewModel(mealPlanService: plans, recipeService: FakeMealPlanRecipeService())

        await viewModel.deleteMealPlan(5)

        #expect(plans.deletedIds == [5])
    }
}

struct MealTypeStyleTests {
    @Test func iconMapsKnownMealTypesCaseInsensitively() {
        #expect(MealTypeStyle.icon(for: "Breakfast") == "sunrise.fill")
        #expect(MealTypeStyle.icon(for: "lunch") == "sun.max.fill")
        #expect(MealTypeStyle.icon(for: "DINNER") == "moon.stars.fill")
        #expect(MealTypeStyle.icon(for: "Snack") == "carrot.fill")
    }

    @Test func iconFallsBackForUnknownMealType() {
        #expect(MealTypeStyle.icon(for: "Brunch") == "fork.knife")
        #expect(MealTypeStyle.icon(for: "") == "fork.knife")
    }

    @Test func sortOrderRunsBreakfastLunchDinnerThenSnackLast() {
        let ordered = ["Snack", "Dinner", "Breakfast", "Lunch"]
            .sorted { MealTypeStyle.sortOrder(for: $0) < MealTypeStyle.sortOrder(for: $1) }
        #expect(ordered == ["Breakfast", "Lunch", "Dinner", "Snack"])
    }

    @Test func sortOrderIsCaseInsensitiveAndPlacesUnknownAfterSnack() {
        #expect(MealTypeStyle.sortOrder(for: "BREAKFAST") == MealTypeStyle.sortOrder(for: "breakfast"))
        #expect(MealTypeStyle.sortOrder(for: "Brunch") > MealTypeStyle.sortOrder(for: "Snack"))
    }
}
