import Foundation
import Supabase

protocol ProfileServicing: Sendable {
    /// Calls the `is_username_available` RPC (see the profiles_first_last_username
    /// migration) — usable pre-signup since it's granted to `anon`, unlike
    /// every other table/function in this app.
    func isUsernameAvailable(_ username: String) async throws -> Bool
    /// The signed-in user's own profile — resolves "who am I" internally,
    /// same reasoning as RecipeRatingService.
    func fetchMine() async throws -> Profile
    /// Updates the signed-in user's own first/last name and username, and
    /// re-derives display_name to match (same "First Last" logic as
    /// handle_new_user() at sign-up, so it can't go stale after an edit).
    func updateMine(firstName: String, lastName: String, username: String) async throws
}

struct ProfileService: ProfileServicing {
    private struct CheckUsernameParams: Encodable {
        let checkUsername: String
    }

    private struct ProfileUpdate: Encodable {
        let firstName: String
        let lastName: String
        let username: String
        let displayName: String
    }

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseManager.client) {
        self.client = client
    }

    func isUsernameAvailable(_ username: String) async throws -> Bool {
        try await client
            .rpc("is_username_available", params: CheckUsernameParams(checkUsername: username))
            .execute()
            .value
    }

    func fetchMine() async throws -> Profile {
        let userId = try await client.auth.session.user.id
        return try await client
            .from("profiles")
            .select()
            .eq("id", value: userId.uuidString)
            .single()
            .execute()
            .value
    }

    func updateMine(firstName: String, lastName: String, username: String) async throws {
        let userId = try await client.auth.session.user.id
        try await client
            .from("profiles")
            .update(ProfileUpdate(firstName: firstName, lastName: lastName, username: username, displayName: "\(firstName) \(lastName)"))
            .eq("id", value: userId.uuidString)
            .execute()
    }
}
