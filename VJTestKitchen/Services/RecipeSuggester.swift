import Foundation

/// A context-aware "what should I cook?" suggestion, derived *purely* from the
/// calendar — no network, no location, no AI. It maps two cheap signals to a
/// friendly headline plus a catalog query so the Home tab can feature a
/// relevant handful of recipes:
///
/// - **Weeknight vs. weekend** — Mon–Thu favor quick recipes (a `maxPrepTime`
///   cap); Fri–Sun relax the cap for slower, showpiece cooking ("the weekend
///   coming up").
/// - **Season** (from the month) — biases a title keyword: soups in winter,
///   grilling in summer, and so on.
///
/// Pure and unit-tested, same shape as `HolidayProvider`/`MealTypeStyle`. The
/// `keyword`/`maxPrepTime` feed straight into `RecipeService.fetchPage`, and the
/// view falls back to an unfiltered page if a keyword happens to match nothing.
struct RecipeSuggestion: Equatable, Sendable {
    /// Short headline shown above the suggested recipes, e.g. "Quick Winter Warmers".
    let title: String
    /// One-line rationale, e.g. "Fast, cozy dinners for a chilly weeknight".
    let subtitle: String
    /// SF Symbol summarizing the vibe.
    let symbol: String
    /// Title keyword biasing the catalog query (trigram `ilike`), or nil for none.
    let keyword: String?
    /// Upper bound on `prep_time` (minutes) — set on weeknights, nil on weekends.
    let maxPrepTime: Int?
}

enum RecipeSuggester {
    /// Coarse season buckets, meteorological (Dec–Feb winter, etc.) rather than
    /// astronomical, since it's only used to pick a cooking vibe.
    enum Season: Sendable {
        case winter, spring, summer, fall
    }

    /// The season a given month (1–12) falls in.
    static func season(forMonth month: Int) -> Season {
        switch month {
        case 12, 1, 2: return .winter
        case 3, 4, 5: return .spring
        case 6, 7, 8: return .summer
        default: return .fall
        }
    }

    /// Whether the given weekday reads as "the weekend" for cooking purposes —
    /// Friday through Sunday, so a Friday-evening plan leans relaxed like the
    /// weekend it kicks off. Weekday values follow `Calendar`: Sunday = 1 …
    /// Saturday = 7.
    static func isWeekend(weekday: Int) -> Bool {
        weekday == 1 || weekday == 6 || weekday == 7
    }

    /// The suggestion for the given date. `calendar` defaults to `.current` so
    /// weekday/season reflect the user's local sense of "today"; tests inject a
    /// fixed calendar for determinism.
    static func suggestion(for date: Date, calendar: Calendar = .current) -> RecipeSuggestion {
        let components = calendar.dateComponents([.month, .weekday], from: date)
        let month = components.month ?? 1
        let weekday = components.weekday ?? 1
        return suggestion(season: season(forMonth: month), isWeekend: isWeekend(weekday: weekday))
    }

    /// Weeknight dinners cap prep time; weekend cooking removes the cap.
    private static let weeknightMaxPrepTime = 30

    /// The lookup table — pure function of (season, weekend). Kept as an explicit
    /// switch so each combination's copy is easy to read and adjust. Keywords are
    /// deliberately common ATK title words (soup, roast, grilled, …) so the
    /// catalog query reliably returns matches.
    private static func suggestion(season: Season, isWeekend: Bool) -> RecipeSuggestion {
        switch (season, isWeekend) {
        case (.winter, false):
            return RecipeSuggestion(
                title: "Quick Winter Warmers",
                subtitle: "Fast, cozy dinners for a chilly weeknight",
                symbol: "snowflake",
                keyword: "soup",
                maxPrepTime: weeknightMaxPrepTime
            )
        case (.winter, true):
            return RecipeSuggestion(
                title: "Weekend Comfort Cooking",
                subtitle: "Slow-cooked, hearty dishes for the weekend",
                symbol: "flame.fill",
                keyword: "roast",
                maxPrepTime: nil
            )
        case (.spring, false):
            return RecipeSuggestion(
                title: "Fresh Weeknight Dinners",
                subtitle: "Bright, quick meals for a busy spring evening",
                symbol: "leaf",
                keyword: "pasta",
                maxPrepTime: weeknightMaxPrepTime
            )
        case (.spring, true):
            return RecipeSuggestion(
                title: "Spring Weekend Cooking",
                subtitle: "Something a little special for a relaxed weekend",
                symbol: "leaf.fill",
                keyword: "roast",
                maxPrepTime: nil
            )
        case (.summer, false):
            return RecipeSuggestion(
                title: "Light Summer Suppers",
                subtitle: "No-fuss meals for a warm weeknight",
                symbol: "sun.max.fill",
                keyword: "salad",
                maxPrepTime: weeknightMaxPrepTime
            )
        case (.summer, true):
            return RecipeSuggestion(
                title: "Weekend Grilling",
                subtitle: "Fire up the grill this weekend",
                symbol: "flame.fill",
                keyword: "grilled",
                maxPrepTime: nil
            )
        case (.fall, false):
            return RecipeSuggestion(
                title: "Cozy Fall Weeknights",
                subtitle: "Warm, quick dinners for a crisp evening",
                symbol: "leaf.fill",
                keyword: "soup",
                maxPrepTime: weeknightMaxPrepTime
            )
        case (.fall, true):
            return RecipeSuggestion(
                title: "Fall Weekend Cooking",
                subtitle: "Hearty dishes worth a slow weekend",
                symbol: "flame.fill",
                keyword: "roast",
                maxPrepTime: nil
            )
        }
    }
}
