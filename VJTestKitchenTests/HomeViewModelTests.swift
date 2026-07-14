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
    var errorToThrow: Error?
    private(set) var fetchedPages: [(offset: Int, limit: Int, search: String?, tag: String?, maxPrepTime: Int?)] = []

    func fetchPage(offset: Int, limit: Int, matching search: String?, tag: String?, minPrepTime: Int?, maxPrepTime: Int?, minAtkRating: Double?) async throws -> [Recipe] {
        if let errorToThrow { throw errorToThrow }
        fetchedPages.append((offset, limit, search, tag, maxPrepTime))
        return pagesByKeyword[search ?? "", default: []]
    }

    func totalCount() async throws -> Int { 0 }
    func fetchDetail(id: Int64) async throws -> RecipeDetail { fatalError("not used") }
    func create(_ draft: RecipeDraft) async throws -> Recipe { fatalError("not used") }
    func update(id: Int64, with draft: RecipeDraft) async throws { fatalError("not used") }
    func delete(id: Int64) async throws { fatalError("not used") }
}

private func makeRecipe(_ id: Int64, _ title: String) -> Recipe {
    Recipe(id: id, userId: nil, title: title, description: nil, instructions: nil, imagePath: nil, prepTime: 25, servings: 4, createdAt: Date())
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

    /// A Tuesday in July → summer weeknight; suggestion keyword is "salad".
    private var referenceDate: Date {
        utcCalendar.date(from: DateComponents(year: 2026, month: 7, day: 7))!
    }

    private func makeViewModel(
        recipes: FakeHomeRecipeService = FakeHomeRecipeService(),
        forecaster: FakeWeatherForecaster = FakeWeatherForecaster(),
        store: FakeWeatherPreferenceStore = FakeWeatherPreferenceStore(),
        snapshotStore: FakeSnapshotStore = FakeSnapshotStore()
    ) -> HomeViewModel {
        HomeViewModel(
            now: { [referenceDate] in referenceDate },
            calendar: utcCalendar,
            recipeService: recipes,
            weatherForecaster: forecaster,
            weatherPreferenceStore: store,
            snapshotStore: snapshotStore
        )
    }

    @Test func suggestionReflectsReferenceDate() {
        let viewModel = makeViewModel()
        #expect(viewModel.suggestion.title == "Light Summer Suppers")
        #expect(viewModel.suggestion.keyword == "salad")
        #expect(viewModel.suggestion.maxPrepTime == 30)
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

    @Test func loadRotatesShelfToADisplaySizedSubsetOfThePool() async {
        // A pool larger than the display count is sliced down; every shown
        // recipe comes from the pool (the rotation only reorders/samples).
        let pool = (1...20).map { makeRecipe(Int64($0), "Salad \($0)") }
        let recipes = FakeHomeRecipeService()
        recipes.pagesByKeyword = ["salad": pool]
        let viewModel = makeViewModel(recipes: recipes)

        await viewModel.load()

        #expect(viewModel.suggestedRecipes.count == 8)
        let poolIds = Set(pool.map(\.id))
        #expect(viewModel.suggestedRecipes.allSatisfy { poolIds.contains($0.id) })
        // No duplicates in the shown slice.
        #expect(Set(viewModel.suggestedRecipes.map(\.id)).count == viewModel.suggestedRecipes.count)
    }

    @Test func weatherRefinesSuggestionAndQueryWhenHomeLocationSet() async {
        // A cold forecast on a summer weeknight overrides the calendar's "salad"
        // with weather-driven "soup", and that keyword reaches the recipe query.
        let store = FakeWeatherPreferenceStore()
        store.homeLocation = makeHomeLocation()
        let forecaster = FakeWeatherForecaster()
        forecaster.forecasts = [makeForecast(date: "2026-07-07", category: .clear, high: 2, unit: .celsius)]
        let recipes = FakeHomeRecipeService()
        recipes.pagesByKeyword = ["soup": [makeRecipe(1, "Chicken Soup")]]
        let viewModel = makeViewModel(recipes: recipes, forecaster: forecaster, store: store)

        await viewModel.load()

        #expect(viewModel.suggestion.title == "Warm Up the Kitchen")
        #expect(viewModel.todayForecast?.category == .clear)
        #expect(recipes.fetchedPages.first?.search == "soup")
        #expect(viewModel.suggestedRecipes.map(\.title) == ["Chicken Soup"])
    }

    @Test func noHomeLocationLeavesCalendarSuggestionAndNoForecast() async {
        // Default store has no home location → suggestion stays calendar-derived
        // and no forecast fetch happens.
        let forecaster = FakeWeatherForecaster()
        forecaster.forecasts = [makeForecast(date: "2026-07-07", category: .snow, high: -2, unit: .celsius)]
        let viewModel = makeViewModel(forecaster: forecaster)

        await viewModel.load()

        #expect(viewModel.suggestion.title == "Light Summer Suppers")
        #expect(viewModel.todayForecast == nil)
        #expect(forecaster.requestedCoordinates.isEmpty)
    }

    @Test func weatherFetchFailureFallsBackToCalendarSuggestion() async {
        // A set home location but a failing forecast → calendar suggestion, no
        // error surfaced (weather is a nice-to-have, not a hard dependency).
        let store = FakeWeatherPreferenceStore()
        store.homeLocation = makeHomeLocation()
        let forecaster = FakeWeatherForecaster()
        forecaster.errorToThrow = WeatherError.badResponse
        let recipes = FakeHomeRecipeService()
        recipes.pagesByKeyword = ["salad": [makeRecipe(1, "Greek Salad")]]
        let viewModel = makeViewModel(recipes: recipes, forecaster: forecaster, store: store)

        await viewModel.load()

        #expect(viewModel.suggestion.title == "Light Summer Suppers")
        #expect(viewModel.todayForecast == nil)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func loadSurfacesRecipeError() async {
        let recipes = FakeHomeRecipeService()
        recipes.errorToThrow = TestError()
        let viewModel = makeViewModel(recipes: recipes)

        await viewModel.load()

        #expect(viewModel.errorMessage == "failed")
        #expect(viewModel.suggestedRecipes.isEmpty)
    }

    // MARK: - Load reuse (freshness) & day rollover

    @Test func revisitWithinTheHourReusesTheLoadedShelf() async {
        // `.task` fires on every tab switch; a fresh recent load must not
        // refetch (and visibly reshuffle) each time.
        let recipes = FakeHomeRecipeService()
        recipes.pagesByKeyword = ["salad": [makeRecipe(1, "Greek Salad")]]
        let viewModel = makeViewModel(recipes: recipes)

        await viewModel.load()
        let callsAfterFirst = recipes.fetchedPages.count
        await viewModel.load()

        #expect(recipes.fetchedPages.count == callsAfterFirst)
        #expect(viewModel.suggestedRecipes.map(\.title) == ["Greek Salad"])
    }

    @Test func forceReloadAlwaysRefetches() async {
        let recipes = FakeHomeRecipeService()
        recipes.pagesByKeyword = ["salad": [makeRecipe(1, "Greek Salad")]]
        let viewModel = makeViewModel(recipes: recipes)

        await viewModel.load()
        let callsAfterFirst = recipes.fetchedPages.count
        await viewModel.load(force: true)

        #expect(recipes.fetchedPages.count > callsAfterFirst)
    }

    @Test func loadAfterDayRolloverRecomputesTheSuggestion() async {
        // Created on a summer Tuesday ("salad"); the app stays in memory into
        // Friday — the next load must re-derive a weekend suggestion (no prep
        // cap) rather than keep the launch-day one, even within any interval.
        var current = utcCalendar.date(from: DateComponents(year: 2026, month: 7, day: 7))!
        let recipes = FakeHomeRecipeService()
        recipes.pagesByKeyword = ["salad": [makeRecipe(1, "Greek Salad")], "grilled": [makeRecipe(2, "Grilled Corn")]]
        let viewModel = HomeViewModel(
            now: { current },
            calendar: utcCalendar,
            recipeService: recipes,
            weatherForecaster: FakeWeatherForecaster(),
            weatherPreferenceStore: FakeWeatherPreferenceStore(),
            snapshotStore: FakeSnapshotStore()
        )
        await viewModel.load()
        #expect(viewModel.suggestion.maxPrepTime == 30)

        // Roll to Friday July 10 and load again (e.g. app foregrounded).
        current = utcCalendar.date(from: DateComponents(year: 2026, month: 7, day: 10))!
        await viewModel.load()

        #expect(viewModel.suggestion.maxPrepTime == nil)
        #expect(viewModel.suggestion.keyword == "grilled")
        #expect(viewModel.suggestedRecipes.map(\.title) == ["Grilled Corn"])
    }

    @Test func loadPaintsCachedShelfWhenTheFetchFails() async {
        // Offline: the fetch fails, but the last-persisted shelf still shows.
        let snapshotStore = FakeSnapshotStore()
        snapshotStore.save([makeRecipe(9, "Cached Salad")], key: .homeShelf)
        let recipes = FakeHomeRecipeService()
        recipes.errorToThrow = TestError()
        let viewModel = makeViewModel(recipes: recipes, snapshotStore: snapshotStore)

        await viewModel.load()

        #expect(viewModel.suggestedRecipes.map(\.title) == ["Cached Salad"])
        #expect(viewModel.errorMessage == "failed")
    }

    @Test func successfulLoadPersistsTheShelf() async {
        let snapshotStore = FakeSnapshotStore()
        let recipes = FakeHomeRecipeService()
        recipes.pagesByKeyword = ["salad": [makeRecipe(1, "Greek Salad")]]
        let viewModel = makeViewModel(recipes: recipes, snapshotStore: snapshotStore)

        await viewModel.load()

        let cached: [Recipe]? = snapshotStore.load([Recipe].self, key: .homeShelf)
        #expect(cached?.map(\.title) == ["Greek Salad"])
    }
}
