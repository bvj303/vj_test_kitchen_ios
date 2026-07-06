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

    func fetchAll() async throws -> [Recipe] { recipesToReturn }
    func fetchDetail(id: Int64) async throws -> RecipeDetail { fatalError("not used") }
    func create(_ draft: RecipeDraft) async throws -> Recipe { fatalError("not used") }
    func update(id: Int64, with draft: RecipeDraft) async throws { fatalError("not used") }
    func delete(id: Int64) async throws { fatalError("not used") }
}

private func makePlan(id: Int64, date: String, title: String) -> MealPlanWithRecipe {
    MealPlanWithRecipe(id: id, userId: UUID(), date: date, mealType: "Dinner", recipeId: 1, createdAt: Date(), recipes: .init(title: title))
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

    @Test func loadSurfacesErrorMessage() async {
        let plans = FakeMealPlanService()
        plans.errorToThrow = TestError()
        let viewModel = MealCalendarViewModel(mealPlanService: plans, recipeService: FakeMealPlanRecipeService())

        await viewModel.load()

        #expect(viewModel.errorMessage == "failed")
    }

    @Test func matchingRecipesFiltersBySearchTextCaseInsensitively() async {
        let recipes = FakeMealPlanRecipeService()
        recipes.recipesToReturn = [
            Recipe(id: 1, userId: nil, title: "Carbonara", description: nil, instructions: nil, imagePath: nil, prepTime: nil, servings: nil, createdAt: Date()),
            Recipe(id: 2, userId: nil, title: "Beef Tacos", description: nil, instructions: nil, imagePath: nil, prepTime: nil, servings: nil, createdAt: Date()),
        ]
        let viewModel = MealCalendarViewModel(mealPlanService: FakeMealPlanService(), recipeService: recipes)
        await viewModel.load()

        #expect(viewModel.matchingRecipes.isEmpty)

        viewModel.recipeSearchText = "taco"
        #expect(viewModel.matchingRecipes.map(\.title) == ["Beef Tacos"])
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
