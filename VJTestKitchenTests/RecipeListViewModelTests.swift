import Foundation
import Testing
@testable import VJTestKitchen

final class FakeRecipeService: RecipeServicing, @unchecked Sendable {
    var recipesToReturn: [Recipe] = []
    var errorToThrow: Error?
    private(set) var deletedIds: [Int64] = []
    private(set) var fetchedPages: [(offset: Int, limit: Int, search: String?, tag: String?, minPrepTime: Int?, maxPrepTime: Int?, minAtkRating: Double?)] = []

    func fetchPage(offset: Int, limit: Int, matching search: String?, tag: String?, minPrepTime: Int?, maxPrepTime: Int?, minAtkRating: Double?) async throws -> [Recipe] {
        fetchedPages.append((offset, limit, search, tag, minPrepTime, maxPrepTime, minAtkRating))
        if let errorToThrow { throw errorToThrow }
        var filtered = search.map { term in
            recipesToReturn.filter { $0.title.localizedCaseInsensitiveContains(term) }
        } ?? recipesToReturn
        if let minPrepTime {
            filtered = filtered.filter { ($0.prepTime ?? .min) >= minPrepTime }
        }
        if let maxPrepTime {
            filtered = filtered.filter { ($0.prepTime ?? .max) <= maxPrepTime }
        }
        if let minAtkRating {
            filtered = filtered.filter { ($0.atkRating ?? -1) >= minAtkRating }
        }
        let start = min(offset, filtered.count)
        let end = min(offset + limit, filtered.count)
        return Array(filtered[start..<end])
    }

    func fetchByIds(_ ids: [Int64]) async throws -> [Recipe] {
        if let errorToThrow { throw errorToThrow }
        let set = Set(ids)
        return recipesToReturn.filter { set.contains($0.id) }
    }

    func fetchDetail(id: Int64) async throws -> RecipeDetail {
        fatalError("not used by RecipeListViewModelTests")
    }

    func create(_ draft: RecipeDraft) async throws -> Recipe {
        fatalError("not used by RecipeListViewModelTests")
    }

    func update(id: Int64, with draft: RecipeDraft) async throws {
        fatalError("not used by RecipeListViewModelTests")
    }

    func delete(id: Int64) async throws {
        deletedIds.append(id)
    }
}

private func makeRecipe(id: Int64, title: String, prepTime: Int? = 20, atkRating: Double? = nil) -> Recipe {
    Recipe(id: id, userId: nil, title: title, description: nil, instructions: nil, imagePath: nil, prepTime: prepTime, servings: 2, createdAt: Date(), atkRating: atkRating)
}

private struct TestError: Error, LocalizedError {
    var errorDescription: String? { "failed to load" }
}

