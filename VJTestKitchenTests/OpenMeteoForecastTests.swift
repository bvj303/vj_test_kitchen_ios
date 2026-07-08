import Foundation
import Testing
@testable import VJTestKitchen

struct WeatherCodeStyleTests {
    @Test func mapsKnownCodesToSymbolAndDescription() {
        #expect(WeatherCodeStyle.style(for: 0) == .init(symbolName: "sun.max.fill", description: "Clear"))
        #expect(WeatherCodeStyle.style(for: 2) == .init(symbolName: "cloud.sun.fill", description: "Partly Cloudy"))
        #expect(WeatherCodeStyle.style(for: 3) == .init(symbolName: "cloud.fill", description: "Overcast"))
        #expect(WeatherCodeStyle.style(for: 65) == .init(symbolName: "cloud.rain.fill", description: "Rain"))
        #expect(WeatherCodeStyle.style(for: 75) == .init(symbolName: "cloud.snow.fill", description: "Snow"))
        #expect(WeatherCodeStyle.style(for: 95) == .init(symbolName: "cloud.bolt.rain.fill", description: "Thunderstorm"))
    }

    @Test func fallsBackForUnknownCode() {
        let fallback = WeatherCodeStyle.style(for: 1234)
        #expect(fallback.symbolName == "cloud.fill")
        #expect(fallback.description == "Unknown")
    }

    @Test func categorizesCodesIntoCoarseBuckets() {
        #expect(WeatherCodeStyle.category(for: 0) == .clear)   // clear
        #expect(WeatherCodeStyle.category(for: 3) == .cloudy)  // overcast
        #expect(WeatherCodeStyle.category(for: 48) == .fog)    // fog
        #expect(WeatherCodeStyle.category(for: 63) == .rain)   // rain
        #expect(WeatherCodeStyle.category(for: 55) == .rain)   // drizzle
        #expect(WeatherCodeStyle.category(for: 82) == .rain)   // rain showers
        #expect(WeatherCodeStyle.category(for: 75) == .snow)   // snow
        #expect(WeatherCodeStyle.category(for: 86) == .snow)   // snow showers
        #expect(WeatherCodeStyle.category(for: 95) == .thunderstorm)
        #expect(WeatherCodeStyle.category(for: 99) == .thunderstorm)
    }

    @Test func unknownCodeCategorizesAsCloudy() {
        #expect(WeatherCodeStyle.category(for: 1234) == .cloudy)
    }
}

struct OpenMeteoForecastServiceTests {
    @Test func buildsForecastURLWithExpectedQuery() {
        let url = OpenMeteoForecastService.forecastURL(latitude: 30.27, longitude: -97.74, forecastDays: 7)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        #expect(components.host == "api.open-meteo.com")
        #expect(components.path == "/v1/forecast")
        #expect(items["latitude"] == "30.27")
        #expect(items["longitude"] == "-97.74")
        #expect(items["daily"] == "weather_code,temperature_2m_max,temperature_2m_min")
        #expect(items["timezone"] == "auto")
        #expect(items["forecast_days"] == "7")
    }

    @Test func parsesDailyForecastResponse() throws {
        let json = """
        {
          "daily": {
            "time": ["2026-07-07", "2026-07-08"],
            "weather_code": [0, 61],
            "temperature_2m_max": [31.2, 24.9],
            "temperature_2m_min": [18.0, 15.5]
          }
        }
        """.data(using: .utf8)!

        let forecasts = try OpenMeteoForecastService.parse(json)

        #expect(forecasts.count == 2)
        #expect(forecasts[0].date == "2026-07-07")
        #expect(forecasts[0].symbolName == "sun.max.fill")
        #expect(forecasts[0].condition == "Clear")
        #expect(forecasts[0].category == .clear)
        #expect(forecasts[0].highTemperature == Measurement(value: 31.2, unit: .celsius))
        #expect(forecasts[0].lowTemperature == Measurement(value: 18.0, unit: .celsius))
        #expect(forecasts[1].symbolName == "cloud.rain.fill")
        #expect(forecasts[1].category == .rain)
        #expect(forecasts[1].date == "2026-07-08")
    }

    @Test func parseUsesShortestArrayWhenLengthsDisagree() throws {
        // A malformed payload with mismatched array lengths shouldn't crash or
        // over-read — the shortest array bounds the result.
        let json = """
        {
          "daily": {
            "time": ["2026-07-07", "2026-07-08", "2026-07-09"],
            "weather_code": [0, 3],
            "temperature_2m_max": [31.2, 24.9, 20.0],
            "temperature_2m_min": [18.0, 15.5, 12.0]
          }
        }
        """.data(using: .utf8)!

        let forecasts = try OpenMeteoForecastService.parse(json)

        #expect(forecasts.count == 2)
    }
}
