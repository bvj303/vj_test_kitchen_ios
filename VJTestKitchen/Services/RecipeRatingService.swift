import Foundation
import Supabase

protocol RecipeRatingServicing: Sendable {
    /// The current user's own rating/notes for a recipe, or nil if they
    /// haven't rated/annotated it yet.
    func fetchMine(recipeId: Int64) async throws -> RecipeRating?
    func upsertMine(recipeId: Int64, rating: Int?, notes: String?) async throws
}

struct RecipeRatingService: RecipeRatingServicing {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseManager.client) {
        self.client = client
    }

    func fetchMine(recipeId: Int64) async throws -> RecipeRating? {
        let userId = try await client.auth.session.user.id
        let ratings: [RecipeRating] = try await client
            .from("recipe_ratings")
            .select()
            .eq("recipe_id", value: String(recipeId))
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
        return ratings.first
    }

    func upsertMine(recipeId: Int64, rating: Int?, notes: String?) async throws {
        let userId = try await client.auth.session.user.id
        let payload = RecipeRatingUpsert(recipeId: recipeId, userId: userId, rating: rating, notes: notes)
        try await client
            .from("recipe_ratings")
            .upsert(payload, onConflict: "recipe_id,user_id")
            .execute()
    }
}
