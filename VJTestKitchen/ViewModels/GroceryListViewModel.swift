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
        aggregatedIngredients = []
        selectedRecipeCount = 0
    }

    func exportToReminders() async {
        errorMessage = nil
        isExporting = true
        defer { isExporting = false }
        let items = aggregatedIngredients.map(Self.formatItem)
        do {
            try await reminderService.export(items: items, listName: "VJ Test Kitchen Groceries")
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    private static func formatItem(_ ingredient: AggregatedIngredient) -> String {
        let amountText = ingredient.amount == ingredient.amount.rounded()
            ? String(Int(ingredient.amount))
            : String(format: "%.2f", ingredient.amount)
        return ingredient.unit.isEmpty ? "\(amountText) \(ingredient.name)" : "\(amountText) \(ingredient.unit) \(ingredient.name)"
    }
}
