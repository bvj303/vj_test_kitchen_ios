import Foundation
import Supabase

protocol RecipeServicing: Sendable {
    func fetchAll() async throws -> [Recipe]
    func fetchDetail(id: Int64) async throws -> RecipeDetail
    @discardableResult
    func create(_ draft: RecipeDraft) async throws -> Recipe
    func update(id: Int64, with draft: RecipeDraft) async throws
    func delete(id: Int64) async throws
}

/// Reference implementation of the Service-layer pattern: one struct per
/// resource, thin async/await wrappers around Postgrest calls, Codable
/// models in and out. Replicate this shape for meal_plans as each screen
/// needs it.
struct RecipeService: RecipeServicing {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseManager.client) {
        self.client = client
    }

    func fetchAll() async throws -> [Recipe] {
        // Paginate so the catalog isn't silently truncated at PostgREST's
        // default max-rows cap once the recipe count grows (Stage 8 import).
        try await Pagination.fetchAllPages { from, to in
            try await client
                .from("recipes")
                .select()
                .order("id")
                .range(from: from, to: to)
                .execute()
                .value
        }
    }

    func fetchDetail(id: Int64) async throws -> RecipeDetail {
        try await client
            .from("recipes")
            .select("*, ingredients(*), recipe_tags(tags(name))")
            .eq("id", value: String(id))
            .single()
            .execute()
            .value
    }

    @discardableResult
    func create(_ draft: RecipeDraft) async throws -> Recipe {
        let userId = try await client.auth.session.user.id
        let insert = RecipeInsert(
            userId: userId,
            title: draft.title,
            description: draft.description,
            instructions: draft.instructions,
            imagePath: draft.imagePath,
            prepTime: draft.prepTime,
            servings: draft.servings
        )
        return try await client
            .from("recipes")
            .insert(insert)
            .select()
            .single()
            .execute()
            .value
    }

    func update(id: Int64, with draft: RecipeDraft) async throws {
        try await client
            .from("recipes")
            .update(RecipeUpdate(draft: draft))
            .eq("id", value: String(id))
            .execute()
    }

    func delete(id: Int64) async throws {
        try await client
            .from("recipes")
            .delete()
            .eq("id", value: String(id))
            .execute()
    }
}
