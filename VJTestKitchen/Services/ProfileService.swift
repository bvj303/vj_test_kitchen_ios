import Foundation
import Supabase

protocol ProfileServicing: Sendable {
    /// Calls the `is_username_available` RPC (see the profiles_first_last_username
    /// migration) — usable pre-signup since it's granted to `anon`, unlike
    /// every other table/function in this app.
    func isUsernameAvailable(_ username: String) async throws -> Bool
}

struct ProfileService: ProfileServicing {
    private struct CheckUsernameParams: Encodable {
        let checkUsername: String
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
}
