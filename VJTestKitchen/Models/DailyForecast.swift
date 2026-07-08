import Foundation

/// One day's weather outlook shown on the meal calendar. A plain value type
/// mapped from WeatherKit in `WeatherKitForecastService`, so the ViewModel and
/// views never import WeatherKit — same boundary the app keeps around every
/// other SDK (`AuthServicing`, `MealPlanServicing`, …).
struct DailyForecast: Equatable, Sendable, Identifiable {
    /// "yyyy-MM-dd" key, formatted with `MealPlan.dateFormatter` (UTC) so it lines
    /// up with `MealCalendarViewModel.weekDates`.
    let date: String
    /// SF Symbol name for the condition — supplied directly by WeatherKit
    /// (no code→symbol table needed, unlike a raw weather-code API).
    let symbolName: String
    /// Human-readable condition, e.g. "Partly Cloudy", for the accessibility label.
    let condition: String
    /// Coarse precipitation/clear bucket driving the Home tab's weather-aware
    /// cooking suggestion (`RecipeSuggester`). Derived from the WMO code at parse
    /// time so downstream never re-inspects the raw code.
    let category: WeatherCategory
    let highTemperature: Measurement<UnitTemperature>
    let lowTemperature: Measurement<UnitTemperature>

    var id: String { date }
}
