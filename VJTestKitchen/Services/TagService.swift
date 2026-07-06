import Foundation
import Supabase

protocol TagServicing: Sendable {
    /// Full replace of a recipe's tags: detach everything currently linked,
    /// find-or-create each named tag (tags are a shared global vocabulary —
    /// see schema decisions in DECISIONS.md), then relink.
    func replaceAll(recipeId: Int64, withTagNames names: [String]) async throws
}

struct TagService: TagServicing {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseManager.client) {
        self.client = client
    }

    func replaceAll(recipeId: Int64, withTagNames names: [String]) async throws {
        try await client
            .from("recipe_tags")
            .delete()
            .eq("recipe_id", value: String(recipeId))
            .execute()

        guard !names.isEmpty else { return }

        // Tags have no UPDATE policy (see migration) — ignoreDuplicates maps
        // to ON CONFLICT DO NOTHING, which only needs INSERT privilege.
        try await client
            .from("tags")
            .upsert(names.map { TagInsert(name: $0) }, onConflict: "name", ignoreDuplicates: true)
            .execute()

        let tags: [Tag] = try await client
            .from("tags")
            .select()
            .in("name", values: names)
            .execute()
            .value

        let joins = tags.map { RecipeTag(recipeId: recipeId, tagId: $0.id) }
        try await client
            .from("recipe_tags")
            .insert(joins)
            .execute()
    }
}
