import Foundation
import Observation

@MainActor
@Observable
final class MealCalendarViewModel {
    static let mealTypes = ["Breakfast", "Lunch", "Dinner", "Snack"]

    /// The 7 "yyyy-MM-dd" days currently shown. Starts at today and shifts a
    /// week at a time via the navigation methods, so the user can plan ahead
    /// (or look back) instead of being stuck on the current week.
    private(set) var weekDates: [String]
    /// Whole weeks the visible window is offset from the reference week (0 = the
    /// week containing today). Drives the ‹/› navigation and the "This Week" jump.
    private(set) var weekOffset = 0
    /// The "yyyy-MM-dd" string for the real today, independent of which week is
    /// shown — so "today" only highlights when the current week is in view.
    /// Derived from the **user's local calendar day**, not UTC — keying to UTC
    /// flipped "today" to tomorrow during the evening for anyone west of UTC
    /// (UTC midnight is 7–8pm in US time zones, prime cooking time). Recomputed
    /// on every `load()` (which also runs on foreground) so an app left
    /// suspended overnight rolls over instead of highlighting yesterday.
    private(set) var todayDate: String

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
    /// Wall clock, injectable for tests — read fresh (never stored as a `Date`)
    /// so "today" tracks real time across day rollovers while the app lives on.
    private let now: () -> Date
    /// Formats a `Date` as its "yyyy-MM-dd" day **in the user's time zone**
    /// (injectable for tests) — see `todayDate`'s note on why this isn't UTC.
    private let dayFormatter: DateFormatter
    private let calendar: Calendar
    private let mealPlanService: MealPlanServicing
    private let recipeService: RecipeServicing
    private let weatherForecaster: WeatherForecasting
    private let weatherPreferenceStore: WeatherPreferenceStoring
    private let widgetPublisher: WidgetPublishing
    private let snapshotStore: LocalSnapshotStoring
    private let debouncer: Debouncer
    private let logger: AppLogger

    /// Matches `.prefix(5)` in `MealCalendarView`'s Quick Planner search results.
    private static let matchingRecipesLimit = 5

    init(
        now: @escaping () -> Date = Date.init,
        timeZone: TimeZone = .current,
        mealPlanService: MealPlanServicing = MealPlanService(),
        recipeService: RecipeServicing = RecipeService(),
        weatherForecaster: WeatherForecasting = OpenMeteoForecastService(),
        weatherPreferenceStore: WeatherPreferenceStoring = UserDefaultsWeatherPreferenceStore(),
        widgetPublisher: WidgetPublishing = WidgetPublisher(),
        snapshotStore: LocalSnapshotStoring = FileSnapshotStore.shared,
        debounceDelay: Duration = .milliseconds(300),
        logger: AppLogger = .shared
    ) {
        self.mealPlanService = mealPlanService
        self.recipeService = recipeService
        self.weatherForecaster = weatherForecaster
        self.weatherPreferenceStore = weatherPreferenceStore
        self.widgetPublisher = widgetPublisher
        self.snapshotStore = snapshotStore
        self.logger = logger
        self.debouncer = Debouncer(delay: debounceDelay)
        self.now = now
        let calendar = Self.makeCalendar(timeZone: timeZone)
        self.calendar = calendar
        self.dayFormatter = Self.makeDayFormatter(timeZone: timeZone)
        let today = dayFormatter.string(from: now())
        todayDate = today
        let dates = Self.computeWeekDates(from: now(), weekOffset: 0, calendar: calendar, formatter: dayFormatter)
        weekDates = dates
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
        weekDates = Self.computeWeekDates(from: now(), weekOffset: newOffset, calendar: calendar, formatter: dayFormatter)
        // Keep the Quick Planner's target day inside the visible week.
        if !weekDates.contains(selectedPlanningDate) {
            selectedPlanningDate = weekDates[0]
        }
        // Meal plans are fetched per visible window (see `loadPlans()`), so
        // paging to a new week needs a fetch for days not yet cached.
        Task { await loadPlans() }
        // No weather refetch here: the outlook is keyed to the fixed home
        // location and only spans ~10 days from today, so paging to another
        // week can't surface new forecast data — refetching (and, previously,
        // taking a fresh GPS fix) on every ‹/› tap was wasted work.
    }

