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

    private let referenceDate: Date
    private let calendar: Calendar
    private let recipeService: RecipeServicing
    private let weatherForecaster: WeatherForecasting
    private let weatherPreferenceStore: WeatherPreferenceStoring

    /// How many recipes the shelf shows at once…
    private static let displayCount = 8
    /// …drawn (and shuffled) from a larger pool, so repeat visits surface a
    /// different slice instead of the same first-N every time.
    private static let poolSize = 40

    init(
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        recipeService: RecipeServicing = RecipeService(),
        weatherForecaster: WeatherForecasting = OpenMeteoForecastService(),
        weatherPreferenceStore: WeatherPreferenceStoring = UserDefaultsWeatherPreferenceStore()
    ) {
        self.referenceDate = referenceDate
        self.calendar = calendar
        self.recipeService = recipeService
        self.weatherForecaster = weatherForecaster
        self.weatherPreferenceStore = weatherPreferenceStore
        self.suggestion = RecipeSuggester.suggestion(for: referenceDate, calendar: calendar)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        // Refine the suggestion from real weather *before* fetching recipes, so
        // the shelf query uses the weather-driven keyword/prep cap.
        await loadWeatherSuggestion()
        await loadSuggestedRecipes()
    }

    /// Fetches the forecast for the saved home location (if any) and recomputes
    /// `suggestion` from today's weather. Failures and a missing home location
    /// both leave `suggestion` at its calendar-derived value — weather is a
    /// refinement, never a hard dependency — so this never surfaces an error.
    private func loadWeatherSuggestion() async {
        guard let home = weatherPreferenceStore.loadHomeLocation() else {
            todayForecast = nil
            suggestion = RecipeSuggester.suggestion(for: referenceDate, calendar: calendar)
            return
        }
        // Open-Meteo returns the outlook starting today, so the first entry is
        // today's forecast (see OpenMeteoForecastService / the calendar's usage).
        todayForecast = try? await weatherForecaster.dailyForecast(for: home.coordinate).first
        suggestion = RecipeSuggester.suggestion(forecast: todayForecast, date: referenceDate, calendar: calendar)
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
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }
}
