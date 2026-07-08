import Foundation
import Observation

@MainActor
@Observable
final class RecipeListViewModel {
    private(set) var items: [Recipe] = []
    var searchText = "" {
        didSet {
            guard oldValue != searchText else { return }
            debouncer.run { [weak self] in await self?.reload() }
        }
    }
    /// Category (tag) filter — nil means "all". Changing it re-queries from the
    /// top through the same debouncer as search so rapid toggles coalesce.
    var selectedTag: String? {
        didSet {
            guard oldValue != selectedTag else { return }
            debouncer.run { [weak self] in await self?.reload() }
        }
    }
    /// Prep-time range filter — nil means "any". Decomposes to gte/lte bounds
    /// when querying (see `PrepTimeFilter`).
    var prepTimeFilter: PrepTimeFilter? {
        didSet {
            guard oldValue != prepTimeFilter else { return }
            debouncer.run { [weak self] in await self?.reload() }
        }
    }
    /// When on, the list shows only the user's favorited recipes (resolved by id
    /// then fetched), narrowed by the search text but not paginated.
    var showFavoritesOnly = false {
        didSet {
            guard oldValue != showFavoritesOnly else { return }
            debouncer.run { [weak self] in await self?.reload() }
        }
    }

    /// The user's favorite recipe ids, loaded once on `load()` and kept current
    /// as rows are toggled — drives the row heart and the Favorites filter.
    private(set) var favoriteIds: Set<Int64> = []

    /// Every tag in the catalog, alphabetical, loaded once. Split into
    /// `courseTags`/`cuisineTags` for the grouped filter menu.
    private(set) var availableTags: [String] = []
    private(set) var isLoading = false
    private(set) var isLoadingPage = false
    private(set) var hasMorePages = true
    var errorMessage: String?

    /// The broad "what kind of dish" tags, kept first and in menu order; every
    /// other tag is treated as a cuisine/origin.
    static let courseTagOrder = ["Main Courses", "Side Dishes", "Appetizers", "Desserts"]

    var courseTags: [String] {
        Self.courseTagOrder.filter { availableTags.contains($0) }
    }

    var cuisineTags: [String] {
        availableTags.filter { !Self.courseTagOrder.contains($0) }
    }

    var hasActiveFilters: Bool {
        selectedTag != nil || prepTimeFilter != nil || showFavoritesOnly
    }

    /// True when the current empty list is the result of a search/filter (vs an
    /// empty catalog) — lets the view show the right "no results" message.
    var isFilteringOrSearching: Bool {
        !searchText.isEmpty || hasActiveFilters
    }

    func isFavorite(_ recipe: Recipe) -> Bool { favoriteIds.contains(recipe.id) }

    /// How many rows before the end of `items` triggers the next page fetch.
    private static let prefetchThreshold = 5
    private static let pageSize = 50

    private let recipeService: RecipeServicing
    private let tagService: TagServicing
    private let favoritesService: FavoritesServicing
    private let imagePrefetcher: ImagePrefetching
    private let debouncer: Debouncer

    init(
        recipeService: RecipeServicing = RecipeService(),
        tagService: TagServicing = TagService(),
        favoritesService: FavoritesServicing = FavoritesService(),
        imagePrefetcher: ImagePrefetching = ImagePrefetcher.shared,
        debounceDelay: Duration = .milliseconds(300)
    ) {
        self.recipeService = recipeService
        self.tagService = tagService
        self.favoritesService = favoritesService
        self.imagePrefetcher = imagePrefetcher
        self.debouncer = Debouncer(delay: debounceDelay)
    }

    func load() async {
        if availableTags.isEmpty {
            await loadTags()
        }
        await loadFavoriteIds()
        await reload()
    }

    func clearFilters() {
        // Assign through the observed properties so their didSet fires; the
        // debouncer coalesces the changes into a single reload.
        selectedTag = nil
        prepTimeFilter = nil
        showFavoritesOnly = false
    }

