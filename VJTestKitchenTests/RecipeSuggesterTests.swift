import Foundation
import Testing
@testable import VJTestKitchen

struct RecipeSuggesterTests {
    /// UTC gregorian calendar so weekday/month are deterministic regardless of
    /// the test host's time zone — matches how the rest of the app computes days.
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utcCalendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: - Season mapping

    @Test func seasonMapsMonthsToMeteorologicalBuckets() {
        #expect(RecipeSuggester.season(forMonth: 12) == .winter)
        #expect(RecipeSuggester.season(forMonth: 1) == .winter)
        #expect(RecipeSuggester.season(forMonth: 2) == .winter)
        #expect(RecipeSuggester.season(forMonth: 4) == .spring)
        #expect(RecipeSuggester.season(forMonth: 7) == .summer)
        #expect(RecipeSuggester.season(forMonth: 10) == .fall)
    }

    // MARK: - Weekend detection

    @Test func weekendIsFridayThroughSunday() {
        // Calendar weekday: Sunday = 1 ... Saturday = 7.
        #expect(RecipeSuggester.isWeekend(weekday: 1))  // Sunday
        #expect(RecipeSuggester.isWeekend(weekday: 6))  // Friday
        #expect(RecipeSuggester.isWeekend(weekday: 7))  // Saturday
        #expect(!RecipeSuggester.isWeekend(weekday: 2)) // Monday
        #expect(!RecipeSuggester.isWeekend(weekday: 5)) // Thursday
    }

    // MARK: - Weeknight caps prep time

    @Test func weeknightCapsPrepTime() {
        // 2026-01-06 is a Tuesday (winter weeknight).
        let suggestion = RecipeSuggester.suggestion(for: date(2026, 1, 6), calendar: utcCalendar)
        #expect(suggestion.maxPrepTime == 30)
        #expect(suggestion.keyword == "soup")
        #expect(suggestion.title == "Quick Winter Warmers")
    }

    @Test func weekendRemovesPrepTimeCap() {
        // 2026-07-04 is a Saturday (summer weekend).
        let suggestion = RecipeSuggester.suggestion(for: date(2026, 7, 4), calendar: utcCalendar)
        #expect(suggestion.maxPrepTime == nil)
        #expect(suggestion.keyword == "grilled")
        #expect(suggestion.title == "Weekend Grilling")
    }

    @Test func summerWeeknightSuggestsLightSaladWithCap() {
        // 2026-07-07 is a Tuesday (summer weeknight).
        let suggestion = RecipeSuggester.suggestion(for: date(2026, 7, 7), calendar: utcCalendar)
        #expect(suggestion.maxPrepTime == 30)
        #expect(suggestion.keyword == "salad")
        #expect(suggestion.title == "Light Summer Suppers")
    }

    @Test func everySuggestionHasCopyAndSymbol() {
        // Sweep a full year so every (season, weekend) branch is exercised and
        // none returns empty copy or a blank symbol.
        for month in 1...12 {
            for day in [2, 3, 4, 5, 6, 7, 8] {  // spans a full week within the month
                let suggestion = RecipeSuggester.suggestion(for: date(2026, month, day), calendar: utcCalendar)
                #expect(!suggestion.title.isEmpty)
                #expect(!suggestion.subtitle.isEmpty)
                #expect(!suggestion.symbol.isEmpty)
            }
        }
    }

    // MARK: - Weather-driven suggestions

    private func forecast(category: WeatherCategory, highCelsius: Double) -> DailyForecast {
        DailyForecast(
            date: "2026-07-07",
            symbolName: "sun.max.fill",
            condition: "Test",
            category: category,
            highTemperature: Measurement(value: highCelsius, unit: .celsius),
            lowTemperature: Measurement(value: highCelsius - 8, unit: .celsius)
        )
    }

    @Test func nilForecastFallsBackToCalendarSuggestion() {
        // No forecast → identical to the purely calendar-derived suggestion.
        let day = date(2026, 7, 7) // summer Tuesday
        let withoutWeather = RecipeSuggester.suggestion(forecast: nil, date: day, calendar: utcCalendar)
        let calendarOnly = RecipeSuggester.suggestion(for: day, calendar: utcCalendar)
        #expect(withoutWeather == calendarOnly)
        #expect(withoutWeather.title == "Light Summer Suppers")
    }

