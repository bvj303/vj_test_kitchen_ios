import Foundation
import Observation

@MainActor
@Observable
final class AuthViewModel {
    enum AuthState: Equatable {
        case loading
        case signedOut
        case signedIn(userId: UUID)
    }

    enum UsernameAvailability: Equatable {
        case invalidFormat
        case checking
        case available
        case taken
        /// The availability check itself failed (e.g. network) — distinct
        /// from `.taken` so the UI doesn't wrongly say "already taken".
        case unknown
    }

    /// Minimum password length enforced client-side at sign-up. Keep in sync
    /// with the Supabase project's `minimum_password_length` (Auth settings /
    /// config.toml) — the server is the real gate; this is fast UX feedback.
    static let minimumPasswordLength = 8

    private(set) var state: AuthState = .loading
    var email = ""
    var password = ""
    var firstName = ""
    var lastName = ""
    var username = "" {
        didSet {
            guard oldValue != username else { return }
            guard UsernameFormat.isValid(username) else {
                usernameAvailability = username.isEmpty ? nil : .invalidFormat
                return
            }
            usernameAvailability = .checking
            usernameDebouncer.run { [weak self] in await self?.checkUsernameAvailability() }
        }
    }
    private(set) var usernameAvailability: UsernameAvailability?
    var errorMessage: String?
    private(set) var isSubmitting = false

    /// Set after a successful sign-up when the project requires email
    /// confirmation (see `AuthService.signUp`): the account exists but no
    /// session is created until the user clicks the emailed link, so the UI
    /// shows a "check your email" message instead of appearing to hang on the
    /// sign-up screen. Cleared when they leave the flow or sign in.
    private(set) var awaitingEmailConfirmation = false

    /// Gates the Create Profile screen's "Next" button — first/last name are
    /// required, and the username must have passed the availability check.
    var canProceedToAccountStep: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty
            && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
            && usernameAvailability == .available
    }

    private let authService: AuthServicing
    private let profileService: ProfileServicing
    private let usernameDebouncer: Debouncer
    // deinit is always non-isolated (even in a @MainActor class), and
    // Task.cancel() is safe to call from any context, so this is exempted
    // from main-actor isolation solely to allow cleanup there. Not UI state,
    // so it's also excluded from @Observable's tracking.
    @ObservationIgnored
    nonisolated(unsafe) private var observationTask: Task<Void, Never>?

    init(
        authService: AuthServicing = AuthService(),
        profileService: ProfileServicing = ProfileService(),
        usernameDebounceDelay: Duration = .milliseconds(300)
    ) {
        self.authService = authService
        self.profileService = profileService
        self.usernameDebouncer = Debouncer(delay: usernameDebounceDelay)
        observationTask = Task { [weak self] in
            guard let self else { return }
            for await userId in self.authService.userIdChanges {
                self.state = userId.map { .signedIn(userId: $0) } ?? .signedOut
            }
        }
    }

    deinit {
        observationTask?.cancel()
    }

    func signUp() async {
        // Validate before hitting the network so a too-short password fails
        // fast with a clear message rather than a generic server error.
        guard password.count >= Self.minimumPasswordLength else {
            errorMessage = "Password must be at least \(Self.minimumPasswordLength) characters."
            return
        }
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let needsConfirmation = try await authService.signUp(
                email: email,
                password: password,
                firstName: firstName.trimmingCharacters(in: .whitespaces),
                lastName: lastName.trimmingCharacters(in: .whitespaces),
                username: username
            )
            // When confirmation is required there's no session yet, so
            // `userIdChanges` won't move us off the sign-up screen — flip the
            // flag so the view can tell the user to check their email. When it's
            // not required, the auth-state stream drives the transition as before.
            awaitingEmailConfirmation = needsConfirmation
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    private func checkUsernameAvailability() async {
        do {
            let available = try await profileService.isUsernameAvailable(username)
            usernameAvailability = available ? .available : .taken
        } catch {
            usernameAvailability = .unknown
        }
    }

    func signIn() async {
        await perform { try await authService.signIn(email: email, password: password) }
    }

    func signOut() async {
        await perform { try await authService.signOut() }
    }

    /// Proactively refreshes the stored session at launch so a valid auth token
    /// is attached to every Supabase sub-client (notably the Functions client,
    /// which caches its token from auth events rather than fetching one per
    /// request) before the user reaches any feature. Fixes the AI Planner
    /// returning "you have no recipes" on a cold launch until the Recipes tab
    /// was opened — see `AuthServicing.warmUpSession`. Failures are swallowed:
    /// this is background housekeeping, not a user action, so it must never
    /// surface an error or disturb the current auth state.
    func warmUpSession() async {
        try? await authService.warmUpSession()
    }

    /// Handles an auth deep link opened from an email (the sign-up confirmation
    /// link). On success the session is established and `userIdChanges` moves the
    /// app to signed-in; the awaiting-confirmation state is cleared. A URL that
    /// isn't a valid/current auth callback is ignored rather than surfacing a
    /// scary error (e.g. a link tapped twice, or an unrelated deep link).
    func handleAuthCallback(url: URL) async {
        do {
            try await authService.handleAuthCallback(url: url)
            awaitingEmailConfirmation = false
        } catch {
            // Intentionally silent — see doc comment.
        }
    }

    func deleteAccount() async {
        await perform { try await authService.deleteAccount() }
    }

    private func perform(_ operation: () async throws -> Void) async {
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await operation()
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }
}
