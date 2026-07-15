import Foundation
import Observation

/// The signed-in user's profile summary needed by app chrome (the account
/// toolbar button on every tab), owned once at the app root and injected via
/// `.environment` — same pattern as `SettingsViewModel`. Keeping it shared
/// means the avatar loads once, and one update after an upload refreshes every
/// account button at once rather than each button fetching on its own.
@MainActor
@Observable
final class AccountViewModel {
    /// The current user's avatar URL, or nil if none set (the button then falls
    /// back to the person symbol).
    private(set) var avatarUrl: String?

    private let profileService: ProfileServicing
    private let logger: AppLogger

    init(profileService: ProfileServicing = ProfileService(), logger: AppLogger = .shared) {
        self.profileService = profileService
        self.logger = logger
    }

    /// Loads the current user's avatar. Best-effort: a failure just leaves the
    /// button on its symbol fallback rather than surfacing an error in chrome.
    func load() async {
        do {
            let profile = try await profileService.fetchMine()
            avatarUrl = profile.avatarUrl
        } catch {
            // Best-effort chrome load, never surfaced to the user — so log it,
            // or a persistently failing avatar fetch is completely invisible.
            logger.warning("Account avatar load failed", category: "account", metadata: [
                "errorType": String(describing: type(of: error)),
            ])
        }
    }

    /// Called after an avatar upload so every account button updates live,
    /// without a round-trip.
    func setAvatarUrl(_ url: String?) {
        avatarUrl = url
    }
}
