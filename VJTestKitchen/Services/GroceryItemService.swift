import Foundation
import Supabase

/// Account-synced grocery list. Items are private per user (RLS-enforced), so
/// every call is implicitly "my" items — the service resolves the current user
/// internally, same pattern as `RecipeRatingService`/`MealPlanService`, so
/// ViewModels never pass a user id around.
protocol GroceryItemServicing: Sendable {
    func fetchAll() async throws -> [GroceryItem]
    func add(_ draft: GroceryItemDraft) async throws -> GroceryItem
    func addMany(_ drafts: [GroceryItemDraft]) async throws -> [GroceryItem]
    func setChecked(id: UUID, isChecked: Bool) async throws
    func setCategory(id: UUID, category: GroceryCategory) async throws
    func delete(id: UUID) async throws
    func clearAll() async throws
}

struct GroceryItemService: GroceryItemServicing {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseManager.client) {
        self.client = client
    }

    func fetchAll() async throws -> [GroceryItem] {
        try await client
            .from("grocery_items")
            .select()
            .order("created_at")
            .execute()
            .value
    }

    func add(_ draft: GroceryItemDraft) async throws -> GroceryItem {
        let userId = try await client.auth.session.user.id
        return try await client
            .from("grocery_items")
            .insert(GroceryItemInsert(userId: userId, draft: draft))
            .select()
            .single()
            .execute()
            .value
    }

    func addMany(_ drafts: [GroceryItemDraft]) async throws -> [GroceryItem] {
        guard !drafts.isEmpty else { return [] }
        let userId = try await client.auth.session.user.id
        let payload = drafts.map { GroceryItemInsert(userId: userId, draft: $0) }
        return try await client
            .from("grocery_items")
            .insert(payload)
            .select()
            .execute()
            .value
    }

    func setChecked(id: UUID, isChecked: Bool) async throws {
        try await client
            .from("grocery_items")
            .update(["is_checked": isChecked])
            .eq("id", value: id.uuidString)
            .execute()
    }

    func setCategory(id: UUID, category: GroceryCategory) async throws {
        try await client
            .from("grocery_items")
            .update(["category": category.rawValue])
            .eq("id", value: id.uuidString)
            .execute()
    }

    func delete(id: UUID) async throws {
        try await client
            .from("grocery_items")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    func clearAll() async throws {
        let userId = try await client.auth.session.user.id
        try await client
            .from("grocery_items")
            .delete()
            .eq("user_id", value: userId.uuidString)
            .execute()
    }
}
