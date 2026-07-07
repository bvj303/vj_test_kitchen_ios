import Foundation

/// Recipe plus its embedded ingredients/tags, matching a Postgrest embedded
/// select (`recipes.select("*, ingredients(*), recipe_tags(tags(name))")`).
/// Kept separate from the plain `Recipe` model since the list screen doesn't
/// need ingredients/tags and shouldn't pay for the join.
struct RecipeDetail: Codable, Sendable, Identifiable {
    let id: Int64
    var userId: UUID?
    var title: String
    var description: String?
    var instructions: String?
    var imagePath: String?
    var imageUrl: String? = nil
    var prepTime: Int?
    var servings: Int?
    let createdAt: Date
    var ingredients: [Ingredient]
    var recipeTags: [RecipeTagJoin]

    var tagNames: [String] { recipeTags.map(\.tags.name) }

    struct RecipeTagJoin: Codable, Sendable, Hashable {
        var tags: TagName
        struct TagName: Codable, Sendable, Hashable {
            var name: String
        }
    }
}
