import Foundation
import WeatherKit
import CoreLocation

/// Fetches a short-range daily weather outlook for the meal calendar. Abstracted
/// behind a protocol (like `MealPlanServicing`/`AuthServicing`) so the ViewModel
/// stays unit-testable with a fake and never imports WeatherKit.
protocol WeatherForecasting: Sendable {
    /// The daily forecast for the given coordinate — one `DailyForecast` per day
    /// WeatherKit returns (typically ~10 days out).
    func dailyForecast(for coordinate: Coordinate) async throws -> [DailyForecast]
    /// The attribution WeatherKit requires be shown wherever its data appears.
    func attribution() async throws -> WeatherAttributionInfo
}

/// Real forecaster backed by Apple WeatherKit.
///
/// Requires the WeatherKit capability enabled on the App ID in the Apple
/// Developer portal and the `com.apple.developer.weatherkit` entitlement (see
/// `VJTestKitchen.entitlements` / `project.yml`). It does **not** function in an
/// unsigned Simulator build — the app compiles and the UI renders, but the fetch
/// throws until the app is signed with a provisioning profile carrying the
/// entitlement. The whole weather feature degrades quietly to "no icons" in that
/// case (see `MealCalendarViewModel.loadWeather`).
///
/// Maps WeatherKit's `DayWeather` to the app's own `DailyForecast`, keying each
/// day with the same UTC "yyyy-MM-dd" formatter the calendar uses so forecasts
/// line up with `weekDates`. For a US home location (device and location in the
/// same negative-UTC-offset zone) local midnight formats to the same UTC
/// calendar day; this matches the app's documented UTC date convention.
struct WeatherKitForecastService: WeatherForecasting {
    func dailyForecast(for coordinate: Coordinate) async throws -> [DailyForecast] {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let daily = try await WeatherKit.WeatherService.shared.weather(for: location, including: .daily)
        return daily.forecast.map { day in
            DailyForecast(
                date: MealPlan.dateFormatter.string(from: day.date),
                symbolName: day.symbolName,
                condition: day.condition.description,
                highTemperature: day.highTemperature,
                lowTemperature: day.lowTemperature
            )
        }
    }

    func attribution() async throws -> WeatherAttributionInfo {
        let attribution = try await WeatherKit.WeatherService.shared.attribution
        return WeatherAttributionInfo(
            markLightURL: attribution.combinedMarkLightURL,
            markDarkURL: attribution.combinedMarkDarkURL,
            legalPageURL: attribution.legalPageURL
        )
    }
}
