import Foundation
import Testing
@testable import VJTestKitchen

struct HolidayProviderTests {
    // MARK: - Fixed-date holidays

    @Test func recognizesFixedDateHolidays() {
        #expect(HolidayProvider.holiday(for: "2026-01-01")?.name == "New Year's Day")
        #expect(HolidayProvider.holiday(for: "2026-02-14")?.name == "Valentine's Day")
        #expect(HolidayProvider.holiday(for: "2026-03-17")?.name == "St. Patrick's Day")
        #expect(HolidayProvider.holiday(for: "2026-06-19")?.name == "Juneteenth")
        #expect(HolidayProvider.holiday(for: "2026-07-04")?.name == "Independence Day")
        #expect(HolidayProvider.holiday(for: "2026-10-31")?.name == "Halloween")
        #expect(HolidayProvider.holiday(for: "2026-11-11")?.name == "Veterans Day")
        #expect(HolidayProvider.holiday(for: "2026-12-24")?.name == "Christmas Eve")
        #expect(HolidayProvider.holiday(for: "2026-12-25")?.name == "Christmas Day")
        #expect(HolidayProvider.holiday(for: "2026-12-31")?.name == "New Year's Eve")
    }

    @Test func returnsNilForOrdinaryDay() {
        #expect(HolidayProvider.holiday(for: "2026-07-07") == nil)
        #expect(HolidayProvider.holiday(for: "2026-03-05") == nil)
    }

    @Test func holidayCarriesAnSFSymbol() {
        let holiday = HolidayProvider.holiday(for: "2026-12-25")
        #expect(holiday?.symbol.isEmpty == false)
    }

    // MARK: - Floating (nth-weekday) holidays

    @Test func recognizesNthWeekdayHolidays2026() {
        // MLK Day: 3rd Monday of January 2026 = Jan 19
        #expect(HolidayProvider.holiday(for: "2026-01-19")?.name == "Martin Luther King Jr. Day")
        // Presidents' Day: 3rd Monday of February 2026 = Feb 16
        #expect(HolidayProvider.holiday(for: "2026-02-16")?.name == "Presidents' Day")
        // Mother's Day: 2nd Sunday of May 2026 = May 10
        #expect(HolidayProvider.holiday(for: "2026-05-10")?.name == "Mother's Day")
        // Memorial Day: last Monday of May 2026 = May 25
        #expect(HolidayProvider.holiday(for: "2026-05-25")?.name == "Memorial Day")
        // Father's Day: 3rd Sunday of June 2026 = Jun 21
        #expect(HolidayProvider.holiday(for: "2026-06-21")?.name == "Father's Day")
        // Labor Day: 1st Monday of September 2026 = Sep 7
        #expect(HolidayProvider.holiday(for: "2026-09-07")?.name == "Labor Day")
        // Thanksgiving: 4th Thursday of November 2026 = Nov 26
        #expect(HolidayProvider.holiday(for: "2026-11-26")?.name == "Thanksgiving")
    }

    @Test func nthWeekdayHolidaysShiftWithTheYear() {
        // Thanksgiving 2025 = Nov 27 (4th Thursday), 2027 = Nov 25
        #expect(HolidayProvider.holiday(for: "2025-11-27")?.name == "Thanksgiving")
        #expect(HolidayProvider.holiday(for: "2027-11-25")?.name == "Thanksgiving")
        #expect(HolidayProvider.holiday(for: "2026-11-27") == nil)
    }

    // MARK: - Easter (computus)

    @Test func recognizesEaster() {
        // Known Gregorian Easter Sundays
        #expect(HolidayProvider.holiday(for: "2026-04-05")?.name == "Easter")
        #expect(HolidayProvider.holiday(for: "2027-03-28")?.name == "Easter")
        #expect(HolidayProvider.holiday(for: "2025-04-20")?.name == "Easter")
    }

    // MARK: - Date overload

    @Test func dateOverloadMatchesStringOverloadInUTC() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let july4 = calendar.date(from: DateComponents(year: 2026, month: 7, day: 4))!
        #expect(HolidayProvider.holiday(for: july4)?.name == "Independence Day")
    }
}
