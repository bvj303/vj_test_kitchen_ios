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
    /// SwiftUI's `Section` in the view. Holds display *rows*, not raw items:
    /// a category row may combine several like-named items into one summed line.
    struct ItemGroup: Identifiable {
        let id: String
        let title: String
        let systemImage: String
        var rows: [GroceryDisplayRow]
    }

    /// Publishing the Grocery widget snapshot from `items`' `didSet` keeps the
    /// widget in sync across *every* mutation — the initial load plus each
    /// optimistic add/toggle/delete/clear (and their reverts) — without
    /// scattering publish calls through every method.
    private(set) var items: [GroceryItem] = [] {
        didSet { widgetPublisher.publishGrocery(items: items) }
    }
    var grouping: Grouping = .byRecipe
    private(set) var isLoading = false
    private(set) var isExporting = false
    var errorMessage: String?

    private let service: GroceryItemServicing
    private let reminderService: ReminderExporting
    private let widgetPublisher: WidgetPublishing

    init(
        service: GroceryItemServicing = GroceryItemService(),
        reminderService: ReminderExporting = ReminderService(),
        widgetPublisher: WidgetPublishing = WidgetPublisher()
    ) {
        self.service = service
        self.reminderService = reminderService
        self.widgetPublisher = widgetPublisher
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
    /// Items" last. Each item stays its own row here (no combining) — the point
    /// of this view is to see what each recipe calls for.
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
                ItemGroup(id: "recipe:\(title)", title: title, systemImage: "fork.knife", rows: displayOrdered(singleRows(byTitle[title] ?? [])))
            }
        if !others.isEmpty {
            result.append(ItemGroup(id: "recipe:__other", title: "Other Items", systemImage: "cart", rows: displayOrdered(singleRows(others))))
        }
        return result
    }

    /// Grouped by food category, in aisle order (`GroceryCategory.allCases`).
    /// Within a category, like ingredients from different recipes are *combined*
    /// into a single summed row (2 lemons + 1 lemon → "3") via `GroceryAggregator`.
    private var categoryGroups: [ItemGroup] {
        var byCategory: [GroceryCategory: [GroceryItem]] = [:]
        for item in items {
            byCategory[item.category, default: []].append(item)
        }
        return GroceryCategory.allCases.compactMap { category in
            guard let group = byCategory[category], !group.isEmpty else { return nil }
            return ItemGroup(id: "cat:\(category.rawValue)", title: category.displayName, systemImage: category.systemImage, rows: displayOrdered(GroceryAggregator.combine(group)))
        }
    }

    private func singleRows(_ items: [GroceryItem]) -> [GroceryDisplayRow] {
        items.map(GroceryDisplayRow.init(single:))
    }

    /// Within a section: unchecked rows first (still to buy), then checked, each
    /// alphabetical — so crossed-off rows sink to the bottom.
    private func displayOrdered(_ rows: [GroceryDisplayRow]) -> [GroceryDisplayRow] {
        rows.sorted { lhs, rhs in
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

    // MARK: - Row mutations
    //
    // The primitives operate on a *row*, fanning the mutation out to every
    // underlying item — so toggling/deleting/recategorizing a combined
    // "by category" line (2 lemons + 1 lemon) affects all of its sources at
    // once. The single-item overloads (used by callers holding a bare
    // `GroceryItem`) just wrap it in a one-item row.

    func toggleChecked(_ row: GroceryDisplayRow) async {
        let newValue = !row.isChecked
        let ids = Set(row.items.map(\.id))
        let snapshot = items
        for i in items.indices where ids.contains(items[i].id) { items[i].isChecked = newValue } // optimistic
        await reconcile(ids: ids, snapshot: snapshot) { try await service.setChecked(id: $0, isChecked: newValue) }
    }

    func toggleChecked(_ item: GroceryItem) async {
        await toggleChecked(GroceryDisplayRow(single: item))
    }

    func setCategory(_ row: GroceryDisplayRow, to category: GroceryCategory) async {
        let ids = Set(row.items.map(\.id))
        let snapshot = items
        for i in items.indices where ids.contains(items[i].id) { items[i].category = category } // optimistic
        await reconcile(ids: ids, snapshot: snapshot) { try await service.setCategory(id: $0, category: category) }
    }

    func setCategory(_ item: GroceryItem, to category: GroceryCategory) async {
        await setCategory(GroceryDisplayRow(single: item), to: category)
    }

    func delete(_ row: GroceryDisplayRow) async {
        let ids = Set(row.items.map(\.id))
        let snapshot = items
        items.removeAll { ids.contains($0.id) } // optimistic
        await reconcile(ids: ids, snapshot: snapshot) { try await service.delete(id: $0) }
    }

    /// Runs the per-item server mutation for every id (the row was already
    /// updated optimistically), reverting **only** the ids whose call throws —
    /// successes stay applied. This keeps a partially-failed combined row (e.g.
    /// "2 lemons + 1 lemon" spanning two DB rows where one write fails) matching
    /// real server state instead of snapping the whole row back, which the old
    /// all-or-nothing `items = snapshot` did. Surfaces the last error, if any.
    private func reconcile(ids: Set<UUID>, snapshot: [GroceryItem], _ op: (UUID) async throws -> Void) async {
        var failed = Set<UUID>()
        var lastError: Error?
        for id in ids {
            do { try await op(id) } catch { failed.insert(id); lastError = error }
        }
        guard !failed.isEmpty else { return }
        // Restore each failed id from the snapshot: a mutated item resets in
        // place, a deleted one is re-inserted (order doesn't matter — `groups`
        // re-sorts). Successful ids are left as the optimistic update set them.
        let snapshotById = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.id, $0) })
        for id in failed {
            guard let original = snapshotById[id] else { continue }
            if let idx = items.firstIndex(where: { $0.id == id }) {
                items[idx] = original
            } else {
                items.append(original)
            }
        }
        if let lastError { errorMessage = ErrorPresenter.message(for: lastError) }
    }

    func delete(_ item: GroceryItem) async {
        await delete(GroceryDisplayRow(single: item))
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
    /// `nonisolated` so pure helpers like `GroceryAggregator` can reuse it as the
    /// single source of quantity formatting without hopping to the main actor.
    nonisolated static func formattedQuantity(amount: Double, unit: String) -> String {
        guard amount > 0 else { return unit.trimmingCharacters(in: .whitespaces) }
        let amountText = amount == amount.rounded()
            ? String(Int(amount))
            : String(format: "%.2f", amount)
        return unit.isEmpty ? amountText : "\(amountText) \(unit)"
    }

    nonisolated static func formatItem(name: String, amount: Double, unit: String) -> String {
        let qty = formattedQuantity(amount: amount, unit: unit)
        return qty.isEmpty ? name : "\(qty) \(name)"
    }
}
