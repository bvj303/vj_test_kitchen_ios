import Foundation
import Testing
@testable import VJTestKitchen

struct PrepTimeFormatTests {
    @Test func formatsSubHourAsMinutesOnly() {
        #expect(PrepTimeFormat.string(minutes: 1) == "1 min")
        #expect(PrepTimeFormat.string(minutes: 30) == "30 min")
        #expect(PrepTimeFormat.string(minutes: 45) == "45 min")
        #expect(PrepTimeFormat.string(minutes: 59) == "59 min")
    }

    @Test func formatsWholeHoursWithoutMinutes() {
        #expect(PrepTimeFormat.string(minutes: 60) == "1 hr")
        #expect(PrepTimeFormat.string(minutes: 120) == "2 hr")
        #expect(PrepTimeFormat.string(minutes: 180) == "3 hr")
    }

    @Test func formatsHoursAndMinutes() {
        #expect(PrepTimeFormat.string(minutes: 90) == "1 hr 30 min")
        #expect(PrepTimeFormat.string(minutes: 105) == "1 hr 45 min")
        #expect(PrepTimeFormat.string(minutes: 150) == "2 hr 30 min")
        #expect(PrepTimeFormat.string(minutes: 61) == "1 hr 1 min")
    }

    @Test func formatsZeroAndNegativeAsZeroMinutes() {
        #expect(PrepTimeFormat.string(minutes: 0) == "0 min")
        #expect(PrepTimeFormat.string(minutes: -5) == "0 min")
    }

    @Test func labelReturnsNilForUnknownPrepTime() {
        // Unknown prep time (nil, 0, or negative) → no label at all, rather than
        // a meaningless "0 min" for the ~2,900 ATK rows with no recorded time.
        #expect(PrepTimeFormat.label(minutes: nil) == nil)
        #expect(PrepTimeFormat.label(minutes: 0) == nil)
        #expect(PrepTimeFormat.label(minutes: -5) == nil)
    }

    @Test func labelFormatsKnownPrepTimeLikeString() {
        #expect(PrepTimeFormat.label(minutes: 30) == "30 min")
        #expect(PrepTimeFormat.label(minutes: 90) == "1 hr 30 min")
    }

    // MARK: - parseMinutes (form input)

    @Test func parsesBareMinuteCounts() {
        #expect(PrepTimeFormat.parseMinutes("45") == 45)
        #expect(PrepTimeFormat.parseMinutes(" 45 ") == 45)
        #expect(PrepTimeFormat.parseMinutes("0") == 0)
    }

    @Test func parsesMinuteKeywordForms() {
        #expect(PrepTimeFormat.parseMinutes("45 min") == 45)
        #expect(PrepTimeFormat.parseMinutes("45 mins") == 45)
        #expect(PrepTimeFormat.parseMinutes("45 minutes") == 45)
        #expect(PrepTimeFormat.parseMinutes("45m") == 45)
    }

    @Test func parsesHourKeywordForms() {
        #expect(PrepTimeFormat.parseMinutes("1 hour") == 60)
        #expect(PrepTimeFormat.parseMinutes("2 hrs") == 120)
        #expect(PrepTimeFormat.parseMinutes("1.5 hours") == 90)
        #expect(PrepTimeFormat.parseMinutes("1h") == 60)
    }

    @Test func parsesCombinedHourAndMinuteForms() {
        #expect(PrepTimeFormat.parseMinutes("1 hr 30 min") == 90)
        #expect(PrepTimeFormat.parseMinutes("1h30m") == 90)
        #expect(PrepTimeFormat.parseMinutes("2 hours 15 minutes") == 135)
    }

    @Test func refusesUnreadableInputInsteadOfGuessing() {
        #expect(PrepTimeFormat.parseMinutes("") == nil)
        #expect(PrepTimeFormat.parseMinutes("a while") == nil)
        #expect(PrepTimeFormat.parseMinutes("45 foo") == nil)
        #expect(PrepTimeFormat.parseMinutes("-10") == nil)
    }
}
