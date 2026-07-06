import Foundation
import Supabase

protocol MealPlanServicing: Sendable {
    /// Meal plans are private per-user (see schema decisions), so this is
    /// implicitly "my" meal plans — RLS enforces it regardless.
    func fetchAll() async throws -> [MealPlanWithRecipe]
    func create(_ draft: MealPlanDraft) async throws
    func delete(id: Int64) async throws
}

struct MealPlanService: MealPlanServicing {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseManager.client) {
        self.client = client
    }

    func fetchAll() async throws -> [MealPlanWithRecipe] {
        try await client
            .from("meal_plans")
            .select("*, recipes(title)")
            .order("date")
            .execute()
            .value
    }

    func create(_ draft: MealPlanDraft) async throws {
        let userId = try await client.auth.session.user.id
        let insert = MealPlanInsert(userId: userId, date: draft.date, mealType: draft.mealType, recipeId: draft.recipeId)
        try await client
            .from("meal_plans")
            .insert(insert)
            .execute()
    }

    func delete(id: Int64) async throws {
        try await client
            .from("meal_plans")
            .delete()
            .eq("id", value: String(id))
            .execute()
    }
}
