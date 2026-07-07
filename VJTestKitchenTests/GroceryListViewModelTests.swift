import Foundation
import Testing
@testable import VJTestKitchen

/// Shared fake for the account-synced grocery service. Mutations act on an
/// in-memory `items` array; `mutationError`/`addError`/`fetchError` let tests
/// exercise failure + optimistic-revert paths.
final class FakeGroceryItemService: GroceryItemServicing, @unchecked Sendable {
    var items: [GroceryItem] = []
    var fetchError: Error?
    var addError: Error?
    var mutationError: Error?
    private(set) var addedDrafts: [GroceryItemDraft] = []

    func fetchAll() async throws -> [GroceryItem] {
        if let fetchError { throw fetchError }
        return items
    }

    func add(_ draft: GroceryItemDraft) async throws -> GroceryItem {
        if let addError { throw addError }
        addedDrafts.append(draft)
        let item = Self.item(from: draft)
        items.append(item)
        return item
    }

    func addMany(_ drafts: [GroceryItemDraft]) async throws -> [GroceryItem] {
        if let addError { throw addError }
        addedDrafts.append(contentsOf: drafts)
        let new = drafts.map(Self.item(from:))
        items.append(contentsOf: new)
        return new
    }

    func setChecked(id: UUID, isChecked: Bool) async throws {
        if let mutationError { throw mutationError }
        if let i = items.firstIndex(where: { $0.id == id }) { items[i].isChecked = isChecked }
    }

    func setCategory(id: UUID, category: GroceryCategory) async throws {
        if let mutationError { throw mutationError }
        if let i = items.firstIndex(where: { $0.id == id }) { items[i].category = category }
    }

    func delete(id: UUID) async throws {
        if let mutationError { throw mutationError }
        items.removeAll { $0.id == id }
    }

    func clearAll() async throws {
        if let mutationError { throw mutationError }
        items = []
    }

    static func item(from draft: GroceryItemDraft) -> GroceryItem {
        GroceryItem(
            id: UUID(), userId: UUID(), name: draft.name, amount: draft.amount,
            unit: draft.unit, category: draft.category, isChecked: false,
            sourceRecipeId: draft.sourceRecipeId, sourceRecipeTitle: draft.sourceRecipeTitle,
            createdAt: Date()
        )
    }
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

private struct TestError: Error, LocalizedError {
    var errorDescription: String? { "failed" }
}

private func makeItem(
    name: String, amount: Double = 1, unit: String = "", category: GroceryCategory = .other,
    isChecked: Bool = false, recipeTitle: String? = nil
) -> GroceryItem {
    GroceryItem(
        id: UUID(), userId: UUID(), name: name, amount: amount, unit: unit,
        category: category, isChecked: isChecked,
        sourceRecipeId: recipeTitle == nil ? nil : 1, sourceRecipeTitle: recipeTitle,
        createdAt: Date()
    )
}

@MainActor
struct GroceryListViewModelTests {
    @Test func loadFetchesItemsFromService() async {
        let service = FakeGroceryItemService()
        service.items = [makeItem(name: "Milk"), makeItem(name: "Eggs")]
        let viewModel = GroceryListViewModel(service: service, reminderService: FakeReminderService())

        await viewModel.load()

        #expect(viewModel.items.count == 2)
        #expect(viewModel.isEmpty == false)
    }

    @Test func loadSurfacesErrorMessage() async {
        let service = FakeGroceryItemService()
        service.fetchError = TestError()
        let viewModel = GroceryListViewModel(service: service, reminderService: FakeReminderService())

        await viewModel.load()

        #expect(viewModel.errorMessage == "failed")
    }

    @Test func addManualItemAutoCategorizesFromName() async {
        let service = FakeGroceryItemService()
        let viewModel = GroceryListViewModel(service: service, reminderService: FakeReminderService())

        await viewModel.addManualItem(name: "Whole Milk", amount: 1, unit: "gallon")

        #expect(viewModel.items.count == 1)
        #expect(service.addedDrafts.first?.category == .dairy)
        #expect(service.addedDrafts.first?.sourceRecipeId == nil)
    }

    @Test func addManualItemRespectsExplicitCategoryOverride() async {
        let service = FakeGroceryItemService()
        let viewModel = GroceryListViewModel(service: service, reminderService: FakeReminderService())

        await viewModel.addManualItem(name: "Milk", amount: 1, unit: "", category: .other)

        #expect(service.addedDrafts.first?.category == .other)
    }

    @Test func addManualItemIgnoresBlankName() async {
        let service = FakeGroceryItemService()
        let viewModel = GroceryListViewModel(service: service, reminderService: FakeReminderService())

        await viewModel.addManualItem(name: "   ", amount: 1, unit: "")

        #expect(viewModel.items.isEmpty)
        #expect(service.addedDrafts.isEmpty)
    }

    @Test func toggleCheckedFlipsAndPersists() async {
        let service = FakeGroceryItemService()
        service.items = [makeItem(name: "Milk")]
        let viewModel = GroceryListViewModel(service: service, reminderService: FakeReminderService())
        await viewModel.load()
        let item = viewModel.items[0]

        await viewModel.toggleChecked(item)

        #expect(viewModel.items[0].isChecked == true)
        #expect(service.items[0].isChecked == true)
    }

