import Foundation

/// Maps a WMO weather interpretation code (as returned by Open-Meteo's
/// `weather_code`) to an SF Symbol and a human-readable condition. Pure and
/// unit-tested — same shape as `MealTypeStyle`/`HolidayProvider`, so the fetch
/// layer stays a thin wrapper and improving the vocabulary needs no view change.
///
/// Symbols use `.fill` variants so they render nicely in `.multicolor` mode on
/// the calendar. Codes are the standard WMO WW ranges Open-Meteo documents:
/// https://open-meteo.com/en/docs (0 clear … 95+ thunderstorm).
enum WeatherCodeStyle {
    struct Style: Equatable, Sendable {
        let symbolName: String
        let description: String
    }

    /// The style for a WMO code, with a neutral cloud fallback for anything
    /// unrecognized (so a new/unknown code renders a plausible icon, never a
    /// blank).
    static func style(for code: Int) -> Style {
        switch code {
        case 0: return Style(symbolName: "sun.max.fill", description: "Clear")
        case 1: return Style(symbolName: "sun.max.fill", description: "Mainly Clear")
        case 2: return Style(symbolName: "cloud.sun.fill", description: "Partly Cloudy")
        case 3: return Style(symbolName: "cloud.fill", description: "Overcast")
        case 45, 48: return Style(symbolName: "cloud.fog.fill", description: "Fog")
        case 51, 53, 55: return Style(symbolName: "cloud.drizzle.fill", description: "Drizzle")
        case 56, 57: return Style(symbolName: "cloud.sleet.fill", description: "Freezing Drizzle")
        case 61, 63, 65: return Style(symbolName: "cloud.rain.fill", description: "Rain")
        case 66, 67: return Style(symbolName: "cloud.sleet.fill", description: "Freezing Rain")
        case 71, 73, 75: return Style(symbolName: "cloud.snow.fill", description: "Snow")
        case 77: return Style(symbolName: "cloud.snow.fill", description: "Snow Grains")
        case 80, 81, 82: return Style(symbolName: "cloud.heavyrain.fill", description: "Rain Showers")
        case 85, 86: return Style(symbolName: "cloud.snow.fill", description: "Snow Showers")
        case 95: return Style(symbolName: "cloud.bolt.rain.fill", description: "Thunderstorm")
        case 96, 99: return Style(symbolName: "cloud.bolt.rain.fill", description: "Thunderstorm with Hail")
        default: return Style(symbolName: "cloud.fill", description: "Unknown")
        }
    }
}
