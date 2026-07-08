import Foundation
import CoreLocation

/// Converts between a coordinate and a postal code, behind a protocol (like
/// `LocationProviding`/`WeatherForecasting`) so `HomeLocationViewModel` stays
/// testable without CLGeocoder or a network round-trip.
protocol GeocodingProviding: Sendable {
    /// Reverse geocode: the postal (ZIP) code for a coordinate, or nil if the
    /// geocoder returns no postal code. Non-throwing — a missing ZIP isn't an
    /// error, we just fall back to storing the bare coordinate.
    func postalCode(for coordinate: Coordinate) async -> String?
    /// Forward geocode: the coordinate for a postal code. Throws
    /// `GeocodingError.notFound` if the code can't be resolved.
    func coordinate(for postalCode: String) async throws -> Coordinate
}

enum GeocodingError: Error {
    case notFound
}

/// CLGeocoder-backed implementation. CLGeocoder is soft-deprecated in favor of
/// MapKit's `MKGeocodingRequest` on iOS 26, but it remains fully functional and
/// `CLPlacemark.postalCode` is the one-line way to pull a ZIP out of a reverse
/// geocode — the MapKit replacement doesn't surface a postal code nearly as
/// directly. Kept behind `GeocodingProviding` so swapping it later is one type.
struct CLGeocoderService: GeocodingProviding {
    func postalCode(for coordinate: Coordinate) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        return placemarks?.first?.postalCode
    }

    func coordinate(for postalCode: String) async throws -> Coordinate {
        // Constrain to a postal-code lookup in the user's current region so a
        // bare "02139" resolves instead of being treated as an arbitrary string.
        let placemarks = try await CLGeocoder().geocodeAddressString(postalCode)
        guard let location = placemarks.first?.location else { throw GeocodingError.notFound }
        return Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }
}
