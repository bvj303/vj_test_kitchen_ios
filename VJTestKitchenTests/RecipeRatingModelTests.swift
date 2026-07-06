import Foundation
import Testing
@testable import VJTestKitchen

struct RecipeRatingModelTests {
    @Test func decodesRecipeRatingFromPostgrestJSON() throws {
        let json = """
        {
          "recipe_id": 42,
          "user_id": "22222222-2222-2222-2222-222222222222",
          "rating": 5,
          "notes": "Add more pepper next time",
          "created_at": "2026-07-06T01:20:29.123456+00:00",
          "updated_at": "2026-07-06T01:25:00+00:00"
        }
        """.data(using: .utf8)!

        let rating = try SupabaseDecoding.decoder.decode(RecipeRating.self, from: json)

        #expect(rating.recipeId == 42)
        #expect(rating.userId == UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        #expect(rating.rating == 5)
        #expect(rating.notes == "Add more pepper next time")
    }

    @Test func decodesRecipeRatingWithNoRatingYet() throws {
        let json = """
        {
          "recipe_id": 42,
          "user_id": "22222222-2222-2222-2222-222222222222",
          "rating": null,
          "notes": null,
          "created_at": "2026-07-06T01:20:29+00:00",
          "updated_at": "2026-07-06T01:20:29+00:00"
        }
        """.data(using: .utf8)!

        let rating = try SupabaseDecoding.decoder.decode(RecipeRating.self, from: json)

        #expect(rating.rating == nil)
        #expect(rating.notes == nil)
    }
}
