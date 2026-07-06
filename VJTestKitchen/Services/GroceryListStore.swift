import Foundation

/// Which recipes are "on the grocery list" is a client-side preference, not
/// shared data — matches the old app's localStorage-backed approach (see
/// DECISIONS.md). No Postgres table for this by design.
protocol GroceryListStoring: Sendable {
    func loadSelectedRecipeIds() -> [Int64]
    func saveSelectedRecipeIds(_ ids: [Int64])
}

struct UserDefaultsGroceryListStore: GroceryListStoring {
    private static let key = "vj_grocery_recipe_ids"
    // UserDefaults is thread-safe in practice but not yet marked Sendable
    // in the SDK — safe to bypass the check here.
    nonisolated(unsafe) private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadSelectedRecipeIds() -> [Int64] {
        (defaults.array(forKey: Self.key) as? [Int])?.map(Int64.init) ?? []
    }

    func saveSelectedRecipeIds(_ ids: [Int64]) {
        defaults.set(ids.map(Int.init), forKey: Self.key)
    }
}
