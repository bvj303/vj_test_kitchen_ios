import Foundation
import Observation

@MainActor
@Observable
final class GroceryListViewModel {
    /// The two ways the checklist can be organized (the top-of-screen toggle).
    enum Grouping: String, CaseIterable, Identifiable {
        case byRecipe
        case byCategory
        var id: String { rawValue }
        var label: String {
            switch self {
            case .byRecipe: "By Recipe"
            case .byCategory: "By Category"
            }
        }
    }

    /// One rendered section of the list — a recipe (or "Other Items") when
    /// grouping by recipe, or a `GroceryCategory` aisle when grouping by
    /// category. Named `ItemGroup` (not `Section`) so it doesn't shadow
    /// SwiftUI's `Section` in the view.
    struct ItemGroup: Identifiable {
        let id: String
        let title: String
        let systemImage: String
        var items: [GroceryItem]
    }

    private(set) var items: [GroceryItem] = []
    var grouping: Grouping = .byRecipe
    private(set) var isLoading = false
    private(set) var isExporting = false
    var errorMessage: String?

    private let service: GroceryItemServicing
    private let reminderService: ReminderExporting

    init(
        service: GroceryItemServicing = GroceryItemService(),
        reminderService: ReminderExporting = ReminderService()
    ) {
        self.service = service
        self.reminderService = reminderService
    }

    var isEmpty: Bool { items.isEmpty }

    var groups: [ItemGroup] {
        switch grouping {
        case .byRecipe: recipeGroups
        case .byCategory: categoryGroups
        }
    }

    /// Grouped by originating recipe (title snapshot), recipe groups first in
    /// alphabetical order, with manually-added items collected under "Other
    /// Items" last.
    private var recipeGroups: [ItemGroup] {
        var byTitle: [String: [GroceryItem]] = [:]
        var others: [GroceryItem] = []
        for item in items {
            if let title = item.sourceRecipeTitle, !title.isEmpty {
                byTitle[title, default: []].append(item)
            } else {
                others.append(item)
            }
        }
        var result = byTitle.keys
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { title in
                ItemGroup(id: "recipe:\(title)", title: title, systemImage: "fork.knife", items: displayOrdered(byTitle[title] ?? []))
            }
        if !others.isEmpty {
            result.append(ItemGroup(id: "recipe:__other", title: "Other Items", systemImage: "cart", items: displayOrdered(others)))
        }
        return result
    }

    /// Grouped by food category, in aisle order (`GroceryCategory.allCases`).
    private var categoryGroups: [ItemGroup] {
        var byCategory: [GroceryCategory: [GroceryItem]] = [:]
        for item in items {
            byCategory[item.category, default: []].append(item)
        }
        return GroceryCategory.allCases.compactMap { category in
            guard let group = byCategory[category], !group.isEmpty else { return nil }
            return ItemGroup(id: "cat:\(category.rawValue)", title: category.displayName, systemImage: category.systemImage, items: displayOrdered(group))
        }
    }

    /// Within a section: unchecked items first (still to buy), then checked,
    /// each alphabetical — so crossed-off items sink to the bottom.
    private func displayOrdered(_ items: [GroceryItem]) -> [GroceryItem] {
        items.sorted { lhs, rhs in
            if lhs.isChecked != rhs.isChecked { return !lhs.isChecked }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func load() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await service.fetchAll()
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// Adds a standalone item typed in on this screen. Category is auto-guessed
    /// from the name unless one is explicitly passed (the Add sheet lets the
    /// user override the guess). Blank names are ignored.
    func addManualItem(name: String, amount: Double, unit: String, category: GroceryCategory? = nil) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let resolved = category ?? GroceryCategorizer.categorize(trimmedName)
        let draft = GroceryItemDraft(
            name: trimmedName,
            amount: amount,
            unit: unit.trimmingCharacters(in: .whitespacesAndNewlines),
            category: resolved
        )
        do {
            let item = try await service.add(draft)
            items.append(item)
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    func toggleChecked(_ item: GroceryItem) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let newValue = !items[index].isChecked
        items[index].isChecked = newValue // optimistic
        do {
            try await service.setChecked(id: item.id, isChecked: newValue)
        } catch {
            if let i = items.firstIndex(where: { $0.id == item.id }) { items[i].isChecked = !newValue }
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    func setCategory(_ item: GroceryItem, to category: GroceryCategory) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let previous = items[index].category
        items[index].category = category // optimistic
        do {
            try await service.setCategory(id: item.id, category: category)
        } catch {
            if let i = items.firstIndex(where: { $0.id == item.id }) { items[i].category = previous }
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    func delete(_ item: GroceryItem) async {
        let snapshot = items
        items.removeAll { $0.id == item.id } // optimistic
        do {
            try await service.delete(id: item.id)
        } catch {
            items = snapshot
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    func clearList() async {
        let snapshot = items
        items = [] // optimistic
        do {
            try await service.clearAll()
        } catch {
            items = snapshot
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    func exportToReminders() async {
        errorMessage = nil
        isExporting = true
        defer { isExporting = false }
        // Export what's still needed (unchecked) — the point of a checklist is
        // that checked items are already in the cart.
        let formatted = items
            .filter { !$0.isChecked }
            .map { Self.formatItem(name: $0.name, amount: $0.amount, unit: $0.unit) }
        do {
            try await reminderService.export(items: formatted, listName: "VJ Test Kitchen Groceries")
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// "200 g" / "1" / "" (blank for a zero/"to taste" amount with no unit).
    static func formattedQuantity(amount: Double, unit: String) -> String {
        guard amount > 0 else { return unit.trimmingCharacters(in: .whitespaces) }
        let amountText = amount == amount.rounded()
            ? String(Int(amount))
            : String(format: "%.2f", amount)
        return unit.isEmpty ? amountText : "\(amountText) \(unit)"
    }

    static func formatItem(name: String, amount: Double, unit: String) -> String {
        let qty = formattedQuantity(amount: amount, unit: unit)
        return qty.isEmpty ? name : "\(qty) \(name)"
    }
}
