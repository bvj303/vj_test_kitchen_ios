import Foundation
import Testing
@testable import VJTestKitchen

final class FakeRecipeDetailService: RecipeServicing, @unchecked Sendable {
    var detailToReturn: RecipeDetail!
    var errorToThrow: Error?

    func fetchPage(offset: Int, limit: Int, matching search: String?) async throws -> [Recipe] {
        fatalError("not used by RecipeDetailViewModelTests")
    }

    func fetchDetail(id: Int64) async throws -> RecipeDetail {
        if let errorToThrow { throw errorToThrow }
        return detailToReturn
    }

    func create(_ draft: RecipeDraft) async throws -> Recipe {
        fatalError("not used by RecipeDetailViewModelTests")
    }

    func update(id: Int64, with draft: RecipeDraft) async throws {
        fatalError("not used by RecipeDetailViewModelTests")
    }

    func delete(id: Int64) async throws {
        fatalError("not used by RecipeDetailViewModelTests")
    }
}

final class FakeRecipeRatingService: RecipeRatingServicing, @unchecked Sendable {
    var ratingToReturn: RecipeRating?
    private(set) var upsertedRating: Int?
    private(set) var upsertedNotes: String?
    var upsertError: Error?

    func fetchMine(recipeId: Int64) async throws -> RecipeRating? {
        ratingToReturn
    }

    func upsertMine(recipeId: Int64, rating: Int?, notes: String?) async throws {
        if let upsertError { throw upsertError }
        upsertedRating = rating
        upsertedNotes = notes
    }
}

private func makeDetail(id: Int64 = 1, title: String = "Carbonara") -> RecipeDetail {
    RecipeDetail(
        id: id, userId: nil, title: title, description: "desc", instructions: "steps",
        imagePath: nil, prepTime: 20, servings: 2, createdAt: Date(),
        ingredients: [Ingredient(id: 1, recipeId: id, name: "Pasta", amount: 200, unit: "g")],
        recipeTags: [.init(tags: .init(name: "Italian"))]
    )
}

private struct TestError: Error, LocalizedError {
    var errorDescription: String? { "failed" }
}

@MainActor
struct RecipeDetailViewModelTests {
    @Test func loadsDetailAndOwnRating() async {
        let recipes = FakeRecipeDetailService()
        recipes.detailToReturn = makeDetail()
        let ratings = FakeRecipeRatingService()
        ratings.ratingToReturn = RecipeRating(recipeId: 1, userId: UUID(), rating: 4, notes: "great", createdAt: Date(), updatedAt: Date())

        let viewModel = RecipeDetailViewModel(recipeId: 1, recipeService: recipes, ratingService: ratings)
        await viewModel.load()

        #expect(viewModel.detail?.title == "Carbonara")
        #expect(viewModel.detail?.tagNames == ["Italian"])
        #expect(viewModel.rating == 4)
        #expect(viewModel.notes == "great")
        #expect(viewModel.errorMessage == nil)
    }

    @Test func loadWithNoExistingRatingLeavesFieldsEmpty() async {
        let recipes = FakeRecipeDetailService()
        recipes.detailToReturn = makeDetail()
        let ratings = FakeRecipeRatingService()
        ratings.ratingToReturn = nil

        let viewModel = RecipeDetailViewModel(recipeId: 1, recipeService: recipes, ratingService: ratings)
        await viewModel.load()

        #expect(viewModel.rating == nil)
        #expect(viewModel.notes == "")
    }

    @Test func loadSurfacesErrorMessage() async {
        let recipes = FakeRecipeDetailService()
        recipes.errorToThrow = TestError()
        let ratings = FakeRecipeRatingService()

        let viewModel = RecipeDetailViewModel(recipeId: 1, recipeService: recipes, ratingService: ratings)
        await viewModel.load()

        #expect(viewModel.errorMessage == "failed")
    }

    @Test func saveRatingCallsServiceWithCurrentFields() async {
        let recipes = FakeRecipeDetailService()
        recipes.detailToReturn = makeDetail()
        let ratings = FakeRecipeRatingService()

        let viewModel = RecipeDetailViewModel(recipeId: 1, recipeService: recipes, ratingService: ratings)
        await viewModel.load()
        viewModel.rating = 5
        viewModel.notes = "add more pepper"

        await viewModel.saveRating()

        #expect(ratings.upsertedRating == 5)
        #expect(ratings.upsertedNotes == "add more pepper")
        #expect(viewModel.errorMessage == nil)
    }

    @Test func saveRatingSurfacesErrorMessage() async {
        let recipes = FakeRecipeDetailService()
        recipes.detailToReturn = makeDetail()
        let ratings = FakeRecipeRatingService()
        ratings.upsertError = TestError()

        let viewModel = RecipeDetailViewModel(recipeId: 1, recipeService: recipes, ratingService: ratings)
        await viewModel.load()
        await viewModel.saveRating()

        #expect(viewModel.errorMessage == "failed")
    }

    @Test func loadReflectsWhetherRecipeIsAlreadyOnGroceryList() async {
        let recipes = FakeRecipeDetailService()
        recipes.detailToReturn = makeDetail(id: 1)
        let groceryStore = FakeGroceryListStore()
        groceryStore.ids = [1, 2]

        let viewModel = RecipeDetailViewModel(recipeId: 1, recipeService: recipes, ratingService: FakeRecipeRatingService(), groceryListStore: groceryStore)
        await viewModel.load()

        #expect(viewModel.isInGroceryList == true)
    }

    @Test func toggleGroceryListAddsThenRemoves() async {
        let recipes = FakeRecipeDetailService()
        recipes.detailToReturn = makeDetail(id: 1)
        let groceryStore = FakeGroceryListStore()

        let viewModel = RecipeDetailViewModel(recipeId: 1, recipeService: recipes, ratingService: FakeRecipeRatingService(), groceryListStore: groceryStore)
        await viewModel.load()
        #expect(viewModel.isInGroceryList == false)

        viewModel.toggleGroceryList()
        #expect(viewModel.isInGroceryList == true)
        #expect(groceryStore.ids == [1])

        viewModel.toggleGroceryList()
        #expect(viewModel.isInGroceryList == false)
        #expect(groceryStore.ids.isEmpty)
    }

    @Test func addIngredientToGroceryListSnapshotsIngredientAsCustomItem() async {
        let recipes = FakeRecipeDetailService()
        recipes.detailToReturn = makeDetail(id: 1)
        let groceryStore = FakeGroceryListStore()

        let viewModel = RecipeDetailViewModel(recipeId: 1, recipeService: recipes, ratingService: FakeRecipeRatingService(), groceryListStore: groceryStore)
        await viewModel.load()
        let ingredient = viewModel.detail!.ingredients[0]

        viewModel.addIngredientToGroceryList(ingredient)

        #expect(groceryStore.customItems.map(\.name) == ["Pasta"])
        #expect(groceryStore.customItems.first?.amount == 200)
        #expect(groceryStore.customItems.first?.unit == "g")
        // Adding an individual ingredient shouldn't also add the whole recipe.
        #expect(groceryStore.ids.isEmpty)
        #expect(viewModel.addedIngredientIds.contains(ingredient.id))
    }
}
