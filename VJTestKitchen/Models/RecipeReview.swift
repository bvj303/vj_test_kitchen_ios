import Foundation

/// One household member's rating + notes on a recipe, joined with their public
/// profile for display. Decodes a PostgREST embed:
/// `recipe_ratings.select("user_id, rating, notes, updated_at, profiles(display_name, username, avatar_url)")`.
///
/// Unlike `RecipeRating` (which is the caller's own editable row), this is a
/// read-only *community* view — every member's rating is now household-readable
/// (see the favorites_and_community_ratings migration).
struct RecipeReview: Codable, Sendable, Identifiable, Hashable {
    let userId: UUID
    var rating: Int?
    var notes: String?
    let updatedAt: Date
    /// The reviewer's public profile — nil only if the join found no row (a
    /// rating whose profile was somehow removed).
    var profile: ReviewerProfile?

    /// Stable per-user identity (a user has at most one rating per recipe).
    var id: UUID { userId }

    struct ReviewerProfile: Codable, Sendable, Hashable {
        var displayName: String?
        var username: String?
        var avatarUrl: String?
    }

    enum CodingKeys: String, CodingKey {
        case userId, rating, notes, updatedAt
        // PostgREST names the embedded relationship after the target table.
        case profile = "profiles"
    }

    /// Display name for the reviewer, falling back through username → "Someone".
    var reviewerName: String {
        if let name = profile?.displayName, !name.isEmpty { return name }
        if let username = profile?.username, !username.isEmpty { return "@\(username)" }
        return "Someone"
    }

    /// True when there's a written comment worth showing.
    var hasComment: Bool {
        (notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
    }
}
