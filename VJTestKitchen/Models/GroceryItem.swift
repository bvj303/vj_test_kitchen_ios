import Foundation

/// A single account-synced grocery-list entry (see `grocery_items` migration and
/// DECISIONS.md). Concrete and standalone — unlike `Ingredient` it isn't tied to
/// a recipe's lifecycle. `sourceRecipeId`/`sourceRecipeTitle` only record where
/// an item was added from so the "by recipe" view has a heading; the title is a
/// snapshot, so a later recipe rename/delete doesn't move or drop the item.
struct GroceryItem: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var userId: UUID
    var name: String
    var amount: Double
    var unit: String
    var category: GroceryCategory
    var isChecked: Bool
    var sourceRecipeId: Int64?
    var sourceRecipeTitle: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, userId, name, amount, unit, category, isChecked
        case sourceRecipeId, sourceRecipeTitle, createdAt
    }

    init(
        id: UUID, userId: UUID, name: String, amount: Double, unit: String,
        category: GroceryCategory, isChecked: Bool,
        sourceRecipeId: Int64?, sourceRecipeTitle: String?, createdAt: Date
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.amount = amount
        self.unit = unit
        self.category = category
        self.isChecked = isChecked
        self.sourceRecipeId = sourceRecipeId
        self.sourceRecipeTitle = sourceRecipeTitle
        self.createdAt = createdAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userId = try container.decode(UUID.self, forKey: .userId)
        name = try container.decode(String.self, forKey: .name)
        amount = try container.decode(Double.self, forKey: .amount)
        unit = try container.decode(String.self, forKey: .unit)
        // Lenient: an unknown/legacy category key falls back to `.other` rather
        // than failing the whole list's decode.
        category = GroceryCategory(storageKey: try container.decode(String.self, forKey: .category))
        isChecked = try container.decode(Bool.self, forKey: .isChecked)
        sourceRecipeId = try container.decodeIfPresent(Int64.self, forKey: .sourceRecipeId)
        sourceRecipeTitle = try container.decodeIfPresent(String.self, forKey: .sourceRecipeTitle)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

/// Insert payload — no `id`/`createdAt` (server-assigned). `category` is the
/// enum's storage key. `GroceryItemService` resolves `userId` internally.
struct GroceryItemInsert: Codable, Sendable {
    var userId: UUID
    var name: String
    var amount: Double
    var unit: String
    var category: String
    var isChecked: Bool
    var sourceRecipeId: Int64?
    var sourceRecipeTitle: String?

    init(userId: UUID, draft: GroceryItemDraft) {
        self.userId = userId
        self.name = draft.name
        self.amount = draft.amount
        self.unit = draft.unit
        self.category = draft.category.rawValue
        self.isChecked = false
        self.sourceRecipeId = draft.sourceRecipeId
        self.sourceRecipeTitle = draft.sourceRecipeTitle
    }
}

/// User-facing fields for a new item — no `id`/`userId`/`createdAt`/`isChecked`.
struct GroceryItemDraft: Sendable, Equatable {
    var name: String
    var amount: Double
    var unit: String
    var category: GroceryCategory
    var sourceRecipeId: Int64?
    var sourceRecipeTitle: String?

    init(
        name: String, amount: Double, unit: String, category: GroceryCategory,
        sourceRecipeId: Int64? = nil, sourceRecipeTitle: String? = nil
    ) {
        self.name = name
        self.amount = amount
        self.unit = unit
        self.category = category
        self.sourceRecipeId = sourceRecipeId
        self.sourceRecipeTitle = sourceRecipeTitle
    }
}
