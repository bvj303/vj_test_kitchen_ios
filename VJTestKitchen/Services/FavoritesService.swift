import Foundation
import Supabase

/// Per-user recipe favorites (private, RLS-scoped). Resolves "who am I"
/// internally, same pattern as `RecipeRatingService` / `GroceryItemService`, so
/// ViewModels never pass a user id around.
protocol FavoritesServicing: Sendable {
    /// The set of recipe ids the current user has favorited.
    func fetchMyFavoriteIds() async throws -> Set<Int64>
    /// Adds or removes a recipe from the current user's favorites.
    func setFavorite(recipeId: Int64, isFavorite: Bool) async throws
}

struct FavoritesService: FavoritesServicing {
    private struct FavoriteRow: Decodable { let recipeId: Int64 }
    private struct FavoriteInsert: Encodable { let userId: UUID; let recipeId: Int64 }

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseManager.client) {
        self.client = client
    }

    func fetchMyFavoriteIds() async throws -> Set<Int64> {
        let userId = try await client.auth.session.user.id
        let rows: [FavoriteRow] = try await client
            .from("recipe_favorites")
            .select("recipe_id")
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
        return Set(rows.map(\.recipeId))
    }

    func setFavorite(recipeId: Int64, isFavorite: Bool) async throws {
        let userId = try await client.auth.session.user.id
        if isFavorite {
            // Upsert-ignore so re-favoriting an already-favorited recipe is a
            // no-op rather than a primary-key conflict.
            try await client
                .from("recipe_favorites")
                .upsert(FavoriteInsert(userId: userId, recipeId: recipeId), onConflict: "user_id,recipe_id", ignoreDuplicates: true)
                .execute()
        } else {
            try await client
                .from("recipe_favorites")
                .delete()
                .eq("user_id", value: userId.uuidString)
                .eq("recipe_id", value: String(recipeId))
                .execute()
        }
    }
}
