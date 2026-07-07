import Foundation
import CoreLocation

/// One-shot access to the device's current location plus authorization control,
/// behind a protocol so `SettingsViewModel`/`MealCalendarViewModel` stay testable
/// without CoreLocation or a real GPS fix.
protocol LocationProviding: Sendable {
    /// The current authorization state, without prompting.
    func currentAuthorization() async -> LocationAuthorization
    /// Prompts for When-In-Use permission if it hasn't been decided yet, then
    /// reports the resulting status. If already decided, returns that status
    /// without a prompt.
    func requestAuthorization() async -> LocationAuthorization
    /// The current coordinate. Throws `LocationError.denied` if permission is
    /// denied, or `LocationError.unavailable` if a fix can't be obtained.
    func currentLocation() async throws -> Coordinate
}

/// App-level mirror of CoreLocation's authorization states, kept SDK-free so it
/// can cross into the ViewModel/UI layer.
enum LocationAuthorization: Sendable {
    case notDetermined
    /// Denied or restricted — the app can't get location until the user changes
    /// it in Settings.
    case denied
    case authorized
}

enum LocationError: Error {
    case denied
    case unavailable
}

/// CoreLocation-backed implementation. Isolated to the main actor because
/// `CLLocationManager` is created on and delivers its delegate callbacks to the
/// main thread; the delegate methods hop back with `assumeIsolated` (safe — the
/// manager was configured on main with no custom dispatch queue). Weather only
/// needs a rough fix, so accuracy is relaxed to the kilometer.
@MainActor
final class CoreLocationService: NSObject, LocationProviding {
    private let manager = CLLocationManager()
    private var authContinuation: CheckedContinuation<LocationAuthorization, Never>?
    private var locationContinuations: [CheckedContinuation<Coordinate, Error>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func currentAuthorization() async -> LocationAuthorization {
        Self.map(manager.authorizationStatus)
    }

    func requestAuthorization() async -> LocationAuthorization {
        let status = manager.authorizationStatus
        guard status == .notDetermined else { return Self.map(status) }
        return await withCheckedContinuation { continuation in
            authContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    func currentLocation() async throws -> Coordinate {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            throw LocationError.denied
        case .notDetermined:
            guard await requestAuthorization() == .authorized else { throw LocationError.denied }
        default:
            break
        }
        return try await withCheckedThrowingContinuation { continuation in
            locationContinuations.append(continuation)
            manager.requestLocation()
        }
    }

    private static func map(_ status: CLAuthorizationStatus) -> LocationAuthorization {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways: return .authorized
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }
}

extension CoreLocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Read the (Sendable) status off the non-Sendable manager here, before
        // hopping to the main actor, so no CoreLocation object crosses actors.
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            // The delegate also fires once with the initial status; only resume a
            // pending request once the user has actually decided.
            guard status != .notDetermined, let continuation = authContinuation else { return }
            authContinuation = nil
            continuation.resume(returning: Self.map(status))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last.map {
            Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }
        MainActor.assumeIsolated {
            guard let coordinate else { return }
            let pending = locationContinuations
            locationContinuations.removeAll()
            pending.forEach { $0.resume(returning: coordinate) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            let pending = locationContinuations
            locationContinuations.removeAll()
            pending.forEach { $0.resume(throwing: LocationError.unavailable) }
        }
    }
}
