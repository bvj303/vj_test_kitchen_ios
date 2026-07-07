import Foundation
import Testing
@testable import VJTestKitchen

final class FakeGroceryListStore: GroceryListStoring, @unchecked Sendable {
    var ids: [Int64] = []
    var customItems: [GroceryItem] = []

    func loadSelectedRecipeIds() -> [Int64] { ids }
    func saveSelectedRecipeIds(_ ids: [Int64]) { self.ids = ids }
    func loadCustomItems() -> [GroceryItem] { customItems }
    func saveCustomItems(_ items: [GroceryItem]) { customItems = items }
}

final class FakeGroceryRecipeService: RecipeServicing, @unchecked Sendable {
    var detailsById: [Int64: RecipeDetail] = [:]
    var errorToThrow: Error?

    func fetchPage(offset: Int, limit: Int, matching search: String?) async throws -> [Recipe] { fatalError("not used") }

    func fetchDetail(id: Int64) async throws -> RecipeDetail {
        if let errorToThrow { throw errorToThrow }
        // A missing id simulates a recipe that was deleted after being added
        // to the grocery list — fetching its detail fails.
        guard let detail = detailsById[id] else { throw TestError() }
        return detail
    }

    func create(_ draft: RecipeDraft) async throws -> Recipe { fatalError("not used") }
    func update(id: Int64, with draft: RecipeDraft) async throws { fatalError("not used") }
    func delete(id: Int64) async throws { fatalError("not used") }
}

final class FakeReminderService: ReminderExporting, @unchecked Sendable {
    private(set) var exportedItems: [String]?
    private(set) var exportedListName: String?
    var errorToThrow: Error?

    func export(items: [String], listName: String) async throws {
        if let errorToThrow { throw errorToThrow }
        exportedItems = items
        exportedListName = listName
    }
}

private func makeDetail(id: Int64, ingredients: [Ingredient]) -> RecipeDetail {
    RecipeDetail(
        id: id, userId: nil, title: "Recipe \(id)", description: nil, instructions: nil,
        imagePath: nil, prepTime: nil, servings: nil, createdAt: Date(),
        ingredients: ingredients, recipeTags: []
    )
}

private struct TestError: Error, LocalizedError {
    var errorDescription: String? { "failed" }
}

@MainActor
struct GroceryListViewModelTests {
    @Test func loadWithEmptyStoreProducesEmptyList() async {
        let viewModel = GroceryListViewModel(store: FakeGroceryListStore(), recipeService: FakeGroceryRecipeService(), reminderService: FakeReminderService())

        await viewModel.load()

        #expect(viewModel.aggregatedIngredients.isEmpty)
        #expect(viewModel.selectedRecipeCount == 0)
    }

    @Test func loadAggregatesIngredientsAcrossRecipesSummingMatchingNameAndUnit() async {
        let store = FakeGroceryListStore()
        store.ids = [1, 2]
        let recipes = FakeGroceryRecipeService()
        recipes.detailsById = [
            1: makeDetail(id: 1, ingredients: [
                Ingredient(id: 1, recipeId: 1, name: "Flour", amount: 200, unit: "g"),
                Ingredient(id: 2, recipeId: 1, name: "Sugar", amount: 50, unit: "g"),
            ]),
            2: makeDetail(id: 2, ingredients: [
                Ingredient(id: 3, recipeId: 2, name: "flour", amount: 100, unit: "g"),
            ]),
        ]
        let viewModel = GroceryListViewModel(store: store, recipeService: recipes, reminderService: FakeReminderService())

        await viewModel.load()

        #expect(viewModel.selectedRecipeCount == 2)
        let flour = viewModel.aggregatedIngredients.first { $0.name.lowercased() == "flour" }
        #expect(flour?.amount == 300)
        let sugar = viewModel.aggregatedIngredients.first { $0.name.lowercased() == "sugar" }
        #expect(sugar?.amount == 50)
    }

    @Test func loadSurfacesErrorMessageWhenNothingCanLoad() async {
        let store = FakeGroceryListStore()
        store.ids = [1]
        let recipes = FakeGroceryRecipeService()
        recipes.errorToThrow = TestError()
        let viewModel = GroceryListViewModel(store: store, recipeService: recipes, reminderService: FakeReminderService())

        await viewModel.load()

        #expect(viewModel.errorMessage == "failed")
    }

    @Test func loadSkipsRecipesThatFailInsteadOfBlankingTheWholeList() async {
        let store = FakeGroceryListStore()
        store.ids = [1, 2, 3]
        let recipes = FakeGroceryRecipeService()
        // id 2 is absent -> its fetch throws, simulating a deleted recipe.
        recipes.detailsById = [
            1: makeDetail(id: 1, ingredients: [Ingredient(id: 1, recipeId: 1, name: "Flour", amount: 100, unit: "g")]),
            3: makeDetail(id: 3, ingredients: [Ingredient(id: 2, recipeId: 3, name: "Sugar", amount: 50, unit: "g")]),
        ]
        let viewModel = GroceryListViewModel(store: store, recipeService: recipes, reminderService: FakeReminderService())

        await viewModel.load()

        #expect(viewModel.aggregatedIngredients.count == 2)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.selectedRecipeCount == 3)
    }

