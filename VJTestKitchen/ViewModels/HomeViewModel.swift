import Foundation
import Observation

/// Backs the Home tab: a context-aware suggested-recipes shelf. Follows the
/// Service/`@Observable` pattern used across the app — all data comes through an
/// injected service so the whole thing is unit-testable without a network or a
/// session.
///
/// The shelf **rotates**: each `load()` (tab switch or pull-to-refresh) pulls a
/// larger pool matching the day's suggestion, shuffles it, and shows a slice —
/// so the Home screen feels alive rather than a static list of the same recipes.
@MainActor
@Observable
final class HomeViewModel {
    /// The cooking suggestion driving the header. Starts calendar-derived
    /// (season + weeknight/weekend) so the header is never blank before data
    /// loads, then is **recomputed from today's actual weather** in `load()` once
    /// the forecast is in — a cold/rainy day pushes hearty cooking, a hot day
    /// pushes no-cook. `private(set) var`, not `let`, precisely so weather can
    /// refine it after the async fetch.
    private(set) var suggestion: RecipeSuggestion

    /// Today's weather outlook when the user has set a home location and the
    /// fetch succeeded — surfaced so the header can show a live "Rainy · 52°"
    /// context chip. Nil means no location set or the forecast is unavailable
    /// (in which case `suggestion` stays calendar-derived).
    private(set) var todayForecast: DailyForecast?

    private(set) var suggestedRecipes: [Recipe] = []
    private(set) var isLoading = false
    var errorMessage: String?

    /// Wall clock, injectable for tests — read fresh on every `load()` (never
    /// frozen at init) so the suggestion tracks the real day: this view model
    /// lives as long as the tab does, and iOS keeps apps suspended for days, so
    /// an init-time date left weekend suggestions showing on a Monday.
    private let now: () -> Date
    private let calendar: Calendar
    private let recipeService: RecipeServicing
    private let weatherForecaster: WeatherForecasting
    private let weatherPreferenceStore: WeatherPreferenceStoring
    private let widgetPublisher: WidgetPublishing
    private let snapshotStore: LocalSnapshotStoring
    private let logger: AppLogger

    /// When the shelf/forecast last loaded, and the calendar-derived suggestion
    /// they loaded for — together they let `load()` skip a refetch when nothing
    /// meaningful changed (see `isFresh`).
    @ObservationIgnored private var lastLoadedAt: Date?
    @ObservationIgnored private var lastCalendarSuggestion: RecipeSuggestion?

    /// How many recipes the shelf shows at once…
    private static let displayCount = 8
    /// …drawn (and shuffled) from a larger pool, so repeat visits surface a
    /// different slice instead of the same first-N every time.
    private static let poolSize = 40
    /// How long a loaded shelf + forecast stay fresh. `.task` re-fires on every
    /// tab switch, and refetching Open-Meteo plus two recipe pages each visit
    /// (with the shelf visibly reshuffling) was wasted churn — within this
    /// window, revisits reuse what's shown. Pull-to-refresh / ⌘R force it.
    private static let reloadInterval: TimeInterval = 3600

    init(
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        recipeService: RecipeServicing = RecipeService(),
        weatherForecaster: WeatherForecasting = OpenMeteoForecastService(),
        weatherPreferenceStore: WeatherPreferenceStoring = UserDefaultsWeatherPreferenceStore(),
        widgetPublisher: WidgetPublishing = WidgetPublisher(),
        snapshotStore: LocalSnapshotStoring = FileSnapshotStore.shared,
        logger: AppLogger = .shared
    ) {
        self.now = now
        self.calendar = calendar
        self.recipeService = recipeService
        self.weatherForecaster = weatherForecaster
        self.weatherPreferenceStore = weatherPreferenceStore
        self.widgetPublisher = widgetPublisher
        self.snapshotStore = snapshotStore
        self.logger = logger
        self.suggestion = RecipeSuggester.suggestion(for: now(), calendar: calendar)
    }

