import Foundation
import Testing
@testable import VJTestKitchen

final class FakeRecipeService: RecipeServicing, @unchecked Sendable {
    var recipesToReturn: [Recipe] = []
    var errorToThrow: Error?
    private(set) var deletedIds: [Int64] = []
    private(set) var fetchedPages: [(offset: Int, limit: Int, search: String?)] = []

    func fetchPage(offset: Int, limit: Int, matching search: String?) async throws -> [Recipe] {
        fetchedPages.append((offset, limit, search))
        if let errorToThrow { throw errorToThrow }
        let filtered = search.map { term in
            recipesToReturn.filter { $0.title.localizedCaseInsensitiveContains(term) }
        } ?? recipesToReturn
        let start = min(offset, filtered.count)
        let end = min(offset + limit, filtered.count)
        return Array(filtered[start..<end])
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

private func makeRecipe(id: Int64, title: String) -> Recipe {
    Recipe(id: id, userId: nil, title: title, description: nil, instructions: nil, imagePath: nil, prepTime: 20, servings: 2, createdAt: Date())
}

private struct TestError: Error, LocalizedError {
    var errorDescription: String? { "failed to load" }
}

@MainActor
struct RecipeListViewModelTests {
    @Test func loadsRecipesOnStart() async {
        let fake = FakeRecipeService()
        fake.recipesToReturn = [makeRecipe(id: 1, title: "Carbonara"), makeRecipe(id: 2, title: "Tacos")]
        let viewModel = RecipeListViewModel(recipeService: fake)

        await viewModel.load()

        #expect(viewModel.items.map(\.title) == ["Carbonara", "Tacos"])
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isLoading == false)
    }

    @Test func loadSurfacesErrorMessage() async {
        let fake = FakeRecipeService()
        fake.errorToThrow = TestError()
        let viewModel = RecipeListViewModel(recipeService: fake)

        await viewModel.load()

        #expect(viewModel.errorMessage == "failed to load")
        #expect(viewModel.items.isEmpty)
    }

    @Test func searchTextReloadsFromServerAfterDebounce() async {
        let fake = FakeRecipeService()
        fake.recipesToReturn = [makeRecipe(id: 1, title: "Carbonara"), makeRecipe(id: 2, title: "Beef Tacos")]
        let viewModel = RecipeListViewModel(recipeService: fake, debounceDelay: .zero)
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
        let viewModel = RecipeListViewModel(recipeService: fake, debounceDelay: .zero)
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
        let viewModel = RecipeListViewModel(recipeService: fake)
        await viewModel.load()
        #expect(viewModel.items.count == 50)

        await viewModel.loadMoreIfNeeded(currentItem: viewModel.items[49])

        #expect(viewModel.items.count == 60)
        #expect(fake.fetchedPages.last?.offset == 50)
    }

    @Test func loadMoreIfNeededDoesNothingWhenFarFromEndOfList() async {
        let fake = FakeRecipeService()
        fake.recipesToReturn = (1...60).map { makeRecipe(id: Int64($0), title: "Recipe \($0)") }
        let viewModel = RecipeListViewModel(recipeService: fake)
        await viewModel.load()
        let pageCountBefore = fake.fetchedPages.count

        await viewModel.loadMoreIfNeeded(currentItem: viewModel.items[0])

        #expect(viewModel.items.count == 50)
        #expect(fake.fetchedPages.count == pageCountBefore)
    }
}
