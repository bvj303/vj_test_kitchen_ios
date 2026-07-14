import Foundation
import Testing
@testable import VJTestKitchen

final class FakeRecipeFormRecipeService: RecipeServicing, @unchecked Sendable {
    var detailToReturn: RecipeDetail!
    var errorToThrow: Error?

    func fetchPage(offset: Int, limit: Int, matching search: String?, tag: String?, minPrepTime: Int?, maxPrepTime: Int?, minAtkRating: Double?) async throws -> [Recipe] { fatalError("not used") }

    func fetchDetail(id: Int64) async throws -> RecipeDetail {
        if let errorToThrow { throw errorToThrow }
        return detailToReturn
    }

    func create(_ draft: RecipeDraft) async throws -> Recipe { fatalError("saving goes through RecipeSaving") }
    func update(id: Int64, with draft: RecipeDraft) async throws { fatalError("saving goes through RecipeSaving") }

    private(set) var deletedId: Int64?

    func delete(id: Int64) async throws {
        if let errorToThrow { throw errorToThrow }
        deletedId = id
    }
}

/// Records the single atomic save call (see `RecipeSaving`).
final class FakeRecipeSaveService: RecipeSaving, @unchecked Sendable {
    var errorToThrow: Error?
    var idToReturn: Int64 = 42
    private(set) var savedRecipeId: Int64??
    private(set) var savedDraft: RecipeDraft?
    private(set) var savedIngredients: [RecipeSaveIngredient]?
    private(set) var savedTagNames: [String]?
    private(set) var saveCallCount = 0

    @discardableResult
    func save(recipeId: Int64?, draft: RecipeDraft, ingredients: [RecipeSaveIngredient], tagNames: [String]) async throws -> Int64 {
        saveCallCount += 1
        if let errorToThrow { throw errorToThrow }
        savedRecipeId = recipeId
        savedDraft = draft
        savedIngredients = ingredients
        savedTagNames = tagNames
        return idToReturn
    }
}

final class FakeTagService: TagServicing, @unchecked Sendable {
    var namesToReturn: [String] = []
    func fetchAllNames() async throws -> [String] { namesToReturn }
}

private struct TestError: Error, LocalizedError {
    var errorDescription: String? { "failed" }
}

@MainActor
private func makeViewModel(
    mode: RecipeFormViewModel.Mode,
    recipeService: FakeRecipeFormRecipeService = FakeRecipeFormRecipeService(),
    saveService: FakeRecipeSaveService = FakeRecipeSaveService()
) -> RecipeFormViewModel {
    RecipeFormViewModel(mode: mode, recipeService: recipeService, saveService: saveService)
}

@MainActor
struct RecipeFormViewModelTests {
    @Test func createModeStartsEmptyAndCannotSaveWithoutTitle() {
        let viewModel = makeViewModel(mode: .create)
        #expect(viewModel.canSave == false)
        viewModel.title = "  "
        #expect(viewModel.canSave == false)
        viewModel.title = "Tacos"
        #expect(viewModel.canSave == true)
    }

    @Test func createModeSavePassesEverythingInOneAtomicCall() async {
        let save = FakeRecipeSaveService()
        let viewModel = makeViewModel(mode: .create, saveService: save)

        viewModel.title = "Tacos"
        viewModel.prepTimeText = "15"
        viewModel.servingsText = "4"
        viewModel.ingredientRows = [
            .init(amount: "200", unit: "g", name: "Beef"),
            .init(amount: "", unit: "", name: ""),
        ]
        viewModel.tagsText = "Mexican, Quick"

        await viewModel.save()

        #expect(save.saveCallCount == 1)
        #expect(save.savedRecipeId == .some(nil))  // create → no id
        #expect(save.savedDraft?.title == "Tacos")
        #expect(save.savedDraft?.prepTime == 15)
        #expect(save.savedDraft?.servings == 4)
        #expect(save.savedIngredients == [RecipeSaveIngredient(name: "Beef", amount: 200, unit: "g")])
        #expect(save.savedTagNames == ["Mexican", "Quick"])
        #expect(viewModel.didSave == true)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func createModeSaveSurfacesErrorAndDoesNotMarkSaved() async {
        let save = FakeRecipeSaveService()
        save.errorToThrow = TestError()
        let viewModel = makeViewModel(mode: .create, saveService: save)
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
        let viewModel = makeViewModel(mode: .edit(recipeId: 3), recipeService: recipes)

        await viewModel.loadIfNeeded()

        #expect(viewModel.title == "Carbonara")
        #expect(viewModel.description == "Roman pasta")
        #expect(viewModel.prepTimeText == "20")
        #expect(viewModel.servingsText == "2")
        #expect(viewModel.ingredientRows.count == 1)
        #expect(viewModel.ingredientRows.first?.name == "Pasta")
        #expect(viewModel.tagsText == "Italian")
    }

