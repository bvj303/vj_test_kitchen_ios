import Foundation
import Testing
@testable import VJTestKitchen

final class FakeRecipeService: RecipeServicing, @unchecked Sendable {
    var recipesToReturn: [Recipe] = []
    var errorToThrow: Error?
    private(set) var deletedIds: [Int64] = []
    private(set) var fetchedPages: [(offset: Int, limit: Int, search: String?, tag: String?, minPrepTime: Int?, maxPrepTime: Int?)] = []

    func fetchPage(offset: Int, limit: Int, matching search: String?, tag: String?, minPrepTime: Int?, maxPrepTime: Int?) async throws -> [Recipe] {
        fetchedPages.append((offset, limit, search, tag, minPrepTime, maxPrepTime))
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

private func makeRecipe(id: Int64, title: String, prepTime: Int? = 20) -> Recipe {
    Recipe(id: id, userId: nil, title: title, description: nil, instructions: nil, imagePath: nil, prepTime: prepTime, servings: 2, createdAt: Date())
}

private struct TestError: Error, LocalizedError {
    var errorDescription: String? { "failed to load" }
}

@MainActor
struct RecipeListViewModelTests {
    @Test func loadsRecipesOnStart() async {
        let fake = FakeRecipeService()
        fake.recipesToReturn = [makeRecipe(id: 1, title: "Carbonara"), makeRecipe(id: 2, title: "Tacos")]
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService())

        await viewModel.load()

        #expect(viewModel.items.map(\.title) == ["Carbonara", "Tacos"])
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isLoading == false)
    }

    @Test func loadSurfacesErrorMessage() async {
        let fake = FakeRecipeService()
        fake.errorToThrow = TestError()
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService())

        await viewModel.load()

        #expect(viewModel.errorMessage == "failed to load")
        #expect(viewModel.items.isEmpty)
    }

    @Test func searchTextReloadsFromServerAfterDebounce() async {
        let fake = FakeRecipeService()
        fake.recipesToReturn = [makeRecipe(id: 1, title: "Carbonara"), makeRecipe(id: 2, title: "Beef Tacos")]
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), debounceDelay: .zero)
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
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), debounceDelay: .zero)
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
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService())
        await viewModel.load()
        #expect(viewModel.items.count == 50)

        await viewModel.loadMoreIfNeeded(currentItem: viewModel.items[49])

        #expect(viewModel.items.count == 60)
        #expect(fake.fetchedPages.last?.offset == 50)
    }

    @Test func loadMoreIfNeededDoesNothingWhenFarFromEndOfList() async {
        let fake = FakeRecipeService()
        fake.recipesToReturn = (1...60).map { makeRecipe(id: Int64($0), title: "Recipe \($0)") }
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService())
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
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: tags)

        await viewModel.load()

        #expect(viewModel.availableTags == ["Appetizers", "Italian", "Main Courses", "Mexican"])
        // Course tags come back in the fixed menu order, not alphabetical.
        #expect(viewModel.courseTags == ["Main Courses", "Appetizers"])
        #expect(viewModel.cuisineTags == ["Italian", "Mexican"])
    }

    @Test func selectingTagReloadsFromServerWithThatTag() async {
        let fake = FakeRecipeService()
        fake.recipesToReturn = [makeRecipe(id: 1, title: "Carbonara"), makeRecipe(id: 2, title: "Tacos")]
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), debounceDelay: .zero)
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
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), debounceDelay: .zero)
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
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), debounceDelay: .zero)
        await viewModel.load()

        viewModel.prepTimeFilter = .overnight
        try? await Task.sleep(for: .milliseconds(50))

        #expect(fake.fetchedPages.last?.minPrepTime == 480)
        #expect(fake.fetchedPages.last?.maxPrepTime == nil)
        #expect(viewModel.items.map(\.title) == ["Overnight Brisket"])
    }

    @Test func clearFiltersResetsTagAndPrepTimeAndReloads() async {
        let fake = FakeRecipeService()
        fake.recipesToReturn = [makeRecipe(id: 1, title: "Carbonara")]
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), debounceDelay: .zero)
        await viewModel.load()
        viewModel.selectedTag = "Italian"
        viewModel.prepTimeFilter = .under30
        try? await Task.sleep(for: .milliseconds(50))
        #expect(viewModel.hasActiveFilters)

        viewModel.clearFilters()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(!viewModel.hasActiveFilters)
        #expect(viewModel.selectedTag == nil)
        #expect(viewModel.prepTimeFilter == nil)
        #expect(fake.fetchedPages.last?.tag == nil)
        #expect(fake.fetchedPages.last?.maxPrepTime == nil)
    }

    // MARK: - Favorites

    @Test func loadPopulatesFavoriteIds() async {
        let fake = FakeRecipeService()
        fake.recipesToReturn = [makeRecipe(id: 1, title: "Carbonara"), makeRecipe(id: 2, title: "Tacos")]
        let favorites = FakeFavoritesService()
        favorites.favoriteIds = [2]
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), favoritesService: favorites)

        await viewModel.load()

        #expect(viewModel.isFavorite(makeRecipe(id: 2, title: "Tacos")))
        #expect(!viewModel.isFavorite(makeRecipe(id: 1, title: "Carbonara")))
    }

    @Test func favoritesFilterShowsOnlyFavoritedRecipes() async {
        let fake = FakeRecipeService()
        fake.recipesToReturn = (1...3).map { makeRecipe(id: Int64($0), title: "Recipe \($0)") }
        let favorites = FakeFavoritesService()
        favorites.favoriteIds = [1, 3]
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), favoritesService: favorites, debounceDelay: .zero)
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
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), favoritesService: favorites, debounceDelay: .zero)
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
        let viewModel = RecipeListViewModel(recipeService: fake, tagService: FakeTagService(), favoritesService: favorites)
        await viewModel.load()
        favorites.setError = TestError()

        await viewModel.toggleFavorite(makeRecipe(id: 1, title: "Carbonara"))

        #expect(!viewModel.isFavorite(makeRecipe(id: 1, title: "Carbonara")))
        #expect(viewModel.errorMessage == "failed to load")
    }
}