@MainActor
struct RecipeListViewModelTests {
    @Test func loadsRecipesOnStart() async {
        let fake = FakeRecipeService()
        fake.recipesToReturn = [makeRecipe(id: 1, title: "Carbonara"), makeRecipe(id: 2, title: "Tacos")]
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), snapshotStore: FakeSnapshotStore())

        await viewModel.load()

        #expect(viewModel.items.map(\.title) == ["Carbonara", "Tacos"])
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isLoading == false)
    }

    @Test func loadSurfacesErrorMessage() async {
        let fake = FakeRecipeService()
        fake.errorToThrow = TestError()
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), snapshotStore: FakeSnapshotStore())

        await viewModel.load()

        #expect(viewModel.errorMessage == "failed to load")
        #expect(viewModel.items.isEmpty)
    }

    @Test func cancelledFetchDoesNotSurfaceAnErrorMessage() async {
        // When a keystroke arrives mid-fetch, the debouncer cancels the in-flight
        // reload; the underlying request throws a cancellation error. That's
        // intentional flow control, not a failure — it must never flash the
        // "Couldn't Load Recipes" alert.
        let fake = FakeRecipeService()
        fake.errorToThrow = CancellationError()
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), snapshotStore: FakeSnapshotStore())

        await viewModel.load()

        #expect(viewModel.errorMessage == nil)
    }

    @Test func cancelledURLRequestDoesNotSurfaceAnErrorMessage() async {
        // URLSession surfaces a cancelled request as URLError(.cancelled) rather
        // than Swift's CancellationError — that shape must be swallowed too.
        let fake = FakeRecipeService()
        fake.errorToThrow = URLError(.cancelled)
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), snapshotStore: FakeSnapshotStore())

        await viewModel.load()

        #expect(viewModel.errorMessage == nil)
    }

    @Test func cancelledFetchIsNotLoggedAsAnError() async {
        // A cancellation is expected churn, not a diagnosable fault — it should
        // not pollute the error log either.
        let fake = FakeRecipeService()
        fake.errorToThrow = CancellationError()
        let sink = SpyLogSink()
        let logger = AppLogger(sinks: [sink], context: LogContext(appVersion: "1", platform: "test"))
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), snapshotStore: FakeSnapshotStore(), logger: logger)

        await viewModel.load()

        #expect(!sink.events.contains { $0.level == .error })
    }

    @Test func loadLogsErrorWhenFetchFails() async {
        let fake = FakeRecipeService()
        fake.errorToThrow = TestError()
        let sink = SpyLogSink()
        let logger = AppLogger(sinks: [sink], context: LogContext(appVersion: "1", platform: "test"))
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), snapshotStore: FakeSnapshotStore(), logger: logger)

        await viewModel.load()

        // Surfaced via errorMessage AND logged raw for diagnosis.
        #expect(sink.events.contains { $0.level == .error && $0.category == "recipes" })
    }

    @Test func searchTextReloadsFromServerAfterDebounce() async {
        let fake = FakeRecipeService()
        fake.recipesToReturn = [makeRecipe(id: 1, title: "Carbonara"), makeRecipe(id: 2, title: "Beef Tacos")]
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), snapshotStore: FakeSnapshotStore(), debounceDelay: .zero)
        await viewModel.load()

        viewModel.searchText = "taco"
        try? await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.items.map(\.title) == ["Beef Tacos"])
        #expect(fake.fetchedPages.last?.search == "taco")
        #expect(fake.fetchedPages.last?.offset == 0)
    }

    @Test func emptySearchTextShowsAllRecipes() async {
        let fake = FakeRecipeService()
        fake.recipesToReturn = [makeRecipe(id: 1, title: "Carbonara"), makeRecipe(id: 2, title: "Tacos")]
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), snapshotStore: FakeSnapshotStore(), debounceDelay: .zero)
        await viewModel.load()

        viewModel.searchText = "taco"
        try? await Task.sleep(for: .milliseconds(50))
        viewModel.searchText = ""
        try? await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.items.count == 2)
    }

    @Test func loadMoreIfNeededFetchesNextPageNearEndOfList() async {
        let fake = FakeRecipeService()
        // 60 recipes so the first 50-row page is full and a second page exists.
        fake.recipesToReturn = (1...60).map { makeRecipe(id: Int64($0), title: "Recipe \($0)") }
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), snapshotStore: FakeSnapshotStore())
        await viewModel.load()
        #expect(viewModel.items.count == 50)

        await viewModel.loadMoreIfNeeded(currentItem: viewModel.items[49])

        #expect(viewModel.items.count == 60)
        #expect(fake.fetchedPages.last?.offset == 50)
    }

    @Test func loadMoreIfNeededDoesNothingWhenFarFromEndOfList() async {
        let fake = FakeRecipeService()
        fake.recipesToReturn = (1...60).map { makeRecipe(id: Int64($0), title: "Recipe \($0)") }
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), snapshotStore: FakeSnapshotStore())
        await viewModel.load()
        let pageCountBefore = fake.fetchedPages.count

        await viewModel.loadMoreIfNeeded(currentItem: viewModel.items[0])

        #expect(viewModel.items.count == 50)
        #expect(fake.fetchedPages.count == pageCountBefore)
    }

    // MARK: - Filtering

    @Test func loadPopulatesAvailableTagsGroupedByCourseAndCuisine() async {
        let fake = FakeRecipeService()
        let tags = FakeTagService()
        tags.namesToReturn = ["Appetizers", "Italian", "Main Courses", "Mexican"]
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: tags, snapshotStore: FakeSnapshotStore())

        await viewModel.load()

        #expect(viewModel.availableTags == ["Appetizers", "Italian", "Main Courses", "Mexican"])
        // Course tags come back in the fixed menu order, not alphabetical.
        #expect(viewModel.courseTags == ["Main Courses", "Appetizers"])
        #expect(viewModel.cuisineTags == ["Italian", "Mexican"])
    }

    @Test func selectingTagReloadsFromServerWithThatTag() async {
        let fake = FakeRecipeService()
        fake.recipesToReturn = [makeRecipe(id: 1, title: "Carbonara"), makeRecipe(id: 2, title: "Tacos")]
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), snapshotStore: FakeSnapshotStore(), debounceDelay: .zero)
        await viewModel.load()

        viewModel.selectedTag = "Italian"
        try? await Task.sleep(for: .milliseconds(50))

        #expect(fake.fetchedPages.last?.tag == "Italian")
        #expect(fake.fetchedPages.last?.offset == 0)
        #expect(viewModel.hasActiveFilters)
    }

    @Test func upperBoundPrepTimeFilterNarrowsResultsAndIsPassedToServer() async {
        let fake = FakeRecipeService()
        fake.recipesToReturn = [
            makeRecipe(id: 1, title: "Quick Salad", prepTime: 15),
            makeRecipe(id: 2, title: "Slow Roast", prepTime: 90)
        ]
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), snapshotStore: FakeSnapshotStore(), debounceDelay: .zero)
        await viewModel.load()

        viewModel.prepTimeFilter = .under30
        try? await Task.sleep(for: .milliseconds(50))

        #expect(fake.fetchedPages.last?.minPrepTime == nil)
        #expect(fake.fetchedPages.last?.maxPrepTime == 30)
        #expect(viewModel.items.map(\.title) == ["Quick Salad"])
    }

    @Test func lowerBoundPrepTimeFilterPassesMinToServer() async {
        let fake = FakeRecipeService()
        fake.recipesToReturn = [
            makeRecipe(id: 1, title: "Quick Salad", prepTime: 15),
            makeRecipe(id: 2, title: "Overnight Brisket", prepTime: 600)
        ]
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), snapshotStore: FakeSnapshotStore(), debounceDelay: .zero)
        await viewModel.load()

        viewModel.prepTimeFilter = .overnight
        try? await Task.sleep(for: .milliseconds(50))

        #expect(fake.fetchedPages.last?.minPrepTime == 480)
        #expect(fake.fetchedPages.last?.maxPrepTime == nil)
        #expect(viewModel.items.map(\.title) == ["Overnight Brisket"])
    }

    @Test func minRatingFilterNarrowsResultsAndIsPassedToServer() async {
        let fake = FakeRecipeService()
        fake.recipesToReturn = [
            makeRecipe(id: 1, title: "Perfect Chocolate Chip Cookies", atkRating: 4.57),
            makeRecipe(id: 2, title: "Untested Recipe", atkRating: nil),
            makeRecipe(id: 3, title: "Mediocre Meatloaf", atkRating: 3.2)
        ]
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), snapshotStore: FakeSnapshotStore(), debounceDelay: .zero)
        await viewModel.load()

        viewModel.minRatingFilter = .four
        try? await Task.sleep(for: .milliseconds(50))

        #expect(fake.fetchedPages.last?.minAtkRating == 4.0)
        #expect(viewModel.items.map(\.title) == ["Perfect Chocolate Chip Cookies"])
        #expect(viewModel.hasActiveFilters)
    }

    @Test func clearFiltersResetsTagAndPrepTimeAndReloads() async {
        let fake = FakeRecipeService()
        fake.recipesToReturn = [makeRecipe(id: 1, title: "Carbonara")]
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), snapshotStore: FakeSnapshotStore(), debounceDelay: .zero)
        await viewModel.load()
        viewModel.selectedTag = "Italian"
        viewModel.prepTimeFilter = .under30
        viewModel.minRatingFilter = .four
        try? await Task.sleep(for: .milliseconds(50))
        #expect(viewModel.hasActiveFilters)

        viewModel.clearFilters()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(!viewModel.hasActiveFilters)
        #expect(viewModel.selectedTag == nil)
        #expect(viewModel.prepTimeFilter == nil)
        #expect(viewModel.minRatingFilter == nil)
        #expect(fake.fetchedPages.last?.tag == nil)
        #expect(fake.fetchedPages.last?.minAtkRating == nil)
        #expect(fake.fetchedPages.last?.maxPrepTime == nil)
    }

    // MARK: - Favorites

    @Test func loadPopulatesFavoriteIds() async {
        let fake = FakeRecipeService()
        fake.recipesToReturn = [makeRecipe(id: 1, title: "Carbonara"), makeRecipe(id: 2, title: "Tacos")]
        let favorites = FakeFavoritesService()
        favorites.favoriteIds = [2]
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), favoritesService: favorites, snapshotStore: FakeSnapshotStore())

        await viewModel.load()

        #expect(viewModel.isFavorite(makeRecipe(id: 2, title: "Tacos")))
        #expect(!viewModel.isFavorite(makeRecipe(id: 1, title: "Carbonara")))
    }

    @Test func favoritesFilterShowsOnlyFavoritedRecipes() async {
        let fake = FakeRecipeService()
        fake.recipesToReturn = (1...3).map { makeRecipe(id: Int64($0), title: "Recipe \($0)") }
        let favorites = FakeFavoritesService()
        favorites.favoriteIds = [1, 3]
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), favoritesService: favorites, snapshotStore: FakeSnapshotStore(), debounceDelay: .zero)
        await viewModel.load()

        viewModel.showFavoritesOnly = true
        try? await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.items.map(\.id).sorted() == [1, 3])
        #expect(viewModel.hasActiveFilters)
    }

    @Test func toggleFavoriteInFavoritesModeDropsUnfavoritedRow() async {
        let fake = FakeRecipeService()
        fake.recipesToReturn = (1...3).map { makeRecipe(id: Int64($0), title: "Recipe \($0)") }
        let favorites = FakeFavoritesService()
        favorites.favoriteIds = [1, 2, 3]
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), favoritesService: favorites, snapshotStore: FakeSnapshotStore(), debounceDelay: .zero)
        await viewModel.load()
        viewModel.showFavoritesOnly = true
        try? await Task.sleep(for: .milliseconds(50))
        #expect(viewModel.items.count == 3)

        await viewModel.toggleFavorite(makeRecipe(id: 2, title: "Recipe 2"))

        #expect(viewModel.items.map(\.id).sorted() == [1, 3])
        #expect(!viewModel.isFavorite(makeRecipe(id: 2, title: "Recipe 2")))
        #expect(favorites.setCalls.last?.isFavorite == false)
    }

    @Test func toggleFavoriteRevertsOnError() async {
        let fake = FakeRecipeService()
        fake.recipesToReturn = [makeRecipe(id: 1, title: "Carbonara")]
        let favorites = FakeFavoritesService()
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), favoritesService: favorites, snapshotStore: FakeSnapshotStore())
        await viewModel.load()
        favorites.setError = TestError()

        await viewModel.toggleFavorite(makeRecipe(id: 1, title: "Carbonara"))

        #expect(!viewModel.isFavorite(makeRecipe(id: 1, title: "Carbonara")))
        #expect(viewModel.errorMessage == "failed to load")
    }

    // MARK: - Reload/page race & dedupe

    @Test func staleNextPageIsDiscardedWhenAReloadSupersedesIt() async {
        // Sequence: a next-page fetch suspends in flight → the user's search
        // triggers a reload that replaces the list → the stale page resumes.
        // Its rows belong to the old, unfiltered list and must be dropped.
        let fake = GatedRecipeService()
        fake.recipesToReturn = (1...60).map { makeRecipe(id: Int64($0), title: "Recipe \($0)") }
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), snapshotStore: FakeSnapshotStore(), debounceDelay: .zero)
        await viewModel.load()
        #expect(viewModel.items.count == 50)

        // Suspend the next-page fetch at the gate.
        fake.gateNextFetch = true
        let pageTask = Task { await viewModel.loadMoreIfNeeded(currentItem: viewModel.items[49]) }
        await fake.waitUntilSuspended()

        // Reload with a search while the page is still in flight.
        fake.gateNextFetch = false
        viewModel.searchText = "Recipe 7"
        try? await Task.sleep(for: .milliseconds(50))
        let itemsAfterReload = viewModel.items.map(\.id)

        // Release the stale page; it must not append.
        await fake.openGate()
        await pageTask.value

        #expect(viewModel.items.map(\.id) == itemsAfterReload)
    }

    @Test func loadMoreDoesNothingWhileAReloadIsInFlight() async {
        let fake = GatedRecipeService()
        fake.recipesToReturn = (1...60).map { makeRecipe(id: Int64($0), title: "Recipe \($0)") }
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), snapshotStore: FakeSnapshotStore(), debounceDelay: .zero)
        await viewModel.load()
        let callsBefore = fake.fetchCallCount

        // Suspend the *reload* at the gate, then poke infinite scroll.
        fake.gateNextFetch = true
        viewModel.searchText = "Recipe"
        await fake.waitUntilSuspended()  // debounced reload reaches the gate
        fake.gateNextFetch = false
        await viewModel.loadMoreIfNeeded(currentItem: viewModel.items[49])
        #expect(fake.fetchCallCount == callsBefore + 1)  // only the reload fetched

        await fake.openGate()
        try? await Task.sleep(for: .milliseconds(20))
    }

    @Test func overlappingPagesNeverProduceDuplicateIds() async {
        // A page that overlaps rows already shown (e.g. a row inserted upstream
        // shifted the offsets) must not create duplicate Identifiable ids —
        // that's undefined behavior in the List's ForEach.
        let fake = OverlappingPageRecipeService()
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), snapshotStore: FakeSnapshotStore())
        await viewModel.load()
        #expect(viewModel.items.count == 50)

        await viewModel.loadMoreIfNeeded(currentItem: viewModel.items[49])

        let ids = viewModel.items.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    // MARK: - Offline snapshot

    @Test func loadPaintsCachedFirstPageWhenTheFetchFails() async {
        let store = FakeSnapshotStore()
        store.save([makeRecipe(id: 9, title: "Cached Carbonara")], key: .recipesFirstPage)
        let fake = FakeRecipeService()
        fake.errorToThrow = TestError()
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), snapshotStore: store)

        await viewModel.load()

        #expect(viewModel.items.map(\.title) == ["Cached Carbonara"])
        #expect(viewModel.errorMessage == "failed to load")
    }

    @Test func successfulUnfilteredLoadPersistsTheFirstPage() async {
        let store = FakeSnapshotStore()
        let fake = FakeRecipeService()
        fake.recipesToReturn = [makeRecipe(id: 1, title: "Carbonara")]
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), snapshotStore: store)

        await viewModel.load()

        let cached: [Recipe]? = store.load([Recipe].self, key: .recipesFirstPage)
        #expect(cached?.map(\.title) == ["Carbonara"])
    }

    @Test func filteredResultsAreNotPersistedAsTheFirstPage() async {
        let store = FakeSnapshotStore()
        let fake = FakeRecipeService()
        fake.recipesToReturn = [makeRecipe(id: 1, title: "Carbonara"), makeRecipe(id: 2, title: "Beef Tacos")]
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), snapshotStore: store, debounceDelay: .zero)
        await viewModel.load()

        viewModel.searchText = "taco"
        try? await Task.sleep(for: .milliseconds(50))

        // The snapshot still holds the unfiltered page, not the search results.
        let cached: [Recipe]? = store.load([Recipe].self, key: .recipesFirstPage)
        #expect(cached?.map(\.title) == ["Carbonara", "Beef Tacos"])
    }
}

