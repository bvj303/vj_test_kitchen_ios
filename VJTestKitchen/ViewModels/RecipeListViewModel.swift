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
    private(set) var isLoading = false
    private(set) var isLoadingPage = false
    private(set) var hasMorePages = true
    var errorMessage: String?

    /// How many rows before the end of `items` triggers the next page fetch.
    private static let prefetchThreshold = 5
    private static let pageSize = 50

    private let recipeService: RecipeServicing
    private let debouncer: Debouncer

    init(recipeService: RecipeServicing = RecipeService(), debounceDelay: Duration = .milliseconds(300)) {
        self.recipeService = recipeService
        self.debouncer = Debouncer(delay: debounceDelay)
    }

    func load() async {
        await reload()
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

    private func reload() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await recipeService.fetchPage(offset: 0, limit: Self.pageSize, matching: normalizedSearch)
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
            let page = try await recipeService.fetchPage(offset: items.count, limit: Self.pageSize, matching: normalizedSearch)
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
