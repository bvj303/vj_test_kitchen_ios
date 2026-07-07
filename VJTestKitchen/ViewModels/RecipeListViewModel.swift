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
    /// Upper bound on `prep_time` in minutes — nil means "any".
    var maxPrepTime: Int? {
        didSet {
            guard oldValue != maxPrepTime else { return }
            debouncer.run { [weak self] in await self?.reload() }
        }
    }

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

    /// Prep-time ceilings (minutes) offered in the filter menu.
    static let prepTimeOptions = [30, 45, 60]

    var courseTags: [String] {
        Self.courseTagOrder.filter { availableTags.contains($0) }
    }

    var cuisineTags: [String] {
        availableTags.filter { !Self.courseTagOrder.contains($0) }
    }

    var hasActiveFilters: Bool {
        selectedTag != nil || maxPrepTime != nil
    }

    /// True when the current empty list is the result of a search/filter (vs an
    /// empty catalog) — lets the view show the right "no results" message.
    var isFilteringOrSearching: Bool {
        !searchText.isEmpty || hasActiveFilters
    }

    /// How many rows before the end of `items` triggers the next page fetch.
    private static let prefetchThreshold = 5
    private static let pageSize = 50

    private let recipeService: RecipeServicing
    private let tagService: TagServicing
    private let debouncer: Debouncer

    init(
        recipeService: RecipeServicing = RecipeService(),
        tagService: TagServicing = TagService(),
        debounceDelay: Duration = .milliseconds(300)
    ) {
        self.recipeService = recipeService
        self.tagService = tagService
        self.debouncer = Debouncer(delay: debounceDelay)
    }

    func load() async {
        if availableTags.isEmpty {
            await loadTags()
        }
        await reload()
    }

    func clearFilters() {
        // Assign through the observed properties so their didSet fires; the
        // debouncer coalesces the two changes into a single reload.
        selectedTag = nil
        maxPrepTime = nil
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
            let page = try await recipeService.fetchPage(
                offset: 0, limit: Self.pageSize,
                matching: normalizedSearch, tag: selectedTag, maxPrepTime: maxPrepTime
            )
            items = page
            hasMorePages = page.count == Self.pageSize
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    private func loadNextPage() async {
        isLoadingPage = true
        defer { isLoadingPage = false }
        do {
            let page = try await recipeService.fetchPage(
                offset: items.count, limit: Self.pageSize,
                matching: normalizedSearch, tag: selectedTag, maxPrepTime: maxPrepTime
            )
            items.append(contentsOf: page)
            hasMorePages = page.count == Self.pageSize
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    private var normalizedSearch: String? {
        searchText.isEmpty ? nil : searchText
    }
}
