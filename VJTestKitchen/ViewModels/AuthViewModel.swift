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

    private(set) var state: AuthState = .loading
    var email = ""
    var password = ""
    var errorMessage: String?
    private(set) var isSubmitting = false

    private let authService: AuthServicing
    // deinit is always non-isolated (even in a @MainActor class), and
    // Task.cancel() is safe to call from any context, so this is exempted
    // from main-actor isolation solely to allow cleanup there. Not UI state,
    // so it's also excluded from @Observable's tracking.
    @ObservationIgnored
    nonisolated(unsafe) private var observationTask: Task<Void, Never>?

    init(authService: AuthServicing = AuthService()) {
        self.authService = authService
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
        await perform { try await authService.signUp(email: email, password: password) }
    }

    func signIn() async {
        await perform { try await authService.signIn(email: email, password: password) }
    }

    func signOut() async {
        await perform { try await authService.signOut() }
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