    /// Loads (or reuses) the forecast and suggested-recipes shelf. `force`
    /// (pull-to-refresh, ⌘R) always refetches; otherwise a fresh recent load
    /// for the same calendar context is reused as-is.
    func load(force: Bool = false) async {
        if !force, isFresh { return }
        // Paint the last-loaded shelf immediately (fresh launch only) while
        // the real load runs — offline, Home still has recipes to show.
        if suggestedRecipes.isEmpty, let cached = snapshotStore.load([Recipe].self, key: .homeShelf) {
            suggestedRecipes = cached
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        // Refine the suggestion from real weather *before* fetching recipes, so
        // the shelf query uses the weather-driven keyword/prep cap.
        await loadWeatherSuggestion()
        await loadSuggestedRecipes()
        lastLoadedAt = now()
        lastCalendarSuggestion = RecipeSuggester.suggestion(for: now(), calendar: calendar)
    }

    /// A previous load still stands when it happened within `reloadInterval`,
    /// actually produced a shelf, and the calendar-derived suggestion hasn't
    /// changed since (a day rollover — weeknight→weekend, new season — must
    /// refetch even inside the interval).
    private var isFresh: Bool {
        guard let lastLoadedAt, !suggestedRecipes.isEmpty else { return false }
        return now().timeIntervalSince(lastLoadedAt) < Self.reloadInterval
            && lastCalendarSuggestion == RecipeSuggester.suggestion(for: now(), calendar: calendar)
    }

    /// Fetches the forecast for the saved home location (if any) and recomputes
    /// `suggestion` from today's weather. Failures and a missing home location
    /// both leave `suggestion` at its calendar-derived value — weather is a
    /// refinement, never a hard dependency — so this never surfaces an error.
    private func loadWeatherSuggestion() async {
        guard let home = weatherPreferenceStore.loadHomeLocation() else {
            todayForecast = nil
            suggestion = RecipeSuggester.suggestion(for: now(), calendar: calendar)
            return
        }
        // Open-Meteo returns the outlook starting today, so the first entry is
        // today's forecast (see OpenMeteoForecastService / the calendar's usage).
        do {
            todayForecast = try await weatherForecaster.dailyForecast(for: home.coordinate).first
        } catch {
            // Weather is a refinement, never surfaced — but log so a persistently
            // failing forecast (bad location, Open-Meteo down) isn't invisible.
            todayForecast = nil
            logger.warning("Home weather forecast fetch failed", category: "home", metadata: [
                "errorType": String(describing: type(of: error)),
            ])
        }
        suggestion = RecipeSuggester.suggestion(forecast: todayForecast, date: now(), calendar: calendar)
    }

    private func loadSuggestedRecipes() async {
        do {
            var pool = try await recipeService.fetchPage(
                offset: 0, limit: Self.poolSize,
                matching: suggestion.keyword, tag: nil, maxPrepTime: suggestion.maxPrepTime
            )
            // The seasonal keyword might match nothing in a small/partial
            // catalog — fall back to a plain page so the shelf is never empty
            // just because "grilled" isn't in the imported subset.
            if pool.isEmpty {
                pool = try await recipeService.fetchPage(offset: 0, limit: Self.poolSize, matching: nil)
            }
            // Shuffle then slice so the shelf rotates on each load/refresh.
            suggestedRecipes = Array(pool.shuffled().prefix(Self.displayCount))
            snapshotStore.save(suggestedRecipes, key: .homeShelf)
            // Publish the current suggestion + a few recipes to the Cook's Idea widget.
            widgetPublisher.publishCooksIdea(suggestion: suggestion, recipes: suggestedRecipes)
        } catch {
            // Surfaced to the user via errorMessage, but also logged raw so the
            // underlying failure is diagnosable (ErrorPresenter is display-only).
            logger.error("Home suggested-recipes load failed", category: "home", error: error)
            errorMessage = ErrorPresenter.message(for: error)
        }
    }
}
