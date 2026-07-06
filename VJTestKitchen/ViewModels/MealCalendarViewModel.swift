import Foundation
import Observation

@MainActor
@Observable
final class MealCalendarViewModel {
    static let mealTypes = ["Breakfast", "Lunch", "Dinner", "Snack"]

    let weekDates: [String]
    private(set) var matchingRecipes: [Recipe] = []
    private(set) var isLoading = false
    var errorMessage: String?
    var recipeSearchText = "" {
        didSet {
            guard oldValue != recipeSearchText else { return }
            debouncer.run { [weak self] in await self?.reloadMatchingRecipes() }
        }
    }
    var selectedMealType = "Dinner"
    /// Which day the Quick Planner adds to. Defaults to the first day of the
    /// visible week; the view exposes a day picker so it isn't stuck on "today".
    var selectedPlanningDate: String

    private var mealPlansByDate: [String: [MealPlanWithRecipe]] = [:]
    private let mealPlanService: MealPlanServicing
    private let recipeService: RecipeServicing
    private let debouncer: Debouncer

    /// Matches `.prefix(5)` in `MealCalendarView`'s Quick Planner search results.
    private static let matchingRecipesLimit = 5

    init(
        referenceDate: Date = Date(),
        mealPlanService: MealPlanServicing = MealPlanService(),
        recipeService: RecipeServicing = RecipeService(),
        debounceDelay: Duration = .milliseconds(300)
    ) {
        self.mealPlanService = mealPlanService
        self.recipeService = recipeService
        self.debouncer = Debouncer(delay: debounceDelay)
        let dates = Self.computeWeekDates(from: referenceDate)
        weekDates = dates
        selectedPlanningDate = dates[0]
    }

    func mealPlans(for date: String) -> [MealPlanWithRecipe] {
        mealPlansByDate[date] ?? []
    }

    func load() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let plans = try await mealPlanService.fetchAll()
            mealPlansByDate = Dictionary(grouping: plans, by: \.date)
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    private func reloadMatchingRecipes() async {
        guard !recipeSearchText.isEmpty else {
            matchingRecipes = []
            return
        }
        do {
            matchingRecipes = try await recipeService.fetchPage(
                offset: 0,
                limit: Self.matchingRecipesLimit,
                matching: recipeSearchText
            )
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
