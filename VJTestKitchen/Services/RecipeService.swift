import Foundation
import Supabase

protocol RecipeServicing: Sendable {
    /// Fetches one page of the recipe list (`id` order), optionally narrowed by
    /// a title substring match, a tag name, and/or a maximum prep time. Selects
    /// only list-relevant columns — `RecipeDetailView` re-fetches full detail
    /// via `fetchDetail(id:)`, so the list never needs to pull `description`/
    /// `instructions` for every row. All filters are applied server-side so the
    /// list stays paginated and scalable at 15K+ rows.
    func fetchPage(offset: Int, limit: Int, matching search: String?, tag: String?, maxPrepTime: Int?) async throws -> [Recipe]
    func fetchDetail(id: Int64) async throws -> RecipeDetail
    @discardableResult
    func create(_ draft: RecipeDraft) async throws -> Recipe
    func update(id: Int64, with draft: RecipeDraft) async throws
    func delete(id: Int64) async throws
}

extension RecipeServicing {
    /// Unfiltered convenience for callers that only page + title-search (e.g.
    /// the Calendar Quick Planner), so they don't spell out the tag/prep-time
    /// filters the Recipes list uses.
    func fetchPage(offset: Int, limit: Int, matching search: String?) async throws -> [Recipe] {
        try await fetchPage(offset: offset, limit: limit, matching: search, tag: nil, maxPrepTime: nil)
    }
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

    func fetchPage(offset: Int, limit: Int, matching search: String?, tag: String?, maxPrepTime: Int?) async throws -> [Recipe] {
        // A tag filter needs an inner join to `recipe_tags`/`tags`; only pay for
        // the embed when a tag is actually selected. Recipe's Codable ignores
        // the extra `recipe_tags` key that the embed adds to each row.
        let hasTag = tag?.isEmpty == false
        let columns = hasTag
            ? "id,title,image_path,prep_time,servings,created_at,recipe_tags!inner(tags!inner(name))"
            : "id,title,image_path,prep_time,servings,created_at"

        var query = client
            .from("recipes")
            .select(columns)

        if let search, !search.isEmpty {
            query = query.ilike("title", pattern: "%\(Self.escapedForIlike(search))%")
        }
        if let tag, hasTag {
            query = query.eq("recipe_tags.tags.name", value: tag)
        }
        if let maxPrepTime {
            // Filter values go over as String (see CLAUDE.md — Int64 doesn't
            // conform to PostgrestFilterValue in supabase-swift 2.x).
            query = query.lte("prep_time", value: String(maxPrepTime))
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
