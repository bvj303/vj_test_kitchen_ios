import Foundation

/// Fetches a short-range daily weather outlook for the meal calendar. Abstracted
/// behind a protocol (like `MealPlanServicing`/`AuthServicing`) so the ViewModel
/// stays unit-testable with a fake and never depends on a concrete weather API.
protocol WeatherForecasting: Sendable {
    /// The daily forecast for the given coordinate — one `DailyForecast` per day
    /// the provider returns, starting today.
    func dailyForecast(for coordinate: Coordinate) async throws -> [DailyForecast]
}

/// Real forecaster backed by Open-Meteo (https://open-meteo.com) — free, keyless,
/// no Apple Developer entitlement or code-signing required, so it works in an
/// unsigned Simulator build. (WeatherKit is the planned future swap; it needs the
/// `com.apple.developer.weatherkit` entitlement + a signed build — see the PR /
/// DECISIONS.md.) The protocol boundary means that swap is this one struct.
///
/// URL building and response parsing are split into pure static helpers so they
/// can be unit-tested without a network round-trip (same split as `ai-chat`'s
/// `buildSearchRecipesUrl`).
struct OpenMeteoForecastService: WeatherForecasting {
    /// A few days past the visible week, so a day-boundary/time-zone skew can't
    /// leave the last day of the week without a forecast.
    private static let forecastDays = 10

    func dailyForecast(for coordinate: Coordinate) async throws -> [DailyForecast] {
        let url = Self.forecastURL(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeatherError.badResponse
        }
        return try Self.parse(data)
    }

    /// Builds the Open-Meteo daily-forecast URL. `timezone=auto` makes the
    /// returned `daily.time` entries local "yyyy-MM-dd" dates, which we use
    /// directly as calendar keys. Temperatures come back in Celsius and are
    /// localized for display by `WeatherFormatting`.
    static func forecastURL(latitude: Double, longitude: Double, forecastDays: Int = forecastDays) -> URL {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: String(forecastDays)),
        ]
        return components.url!
    }

    /// Decodes an Open-Meteo forecast response into `DailyForecast`s, one per day.
    /// If the three parallel arrays disagree in length, the shortest wins rather
    /// than failing the whole outlook.
    static func parse(_ data: Data) throws -> [DailyForecast] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let daily = response.daily
        let count = min(daily.time.count, daily.weatherCode.count, daily.temperatureMax.count, daily.temperatureMin.count)
        return (0..<count).map { index in
            let style = WeatherCodeStyle.style(for: daily.weatherCode[index])
            return DailyForecast(
                date: daily.time[index],
                symbolName: style.symbolName,
                condition: style.description,
                highTemperature: Measurement(value: daily.temperatureMax[index], unit: .celsius),
                lowTemperature: Measurement(value: daily.temperatureMin[index], unit: .celsius)
            )
        }
    }

    // MARK: - Wire format

    private struct Response: Decodable {
        let daily: Daily

        struct Daily: Decodable {
            let time: [String]
            let weatherCode: [Int]
            let temperatureMax: [Double]
            let temperatureMin: [Double]

            enum CodingKeys: String, CodingKey {
                case time
                case weatherCode = "weather_code"
                case temperatureMax = "temperature_2m_max"
                case temperatureMin = "temperature_2m_min"
            }
        }
    }
}

enum WeatherError: Error {
    case badResponse
}
