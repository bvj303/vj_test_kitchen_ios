import Foundation

struct Recipe: Codable, Identifiable, Sendable, Hashable {
    let id: Int64
    var userId: UUID?
    var title: String
    var description: String?
    var instructions: String?
    var imagePath: String?
    var imageUrl: String? = nil
    var prepTime: Int?
    var servings: Int?
    let createdAt: Date
}

/// Payload for creating a recipe — no `id`/`createdAt`, both server-assigned.
struct RecipeInsert: Codable, Sendable {
    var userId: UUID
    var title: String
    var description: String?
    var instructions: String?
    var imagePath: String?
    var prepTime: Int?
    var servings: Int?
}

/// User-editable recipe fields — no `id`/`userId`/`createdAt`. `RecipeService`
/// resolves the current user internally when creating (see
/// `RecipeRatingService` for the same "auth-awareness stays in the Service
/// layer" pattern), and ownership never changes on update.
struct RecipeDraft: Codable, Sendable {
    var title: String
    var description: String?
    var instructions: String?
    var imagePath: String?
    var prepTime: Int?
    var servings: Int?
}

/// PATCH payload for updating a recipe's editable fields. Unlike `RecipeDraft`,
/// whose *synthesized* `Encodable` uses `encodeIfPresent` and therefore omits
/// nil optionals, this encodes description/instructions/prepTime/servings as
/// explicit JSON `null` — so clearing a field in the edit form actually clears
/// it in the database instead of silently leaving the old value. `imagePath`
/// is intentionally excluded: the recipe form doesn't manage cover images
/// (Stage 6), so an edit must never overwrite whatever `image_path` the row
/// already has.
struct RecipeUpdate: Encodable, Sendable {
    var title: String
    var description: String?
    var instructions: String?
    var prepTime: Int?
    var servings: Int?

    init(draft: RecipeDraft) {
        title = draft.title
        description = draft.description
        instructions = draft.instructions
        prepTime = draft.prepTime
        servings = draft.servings
    }

    enum CodingKeys: String, CodingKey {
        case title, description, instructions, prepTime, servings
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        // `encode` (not `encodeIfPresent`) so nil becomes explicit JSON null.
        try container.encode(description, forKey: .description)
        try container.encode(instructions, forKey: .instructions)
        try container.encode(prepTime, forKey: .prepTime)
        try container.encode(servings, forKey: .servings)
    }
}
