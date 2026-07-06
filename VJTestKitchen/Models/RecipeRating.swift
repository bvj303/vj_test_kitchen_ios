import Foundation

/// A single user's personal rating/notes on a recipe — private to that user,
/// never shared or aggregated (see DECISIONS.md, 2026-07-06).
struct RecipeRating: Codable, Sendable, Hashable {
    let recipeId: Int64
    let userId: UUID
    var rating: Int?
    var notes: String?
    let createdAt: Date
    let updatedAt: Date
}

struct RecipeRatingUpsert: Codable, Sendable {
    var recipeId: Int64
    var userId: UUID
    var rating: Int?
    var notes: String?
}
