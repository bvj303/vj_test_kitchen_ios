import Foundation
import Testing
@testable import VJTestKitchen

struct RecipeModelTests {
    @Test func decodesRecipeFromPostgrestJSON() throws {
        let json = """
        {
          "id": 42,
          "user_id": "11111111-1111-1111-1111-111111111111",
          "title": "Carbonara",
          "description": "Roman pasta",
          "instructions": "Boil, whisk, toss.",
          "image_path": "recipes/carbonara.jpg",
          "prep_time": 20,
          "servings": 2,
          "created_at": "2026-07-06T01:20:29.123456+00:00"
        }
        """.data(using: .utf8)!

        let recipe = try SupabaseDecoding.decoder.decode(Recipe.self, from: json)

        #expect(recipe.id == 42)
        #expect(recipe.userId == UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        #expect(recipe.title == "Carbonara")
        #expect(recipe.prepTime == 20)
        #expect(recipe.servings == 2)
    }

    @Test func decodesRecipeWithNullUserAndOptionalFields() throws {
        let json = """
        {
          "id": 7,
          "user_id": null,
          "title": "Orphaned Recipe",
          "description": null,
          "instructions": null,
          "image_path": null,
          "prep_time": null,
          "servings": null,
          "created_at": "2026-07-06T01:20:29+00:00"
        }
        """.data(using: .utf8)!

        let recipe = try SupabaseDecoding.decoder.decode(Recipe.self, from: json)

        #expect(recipe.userId == nil)
        #expect(recipe.description == nil)
    }

    @Test func encodesNewRecipeInsertWithoutIdOrCreatedAt() throws {
        let insert = RecipeInsert(
            userId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "New Recipe",
            description: nil,
            instructions: nil,
            imagePath: nil,
            prepTime: 15,
            servings: 4
        )

        let data = try SupabaseDecoding.encoder.encode(insert)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(object?["title"] as? String == "New Recipe")
        #expect(object?["prep_time"] as? Int == 15)
        #expect(object?["id"] == nil)
        #expect(object?["created_at"] == nil)
    }

    @Test func recipeUpdateEncodesClearedOptionalFieldsAsExplicitNull() throws {
        // A RecipeDraft whose optional fields were cleared in the edit form.
        let draft = RecipeDraft(
            title: "Trimmed Down",
            description: nil,
            instructions: nil,
            imagePath: nil,
            prepTime: nil,
            servings: nil
        )

        let data = try SupabaseDecoding.encoder.encode(RecipeUpdate(draft: draft))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(object?["title"] as? String == "Trimmed Down")
        // Cleared fields must be present as explicit JSON null, so the PATCH
        // actually clears them (synthesized Encodable would omit them instead,
        // silently keeping the old DB value).
        #expect(object?.keys.contains("description") == true)
        #expect(object?["description"] is NSNull)
        #expect(object?["instructions"] is NSNull)
        #expect(object?["prep_time"] is NSNull)
        #expect(object?["servings"] is NSNull)
        // image_path is deliberately omitted — the recipe form doesn't manage
        // cover images, so an edit must never overwrite the existing value.
        #expect(object?.keys.contains("image_path") == false)
    }

    @Test func recipeUpdateEncodesProvidedValues() throws {
        let draft = RecipeDraft(
            title: "Full",
            description: "desc",
            instructions: "steps",
            imagePath: nil,
            prepTime: 30,
            servings: 6
        )

        let data = try SupabaseDecoding.encoder.encode(RecipeUpdate(draft: draft))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(object?["description"] as? String == "desc")
        #expect(object?["prep_time"] as? Int == 30)
        #expect(object?["servings"] as? Int == 6)
    }
}
