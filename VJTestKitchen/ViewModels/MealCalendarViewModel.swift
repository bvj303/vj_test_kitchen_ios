import Foundation
import Observation

@MainActor
@Observable
final class MealCalendarViewModel {
    static let mealTypes = ["Breakfast", "Lunch", "Dinner", "Snack"]

    /// The 7 "yyyy-MM-dd" days currently shown. Starts at the reference date and
    /// shifts a week at a time via the navigation methods, so the user can plan
    /// ahead (or look back) instead of being stuck on the current week.
    private(set) var weekDates: [String]
    /// Whole weeks the visible window is offset from the reference week (0 = the
    /// week containing today). Drives the ‹/› navigation and the "This Week" jump.
    private(set) var weekOffset = 0
    /// The "yyyy-MM-dd" string for the real today (from the reference date),
    /// independent of which week is shown — so "today" only highlights when the
    /// current week is in view.
    let todayDate: String

    /// True when the visible window is the week containing today.
    var isCurrentWeek: Bool { weekOffset == 0 }
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

    /// The week's forecasts keyed by "yyyy-MM-dd", populated by `loadWeather()`
    /// when the user has opted into location-based weather. Empty otherwise (or
    /// when the fetch fails) — weather is a supplementary outlook, never required.
    private(set) var forecastByDate: [String: DailyForecast] = [:]

    private var mealPlansByDate: [String: [MealPlanWithRecipe]] = [:]
    /// Kept so the week window can be recomputed for a new offset.
    private let referenceDate: Date
    private let mealPlanService: MealPlanServicing
    private let recipeService: RecipeServicing
    private let weatherForecaster: WeatherForecasting
    private let weatherPreferenceStore: WeatherPreferenceStoring
    private let debouncer: Debouncer

    /// Matches `.prefix(5)` in `MealCalendarView`'s Quick Planner search results.
    private static let matchingRecipesLimit = 5

    init(
        referenceDate: Date = Date(),
        mealPlanService: MealPlanServicing = MealPlanService(),
        recipeService: RecipeServicing = RecipeService(),
        weatherForecaster: WeatherForecasting = OpenMeteoForecastService(),
        weatherPreferenceStore: WeatherPreferenceStoring = UserDefaultsWeatherPreferenceStore(),
        debounceDelay: Duration = .milliseconds(300)
    ) {
        self.mealPlanService = mealPlanService
        self.recipeService = recipeService
        self.weatherForecaster = weatherForecaster
        self.weatherPreferenceStore = weatherPreferenceStore
        self.debouncer = Debouncer(delay: debounceDelay)
        self.referenceDate = referenceDate
        let dates = Self.computeWeekDates(from: referenceDate, weekOffset: 0)
        weekDates = dates
        todayDate = dates[0]
        selectedPlanningDate = dates[0]
    }

    // MARK: - Week navigation

    /// Move the visible window one week earlier.
    func goToPreviousWeek() { shiftWeek(to: weekOffset - 1) }
    /// Move the visible window one week later.
    func goToNextWeek() { shiftWeek(to: weekOffset + 1) }
    /// Jump back to the week containing today.
    func goToThisWeek() { shiftWeek(to: 0) }

    private func shiftWeek(to newOffset: Int) {
        guard newOffset != weekOffset else { return }
        weekOffset = newOffset
        weekDates = Self.computeWeekDates(from: referenceDate, weekOffset: newOffset)
        // Keep the Quick Planner's target day inside the visible week.
        if !weekDates.contains(selectedPlanningDate) {
            selectedPlanningDate = weekDates[0]
        }
        // No weather refetch here: the outlook is keyed to the fixed home
        // location and only spans ~10 days from today, so paging to another
        // week can't surface new forecast data — refetching (and, previously,
        // taking a fresh GPS fix) on every ‹/› tap was wasted work.
    }

    /// The forecast (if any) for the given "yyyy-MM-dd" string, so the schedule
    /// view can show a weather badge beside that day. Pure lookup.
    func forecast(for date: String) -> DailyForecast? {
        forecastByDate[date]
    }

    /// A day's meals ordered as they'd be eaten — Breakfast, Lunch, Dinner, then
    /// Snack (and any unknown type) last, via `MealTypeStyle.sortOrder`. Ties within
    /// the same meal type fall back to `id` so the order is stable across reloads
    /// rather than following the DB's fetch order.
    func mealPlans(for date: String) -> [MealPlanWithRecipe] {
        (mealPlansByDate[date] ?? []).sorted { lhs, rhs in
            let lhsOrder = MealTypeStyle.sortOrder(for: lhs.mealType)
            let rhsOrder = MealTypeStyle.sortOrder(for: rhs.mealType)
            if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
            return lhs.id < rhs.id
        }
    }

    /// Whether the given "yyyy-MM-dd" string is today, for highlighting the
    /// current day in the week view.
    func isToday(_ date: String) -> Bool {
        date == todayDate
    }

    /// The holiday (if any) falling on the given "yyyy-MM-dd" string, so the
    /// schedule view can flag it alongside that day's meals. Pure lookup — see
    /// `HolidayProvider`.
    func holiday(for date: String) -> Holiday? {
        HolidayProvider.holiday(for: date)
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
        await loadWeather()
    }

    /// Loads the weather outlook for the saved home location, if the user has
    /// set one (see `HomeLocationViewModel`). No live GPS — the forecast is
    /// keyed to the stored home coordinate, so this is a single network call and
    /// safe to call on load/foreground without a per-visit location fix.
    /// Failures (network, provider error) are swallowed into an empty forecast
    /// rather than raising the meal-plan error alert — weather is a nice-to-have.
    func loadWeather() async {
        guard let home = weatherPreferenceStore.loadHomeLocation() else {
            forecastByDate = [:]
            return
        }
        do {
            let forecasts = try await weatherForecaster.dailyForecast(for: home.coordinate)
            forecastByDate = Dictionary(forecasts.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        } catch {
            forecastByDate = [:]
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

    private static func computeWeekDates(from date: Date, weekOffset: Int) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.date(byAdding: .day, value: weekOffset * 7, to: date)!
        return (0..<7).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: start)!
            return MealPlan.dateFormatter.string(from: day)
        }
    }
}
