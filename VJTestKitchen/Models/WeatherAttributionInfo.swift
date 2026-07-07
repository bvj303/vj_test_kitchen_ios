import Foundation

/// The attribution WeatherKit legally requires apps to display wherever its data
/// appears: the Apple Weather mark plus a link to the data-sources legal page.
/// Mapped from WeatherKit's `WeatherAttribution` so the view can render it
/// without importing WeatherKit.
struct WeatherAttributionInfo: Equatable, Sendable {
    let markLightURL: URL
    let markDarkURL: URL
    let legalPageURL: URL
}
