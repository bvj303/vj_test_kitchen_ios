import Foundation
import Supabase

/// One ingredient in an atomic save payload — mirrors the `jsonb` element shape
/// the `save_recipe` Postgres function unpacks.
struct RecipeSaveIngredient: Codable, Sendable, Equatable {
    var name: String
    var amount: Double
    var unit: String
}

/// Saves a recipe together with its ingredients and tags **atomically**, via
/// the `save_recipe` Postgres function (see the `save_recipe_atomic`
/// migration). The previous client-side sequence (create/update recipe →
/// replace ingredients → replace tags) was 3+ separate requests: a network
/// drop mid-save could permanently lose a recipe's ingredients (deleted but
/// not re-inserted) or duplicate the recipe on retry. One RPC = one
/// transaction: it all lands or none of it does.
protocol RecipeSaving: Sendable {
    /// Creates (`recipeId == nil`) or fully updates a recipe, returning its id.
    @discardableResult
    func save(recipeId: Int64?, draft: RecipeDraft, ingredients: [RecipeSaveIngredient], tagNames: [String]) async throws -> Int64
}

struct RecipeSaveService: RecipeSaving {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseManager.client) {
        self.client = client
    }

    /// RPC params, keyed to the function's `p_…` argument names (the client's
    /// snake_case encoder turns `pRecipeId` into `p_recipe_id`). Optionals are
    /// encoded as explicit JSON nulls — PostgREST matches the function by the
    /// full set of provided keys, so omitting a nil key would 404 the call.
    private struct Params: Encodable {
        let pRecipeId: Int64?
        let pTitle: String
        let pDescription: String?
        let pInstructions: String?
        let pImagePath: String?
        let pPrepTime: Int?
        let pServings: Int?
        let pIngredients: [RecipeSaveIngredient]
        let pTagNames: [String]

        enum CodingKeys: CodingKey {
            case pRecipeId, pTitle, pDescription, pInstructions, pImagePath, pPrepTime, pServings, pIngredients, pTagNames
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(pRecipeId, forKey: .pRecipeId)
            try container.encode(pTitle, forKey: .pTitle)
            try container.encode(pDescription, forKey: .pDescription)
            try container.encode(pInstructions, forKey: .pInstructions)
            try container.encode(pImagePath, forKey: .pImagePath)
            try container.encode(pPrepTime, forKey: .pPrepTime)
            try container.encode(pServings, forKey: .pServings)
            try container.encode(pIngredients, forKey: .pIngredients)
            try container.encode(pTagNames, forKey: .pTagNames)
        }
    }

    @discardableResult
    func save(recipeId: Int64?, draft: RecipeDraft, ingredients: [RecipeSaveIngredient], tagNames: [String]) async throws -> Int64 {
        let params = Params(
            pRecipeId: recipeId,
            pTitle: draft.title,
            pDescription: draft.description,
            pInstructions: draft.instructions,
            pImagePath: draft.imagePath,
            pPrepTime: draft.prepTime,
            pServings: draft.servings,
            pIngredients: ingredients,
            pTagNames: tagNames
        )
        return try await client
            .rpc("save_recipe", params: params)
            .execute()
            .value
    }
}
