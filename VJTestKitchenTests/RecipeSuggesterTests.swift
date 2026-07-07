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
}
