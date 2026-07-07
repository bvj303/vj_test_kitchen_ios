import Foundation

/// Computes US holidays for a given day so the meal calendar can flag them
/// (Thanksgiving, Christmas, the Fourth — all meal-relevant) without any
/// network dependency. Pure and unit-tested; covers fixed-date holidays,
/// nth-weekday floating holidays, and Easter (computus).
///
/// All date math uses a UTC gregorian calendar to match how the calendar's
/// "yyyy-MM-dd" strings are computed elsewhere (see `MealPlan.dateFormatter`).
enum HolidayProvider {
    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// The holiday on the given "yyyy-MM-dd" date, if any.
    static func holiday(for dateString: String) -> Holiday? {
        guard let date = MealPlan.dateFormatter.date(from: dateString) else { return nil }
        return holiday(for: date)
    }

    /// The holiday on the given date (interpreted in UTC), if any.
    static func holiday(for date: Date) -> Holiday? {
        let calendar = utcCalendar
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return nil
        }
        return holidays(in: year, calendar: calendar)[MonthDay(month: month, day: day)]
    }

    // MARK: - Per-year table

    private struct MonthDay: Hashable {
        let month: Int
        let day: Int
    }

    /// Builds the month/day → holiday map for a single year. Cheap enough to
    /// compute on demand for the handful of days the schedule view shows.
    private static func holidays(in year: Int, calendar: Calendar) -> [MonthDay: Holiday] {
        var table: [MonthDay: Holiday] = [
            MonthDay(month: 1, day: 1): Holiday(name: "New Year's Day", symbol: "sparkles"),
            MonthDay(month: 2, day: 14): Holiday(name: "Valentine's Day", symbol: "heart.fill"),
            MonthDay(month: 3, day: 17): Holiday(name: "St. Patrick's Day", symbol: "leaf.fill"),
            MonthDay(month: 6, day: 19): Holiday(name: "Juneteenth", symbol: "flag.fill"),
            MonthDay(month: 7, day: 4): Holiday(name: "Independence Day", symbol: "flag.fill"),
            MonthDay(month: 10, day: 31): Holiday(name: "Halloween", symbol: "moon.stars.fill"),
            MonthDay(month: 11, day: 11): Holiday(name: "Veterans Day", symbol: "flag.fill"),
            MonthDay(month: 12, day: 24): Holiday(name: "Christmas Eve", symbol: "gift.fill"),
            MonthDay(month: 12, day: 25): Holiday(name: "Christmas Day", symbol: "gift.fill"),
            MonthDay(month: 12, day: 31): Holiday(name: "New Year's Eve", symbol: "sparkles"),
        ]

        func set(_ holiday: Holiday, on date: Date?) {
            guard let date else { return }
            let comps = calendar.dateComponents([.month, .day], from: date)
            guard let month = comps.month, let day = comps.day else { return }
            table[MonthDay(month: month, day: day)] = holiday
        }

        // Floating (nth-weekday) holidays. Weekday values: Sunday = 1 ... Saturday = 7.
        set(Holiday(name: "Martin Luther King Jr. Day", symbol: "star.fill"),
            on: nthWeekday(3, weekday: 2, month: 1, year: year, calendar: calendar))
        set(Holiday(name: "Presidents' Day", symbol: "star.fill"),
            on: nthWeekday(3, weekday: 2, month: 2, year: year, calendar: calendar))
        set(Holiday(name: "Mother's Day", symbol: "heart.fill"),
            on: nthWeekday(2, weekday: 1, month: 5, year: year, calendar: calendar))
        set(Holiday(name: "Memorial Day", symbol: "flag.fill"),
            on: lastWeekday(2, month: 5, year: year, calendar: calendar))
        set(Holiday(name: "Father's Day", symbol: "heart.fill"),
            on: nthWeekday(3, weekday: 1, month: 6, year: year, calendar: calendar))
        set(Holiday(name: "Labor Day", symbol: "star.fill"),
            on: nthWeekday(1, weekday: 2, month: 9, year: year, calendar: calendar))
        set(Holiday(name: "Thanksgiving", symbol: "fork.knife"),
            on: nthWeekday(4, weekday: 5, month: 11, year: year, calendar: calendar))
        set(Holiday(name: "Easter", symbol: "leaf.fill"),
            on: easter(year: year, calendar: calendar))

        return table
    }

    // MARK: - Weekday math

    /// The `n`th occurrence of `weekday` in the given month (n is 1-based).
    private static func nthWeekday(_ n: Int, weekday: Int, month: Int, year: Int, calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.weekday = weekday
        components.weekdayOrdinal = n
        return calendar.date(from: components)
    }

    /// The last occurrence of `weekday` in the given month.
    private static func lastWeekday(_ weekday: Int, month: Int, year: Int, calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.weekday = weekday
        components.weekdayOrdinal = -1
        return calendar.date(from: components)
    }

    /// Gregorian Easter Sunday via the Anonymous (Meeus/Jones/Butcher) algorithm.
    private static func easter(year: Int, calendar: Calendar) -> Date? {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}