    @Test func toggleCheckedRevertsOnError() async {
        let service = FakeGroceryItemService()
        service.items = [makeItem(name: "Milk")]
        let viewModel = GroceryListViewModel(service: service, reminderService: FakeReminderService())
        await viewModel.load()
        service.mutationError = TestError()

        await viewModel.toggleChecked(viewModel.items[0])

        #expect(viewModel.items[0].isChecked == false)
        #expect(viewModel.errorMessage == "failed")
    }

    @Test func setCategoryUpdatesItem() async {
        let service = FakeGroceryItemService()
        service.items = [makeItem(name: "Mystery", category: .other)]
        let viewModel = GroceryListViewModel(service: service, reminderService: FakeReminderService())
        await viewModel.load()

        await viewModel.setCategory(viewModel.items[0], to: .produce)

        #expect(viewModel.items[0].category == .produce)
        #expect(service.items[0].category == .produce)
    }

    @Test func deleteRemovesItem() async {
        let service = FakeGroceryItemService()
        service.items = [makeItem(name: "Milk"), makeItem(name: "Eggs")]
        let viewModel = GroceryListViewModel(service: service, reminderService: FakeReminderService())
        await viewModel.load()

        await viewModel.delete(viewModel.items[0])

        #expect(viewModel.items.count == 1)
        #expect(service.items.count == 1)
    }

    @Test func clearListEmptiesEverything() async {
        let service = FakeGroceryItemService()
        service.items = [makeItem(name: "Milk"), makeItem(name: "Eggs")]
        let viewModel = GroceryListViewModel(service: service, reminderService: FakeReminderService())
        await viewModel.load()

        await viewModel.clearList()

        #expect(viewModel.items.isEmpty)
        #expect(service.items.isEmpty)
    }

    @Test func recipeGroupingPutsManualItemsUnderOtherLast() async {
        let service = FakeGroceryItemService()
        service.items = [
            makeItem(name: "Flour", recipeTitle: "Bread"),
            makeItem(name: "Salt", recipeTitle: "Aioli"),
            makeItem(name: "Paper Towels"), // manual, no recipe
        ]
        let viewModel = GroceryListViewModel(service: service, reminderService: FakeReminderService())
        await viewModel.load()
        viewModel.grouping = .byRecipe

        let titles = viewModel.groups.map(\.title)
        #expect(titles == ["Aioli", "Bread", "Other Items"])
    }

    @Test func categoryGroupingOrdersByAisle() async {
        let service = FakeGroceryItemService()
        service.items = [
            makeItem(name: "Milk", category: .dairy),
            makeItem(name: "Apple", category: .produce),
        ]
        let viewModel = GroceryListViewModel(service: service, reminderService: FakeReminderService())
        await viewModel.load()
        viewModel.grouping = .byCategory

        // Produce precedes Dairy in GroceryCategory.allCases (aisle order).
        #expect(viewModel.groups.map(\.title) == ["Produce", "Dairy & Eggs"])
    }

    @Test func exportSendsUncheckedItemsFormattedWithAmountUnitName() async {
        let service = FakeGroceryItemService()
        service.items = [
            makeItem(name: "Flour", amount: 200, unit: "g"),
            makeItem(name: "Salt", amount: 1, unit: ""),
            makeItem(name: "Sugar", amount: 50, unit: "g", isChecked: true),
        ]
        let reminders = FakeReminderService()
        let viewModel = GroceryListViewModel(service: service, reminderService: reminders)
        await viewModel.load()

        await viewModel.exportToReminders()

        #expect(reminders.exportedItems?.contains("200 g Flour") == true)
        #expect(reminders.exportedItems?.contains("1 Salt") == true)
        // Checked items are already "in the cart" and excluded from the export.
        #expect(reminders.exportedItems?.contains(where: { $0.contains("Sugar") }) == false)
    }

    @Test func exportSurfacesErrorMessage() async {
        let reminders = FakeReminderService()
        reminders.errorToThrow = TestError()
        let service = FakeGroceryItemService()
        service.items = [makeItem(name: "Milk")]
        let viewModel = GroceryListViewModel(service: service, reminderService: reminders)
        await viewModel.load()

        await viewModel.exportToReminders()

        #expect(viewModel.errorMessage == "failed")
    }

    @Test func formattedQuantityHandlesZeroAndFractions() {
        #expect(GroceryListViewModel.formattedQuantity(amount: 200, unit: "g") == "200 g")
        #expect(GroceryListViewModel.formattedQuantity(amount: 1, unit: "") == "1")
        #expect(GroceryListViewModel.formattedQuantity(amount: 0, unit: "") == "")
        #expect(GroceryListViewModel.formattedQuantity(amount: 0, unit: "cloves") == "cloves")
        #expect(GroceryListViewModel.formattedQuantity(amount: 1.5, unit: "cups") == "1.50 cups")
    }
}