    @Test func hotWeatherPushesNoCookRegardlessOfSeason() {
        // A hot day in *January* still suggests beating the heat — weather wins
        // over the season the calendar-only path would key off.
        let winterDay = date(2026, 1, 6) // Tuesday
        let suggestion = RecipeSuggester.suggestion(
            forecast: forecast(category: .clear, highCelsius: 33),
            date: winterDay, calendar: utcCalendar
        )
        #expect(suggestion.title == "Beat the Heat")
        #expect(suggestion.keyword == "salad")
        #expect(suggestion.maxPrepTime == 30)
    }

    @Test func coldWeatherPushesHeartyCooking() {
        // A cold day in *July* suggests warming up the kitchen.
        let summerWeeknight = date(2026, 7, 7) // Tuesday
        let suggestion = RecipeSuggester.suggestion(
            forecast: forecast(category: .clear, highCelsius: 2),
            date: summerWeeknight, calendar: utcCalendar
        )
        #expect(suggestion.title == "Warm Up the Kitchen")
        #expect(suggestion.keyword == "soup")
        #expect(suggestion.maxPrepTime == 30) // weeknight cap still applies
    }

    @Test func rainOverridesTemperatureIntoComfortFood() {
        // Warm *and* rainy → still comfort food (precipitation wins).
        let suggestion = RecipeSuggester.suggestion(
            forecast: forecast(category: .rain, highCelsius: 24),
            date: date(2026, 7, 7), calendar: utcCalendar // Tuesday
        )
        #expect(suggestion.title == "Rainy-Day Comfort")
        #expect(suggestion.keyword == "soup")
    }

    @Test func warmWeekendSuggestsGrilling() {
        let saturday = date(2026, 7, 4) // Saturday
        let suggestion = RecipeSuggester.suggestion(
            forecast: forecast(category: .clear, highCelsius: 25),
            date: saturday, calendar: utcCalendar
        )
        #expect(suggestion.title == "Fire Up the Grill")
        #expect(suggestion.keyword == "grilled")
        #expect(suggestion.maxPrepTime == nil) // weekend removes the cap
    }

    @Test func cookingWeatherBucketsTemperature() {
        #expect(RecipeSuggester.cookingWeather(category: .clear, highTemperatureCelsius: 35) == .hot)
        #expect(RecipeSuggester.cookingWeather(category: .clear, highTemperatureCelsius: 24) == .warm)
        #expect(RecipeSuggester.cookingWeather(category: .cloudy, highTemperatureCelsius: 15) == .mild)
        #expect(RecipeSuggester.cookingWeather(category: .fog, highTemperatureCelsius: 5) == .cold)
        // Precipitation ignores temperature.
        #expect(RecipeSuggester.cookingWeather(category: .rain, highTemperatureCelsius: 35) == .rainy)
        #expect(RecipeSuggester.cookingWeather(category: .snow, highTemperatureCelsius: 35) == .snowy)
        #expect(RecipeSuggester.cookingWeather(category: .thunderstorm, highTemperatureCelsius: 35) == .stormy)
    }

    @Test func everyWeatherSuggestionHasCopyKeywordAndSymbol() {
        let categories: [WeatherCategory] = [.clear, .cloudy, .fog, .rain, .snow, .thunderstorm]
        let temps: [Double] = [-5, 5, 15, 24, 35]
        for isWeekend in [false, true] {
            let day = isWeekend ? date(2026, 7, 4) : date(2026, 7, 7)
            for category in categories {
                for temp in temps {
                    let s = RecipeSuggester.suggestion(
                        forecast: forecast(category: category, highCelsius: temp),
                        date: day, calendar: utcCalendar
                    )
                    #expect(!s.title.isEmpty)
                    #expect(!s.subtitle.isEmpty)
                    #expect(!s.symbol.isEmpty)
                    #expect(!(s.keyword ?? "").isEmpty)
                    // Weeknights always cap prep time; weekends only relax it
                    // for the non-"hot" moods (a heat wave stays no-cook even on
                    // a weekend).
                    let isHot = (category == .clear || category == .cloudy || category == .fog) && temp >= 29
                    if !isWeekend {
                        #expect(s.maxPrepTime == 30)
                    } else if !isHot {
                        #expect(s.maxPrepTime == nil)
                    }
                }
            }
        }
    }
}