/// A `FakeRecipeService` whose next `fetchPage` can be suspended at a gate,
/// letting tests interleave a reload with an in-flight page fetch. Main-actor
/// isolated so the gate bookkeeping can't race the test body.
@MainActor
final class GatedRecipeService: RecipeServicing {
    var recipesToReturn: [Recipe] = []
    /// When true, the next `fetchPage` call suspends until `openGate()`.
    var gateNextFetch = false
    private(set) var fetchCallCount = 0
    private var gateContinuation: CheckedContinuation<Void, Never>?
    private var suspendedContinuation: CheckedContinuation<Void, Never>?

    func fetchPage(offset: Int, limit: Int, matching search: String?, tag: String?, minPrepTime: Int?, maxPrepTime: Int?, minAtkRating: Double?) async throws -> [Recipe] {
        fetchCallCount += 1
        if gateNextFetch {
            gateNextFetch = false
            await withCheckedContinuation { continuation in
                gateContinuation = continuation
                suspendedContinuation?.resume()
                suspendedContinuation = nil
            }
        }
        let filtered = search.map { term in
            recipesToReturn.filter { $0.title.localizedCaseInsensitiveContains(term) }
        } ?? recipesToReturn
        let start = min(offset, filtered.count)
        let end = min(offset + limit, filtered.count)
        return Array(filtered[start..<end])
    }

