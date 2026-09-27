import Foundation
import CoreLocation
import MapKit

/// Converts between a coordinate and a postal code, behind a protocol (like
/// `LocationProviding`/`WeatherForecasting`) so `HomeLocationViewModel` stays
/// testable without MapKit or a network round-trip.
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

/// MapKit-backed implementation (`MKGeocodingRequest` / `MKReverseGeocodingRequest`,
/// iOS/macOS 26) — replaces the deprecated `CLGeocoder`.
///
/// The one wrinkle: the non-deprecated MapKit API has no structured postal-code
/// field (`MKMapItem.placemark.postalCode` is deprecated; `MKAddress` is
/// formatted strings only), so the reverse path reads the ZIP out of the
/// formatted address via `postalCode(inFormattedAddress:)` (pure, unit-tested).
/// A miss is harmless: the protocol already returns nil for "no ZIP" and the
/// caller stores the bare coordinate.
struct MapKitGeocodingService: GeocodingProviding {
    func postalCode(for coordinate: Coordinate) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first else { return nil }
        let formatted = item.address?.fullAddress
            ?? item.addressRepresentations?.fullAddress(includingRegion: true, singleLine: true)
        return Self.postalCode(inFormattedAddress: formatted)
    }

    func coordinate(for postalCode: String) async throws -> Coordinate {
        guard let request = MKGeocodingRequest(addressString: postalCode),
              let location = try await request.mapItems.first?.location else {
            throw GeocodingError.notFound
        }
        return Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    /// The US ZIP in a formatted address — the LAST standalone 5-digit run
    /// (optionally ZIP+4, suffix dropped), so a 5-digit house number that comes
    /// first never wins. nil when there's no US ZIP (e.g. a UK postcode).
    static func postalCode(inFormattedAddress address: String?) -> String? {
        guard let address, !address.isEmpty else { return nil }
        let pattern = /\b(\d{5})(?:-\d{4})?\b/
        return address.matches(of: pattern).last.map { String($0.output.1) }
    }
}
