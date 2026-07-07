import Foundation

/// Grocery aisle a `GroceryItem` belongs to. Declared in the order they should
/// appear in the "by category" view (roughly a store's layout), so `allCases`
/// doubles as the section order. The `rawValue` is the stable key persisted in
/// the `grocery_items.category` column — don't rename these without a data
/// migration.
enum GroceryCategory: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case produce
    case meat
    case seafood
    case dairy
    case bakery
    case pantry
    case bakingSpices = "baking_spices"
    case condiments
    case frozen
    case beverages
    case snacks
    case household
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .produce: "Produce"
        case .meat: "Meat & Poultry"
        case .seafood: "Seafood"
        case .dairy: "Dairy & Eggs"
        case .bakery: "Bakery"
        case .pantry: "Pantry"
        case .bakingSpices: "Baking & Spices"
        case .condiments: "Condiments & Sauces"
        case .frozen: "Frozen"
        case .beverages: "Beverages"
        case .snacks: "Snacks"
        case .household: "Household"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .produce: "carrot"
        case .meat: "fork.knife"
        case .seafood: "fish"
        case .dairy: "carton.fill"
        case .bakery: "birthday.cake"
        case .pantry: "cabinet"
        case .bakingSpices: "leaf"
        case .condiments: "drop"
        case .frozen: "snowflake"
        case .beverages: "cup.and.saucer"
        case .snacks: "popcorn"
        case .household: "house"
        case .other: "bag"
        }
    }

    /// Tolerates an unknown/legacy key from the DB by falling back to `.other`
    /// rather than failing to decode the whole row.
    init(storageKey: String) {
        self = GroceryCategory(rawValue: storageKey) ?? .other
    }
}