    /// Re-derives "today" — and, when the day has rolled over since the last
    /// look, the week window with it — from the wall clock. Called at the top
    /// of every `load()` so the highlight, the Quick Planner default, and the
    /// widget snapshot all track real time instead of the launch-time date.
    private func refreshDayContext() {
        let newToday = dayFormatter.string(from: now())
        guard newToday != todayDate else { return }
        todayDate = newToday
        weekDates = Self.computeWeekDates(from: now(), weekOffset: weekOffset, calendar: calendar, formatter: dayFormatter)
        if !weekDates.contains(selectedPlanningDate) {
            selectedPlanningDate = weekDates[0]
        }
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
        await loadPlans()
        await loadWeather()
    }

    /// Fetches the meal plans for the visible window. Split from `load()` so
    /// week paging can refresh plans without also re-fetching the weather (the
    /// forecast is keyed to today's fixed home location — see `shiftWeek`).
    func loadPlans() async {
        refreshDayContext()
        // Paint the last-fetched window immediately (fresh launch only) while
        // the real fetch runs — offline, the week still shows its plans.
        if mealPlansByDate.isEmpty, let cached = snapshotStore.load([MealPlanWithRecipe].self, key: .mealPlansWindow) {
            mealPlansByDate = Dictionary(grouping: cached, by: \.date)
        }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        // Fetch only the visible week — plus today when the user has paged away
        // from it, so the Today's Meals widget snapshot stays accurate. Fetching
        // the whole table grew without bound as planning history accumulated.
        let start = min(weekDates[0], todayDate)
        let end = max(weekDates[weekDates.count - 1], todayDate)
        do {
            let plans = try await mealPlanService.fetch(from: start, to: end)
            // Replace the fetched window in the cache; days outside it keep
            // whatever an earlier fetch loaded (so paging back is instant).
            let grouped = Dictionary(grouping: plans, by: \.date)
            mealPlansByDate = mealPlansByDate.filter { $0.key < start || $0.key > end }
            for (date, dayPlans) in grouped {
                mealPlansByDate[date] = dayPlans
            }
            publishTodaysMealsWidget()
            // Persist only when the fetch included today (i.e. the launch-time
            // window) — that's what the next fresh launch wants to paint.
            if weekOffset == 0 {
                snapshotStore.save(plans, key: .mealPlansWindow)
            }
        } catch {
            // Surfaced via errorMessage, but also logged raw — this load fires on
            // appear/paging/foreground, so a persistent failure needs a trail.
            logger.error("Meal plans load failed", category: "calendar", error: error)
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// Publish today's meals to the Today's Meals widget from the local cache.
    private func publishTodaysMealsWidget() {
        widgetPublisher.publishTodaysMeals(plans: mealPlansByDate[todayDate] ?? [], today: todayDate)
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
            // Weather is a nice-to-have, never surfaced — but log so a persistently
            // failing forecast isn't invisible.
            forecastByDate = [:]
            logger.warning("Calendar weather forecast fetch failed", category: "calendar", metadata: [
                "errorType": String(describing: type(of: error)),
            ])
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
            // The service returns the created row (with its recipe title), so
            // the day is patched in place — no re-fetch of the whole window.
            let plan = try await mealPlanService.create(MealPlanDraft(date: date, mealType: selectedMealType, recipeId: recipeId))
            mealPlansByDate[plan.date, default: []].append(plan)
            publishTodaysMealsWidget()
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    func deleteMealPlan(_ id: Int64) async {
        errorMessage = nil
        do {
            try await mealPlanService.delete(id: id)
            for (date, dayPlans) in mealPlansByDate where dayPlans.contains(where: { $0.id == id }) {
                mealPlansByDate[date] = dayPlans.filter { $0.id != id }
            }
            publishTodaysMealsWidget()
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    private static func makeCalendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private static func makeDayFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        return formatter
    }

    private static func computeWeekDates(from date: Date, weekOffset: Int, calendar: Calendar, formatter: DateFormatter) -> [String] {
        let start = calendar.date(byAdding: .day, value: weekOffset * 7, to: date)!
        return (0..<7).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: start)!
            return formatter.string(from: day)
        }
    }
}
