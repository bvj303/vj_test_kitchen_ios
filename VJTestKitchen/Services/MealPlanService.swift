import Foundation
import Supabase

protocol MealPlanServicing: Sendable {
    /// Meal plans are private per-user (see schema decisions), so this is
    /// implicitly "my" meal plans — RLS enforces it regardless. Bounded to a
    /// "yyyy-MM-dd" date window (inclusive) so the calendar only pays for the
    /// days it shows — planning history accumulates without bound, and the old
    /// fetch-everything call re-downloaded all of it on every visit.
    func fetch(from startDate: String, to endDate: String) async throws -> [MealPlanWithRecipe]
    /// Returns the created row (joined with its recipe title) so callers can
    /// patch local state instead of re-fetching the window.
    @discardableResult
    func create(_ draft: MealPlanDraft) async throws -> MealPlanWithRecipe
    func delete(id: Int64) async throws
}

struct MealPlanService: MealPlanServicing {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseManager.client) {
        self.client = client
    }

    func fetch(from startDate: String, to endDate: String) async throws -> [MealPlanWithRecipe] {
        try await client
            .from("meal_plans")
            .select("*, recipes(title)")
            .gte("date", value: startDate)
            .lte("date", value: endDate)
            .order("date")
            .execute()
            .value
    }

    @discardableResult
    func create(_ draft: MealPlanDraft) async throws -> MealPlanWithRecipe {
        let userId = try await client.auth.session.user.id
        let insert = MealPlanInsert(userId: userId, date: draft.date, mealType: draft.mealType, recipeId: draft.recipeId)
        return try await client
            .from("meal_plans")
            .insert(insert)
            .select("*, recipes(title)")
            .single()
            .execute()
            .value
    }

    func delete(id: Int64) async throws {
        try await client
            .from("meal_plans")
            .delete()
            .eq("id", value: String(id))
            .execute()
    }
}
