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
    /// Ids whose per-item mutation should throw, so tests can exercise a
    /// *partial* failure of a multi-item row (some writes succeed, some don't).
    var failingIds: Set<UUID> = []
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
        if failingIds.contains(id) { throw TestError() }
        if let i = items.firstIndex(where: { $0.id == id }) { items[i].isChecked = isChecked }
    }

    func setCategory(id: UUID, category: GroceryCategory) async throws {
        if let mutationError { throw mutationError }
        if failingIds.contains(id) { throw TestError() }
        if let i = items.firstIndex(where: { $0.id == id }) { items[i].category = category }
    }

    func delete(id: UUID) async throws {
        if let mutationError { throw mutationError }
        if failingIds.contains(id) { throw TestError() }
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
        let viewModel = GroceryListViewModel(service: service, reminderService: FakeReminderService(), snapshotStore: FakeSnapshotStore())

        await viewModel.load()

        #expect(viewModel.items.count == 2)
        #expect(viewModel.isEmpty == false)
    }

    @Test func loadSurfacesErrorMessage() async {
        let service = FakeGroceryItemService()
        service.fetchError = TestError()
        let viewModel = GroceryListViewModel(service: service, reminderService: FakeReminderService(), snapshotStore: FakeSnapshotStore())

        await viewModel.load()

        #expect(viewModel.errorMessage == "failed")
    }

    @Test func loadLogsErrorWhenFetchFails() async {
        let service = FakeGroceryItemService()
        service.fetchError = TestError()
        let sink = SpyLogSink()
        let logger = AppLogger(sinks: [sink], context: LogContext(appVersion: "1", platform: "test"))
        let viewModel = GroceryListViewModel(service: service, reminderService: FakeReminderService(), snapshotStore: FakeSnapshotStore(), logger: logger)

        await viewModel.load()

        // Surfaced via errorMessage AND logged raw for diagnosis.
        #expect(sink.events.contains { $0.level == .error && $0.category == "grocery" })
    }

    @Test func addManualItemAutoCategorizesFromName() async {
        let service = FakeGroceryItemService()
        let viewModel = GroceryListViewModel(service: service, reminderService: FakeReminderService(), snapshotStore: FakeSnapshotStore())

        await viewModel.addManualItem(name: "Whole Milk", amount: 1, unit: "gallon")

        #expect(viewModel.items.count == 1)
        #expect(service.addedDrafts.first?.category == .dairy)
        #expect(service.addedDrafts.first?.sourceRecipeId == nil)
    }

    @Test func addManualItemRespectsExplicitCategoryOverride() async {
        let service = FakeGroceryItemService()
        let viewModel = GroceryListViewModel(service: service, reminderService: FakeReminderService(), snapshotStore: FakeSnapshotStore())

        await viewModel.addManualItem(name: "Milk", amount: 1, unit: "", category: .other)

        #expect(service.addedDrafts.first?.category == .other)
    }

    @Test func addManualItemIgnoresBlankName() async {
        let service = FakeGroceryItemService()
        let viewModel = GroceryListViewModel(service: service, reminderService: FakeReminderService(), snapshotStore: FakeSnapshotStore())

        await viewModel.addManualItem(name: "   ", amount: 1, unit: "")

        #expect(viewModel.items.isEmpty)
        #expect(service.addedDrafts.isEmpty)
    }

    @Test func toggleCheckedFlipsAndPersists() async {
        let service = FakeGroceryItemService()
        service.items = [makeItem(name: "Milk")]
        let viewModel = GroceryListViewModel(service: service, reminderService: FakeReminderService(), snapshotStore: FakeSnapshotStore())
        await viewModel.load()
        let item = viewModel.items[0]

        await viewModel.toggleChecked(item)

        #expect(viewModel.items[0].isChecked == true)
        #expect(service.items[0].isChecked == true)
    }

    @Test func toggleCheckedRevertsOnError() async {
        let service = FakeGroceryItemService()
        service.items = [makeItem(name: "Milk")]
        let viewModel = GroceryListViewModel(service: service, reminderService: FakeReminderService(), snapshotStore: FakeSnapshotStore())
        await viewModel.load()
        service.mutationError = TestError()

        await viewModel.toggleChecked(viewModel.items[0])

        #expect(viewModel.items[0].isChecked == false)
        #expect(viewModel.errorMessage == "failed")
    }

    @Test func toggleCheckedOnCombinedRowKeepsSuccessesWhenOneItemFails() async {
        // Two like-named produce items combine into one "by category" row, so
        // toggling it fans out to both underlying ids. When only one server
        // write fails, the successful one must stay checked (reconcile reverts
        // just the failure) rather than the whole row snapping back.
        let service = FakeGroceryItemService()
        let good = makeItem(name: "Lemon", category: .produce)
        let bad = makeItem(name: "Lemon", category: .produce)
        service.items = [good, bad]
        let viewModel = GroceryListViewModel(service: service, reminderService: FakeReminderService(), snapshotStore: FakeSnapshotStore())
        viewModel.grouping = .byCategory
        await viewModel.load()
        service.failingIds = [bad.id]

        let combinedRow = viewModel.groups.first { $0.title == GroceryCategory.produce.displayName }!.rows.first!
        #expect(combinedRow.items.count == 2)

        await viewModel.toggleChecked(combinedRow)

        #expect(viewModel.items.first { $0.id == good.id }?.isChecked == true)   // success kept
        #expect(viewModel.items.first { $0.id == bad.id }?.isChecked == false)   // failure reverted
        #expect(viewModel.errorMessage == "failed")
    }

    @Test func deleteOnCombinedRowReinsertsOnlyTheFailedItem() async {
        let service = FakeGroceryItemService()
        let good = makeItem(name: "Lemon", category: .produce)
        let bad = makeItem(name: "Lemon", category: .produce)
        service.items = [good, bad]
        let viewModel = GroceryListViewModel(service: service, reminderService: FakeReminderService(), snapshotStore: FakeSnapshotStore())
        viewModel.grouping = .byCategory
        await viewModel.load()
        service.failingIds = [bad.id]

        let combinedRow = viewModel.groups.first { $0.title == GroceryCategory.produce.displayName }!.rows.first!
        await viewModel.delete(combinedRow)

        // The deleted-successfully item is gone; the failed one is restored.
        #expect(viewModel.items.contains { $0.id == good.id } == false)
        #expect(viewModel.items.contains { $0.id == bad.id })
        #expect(viewModel.errorMessage == "failed")
    }

    @Test func setCategoryUpdatesItem() async {
        let service = FakeGroceryItemService()
        service.items = [makeItem(name: "Mystery", category: .other)]
        let viewModel = GroceryListViewModel(service: service, reminderService: FakeReminderService(), snapshotStore: FakeSnapshotStore())
        await viewModel.load()

        await viewModel.setCategory(viewModel.items[0], to: .produce)

        #expect(viewModel.items[0].category == .produce)
        #expect(service.items[0].category == .produce)
    }

    @Test func deleteRemovesItem() async {
        let service = FakeGroceryItemService()
        service.items = [makeItem(name: "Milk"), makeItem(name: "Eggs")]
        let viewModel = GroceryListViewModel(service: service, reminderService: FakeReminderService(), snapshotStore: FakeSnapshotStore())
        await viewModel.load()

        await viewModel.delete(viewModel.items[0])

        #expect(viewModel.items.count == 1)
        #expect(service.items.count == 1)
    }

    @Test func clearListEmptiesEverything() async {
        let service = FakeGroceryItemService()
        service.items = [makeItem(name: "Milk"), makeItem(name: "Eggs")]
        let viewModel = GroceryListViewModel(service: service, reminderService: FakeReminderService(), snapshotStore: FakeSnapshotStore())
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
        let viewModel = GroceryListViewModel(service: service, reminderService: FakeReminderService(), snapshotStore: FakeSnapshotStore())
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
        let viewModel = GroceryListViewModel(service: service, reminderService: FakeReminderService(), snapshotStore: FakeSnapshotStore())
        await viewModel.load()
        viewModel.grouping = .byCategory

        // Produce precedes Dairy in GroceryCategory.allCases (aisle order).
        #expect(viewModel.groups.map(\.title) == ["Produce", "Dairy & Eggs"])
    }

    @Test func categoryGroupingCombinesLikeItemsButRecipeGroupingKeepsThemSeparate() async {
        let service = FakeGroceryItemService()
        service.items = [
            makeItem(name: "Lemons", amount: 2, category: .produce, recipeTitle: "Lemonade"),
            makeItem(name: "Lemon", amount: 1, category: .produce, recipeTitle: "Pie"),
        ]
        let viewModel = GroceryListViewModel(service: service, reminderService: FakeReminderService(), snapshotStore: FakeSnapshotStore())
        await viewModel.load()

        // By recipe: one row under each recipe, uncombined.
        viewModel.grouping = .byRecipe
        #expect(viewModel.groups.flatMap(\.rows).count == 2)

        // By category: a single combined "3" row in Produce.
        viewModel.grouping = .byCategory
        let produce = viewModel.groups.first { $0.title == "Produce" }
        #expect(produce?.rows.count == 1)
        #expect(produce?.rows.first?.quantityText == "3")
    }

    @Test func togglingCombinedRowChecksAllUnderlyingItems() async {
        let service = FakeGroceryItemService()
        service.items = [
            makeItem(name: "Lemons", amount: 2, category: .produce),
            makeItem(name: "Lemon", amount: 1, category: .produce),
        ]
        let viewModel = GroceryListViewModel(service: service, reminderService: FakeReminderService(), snapshotStore: FakeSnapshotStore())
        await viewModel.load()
        viewModel.grouping = .byCategory
        let combined = viewModel.groups[0].rows[0]

        await viewModel.toggleChecked(combined)

        let vmAllChecked = viewModel.items.allSatisfy(\.isChecked)
        let serviceAllChecked = service.items.allSatisfy(\.isChecked)
        #expect(vmAllChecked)
        #expect(serviceAllChecked)
    }

    @Test func deletingCombinedRowDeletesAllUnderlyingItems() async {
        let service = FakeGroceryItemService()
        service.items = [
            makeItem(name: "Lemons", amount: 2, category: .produce),
            makeItem(name: "Lemon", amount: 1, category: .produce),
            makeItem(name: "Milk", category: .dairy),
        ]
        let viewModel = GroceryListViewModel(service: service, reminderService: FakeReminderService(), snapshotStore: FakeSnapshotStore())
        await viewModel.load()
        viewModel.grouping = .byCategory
        let combined = viewModel.groups.first { $0.title == "Produce" }!.rows[0]

        await viewModel.delete(combined)

        #expect(viewModel.items.map(\.name) == ["Milk"])
        #expect(service.items.map(\.name) == ["Milk"])
    }

    @Test func recategorizingCombinedRowMovesAllUnderlyingItems() async {
        let service = FakeGroceryItemService()
        service.items = [
            makeItem(name: "Lemons", amount: 2, category: .produce),
            makeItem(name: "Lemon", amount: 1, category: .produce),
        ]
        let viewModel = GroceryListViewModel(service: service, reminderService: FakeReminderService(), snapshotStore: FakeSnapshotStore())
        await viewModel.load()
        viewModel.grouping = .byCategory
        let combined = viewModel.groups[0].rows[0]

        await viewModel.setCategory(combined, to: .beverages)

        let vmAllBeverages = viewModel.items.allSatisfy { $0.category == .beverages }
        let serviceAllBeverages = service.items.allSatisfy { $0.category == .beverages }
        #expect(vmAllBeverages)
        #expect(serviceAllBeverages)
    }

    @Test func exportSendsUncheckedItemsFormattedWithAmountUnitName() async {
        let service = FakeGroceryItemService()
        service.items = [
            makeItem(name: "Flour", amount: 200, unit: "g"),
            makeItem(name: "Salt", amount: 1, unit: ""),
            makeItem(name: "Sugar", amount: 50, unit: "g", isChecked: true),
        ]
        let reminders = FakeReminderService()
        let viewModel = GroceryListViewModel(service: service, reminderService: reminders, snapshotStore: FakeSnapshotStore())
        await viewModel.load()

        await viewModel.exportToReminders()

        #expect(reminders.exportedItems?.contains("200 g Flour") == true)
        #expect(reminders.exportedItems?.contains("1 Salt") == true)
        // Checked items are already "in the cart" and excluded from the export.
        #expect(reminders.exportedItems?.contains(where: { $0.contains("Sugar") }) == false)
    }

    @Test func exportCombinesLikeItemsTheWayTheCategoryViewDoes() async {
        // "2 Lemons" (one recipe) + "1 Lemon" (another) export as a single
        // "3 Lemons" reminder, matching the combined by-category row — not two
        // separate reminders.
        let service = FakeGroceryItemService()
        service.items = [
            makeItem(name: "Lemons", amount: 2, category: .produce, recipeTitle: "Lemonade"),
            makeItem(name: "Lemon", amount: 1, category: .produce, recipeTitle: "Pie"),
        ]
        let reminders = FakeReminderService()
        let viewModel = GroceryListViewModel(service: service, reminderService: reminders, snapshotStore: FakeSnapshotStore())
        await viewModel.load()

        await viewModel.exportToReminders()

        #expect(reminders.exportedItems == ["3 Lemons"])
    }

    @Test func loadPaintsCachedItemsWhenTheFetchFails() async {
        // Offline: the fetch fails, but the last-persisted list still shows.
        let store = FakeSnapshotStore()
        store.save([makeItem(name: "Cached Milk")], key: .groceryItems)
        let service = FakeGroceryItemService()
        service.fetchError = TestError()
        let viewModel = GroceryListViewModel(service: service, reminderService: FakeReminderService(), snapshotStore: store)

        await viewModel.load()

        #expect(viewModel.items.map(\.name) == ["Cached Milk"])
        #expect(viewModel.errorMessage == "failed")
    }

    @Test func mutationsPersistTheSnapshotForNextLaunch() async {
        let store = FakeSnapshotStore()
        let service = FakeGroceryItemService()
        let viewModel = GroceryListViewModel(service: service, reminderService: FakeReminderService(), snapshotStore: store)

        await viewModel.addManualItem(name: "Milk", amount: 1, unit: "")

        #expect(store.hasValue(for: .groceryItems))
        let cached: [GroceryItem]? = store.load([GroceryItem].self, key: .groceryItems)
        #expect(cached?.map(\.name) == ["Milk"])
    }

    @Test func exportSurfacesErrorMessage() async {
        let reminders = FakeReminderService()
        reminders.errorToThrow = TestError()
        let service = FakeGroceryItemService()
        service.items = [makeItem(name: "Milk")]
        let viewModel = GroceryListViewModel(service: service, reminderService: reminders, snapshotStore: FakeSnapshotStore())
        await viewModel.load()

        await viewModel.exportToReminders()

        #expect(viewModel.errorMessage == "failed")
    }

    @Test func formattedQuantityHandlesZeroAndFractions() {
        #expect(GroceryListViewModel.formattedQuantity(amount: 200, unit: "g") == "200 g")
        #expect(GroceryListViewModel.formattedQuantity(amount: 1, unit: "") == "1")
        #expect(GroceryListViewModel.formattedQuantity(amount: 0, unit: "") == "")
        #expect(GroceryListViewModel.formattedQuantity(amount: 0, unit: "cloves") == "cloves")
        // Friendly kitchen fraction, not a raw decimal, with the unit pluralized.
        #expect(GroceryListViewModel.formattedQuantity(amount: 1.5, unit: "cups") == "1½ cups")
    }

    @Test func formattedQuantityRoundsToFriendlyFractionsAndPluralizes() {
        // 1.12 → nearest common fraction (⅛), and "teaspoon" pluralizes above 1.
        #expect(GroceryListViewModel.formattedQuantity(amount: 1.12, unit: "teaspoon") == "1⅛ teaspoons")
        // Exactly one stays singular.
        #expect(GroceryListViewModel.formattedQuantity(amount: 1, unit: "cloves") == "1 clove")
        // A whole number above one pluralizes a singular unit.
        #expect(GroceryListViewModel.formattedQuantity(amount: 3, unit: "clove") == "3 cloves")
        // A pure fraction under one stays singular ("½ cup", not "½ cups").
        #expect(GroceryListViewModel.formattedQuantity(amount: 0.5, unit: "cups") == "½ cup")
        // Abbreviated units never inflect.
        #expect(GroceryListViewModel.formattedQuantity(amount: 2, unit: "tbsp") == "2 tbsp")
        #expect(GroceryListViewModel.formattedQuantity(amount: 12, unit: "oz") == "12 oz")
    }
}