    /// Suspends the caller until a gated `fetchPage` is actually waiting.
    func waitUntilSuspended() async {
        guard gateContinuation == nil else { return }
        await withCheckedContinuation { continuation in
            suspendedContinuation = continuation
        }
    }

    func openGate() async {
        gateContinuation?.resume()
        gateContinuation = nil
        // Let the resumed fetch finish before the test continues.
        await Task.yield()
    }

    func fetchDetail(id: Int64) async throws -> RecipeDetail { fatalError("not used") }
    func create(_ draft: RecipeDraft) async throws -> Recipe { fatalError("not used") }
    func update(id: Int64, with draft: RecipeDraft) async throws { fatalError("not used") }
    func delete(id: Int64) async throws { fatalError("not used") }
}

/// Returns a full 50-row first page, then a second page whose first rows
/// *overlap* the first page's tail — simulating offsets shifting under the
/// paginator (an upstream insert/delete between page fetches).
final class OverlappingPageRecipeService: RecipeServicing, @unchecked Sendable {
    func fetchPage(offset: Int, limit: Int, matching search: String?, tag: String?, minPrepTime: Int?, maxPrepTime: Int?, minAtkRating: Double?) async throws -> [Recipe] {
        let startId = offset == 0 ? 1 : offset - 9  // second page re-serves ids 41…
        return (0..<limit).map { i in
            Recipe(id: Int64(startId + i), userId: nil, title: "Recipe \(startId + i)", description: nil, instructions: nil, imagePath: nil, prepTime: 20, servings: 2, createdAt: Date())
        }
    }

    func fetchDetail(id: Int64) async throws -> RecipeDetail { fatalError("not used") }
    func create(_ draft: RecipeDraft) async throws -> Recipe { fatalError("not used") }
    func update(id: Int64, with draft: RecipeDraft) async throws { fatalError("not used") }
    func delete(id: Int64) async throws { fatalError("not used") }
}