    @Test func editModeSavePassesTheExistingIdToTheAtomicCall() async {
        let recipes = FakeRecipeFormRecipeService()
        recipes.detailToReturn = RecipeDetail(
            id: 3, userId: nil, title: "Carbonara", description: nil, instructions: nil,
            imagePath: nil, prepTime: nil, servings: nil, createdAt: Date(), ingredients: [], recipeTags: []
        )
        let save = FakeRecipeSaveService()
        let viewModel = makeViewModel(mode: .edit(recipeId: 3), recipeService: recipes, saveService: save)
        await viewModel.loadIfNeeded()
        viewModel.title = "Updated Carbonara"

        await viewModel.save()

        #expect(save.saveCallCount == 1)
        #expect(save.savedRecipeId == 3)
        #expect(save.savedDraft?.title == "Updated Carbonara")
        #expect(viewModel.didSave == true)
    }

    @Test func deleteRemovesExistingRecipe() async {
        let recipes = FakeRecipeFormRecipeService()
        let viewModel = makeViewModel(mode: .edit(recipeId: 9), recipeService: recipes)

        let didDelete = await viewModel.delete()

        #expect(didDelete == true)
        #expect(recipes.deletedId == 9)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func deleteSurfacesErrorMessage() async {
        let recipes = FakeRecipeFormRecipeService()
        recipes.errorToThrow = TestError()
        let viewModel = makeViewModel(mode: .edit(recipeId: 9), recipeService: recipes)

        let didDelete = await viewModel.delete()

        #expect(didDelete == false)
        #expect(viewModel.errorMessage == "failed")
    }

    @Test func addAndRemoveIngredientRow() {
        let viewModel = makeViewModel(mode: .create)
        let initialCount = viewModel.ingredientRows.count

        viewModel.addIngredientRow()
        #expect(viewModel.ingredientRows.count == initialCount + 1)

        let row = viewModel.ingredientRows.last!
        viewModel.removeIngredientRow(row)
        #expect(viewModel.ingredientRows.count == initialCount)
    }

    // MARK: - Quick Stats validation

    @Test func naturalLanguagePrepTimeParsesInsteadOfSilentlyDropping() async {
        // The old form's `Int("45 min")` was nil — the user's typed prep time
        // silently vanished on save.
        let save = FakeRecipeSaveService()
        let viewModel = makeViewModel(mode: .create, saveService: save)
        viewModel.title = "Tacos"
        viewModel.prepTimeText = "1 hr 30 min"
        viewModel.servingsText = "serves 4"

        #expect(viewModel.canSave)
        await viewModel.save()

        #expect(save.savedDraft?.prepTime == 90)
        #expect(save.savedDraft?.servings == 4)
    }

    @Test func unreadablePrepTimeBlocksSaveWithInlineMessage() {
        let viewModel = makeViewModel(mode: .create)
        viewModel.title = "Tacos"
        viewModel.prepTimeText = "a while"

        #expect(!viewModel.prepTimeIsValid)
        #expect(!viewModel.canSave)
        #expect(viewModel.quickStatsValidationMessage?.contains("Prep time") == true)
    }

    @Test func unreadableServingsBlocksSaveWithInlineMessage() {
        let viewModel = makeViewModel(mode: .create)
        viewModel.title = "Tacos"
        viewModel.servingsText = "some"

        #expect(!viewModel.servingsIsValid)
        #expect(!viewModel.canSave)
        #expect(viewModel.quickStatsValidationMessage?.contains("Servings") == true)
    }

    @Test func emptyQuickStatsAreValidAndSaveAsNil() async {
        let save = FakeRecipeSaveService()
        let viewModel = makeViewModel(mode: .create, saveService: save)
        viewModel.title = "Tacos"

        #expect(viewModel.canSave)
        #expect(viewModel.quickStatsValidationMessage == nil)
        await viewModel.save()

        #expect(save.savedDraft?.prepTime == nil)
        #expect(save.savedDraft?.servings == nil)
    }
}
