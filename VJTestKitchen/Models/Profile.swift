import Foundation

struct Profile: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var displayName: String?
    var firstName: String?
    var lastName: String?
    var username: String?
    /// Public URL of the user's profile picture in the `avatars` Storage
    /// bucket, or nil if they haven't set one. Publicly readable (see the
    /// profile_avatars migration) so other users can display it.
    var avatarUrl: String?
    let createdAt: Date

    // Explicit init (rather than the synthesized memberwise one) so `avatarUrl`
    // can default to nil — existing call sites that don't set an avatar keep
    // compiling. Codable synthesis is unaffected; a missing `avatar_url` key
    // decodes to nil like any optional.
    init(
        id: UUID,
        displayName: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        username: String? = nil,
        avatarUrl: String? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.displayName = displayName
        self.firstName = firstName
        self.lastName = lastName
        self.username = username
        self.avatarUrl = avatarUrl
        self.createdAt = createdAt
    }
}