    /// A missing favorites set only disables the heart/filter — never blocks the list.
    private func loadFavoriteIds() async {
        favoriteIds = (try? await favoritesService.fetchMyFavoriteIds()) ?? []
    }

    /// Toggles a row's favorite state (optimistic; reverts on error). If the
    /// Favorites filter is on, unfavoriting drops the row on the next reload.
    func toggleFavorite(_ recipe: Recipe) async {
        let nowFavorite = !favoriteIds.contains(recipe.id)
        if nowFavorite { favoriteIds.insert(recipe.id) } else { favoriteIds.remove(recipe.id) }
        do {
            try await favoritesService.setFavorite(recipeId: recipe.id, isFavorite: nowFavorite)
            if showFavoritesOnly, !nowFavorite {
                items.removeAll { $0.id == recipe.id }
            }
        } catch {
            if nowFavorite { favoriteIds.remove(recipe.id) } else { favoriteIds.insert(recipe.id) }
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// Called from the list row's `.onAppear` (wrapped in a `Task` by the
    /// view, since `onAppear` itself isn't async) to drive infinite scroll.
    func loadMoreIfNeeded(currentItem: Recipe) async {
        guard hasMorePages, !isLoadingPage,
              let index = items.firstIndex(where: { $0.id == currentItem.id }),
              index >= items.count - Self.prefetchThreshold
        else { return }
        await loadNextPage()
    }

    private func loadTags() async {
        // A missing tag list only disables the category filter — never block or
        // fail the recipe list over it.
        availableTags = (try? await tagService.fetchAllNames()) ?? []
    }

    private func reload() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            if showFavoritesOnly {
                // Favorites are a small, bounded set: fetch them all by id and
                // narrow by the search text client-side (no pagination).
                let favorites = try await recipeService.fetchByIds(favoriteIds.sorted())
                items = filteredBySearch(favorites)
                hasMorePages = false
                prefetchImages(for: items)
                return
            }
            let page = try await recipeService.fetchPage(
                offset: 0, limit: Self.pageSize,
                matching: normalizedSearch, tag: selectedTag,
                minPrepTime: prepTimeFilter?.minMinutes, maxPrepTime: prepTimeFilter?.maxMinutes
            )
            items = page
            hasMorePages = page.count == Self.pageSize
            prefetchImages(for: page)
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// Client-side title filter for the favorites path (case/diacritic-insensitive).
    private func filteredBySearch(_ recipes: [Recipe]) -> [Recipe] {
        guard let search = normalizedSearch else { return recipes }
        return recipes.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }

    private func loadNextPage() async {
        isLoadingPage = true
        defer { isLoadingPage = false }
        do {
            let page = try await recipeService.fetchPage(
                offset: items.count, limit: Self.pageSize,
                matching: normalizedSearch, tag: selectedTag,
                minPrepTime: prepTimeFilter?.minMinutes, maxPrepTime: prepTimeFilter?.maxMinutes
            )
            items.append(contentsOf: page)
            hasMorePages = page.count == Self.pageSize
            prefetchImages(for: page)
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// Warm the image cache for a freshly-loaded page so `CachedAsyncImage`
    /// renders each thumbnail immediately when its row scrolls in, rather than
    /// fading in after an on-appearance fetch. Pages load ~5 rows before the
    /// user reaches them (see `prefetchThreshold`), so this front-runs the
    /// downloads by roughly a screen.
    private func prefetchImages(for page: [Recipe]) {
        let urls = page.compactMap { recipe -> URL? in
            guard let imageUrl = recipe.imageUrl, !imageUrl.isEmpty else { return nil }
            return URL(string: imageUrl)
        }
        guard !urls.isEmpty else { return }
        imagePrefetcher.prefetch(urls)
    }

    private var normalizedSearch: String? {
        searchText.isEmpty ? nil : searchText
    }
}
