import Foundation
import Testing
@testable import VJTestKitchen

final class FakeRecipeFormRecipeService: RecipeServicing, @unchecked Sendable {
    var detailToReturn: RecipeDetail!
    var createdRecipeId: Int64 = 42
    var errorToThrow: Error?
    private(set) var createdDraft: RecipeDraft?
    private(set) var updatedId: Int64?
    private(set) var updatedDraft: RecipeDraft?

    func fetchAll() async throws -> [Recipe] { fatalError("not used") }

    func fetchDetail(id: Int64) async throws -> RecipeDetail {
        if let errorToThrow { throw errorToThrow }
        return detailToReturn
    }

    func create(_ draft: RecipeDraft) async throws -> Recipe {
        if let errorToThrow { throw errorToThrow }
        createdDraft = draft
        return Recipe(
            id: createdRecipeId, userId: nil, title: draft.title, description: draft.description,
            instructions: draft.instructions, imagePath: draft.imagePath, prepTime: draft.prepTime,
            servings: draft.servings, createdAt: Date()
        )
    }

    func update(id: Int64, with draft: RecipeDraft) async throws {
        if let errorToThrow { throw errorToThrow }
        updatedId = id
        updatedDraft = draft
    }

    private(set) var deletedId: Int64?

    func delete(id: Int64) async throws {
        if let errorToThrow { throw errorToThrow }
        deletedId = id
    }
}

final class FakeIngredientService: IngredientServicing, @unchecked Sendable {
    private(set) var replacedRecipeId: Int64?
    private(set) var replacedIngredients: [IngredientInsert]?
    var errorToThrow: Error?

    func replaceAll(recipeId: Int64, with ingredients: [IngredientInsert]) async throws {
        if let errorToThrow { throw errorToThrow }
        replacedRecipeId = recipeId
        replacedIngredients = ingredients
    }
}

final class FakeTagService: TagServicing, @unchecked Sendable {
    private(set) var replacedRecipeId: Int64?
    private(set) var replacedTagNames: [String]?
    var errorToThrow: Error?

    func replaceAll(recipeId: Int64, withTagNames names: [String]) async throws {
        if let errorToThrow { throw errorToThrow }
        replacedRecipeId = recipeId
        replacedTagNames = names
    }
}

private struct TestError: Error, LocalizedError {
    var errorDescription: String? { "failed" }
}

@MainActor
struct RecipeFormViewModelTests {
    @Test func createModeStartsEmptyAndCannotSaveWithoutTitle() {
        let viewModel = RecipeFormViewModel(
            mode: .create,
            recipeService: FakeRecipeFormRecipeService(),
            ingredientService: FakeIngredientService(),
            tagService: FakeTagService()
        )
        #expect(viewModel.canSave == false)
        viewModel.title = "  "
        #expect(viewModel.canSave == false)
        viewModel.title = "Tacos"
        #expect(viewModel.canSave == true)
    }

    @Test func createModeSaveCreatesRecipeThenIngredientsAndTags() async {
        let recipes = FakeRecipeFormRecipeService()
        recipes.createdRecipeId = 7
        let ingredients = FakeIngredientService()
        let tags = FakeTagService()
        let viewModel = RecipeFormViewModel(mode: .create, recipeService: recipes, ingredientService: ingredients, tagService: tags)

        viewModel.title = "Tacos"
        viewModel.prepTimeText = "15"
        viewModel.servingsText = "4"
        viewModel.ingredientRows = [
            .init(amount: "200", unit: "g", name: "Beef"),
            .init(amount: "", unit: "", name: ""),
        ]
        viewModel.tagsText = "Mexican, Quick"

        await viewModel.save()

        #expect(recipes.createdDraft?.title == "Tacos")
        #expect(recipes.createdDraft?.prepTime == 15)
        #expect(recipes.createdDraft?.servings == 4)
        #expect(ingredients.replacedRecipeId == 7)
        #expect(ingredients.replacedIngredients?.count == 1)
        #expect(ingredients.replacedIngredients?.first?.name == "Beef")
        #expect(tags.replacedRecipeId == 7)
        #expect(tags.replacedTagNames == ["Mexican", "Quick"])
        #expect(viewModel.didSave == true)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func createModeSaveSurfacesErrorAndDoesNotMarkSaved() async {
        let recipes = FakeRecipeFormRecipeService()
        recipes.errorToThrow = TestError()
        let viewModel = RecipeFormViewModel(mode: .create, recipeService: recipes, ingredientService: FakeIngredientService(), tagService: FakeTagService())
        viewModel.title = "Tacos"

        await viewModel.save()

        #expect(viewModel.errorMessage == "failed")
        #expect(viewModel.didSave == false)
    }

