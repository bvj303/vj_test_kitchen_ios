import Foundation

struct Tag: Codable, Identifiable, Sendable, Hashable {
    let id: Int64
    var name: String
}

struct TagInsert: Codable, Sendable {
    var name: String
}

/// Join row for the recipes<->tags many-to-many relationship.
struct RecipeTag: Codable, Sendable, Hashable {
    var recipeId: Int64
    var tagId: Int64
}
