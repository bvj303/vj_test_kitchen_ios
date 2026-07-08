import Foundation
import Testing
@testable import VJTestKitchen

struct CommunityRatingSummaryTests {
    private func review(_ rating: Int?, notes: String? = nil) -> RecipeReview {
        RecipeReview(userId: UUID(), rating: rating, notes: notes, updatedAt: Date(), profile: nil)
    }

    @Test func emptyWhenNoRatings() {
        #expect(CommunityRatingSummary.from([]) == .empty)
        // A notes-only review (no star) doesn't count toward the average.
        let summary = CommunityRatingSummary.from([review(nil, notes: "just a comment")])
        #expect(summary.hasRatings == false)
        #expect(summary.count == 0)
    }

    @Test func averagesOnlyStarRatings() {
        let summary = CommunityRatingSummary.from([
            review(5), review(4), review(nil, notes: "no star"), review(3),
        ])
        #expect(summary.count == 3)
        #expect(summary.average == 4.0)
        #expect(summary.roundedStars == 4)
        #expect(summary.averageText == "4.0")
    }

    @Test func roundsHalfUpForStars() {
        let summary = CommunityRatingSummary.from([review(5), review(4)]) // 4.5
        #expect(summary.averageText == "4.5")
        #expect(summary.roundedStars == 5)
    }
}

struct RecipeReviewDecodingTests {
    @Test func decodesEmbeddedProfileFromPostgrestShape() throws {
        // PostgREST names the embedded relationship after the target table
        // ("profiles"); the shared decoder converts snake_case keys.
        let json = """
        {
          "user_id": "00000000-0000-0000-0000-000000000009",
          "rating": 4,
          "notes": "Loved it",
          "updated_at": "2026-07-08T01:00:00Z",
          "profiles": { "display_name": "Ada Lovelace", "username": "ada", "avatar_url": null }
        }
        """.data(using: .utf8)!

        let review = try SupabaseDecoding.decoder.decode(RecipeReview.self, from: json)

        #expect(review.rating == 4)
        #expect(review.notes == "Loved it")
        #expect(review.profile?.displayName == "Ada Lovelace")
        #expect(review.reviewerName == "Ada Lovelace")
        #expect(review.hasComment == true)
    }

    @Test func reviewerNameFallsBackThroughUsernameThenGeneric() {
        let usernameOnly = RecipeReview(userId: UUID(), rating: 3, notes: nil, updatedAt: Date(),
                                        profile: .init(displayName: "", username: "bo", avatarUrl: nil))
        #expect(usernameOnly.reviewerName == "@bo")

        let nothing = RecipeReview(userId: UUID(), rating: 3, notes: nil, updatedAt: Date(), profile: nil)
        #expect(nothing.reviewerName == "Someone")
    }
}
