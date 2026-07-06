import Foundation
import Supabase

protocol IngredientServicing: Sendable {
    /// Full replace, matching how the old app's recipe form worked: delete
    /// everything currently attached to the recipe, then insert the new set.
    func replaceAll(recipeId: Int64, with ingredients: [IngredientInsert]) async throws
}

struct IngredientService: IngredientServicing {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseManager.client) {
        self.client = client
    }

    func replaceAll(recipeId: Int64, with ingredients: [IngredientInsert]) async throws {
        try await client
            .from("ingredients")
            .delete()
            .eq("recipe_id", value: String(recipeId))
            .execute()

        guard !ingredients.isEmpty else { return }

        try await client
            .from("ingredients")
            .insert(ingredients)
            .execute()
    }
}
