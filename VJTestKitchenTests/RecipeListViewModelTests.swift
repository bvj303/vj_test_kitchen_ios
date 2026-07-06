import Foundation
import Testing
@testable import VJTestKitchen

final class FakeRecipeService: RecipeServicing, @unchecked Sendable {
    var recipesToReturn: [Recipe] = []
    var errorToThrow: Error?
    private(set) var deletedIds: [Int64] = []

    func fetchAll() async throws -> [Recipe] {
        if let errorToThrow { throw errorToThrow }
        return recipesToReturn
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

        #expect(viewModel.recipes.map(\.title) == ["Carbonara", "Tacos"])
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isLoading == false)
    }

    @Test func loadSurfacesErrorMessage() async {
        let fake = FakeRecipeService()
        fake.errorToThrow = TestError()
        let viewModel = RecipeListViewModel(recipeService: fake)

        await viewModel.load()

        #expect(viewModel.errorMessage == "failed to load")
        #expect(viewModel.recipes.isEmpty)
    }

    @Test func searchTextFiltersByTitleCaseInsensitively() async {
        let fake = FakeRecipeService()
        fake.recipesToReturn = [makeRecipe(id: 1, title: "Carbonara"), makeRecipe(id: 2, title: "Beef Tacos")]
        let viewModel = RecipeListViewModel(recipeService: fake)
        await viewModel.load()

        viewModel.searchText = "taco"

        #expect(viewModel.filteredRecipes.map(\.title) == ["Beef Tacos"])
    }

    @Test func emptySearchTextShowsAllRecipes() async {
        let fake = FakeRecipeService()
        fake.recipesToReturn = [makeRecipe(id: 1, title: "Carbonara"), makeRecipe(id: 2, title: "Tacos")]
        let viewModel = RecipeListViewModel(recipeService: fake)
        await viewModel.load()

        viewModel.searchText = ""

        #expect(viewModel.filteredRecipes.count == 2)
    }
}
