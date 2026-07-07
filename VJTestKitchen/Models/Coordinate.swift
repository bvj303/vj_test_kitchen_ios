import Foundation

/// A geographic coordinate. A tiny value type so the location and weather layers
/// hand latitude/longitude around without leaking CoreLocation's
/// `CLLocationCoordinate2D` up into the ViewModel (same SDK-isolation reasoning
/// as keeping `Session`/`User` out of the ViewModels — see CLAUDE.md).
struct Coordinate: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
}
