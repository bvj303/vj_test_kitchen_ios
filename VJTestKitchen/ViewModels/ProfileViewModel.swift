import Foundation
import Observation

@MainActor
@Observable
final class ProfileViewModel {
    enum UsernameAvailability: Equatable {
        case invalidFormat
        /// Matches the profile's own current username — trivially fine to
        /// save without a round-trip, but distinct from `.available` so the
        /// UI doesn't say "available" about a username the user already has.
        case unchanged
        case checking
        case available
        case taken
        /// The availability check itself failed (e.g. network) — distinct
        /// from `.taken` so the UI doesn't wrongly say "already taken".
        case unknown
    }

    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var didSave = false
    private(set) var isUploadingAvatar = false
    /// Public URL of the current avatar, or nil if none set. Updated
    /// immediately after a successful upload so the UI reflects the new
    /// picture without waiting for a Save.
    private(set) var avatarUrl: String?
    var errorMessage: String?

    var firstName = ""
    var lastName = ""
    var username = "" {
        didSet {
            guard oldValue != username else { return }
            guard UsernameFormat.isValid(username) else {
                usernameAvailability = username.isEmpty ? nil : .invalidFormat
                return
            }
            guard username.caseInsensitiveCompare(originalUsername) != .orderedSame else {
                usernameAvailability = .unchanged
                return
            }
            usernameAvailability = .checking
            usernameDebouncer.run { [weak self] in await self?.checkUsernameAvailability() }
        }
    }
    private(set) var usernameAvailability: UsernameAvailability?
    private var originalUsername = ""

    /// Gates the "Save" button — first/last name are required, and the
    /// username must either be unchanged or have passed the availability
    /// check.
    var canSave: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty
            && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
            && (usernameAvailability == .available || usernameAvailability == .unchanged)
    }

    private let profileService: ProfileServicing
    private let usernameDebouncer: Debouncer
    private let logger: AppLogger

    init(profileService: ProfileServicing = ProfileService(), usernameDebounceDelay: Duration = .milliseconds(300), logger: AppLogger = .shared) {
        self.profileService = profileService
        self.usernameDebouncer = Debouncer(delay: usernameDebounceDelay)
        self.logger = logger
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let profile = try await profileService.fetchMine()
            firstName = profile.firstName ?? ""
            lastName = profile.lastName ?? ""
            avatarUrl = profile.avatarUrl
            originalUsername = profile.username ?? ""
            username = originalUsername
        } catch {
            logger.error("Profile load failed", category: "profile", error: error)
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    func save() async {
        guard canSave else { return }
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        do {
            let trimmedFirstName = firstName.trimmingCharacters(in: .whitespaces)
            let trimmedLastName = lastName.trimmingCharacters(in: .whitespaces)
            try await profileService.updateMine(firstName: trimmedFirstName, lastName: trimmedLastName, username: username)
            originalUsername = username
            didSave = true
        } catch {
            logger.error("Profile save failed", category: "profile", error: error)
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// Uploads a newly-picked avatar image and reflects the new URL right
    /// away. Independent of `save()` — the picture persists on pick, the way
    /// avatar pickers usually behave, so it isn't lost if the user backs out
    /// without tapping Save.
    func uploadAvatar(_ imageData: Data) async {
        errorMessage = nil
        isUploadingAvatar = true
        defer { isUploadingAvatar = false }
        do {
            avatarUrl = try await profileService.uploadAvatar(imageData)
        } catch {
            logger.error("Avatar upload failed", category: "profile", error: error)
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    private func checkUsernameAvailability() async {
        do {
            let available = try await profileService.isUsernameAvailable(username)
            usernameAvailability = available ? .available : .taken
        } catch {
            // Background check, not surfaced as an alert — log so a persistently
            // failing availability check isn't invisible (see AuthViewModel).
            logger.warning("Profile username availability check failed", category: "profile", metadata: [
                "errorType": String(describing: type(of: error)),
            ])
            usernameAvailability = .unknown
        }
    }
}
