import Foundation

/// A standalone grocery entry — either typed in directly on the Grocery List
/// screen, or snapshotted from a single recipe ingredient. Unlike `Ingredient`,
/// this has no `recipeId`: it isn't tied to (or kept in sync with) any recipe,
/// matching the client-side-only nature of the rest of the grocery list.
struct GroceryItem: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var name: String
    var amount: Double
    var unit: String

    init(id: UUID = UUID(), name: String, amount: Double, unit: String) {
        self.id = id
        self.name = name
        self.amount = amount
        self.unit = unit
    }
}
