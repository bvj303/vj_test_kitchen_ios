import Foundation
import Supabase

protocol RecipeRatingServicing: Sendable {
    /// The current user's own rating/notes for a recipe, or nil if they
    /// haven't rated/annotated it yet.
    func fetchMine(recipeId: Int64) async throws -> RecipeRating?
    func upsertMine(recipeId: Int64, rating: Int?, notes: String?) async throws
    /// Every household member's rating + notes for a recipe (a star rating or a
    /// written note), joined with the reviewer's public profile, newest first.
    /// Household-readable per the favorites_and_community_ratings migration.
    func fetchReviews(recipeId: Int64) async throws -> [RecipeReview]
}

extension RecipeRatingServicing {
    /// Default so existing test fakes needn't implement community reviews.
    func fetchReviews(recipeId: Int64) async throws -> [RecipeReview] { [] }
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

    func fetchReviews(recipeId: Int64) async throws -> [RecipeReview] {
        try await client
            .from("recipe_ratings")
            .select("user_id, rating, notes, updated_at, profiles(display_name, username, avatar_url)")
            .eq("recipe_id", value: String(recipeId))
            // Only rows with something to show — a star rating or a written note.
            .or("rating.not.is.null,notes.not.is.null")
            .order("updated_at", ascending: false)
            .execute()
            .value
    }
}
