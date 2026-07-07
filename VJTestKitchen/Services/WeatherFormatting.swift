import Foundation

/// Pure, locale-aware formatting for the temperatures shown on the calendar's
/// weather badges. Split out (like `MealTypeStyle`) so the display rules are
/// unit-tested without spinning up a view.
enum WeatherFormatting {
    /// A compact "72°" style label: the temperature converted to the locale's
    /// preferred unit (°F in the US, °C elsewhere), rounded to a whole degree,
    /// with a degree sign but no unit letter — the calendar shows a high/low
    /// pair where a repeated "F"/"C" would just be noise.
    static func temperatureLabel(_ measurement: Measurement<UnitTemperature>, locale: Locale = .current) -> String {
        let unit: UnitTemperature = locale.measurementSystem == .us ? .fahrenheit : .celsius
        let value = measurement.converted(to: unit).value.rounded()
        return "\(Int(value))°"
    }
}
