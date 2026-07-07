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
        await perform {
            try await authService.signUp(
                email: email,
                password: password,
                firstName: firstName.trimmingCharacters(in: .whitespaces),
                lastName: lastName.trimmingCharacters(in: .whitespaces),
                username: username
            )
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