    @Test func editModeLoadsExistingRecipeIntoFields() async {
        let recipes = FakeRecipeFormRecipeService()
        recipes.detailToReturn = RecipeDetail(
            id: 3, userId: nil, title: "Carbonara", description: "Roman pasta", instructions: "Cook it",
            imagePath: nil, prepTime: 20, servings: 2, createdAt: Date(),
            ingredients: [Ingredient(id: 1, recipeId: 3, name: "Pasta", amount: 200, unit: "g")],
            recipeTags: [.init(tags: .init(name: "Italian"))]
        )
        let viewModel = RecipeFormViewModel(mode: .edit(recipeId: 3), recipeService: recipes, ingredientService: FakeIngredientService(), tagService: FakeTagService())

        await viewModel.loadIfNeeded()

        #expect(viewModel.title == "Carbonara")
        #expect(viewModel.description == "Roman pasta")
        #expect(viewModel.prepTimeText == "20")
        #expect(viewModel.servingsText == "2")
        #expect(viewModel.ingredientRows.count == 1)
        #expect(viewModel.ingredientRows.first?.name == "Pasta")
        #expect(viewModel.tagsText == "Italian")
    }

    @Test func editModeSaveUpdatesRecipeAtExistingId() async {
        let recipes = FakeRecipeFormRecipeService()
        recipes.detailToReturn = RecipeDetail(
            id: 3, userId: nil, title: "Carbonara", description: nil, instructions: nil,
            imagePath: nil, prepTime: nil, servings: nil, createdAt: Date(), ingredients: [], recipeTags: []
        )
        let ingredients = FakeIngredientService()
        let tags = FakeTagService()
        let viewModel = RecipeFormViewModel(mode: .edit(recipeId: 3), recipeService: recipes, ingredientService: ingredients, tagService: tags)
        await viewModel.loadIfNeeded()
        viewModel.title = "Updated Carbonara"

        await viewModel.save()

        #expect(recipes.updatedId == 3)
        #expect(recipes.updatedDraft?.title == "Updated Carbonara")
        #expect(recipes.createdDraft == nil)
        #expect(ingredients.replacedRecipeId == 3)
        #expect(tags.replacedRecipeId == 3)
        #expect(viewModel.didSave == true)
    }

    @Test func deleteRemovesExistingRecipe() async {
        let recipes = FakeRecipeFormRecipeService()
        let viewModel = RecipeFormViewModel(mode: .edit(recipeId: 9), recipeService: recipes, ingredientService: FakeIngredientService(), tagService: FakeTagService())

        let didDelete = await viewModel.delete()

        #expect(didDelete == true)
        #expect(recipes.deletedId == 9)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func deleteSurfacesErrorMessage() async {
        let recipes = FakeRecipeFormRecipeService()
        recipes.errorToThrow = TestError()
        let viewModel = RecipeFormViewModel(mode: .edit(recipeId: 9), recipeService: recipes, ingredientService: FakeIngredientService(), tagService: FakeTagService())

        let didDelete = await viewModel.delete()

        #expect(didDelete == false)
        #expect(viewModel.errorMessage == "failed")
    }

    @Test func addAndRemoveIngredientRow() {
        let viewModel = RecipeFormViewModel(mode: .create, recipeService: FakeRecipeFormRecipeService(), ingredientService: FakeIngredientService(), tagService: FakeTagService())
        let initialCount = viewModel.ingredientRows.count

        viewModel.addIngredientRow()
        #expect(viewModel.ingredientRows.count == initialCount + 1)

        let row = viewModel.ingredientRows.last!
        viewModel.removeIngredientRow(row)
        #expect(viewModel.ingredientRows.count == initialCount)
    }
}