    @Test func loadAggregatesUnitsIgnoringCaseAndWhitespace() async {
        let store = FakeGroceryListStore()
        store.ids = [1, 2]
        let recipes = FakeGroceryRecipeService()
        recipes.detailsById = [
            1: makeDetail(id: 1, ingredients: [Ingredient(id: 1, recipeId: 1, name: "Sugar", amount: 50, unit: "g")]),
            2: makeDetail(id: 2, ingredients: [Ingredient(id: 3, recipeId: 2, name: "sugar", amount: 25, unit: " G ")]),
        ]
        let viewModel = GroceryListViewModel(store: store, recipeService: recipes, reminderService: FakeReminderService())

        await viewModel.load()

        #expect(viewModel.aggregatedIngredients.count == 1)
        #expect(viewModel.aggregatedIngredients.first?.amount == 75)
    }

    @Test func clearListResetsStoreAndState() async {
        let store = FakeGroceryListStore()
        store.ids = [1]
        let recipes = FakeGroceryRecipeService()
        recipes.detailsById = [1: makeDetail(id: 1, ingredients: [Ingredient(id: 1, recipeId: 1, name: "Flour", amount: 200, unit: "g")])]
        let viewModel = GroceryListViewModel(store: store, recipeService: recipes, reminderService: FakeReminderService())
        await viewModel.load()

        viewModel.clearList()

        #expect(store.ids.isEmpty)
        #expect(viewModel.aggregatedIngredients.isEmpty)
        #expect(viewModel.selectedRecipeCount == 0)
    }

    @Test func exportToRemindersFormatsItemsWithAmountUnitName() async {
        let store = FakeGroceryListStore()
        store.ids = [1]
        let recipes = FakeGroceryRecipeService()
        recipes.detailsById = [1: makeDetail(id: 1, ingredients: [
            Ingredient(id: 1, recipeId: 1, name: "Flour", amount: 200, unit: "g"),
            Ingredient(id: 2, recipeId: 1, name: "Salt", amount: 1, unit: ""),
        ])]
        let reminders = FakeReminderService()
        let viewModel = GroceryListViewModel(store: store, recipeService: recipes, reminderService: reminders)
        await viewModel.load()

        await viewModel.exportToReminders()

        #expect(reminders.exportedItems?.contains("200 g Flour") == true)
        #expect(reminders.exportedItems?.contains("1 Salt") == true)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func exportToRemindersSurfacesErrorMessage() async {
        let store = FakeGroceryListStore()
        let reminders = FakeReminderService()
        reminders.errorToThrow = TestError()
        let viewModel = GroceryListViewModel(store: store, recipeService: FakeGroceryRecipeService(), reminderService: reminders)

        await viewModel.exportToReminders()

        #expect(viewModel.errorMessage == "failed")
    }

    @Test func loadReadsCustomItemsFromStore() async {
        let store = FakeGroceryListStore()
        store.customItems = [GroceryItem(name: "Paper Towels", amount: 1, unit: "")]
        let viewModel = GroceryListViewModel(store: store, recipeService: FakeGroceryRecipeService(), reminderService: FakeReminderService())

        await viewModel.load()

        #expect(viewModel.customItems.map(\.name) == ["Paper Towels"])
    }

    @Test func addCustomItemPersistsToStoreAndUpdatesState() async {
        let store = FakeGroceryListStore()
        let viewModel = GroceryListViewModel(store: store, recipeService: FakeGroceryRecipeService(), reminderService: FakeReminderService())
        await viewModel.load()

        viewModel.addCustomItem(name: "Olive Oil", amount: 1, unit: "bottle")

        #expect(viewModel.customItems.map(\.name) == ["Olive Oil"])
        #expect(store.customItems.map(\.name) == ["Olive Oil"])
    }

    @Test func addCustomItemIgnoresBlankName() async {
        let store = FakeGroceryListStore()
        let viewModel = GroceryListViewModel(store: store, recipeService: FakeGroceryRecipeService(), reminderService: FakeReminderService())
        await viewModel.load()

        viewModel.addCustomItem(name: "   ", amount: 1, unit: "")

        #expect(viewModel.customItems.isEmpty)
        #expect(store.customItems.isEmpty)
    }

    @Test func removeCustomItemDeletesJustThatItem() async {
        let store = FakeGroceryListStore()
        let keep = GroceryItem(name: "Keep Me", amount: 1, unit: "")
        let remove = GroceryItem(name: "Remove Me", amount: 1, unit: "")
        store.customItems = [keep, remove]
        let viewModel = GroceryListViewModel(store: store, recipeService: FakeGroceryRecipeService(), reminderService: FakeReminderService())
        await viewModel.load()

        viewModel.removeCustomItem(remove)

        #expect(viewModel.customItems == [keep])
        #expect(store.customItems == [keep])
    }

    @Test func clearListAlsoClearsCustomItems() async {
        let store = FakeGroceryListStore()
        store.customItems = [GroceryItem(name: "Paper Towels", amount: 1, unit: "")]
        let viewModel = GroceryListViewModel(store: store, recipeService: FakeGroceryRecipeService(), reminderService: FakeReminderService())
        await viewModel.load()

        viewModel.clearList()

        #expect(viewModel.customItems.isEmpty)
        #expect(store.customItems.isEmpty)
    }

    @Test func exportToRemindersIncludesCustomItems() async {
        let store = FakeGroceryListStore()
        store.customItems = [GroceryItem(name: "Paper Towels", amount: 2, unit: "rolls")]
        let reminders = FakeReminderService()
        let viewModel = GroceryListViewModel(store: store, recipeService: FakeGroceryRecipeService(), reminderService: reminders)
        await viewModel.load()

        await viewModel.exportToReminders()

        #expect(reminders.exportedItems?.contains("2 rolls Paper Towels") == true)
    }
}
