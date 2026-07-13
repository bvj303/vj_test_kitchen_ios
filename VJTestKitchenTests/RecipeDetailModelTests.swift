import Foundation
import Testing
@testable import VJTestKitchen

struct RecipeDetailModelTests {
    @Test func decodesAtkRatingFromPostgrestJSON() throws {
        let json = """
        {
          "id": 42,
          "user_id": null,
          "title": "Carbonara",
          "description": "Roman pasta",
          "instructions": "Boil, whisk, toss.",
          "image_path": null,
          "prep_time": 20,
          "servings": 2,
          "created_at": "2026-07-06T01:20:29.123456+00:00",
          "atk_rating": 4.28,
          "atk_rating_count": 23,
          "ingredients": [],
          "recipe_tags": []
        }
        """.data(using: .utf8)!

        let detail = try SupabaseDecoding.decoder.decode(RecipeDetail.self, from: json)

        #expect(detail.atkRating == 4.28)
        #expect(detail.atkRatingCount == 23)
    }

    @Test func decodesMissingAtkRatingAsNil() throws {
        let json = """
        {
          "id": 7,
          "user_id": null,
          "title": "Untested Recipe",
          "description": null,
          "instructions": null,
          "image_path": null,
          "prep_time": null,
          "servings": null,
          "created_at": "2026-07-06T01:20:29+00:00",
          "atk_rating": null,
          "atk_rating_count": null,
          "ingredients": [],
          "recipe_tags": []
        }
        """.data(using: .utf8)!

        let detail = try SupabaseDecoding.decoder.decode(RecipeDetail.self, from: json)

        #expect(detail.atkRating == nil)
        #expect(detail.atkRatingCount == nil)
    }
}
