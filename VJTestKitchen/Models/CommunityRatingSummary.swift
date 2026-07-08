import Foundation

/// Aggregate of a recipe's household ratings — the average and how many people
/// rated it. Pure and unit-tested; computed client-side from the fetched
/// `RecipeReview` list (a household is small, so there's no need for a
/// server-side aggregate).
struct CommunityRatingSummary: Equatable, Sendable {
    let average: Double
    /// Number of members who left a star rating (notes-only rows don't count).
    let count: Int

    static let empty = CommunityRatingSummary(average: 0, count: 0)

    var hasRatings: Bool { count > 0 }

    /// Average rounded to the nearest whole star, for a filled-stars display.
    var roundedStars: Int { Int(average.rounded()) }

    /// One-decimal average for a label, e.g. "4.3".
    var averageText: String { String(format: "%.1f", average) }

    static func from(_ reviews: [RecipeReview]) -> CommunityRatingSummary {
        let stars = reviews.compactMap(\.rating)
        guard !stars.isEmpty else { return .empty }
        return CommunityRatingSummary(
            average: Double(stars.reduce(0, +)) / Double(stars.count),
            count: stars.count
        )
    }
}
