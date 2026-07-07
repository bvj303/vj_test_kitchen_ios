import Foundation

/// Which recipes are "on the grocery list" (and any standalone items added
/// alongside them) is a client-side preference, not shared data — matches the
/// old app's localStorage-backed approach (see DECISIONS.md). No Postgres
/// table for this by design.
protocol GroceryListStoring: Sendable {
    func loadSelectedRecipeIds() -> [Int64]
    func saveSelectedRecipeIds(_ ids: [Int64])
    func loadCustomItems() -> [GroceryItem]
    func saveCustomItems(_ items: [GroceryItem])
}

struct UserDefaultsGroceryListStore: GroceryListStoring {
    private static let recipeIdsKey = "vj_grocery_recipe_ids"
    private static let customItemsKey = "vj_grocery_custom_items"
    // UserDefaults is thread-safe in practice but not yet marked Sendable
    // in the SDK — safe to bypass the check here.
    nonisolated(unsafe) private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadSelectedRecipeIds() -> [Int64] {
        (defaults.array(forKey: Self.recipeIdsKey) as? [Int])?.map(Int64.init) ?? []
    }

    func saveSelectedRecipeIds(_ ids: [Int64]) {
        defaults.set(ids.map(Int.init), forKey: Self.recipeIdsKey)
    }

    func loadCustomItems() -> [GroceryItem] {
        guard let data = defaults.data(forKey: Self.customItemsKey) else { return [] }
        return (try? JSONDecoder().decode([GroceryItem].self, from: data)) ?? []
    }

    func saveCustomItems(_ items: [GroceryItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Self.customItemsKey)
    }
}
