import Foundation
import Supabase

protocol TagServicing: Sendable {
    /// All tag names in the shared vocabulary, alphabetical — drives the
    /// Recipes list's category filter menu so it reflects the actual catalog.
    /// (Writing a recipe's tags moved into the atomic `save_recipe` RPC — see
    /// `RecipeSaveService`.)
    func fetchAllNames() async throws -> [String]
}

struct TagService: TagServicing {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseManager.client) {
        self.client = client
    }

    func fetchAllNames() async throws -> [String] {
        let tags: [Tag] = try await client
            .from("tags")
            .select("id,name")
            .order("name")
            .execute()
            .value
        return tags.map(\.name)
    }
}
