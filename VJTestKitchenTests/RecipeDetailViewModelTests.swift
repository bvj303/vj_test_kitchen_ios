import Foundation
import Testing
@testable import VJTestKitchen

final class FakeRecipeDetailService: RecipeServicing, @unchecked Sendable {
    var detailToReturn: RecipeDetail!
    var errorToThrow: Error?

    func fetchPage(offset: Int, limit: Int, matching search: String?, tag: String?, minPrepTime: Int?, maxPrepTime: Int?) async throws -> [Recipe] {
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
    var reviewsToReturn: [RecipeReview] = []
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

    func fetchReviews(recipeId: Int64) async throws -> [RecipeReview] {
        reviewsToReturn
    }
}

final class FakeFavoritesService: FavoritesServicing, @unchecked Sendable {
    var favoriteIds: Set<Int64> = []
    var setError: Error?
    private(set) var setCalls: [(recipeId: Int64, isFavorite: Bool)] = []

    func fetchMyFavoriteIds() async throws -> Set<Int64> { favoriteIds }

    func setFavorite(recipeId: Int64, isFavorite: Bool) async throws {
        if let setError { throw setError }
        setCalls.append((recipeId, isFavorite))
        if isFavorite { favoriteIds.insert(recipeId) } else { favoriteIds.remove(recipeId) }
    }
}

private func makeReview(userId: UUID = UUID(), rating: Int? = nil, notes: String? = nil, name: String = "Sam") -> RecipeReview {
    RecipeReview(
        userId: userId, rating: rating, notes: notes, updatedAt: Date(),
        profile: .init(displayName: name, username: nil, avatarUrl: nil)
    )
}

private func makeDetail(id: Int64 = 1, title: String = "Carbonara") -> RecipeDetail {
    RecipeDetail(
        id: id, userId: nil, title: title, description: "desc", instructions: "steps",
        imagePath: nil, prepTime: 20, servings: 2, createdAt: Date(),
        ingredients: [
            Ingredient(id: 1, recipeId: id, name: "Pasta", amount: 200, unit: "g"),
            Ingredient(id: 2, recipeId: id, name: "Pancetta", amount: 100, unit: "g"),
        ],
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

    @Test func addIngredientAddsToGroceryListTaggedWithRecipeSource() async {
        let recipes = FakeRecipeDetailService()
        recipes.detailToReturn = makeDetail(id: 1, title: "Carbonara")
        let grocery = FakeGroceryItemService()

        let viewModel = RecipeDetailViewModel(recipeId: 1, recipeService: recipes, ratingService: FakeRecipeRatingService(), groceryItemService: grocery)
        await viewModel.load()
        let ingredient = viewModel.detail!.ingredients[0]

        await viewModel.addIngredientToGroceryList(ingredient)

        #expect(grocery.addedDrafts.count == 1)
        #expect(grocery.addedDrafts.first?.name == "Pasta")
        #expect(grocery.addedDrafts.first?.sourceRecipeId == 1)
        #expect(grocery.addedDrafts.first?.sourceRecipeTitle == "Carbonara")
        #expect(viewModel.addedIngredientIds.contains(ingredient.id))
    }

    @Test func addAllIngredientsTagsEveryItemWithRecipe() async {
        let recipes = FakeRecipeDetailService()
        recipes.detailToReturn = makeDetail(id: 1, title: "Carbonara")
        let grocery = FakeGroceryItemService()

        let viewModel = RecipeDetailViewModel(recipeId: 1, recipeService: recipes, ratingService: FakeRecipeRatingService(), groceryItemService: grocery)
        await viewModel.load()

        await viewModel.addAllIngredientsToGroceryList()

        #expect(grocery.addedDrafts.count == viewModel.detail!.ingredients.count)
        #expect(grocery.addedDrafts.allSatisfy { $0.sourceRecipeTitle == "Carbonara" })
        #expect(viewModel.didAddAllToGroceryList == true)
    }

    @Test func addIngredientScalesAndNormalizesTheGroceryDraft() async {
        let recipes = FakeRecipeDetailService()
        // A row with the imported mixed-number bug: amount=1, unit="",
        // name="½ teaspoons paprika" really means 1½ teaspoons paprika.
        recipes.detailToReturn = RecipeDetail(
            id: 1, userId: nil, title: "Rub", description: nil, instructions: nil,
            imagePath: nil, prepTime: 5, servings: 4, createdAt: Date(),
            ingredients: [Ingredient(id: 1, recipeId: 1, name: "½ teaspoons paprika", amount: 1, unit: "")],
            recipeTags: []
        )
        let grocery = FakeGroceryItemService()
        let viewModel = RecipeDetailViewModel(recipeId: 1, recipeService: recipes, ratingService: FakeRecipeRatingService(), groceryItemService: grocery)
        await viewModel.load()

        await viewModel.addIngredientToGroceryList(viewModel.detail!.ingredients[0], scale: 2)

        let draft = grocery.addedDrafts.first
        #expect(draft?.name == "paprika")        // fraction/unit peeled out of the name
        #expect(draft?.unit == "teaspoons")      // unit recovered
        #expect(draft?.amount == 3)              // (1 + ½) × 2
    }

    @Test func addIngredientSurfacesErrorMessageAndDoesNotMarkAdded() async {
        let recipes = FakeRecipeDetailService()
        recipes.detailToReturn = makeDetail(id: 1)
        let grocery = FakeGroceryItemService()
        grocery.addError = TestError()

        let viewModel = RecipeDetailViewModel(recipeId: 1, recipeService: recipes, ratingService: FakeRecipeRatingService(), groceryItemService: grocery)
        await viewModel.load()

        await viewModel.addIngredientToGroceryList(viewModel.detail!.ingredients[0])

        #expect(viewModel.errorMessage == "failed")
        #expect(viewModel.addedIngredientIds.isEmpty)
    }

    @Test func removeIngredientDeletesItsGroceryItemAndClearsAddedState() async {
        let recipes = FakeRecipeDetailService()
        recipes.detailToReturn = makeDetail(id: 1, title: "Carbonara")
        let grocery = FakeGroceryItemService()

        let viewModel = RecipeDetailViewModel(recipeId: 1, recipeService: recipes, ratingService: FakeRecipeRatingService(), groceryItemService: grocery)
        await viewModel.load()
        let ingredient = viewModel.detail!.ingredients[0]

        await viewModel.addIngredientToGroceryList(ingredient)
        #expect(viewModel.isInGroceryList(ingredient))
        #expect(grocery.items.count == 1)

        await viewModel.removeIngredientFromGroceryList(ingredient)

        #expect(!viewModel.isInGroceryList(ingredient))
        #expect(viewModel.addedIngredientIds.isEmpty)
        #expect(grocery.items.isEmpty)
    }

    @Test func removeIngredientNeverAddedIsANoOp() async {
        let recipes = FakeRecipeDetailService()
        recipes.detailToReturn = makeDetail(id: 1)
        let grocery = FakeGroceryItemService()

        let viewModel = RecipeDetailViewModel(recipeId: 1, recipeService: recipes, ratingService: FakeRecipeRatingService(), groceryItemService: grocery)
        await viewModel.load()

        await viewModel.removeIngredientFromGroceryList(viewModel.detail!.ingredients[0])

        #expect(viewModel.errorMessage == nil)
    }

    @Test func removeIngredientSurfacesErrorAndLeavesItMarkedAdded() async {
        let recipes = FakeRecipeDetailService()
        recipes.detailToReturn = makeDetail(id: 1)
        let grocery = FakeGroceryItemService()

        let viewModel = RecipeDetailViewModel(recipeId: 1, recipeService: recipes, ratingService: FakeRecipeRatingService(), groceryItemService: grocery)
        await viewModel.load()
        let ingredient = viewModel.detail!.ingredients[0]
        await viewModel.addIngredientToGroceryList(ingredient)
        grocery.mutationError = TestError()

        await viewModel.removeIngredientFromGroceryList(ingredient)

        #expect(viewModel.errorMessage == "failed")
        #expect(viewModel.isInGroceryList(ingredient))
    }

    @Test func addAllThenRemoveOneAllowsAddAllAgainWithoutDuplicating() async {
        let recipes = FakeRecipeDetailService()
        recipes.detailToReturn = makeDetail(id: 1, title: "Carbonara")
        let grocery = FakeGroceryItemService()

        let viewModel = RecipeDetailViewModel(recipeId: 1, recipeService: recipes, ratingService: FakeRecipeRatingService(), groceryItemService: grocery)
        await viewModel.load()
        let ingredients = viewModel.detail!.ingredients

        await viewModel.addAllIngredientsToGroceryList()
        #expect(viewModel.didAddAllToGroceryList == true)

        await viewModel.removeIngredientFromGroceryList(ingredients[0])
        #expect(viewModel.didAddAllToGroceryList == false)
        #expect(grocery.items.count == ingredients.count - 1)

        // Re-tapping "Add All" should only add the one that's missing, not
        // re-add (and duplicate) the ones still on the list.
        await viewModel.addAllIngredientsToGroceryList()

        #expect(viewModel.didAddAllToGroceryList == true)
        #expect(grocery.items.count == ingredients.count)
        #expect(grocery.addedDrafts.count == ingredients.count + 1)
    }

    // MARK: - Favorites

    @Test func loadReflectsFavoriteState() async {
        let recipes = FakeRecipeDetailService()
        recipes.detailToReturn = makeDetail(id: 7)
        let favorites = FakeFavoritesService()
        favorites.favoriteIds = [7]

        let viewModel = RecipeDetailViewModel(recipeId: 7, recipeService: recipes, ratingService: FakeRecipeRatingService(), favoritesService: favorites)
        await viewModel.load()

        #expect(viewModel.isFavorite == true)
    }

    @Test func toggleFavoriteOptimisticallyPersists() async {
        let recipes = FakeRecipeDetailService()
        recipes.detailToReturn = makeDetail(id: 7)
        let favorites = FakeFavoritesService()

        let viewModel = RecipeDetailViewModel(recipeId: 7, recipeService: recipes, ratingService: FakeRecipeRatingService(), favoritesService: favorites)
        await viewModel.load()
        #expect(viewModel.isFavorite == false)

        await viewModel.toggleFavorite()

        #expect(viewModel.isFavorite == true)
        #expect(favorites.setCalls.last?.isFavorite == true)
        #expect(favorites.favoriteIds.contains(7))
    }

    @Test func toggleFavoriteRevertsOnError() async {
        let recipes = FakeRecipeDetailService()
        recipes.detailToReturn = makeDetail(id: 7)
        let favorites = FakeFavoritesService()
        favorites.setError = TestError()

        let viewModel = RecipeDetailViewModel(recipeId: 7, recipeService: recipes, ratingService: FakeRecipeRatingService(), favoritesService: favorites)
        await viewModel.load()

        await viewModel.toggleFavorite()

        #expect(viewModel.isFavorite == false)
        #expect(viewModel.errorMessage == "failed")
    }

    // MARK: - Community ratings

    @Test func communitySummaryAveragesAllAndOtherReviewsExcludeSelf() async {
        let me = UUID()
        let recipes = FakeRecipeDetailService()
        recipes.detailToReturn = makeDetail(id: 1)
        let ratings = FakeRecipeRatingService()
        ratings.reviewsToReturn = [
            makeReview(userId: me, rating: 5, notes: "mine", name: "Me"),
            makeReview(rating: 4, notes: "solid", name: "Ada"),
            makeReview(rating: 3, notes: nil, name: "Bo"),
        ]

        let viewModel = RecipeDetailViewModel(recipeId: 1, recipeService: recipes, ratingService: ratings)
        viewModel.currentUserId = me
        await viewModel.load()

        // Average across all three raters (5+4+3)/3 = 4.0, count 3.
        #expect(viewModel.communitySummary.count == 3)
        #expect(viewModel.communitySummary.average == 4.0)
        // The current user's own review is omitted from the "others" list.
        #expect(viewModel.otherReviews.count == 2)
        #expect(viewModel.otherReviews.allSatisfy { $0.userId != me })
    }
}
