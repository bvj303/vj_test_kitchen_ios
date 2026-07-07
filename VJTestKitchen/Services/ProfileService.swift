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
    /// Uploads `imageData` as the signed-in user's avatar (JPEG) to the public
    /// `avatars` bucket at `<uid>/avatar.jpg` (upsert), records the resulting
    /// public URL on their profile row, and returns that URL. The public bucket
    /// plus the world-readable profiles row is what makes an avatar visible to
    /// others.
    func uploadAvatar(_ imageData: Data) async throws -> String
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

    private struct AvatarUpdate: Encodable {
        let avatarUrl: String
    }

    private static let avatarBucket = "avatars"

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

    /// Storage object path for a user's avatar: `<uid>/avatar.jpg`, with the
    /// uid **lowercased**. This matters: `UUID.uuidString` is uppercase, but the
    /// bucket's owner-folder RLS check compares against `auth.uid()::text`, which
    /// Postgres renders lowercase — an uppercase folder fails the policy with
    /// "new row violates row-level security policy". Keep this the single source
    /// of the path so read and write always agree.
    static func avatarObjectPath(userId: UUID) -> String {
        "\(userId.uuidString.lowercased())/avatar.jpg"
    }

    func uploadAvatar(_ imageData: Data) async throws -> String {
        let userId = try await client.auth.session.user.id
        let path = Self.avatarObjectPath(userId: userId)

        try await client.storage
            .from(Self.avatarBucket)
            .upload(
                path,
                data: imageData,
                options: FileOptions(contentType: "image/jpeg", upsert: true)
            )

        // The object path is stable across re-uploads (upsert overwrites the
        // same "avatar.jpg"), so append a cache-busting query item — otherwise
        // AsyncImage / the CDN would keep serving the previous image after a
        // change. The row stores the busted URL so every reader gets the fresh one.
        let publicURL = try client.storage.from(Self.avatarBucket).getPublicURL(path: path)
        let bustedURL = "\(publicURL.absoluteString)?v=\(Int(Date().timeIntervalSince1970))"

        try await client
            .from("profiles")
            .update(AvatarUpdate(avatarUrl: bustedURL))
            .eq("id", value: userId.uuidString)
            .execute()

        return bustedURL
    }
}
