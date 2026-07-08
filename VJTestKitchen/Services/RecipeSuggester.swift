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

    /// The suggestion for today, given the day's actual weather. When a
    /// `forecast` is available (the user has set a home location and the fetch
    /// succeeded), it drives the copy — a cold or rainy day pushes hearty,
    /// cozy cooking; a hot day pushes no-cook and chilled dishes — so the Home
    /// header changes with real conditions rather than only by season. When
    /// there's no forecast, it falls back to the purely calendar-derived
    /// `suggestion(for:calendar:)`. The weeknight/weekend prep-time cap still
    /// applies either way.
    static func suggestion(forecast: DailyForecast?, date: Date, calendar: Calendar = .current) -> RecipeSuggestion {
        guard let forecast else {
            return suggestion(for: date, calendar: calendar)
        }
        let weekday = calendar.dateComponents([.weekday], from: date).weekday ?? 1
        let weather = cookingWeather(
            category: forecast.category,
            highTemperatureCelsius: forecast.highTemperature.converted(to: .celsius).value
        )
        return suggestion(weather: weather, isWeekend: isWeekend(weekday: weekday))
    }

    /// How the day's weather reads for choosing what to cook. Precipitation
    /// (rain/snow/storm) wins outright — a wet or snowy day calls for comfort
    /// food no matter the thermometer — otherwise temperature buckets it. Pure
    /// so it's exhaustively unit-testable without a live forecast.
    enum CookingWeather: Sendable, Equatable {
        case hot, warm, mild, cold, rainy, snowy, stormy
    }

    /// Celsius thresholds for the non-precipitating temperature buckets. ~29°C
    /// (≈84°F) reads as "hot", ~22°C (≈72°F) as pleasantly "warm", ~10°C (≈50°F)
    /// as the floor for "mild"; below that is "cold".
    static func cookingWeather(category: WeatherCategory, highTemperatureCelsius: Double) -> CookingWeather {
        switch category {
        case .snow: return .snowy
        case .thunderstorm: return .stormy
        case .rain: return .rainy
        case .clear, .cloudy, .fog:
            if highTemperatureCelsius >= 29 { return .hot }
            if highTemperatureCelsius >= 22 { return .warm }
            if highTemperatureCelsius >= 10 { return .mild }
            return .cold
        }
    }

    /// The weather-driven lookup table — pure function of (weather, weekend),
    /// same explicit-switch style as the seasonal table so each combination's
    /// copy is easy to read and adjust. Keywords stay common ATK title words so
    /// the trigram catalog query reliably returns matches.
    private static func suggestion(weather: CookingWeather, isWeekend: Bool) -> RecipeSuggestion {
        let cap = isWeekend ? nil : weeknightMaxPrepTime
        switch weather {
        case .hot:
            // No-cook / chilled regardless of the day — nobody wants the oven on.
            return RecipeSuggestion(
                title: "Beat the Heat",
                subtitle: "No-cook, chilled dishes for a hot day",
                symbol: "thermometer.sun.fill",
                keyword: "salad",
                maxPrepTime: weeknightMaxPrepTime
            )
        case .warm where isWeekend:
            return RecipeSuggestion(
                title: "Fire Up the Grill",
                subtitle: "A warm weekend made for grilling out",
                symbol: "flame.fill",
                keyword: "grilled",
                maxPrepTime: nil
            )
        case .warm:
            return RecipeSuggestion(
                title: "Light & Fresh Tonight",
                subtitle: "Easy, breezy dinners for a warm evening",
                symbol: "sun.max.fill",
                keyword: "salad",
                maxPrepTime: cap
            )
        case .mild:
            return RecipeSuggestion(
                title: "Just-Right Cooking Weather",
                subtitle: isWeekend ? "A mild day for something a little special" : "Comfortable weather for an easy weeknight dinner",
                symbol: "cloud.sun.fill",
                keyword: isWeekend ? "roast" : "chicken",
                maxPrepTime: cap
            )
        case .cold:
            return RecipeSuggestion(
                title: "Warm Up the Kitchen",
                subtitle: "Hearty, hot cooking for a cold day",
                symbol: "thermometer.snowflake",
                keyword: isWeekend ? "roast" : "soup",
                maxPrepTime: cap
            )
        case .rainy:
            return RecipeSuggestion(
                title: "Rainy-Day Comfort",
                subtitle: "Cozy up a wet day with something warm",
                symbol: "cloud.rain.fill",
                keyword: isWeekend ? "roast" : "soup",
                maxPrepTime: cap
            )
        case .snowy:
            return RecipeSuggestion(
                title: "Snow-Day Warmers",
                subtitle: "Slow, hearty cooking for a snowy day",
                symbol: "cloud.snow.fill",
                keyword: isWeekend ? "roast" : "soup",
                maxPrepTime: cap
            )
        case .stormy:
            return RecipeSuggestion(
                title: "Stormy-Day Comfort",
                subtitle: "Ride out the storm with a slow, cozy meal",
                symbol: "cloud.bolt.rain.fill",
                keyword: isWeekend ? "roast" : "soup",
                maxPrepTime: cap
            )
        }
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
