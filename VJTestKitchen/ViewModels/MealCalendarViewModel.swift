import Foundation
import Observation

@MainActor
@Observable
final class MealCalendarViewModel {
    static let mealTypes = ["Breakfast", "Lunch", "Dinner", "Snack"]

    let weekDates: [String]
    private(set) var allRecipes: [Recipe] = []
    private(set) var isLoading = false
    var errorMessage: String?
    var recipeSearchText = ""
    var selectedMealType = "Dinner"
    /// Which day the Quick Planner adds to. Defaults to the first day of the
    /// visible week; the view exposes a day picker so it isn't stuck on "today".
    var selectedPlanningDate: String

    private var mealPlansByDate: [String: [MealPlanWithRecipe]] = [:]
    private let mealPlanService: MealPlanServicing
    private let recipeService: RecipeServicing

    init(
        referenceDate: Date = Date(),
        mealPlanService: MealPlanServicing = MealPlanService(),
        recipeService: RecipeServicing = RecipeService()
    ) {
        self.mealPlanService = mealPlanService
        self.recipeService = recipeService
        let dates = Self.computeWeekDates(from: referenceDate)
        weekDates = dates
        selectedPlanningDate = dates[0]
    }

    var matchingRecipes: [Recipe] {
        guard !recipeSearchText.isEmpty else { return [] }
        return allRecipes.filter { $0.title.localizedCaseInsensitiveContains(recipeSearchText) }
    }

    func mealPlans(for date: String) -> [MealPlanWithRecipe] {
        mealPlansByDate[date] ?? []
    }

    func load() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            async let plansTask = mealPlanService.fetchAll()
            async let recipesTask = recipeService.fetchAll()
            let (plans, recipes) = try await (plansTask, recipesTask)
            mealPlansByDate = Dictionary(grouping: plans, by: \.date)
            allRecipes = recipes
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    func addMealPlan(date: String, recipeId: Int64) async {
        errorMessage = nil
        do {
            try await mealPlanService.create(MealPlanDraft(date: date, mealType: selectedMealType, recipeId: recipeId))
            await load()
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    func deleteMealPlan(_ id: Int64) async {
        errorMessage = nil
        do {
            try await mealPlanService.delete(id: id)
            await load()
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
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
