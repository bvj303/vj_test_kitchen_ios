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
}
