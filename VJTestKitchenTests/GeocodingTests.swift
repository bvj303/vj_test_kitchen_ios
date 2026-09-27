import Foundation
import Testing
@testable import VJTestKitchen

/// MapKit's non-deprecated geocoding (`MKReverseGeocodingRequest`, iOS/macOS 26)
/// no longer exposes a structured postal code — `MKMapItem.placemark.postalCode`
/// is deprecated and `MKAddress` is formatted strings only — so the ZIP is read
/// out of the formatted address. A miss returns nil, which HomeLocationViewModel
/// already handles by storing the bare coordinate.
struct GeocodingTests {
    @Test func extractsTheZipFromASingleLineUSAddress() {
        #expect(MapKitGeocodingService.postalCode(inFormattedAddress: "77 Massachusetts Ave, Cambridge, MA 02139, United States") == "02139")
    }

    @Test func prefersTheLastFiveDigitRunSoAHouseNumberNeverWins() {
        let address = "12345 Main St\nSpringfield, IL 62704\nUnited States"
        #expect(MapKitGeocodingService.postalCode(inFormattedAddress: address) == "62704")
    }

    @Test func dropsTheZipPlusFourSuffix() {
        #expect(MapKitGeocodingService.postalCode(inFormattedAddress: "1600 Amphitheatre Pkwy, Mountain View, CA 94043-1351") == "94043")
    }

    @Test func returnsNilWhenThereIsNoUSZip() {
        #expect(MapKitGeocodingService.postalCode(inFormattedAddress: "10 Downing Street, London SW1A 2AA, United Kingdom") == nil)
        #expect(MapKitGeocodingService.postalCode(inFormattedAddress: "") == nil)
        #expect(MapKitGeocodingService.postalCode(inFormattedAddress: nil) == nil)
    }

    @Test func ignoresLongerDigitRuns() {
        // A phone number or a 6+ digit run is not a ZIP.
        #expect(MapKitGeocodingService.postalCode(inFormattedAddress: "Suite 1234567, Anytown") == nil)
    }
}
