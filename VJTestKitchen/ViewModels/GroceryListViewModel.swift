import Foundation
import Observation

@MainActor
@Observable
final class GroceryListViewModel {
    struct AggregatedIngredient: Identifiable, Equatable {
        var id: String { "\(name.lowercased())|\(Self.normalizedUnit(unit))" }
        var name: String
        var amount: Double
        var unit: String

        /// Case- and whitespace-insensitive unit key, so "g", "G" and " g "
        /// all aggregate into one line item.
        static func normalizedUnit(_ unit: String) -> String {
            unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    private(set) var aggregatedIngredients: [AggregatedIngredient] = []
    private(set) var customItems: [GroceryItem] = []
    private(set) var selectedRecipeCount = 0
    private(set) var isLoading = false
    private(set) var isExporting = false
    var errorMessage: String?

    private let store: GroceryListStoring
    private let recipeService: RecipeServicing
    private let reminderService: ReminderExporting

    init(
        store: GroceryListStoring = UserDefaultsGroceryListStore(),
        recipeService: RecipeServicing = RecipeService(),
        reminderService: ReminderExporting = ReminderService()
    ) {
        self.store = store
        self.recipeService = recipeService
        self.reminderService = reminderService
    }

    func load() async {
        errorMessage = nil
        customItems = store.loadCustomItems()
        let ids = store.loadSelectedRecipeIds()
        selectedRecipeCount = ids.count
        guard !ids.isEmpty else {
            aggregatedIngredients = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        var list: [AggregatedIngredient] = []
        var loadedCount = 0
        var lastError: Error?
        for id in ids {
            do {
                let detail = try await recipeService.fetchDetail(id: id)
                loadedCount += 1
                for ingredient in detail.ingredients {
                    if let index = list.firstIndex(where: {
                        $0.name.caseInsensitiveCompare(ingredient.name) == .orderedSame
                            && AggregatedIngredient.normalizedUnit($0.unit) == AggregatedIngredient.normalizedUnit(ingredient.unit)
                    }) {
                        list[index].amount += ingredient.amount
                    } else {
                        list.append(AggregatedIngredient(name: ingredient.name, amount: ingredient.amount, unit: ingredient.unit))
                    }
                }
            } catch {
                // A single stale/deleted recipe (or a transient failure on one
                // fetch) must not blank out the whole list — skip it and keep
                // aggregating the rest.
                lastError = error
            }
        }
        aggregatedIngredients = list
        // Only surface an error if nothing at all could be loaded.
        if loadedCount == 0, let lastError {
            errorMessage = ErrorPresenter.message(for: lastError)
        }
    }

    func clearList() {
        store.saveSelectedRecipeIds([])
        store.saveCustomItems([])
        aggregatedIngredients = []
        customItems = []
        selectedRecipeCount = 0
    }

    /// Adds a standalone item — either typed in directly on this screen, or
    /// (via `RecipeDetailViewModel.addIngredientToGroceryList`) snapshotted
    /// from a single recipe ingredient. Blank names are ignored so an empty
    /// "Add Item" form can't create a junk row.
    func addCustomItem(name: String, amount: Double, unit: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        var items = store.loadCustomItems()
        items.append(GroceryItem(name: trimmedName, amount: amount, unit: unit.trimmingCharacters(in: .whitespacesAndNewlines)))
        store.saveCustomItems(items)
        customItems = items
    }

    func removeCustomItem(_ item: GroceryItem) {
        var items = store.loadCustomItems()
        items.removeAll { $0.id == item.id }
        store.saveCustomItems(items)
        customItems = items
    }

    func exportToReminders() async {
        errorMessage = nil
        isExporting = true
        defer { isExporting = false }
        let items = aggregatedIngredients.map { Self.formatItem(name: $0.name, amount: $0.amount, unit: $0.unit) }
            + customItems.map { Self.formatItem(name: $0.name, amount: $0.amount, unit: $0.unit) }
        do {
            try await reminderService.export(items: items, listName: "VJ Test Kitchen Groceries")
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    static func formatItem(name: String, amount: Double, unit: String) -> String {
        let amountText = amount == amount.rounded()
            ? String(Int(amount))
            : String(format: "%.2f", amount)
        return unit.isEmpty ? "\(amountText) \(name)" : "\(amountText) \(unit) \(name)"
    }
}
