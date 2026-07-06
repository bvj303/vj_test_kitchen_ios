import Foundation
import Supabase

protocol RecipeServicing: Sendable {
    /// Fetches one page of the recipe list, newest-column-set-first (`id`
    /// order), optionally narrowed by a title substring match. Selects only
    /// list-relevant columns — `RecipeDetailView` re-fetches full detail via
    /// `fetchDetail(id:)`, so the list never needs to pull `description`/
    /// `instructions` for every row.
    func fetchPage(offset: Int, limit: Int, matching search: String?) async throws -> [Recipe]
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

    func fetchPage(offset: Int, limit: Int, matching search: String?) async throws -> [Recipe] {
        var query = client
            .from("recipes")
            .select("id,title,image_path,prep_time,servings,created_at")

        if let search, !search.isEmpty {
            query = query.ilike("title", pattern: "%\(Self.escapedForIlike(search))%")
        }

        return try await query
            .order("id")
            .range(from: offset, to: offset + limit - 1)
            .execute()
            .value
    }

    /// Escapes `ilike` wildcard characters (`%`, `_`) and the escape
    /// character itself so user-typed search text is matched literally
    /// rather than being read as a pattern.
    private static func escapedForIlike(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
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
