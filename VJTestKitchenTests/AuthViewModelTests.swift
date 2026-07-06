import Foundation
import Testing
@testable import VJTestKitchen

/// Fake AuthServicing conformer — deliberately decoupled from supabase-swift's
/// Session type (see DECISIONS.md) so these tests stay fast and don't depend
/// on constructing real SDK models.
final class FakeAuthService: AuthServicing, @unchecked Sendable {
    private(set) var signUpCallCount = 0
    private(set) var signInCallCount = 0
    private(set) var signOutCallCount = 0
    private(set) var lastEmail: String?
    private(set) var lastPassword: String?
    var errorToThrow: Error?

    let userIdChanges: AsyncStream<UUID?>
    private let continuation: AsyncStream<UUID?>.Continuation

    init() {
        var continuation: AsyncStream<UUID?>.Continuation!
        userIdChanges = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func signUp(email: String, password: String) async throws {
        signUpCallCount += 1
        lastEmail = email
        lastPassword = password
        if let errorToThrow { throw errorToThrow }
    }

    func signIn(email: String, password: String) async throws {
        signInCallCount += 1
        lastEmail = email
        lastPassword = password
        if let errorToThrow { throw errorToThrow }
    }

    func signOut() async throws {
        signOutCallCount += 1
        if let errorToThrow { throw errorToThrow }
    }

    func emit(userId: UUID?) {
        continuation.yield(userId)
    }
}

private struct TestError: Error, LocalizedError {
    var errorDescription: String? { "invalid credentials" }
}

@MainActor
struct AuthViewModelTests {
    @Test func startsInLoadingState() {
        let viewModel = AuthViewModel(authService: FakeAuthService())
        #expect(viewModel.state == .loading)
    }

    @Test func transitionsToSignedOutWhenStreamEmitsNilUserId() async {
        let fake = FakeAuthService()
        let viewModel = AuthViewModel(authService: fake)
        fake.emit(userId: nil)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(viewModel.state == .signedOut)
    }

    @Test func transitionsToSignedInWhenStreamEmitsUserId() async {
        let fake = FakeAuthService()
        let viewModel = AuthViewModel(authService: fake)
        let userId = UUID()
        fake.emit(userId: userId)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(viewModel.state == .signedIn(userId: userId))
    }

    @Test func signInCallsServiceWithEnteredCredentials() async {
        let fake = FakeAuthService()
        let viewModel = AuthViewModel(authService: fake)
        viewModel.email = "test@example.com"
        viewModel.password = "hunter2"

        await viewModel.signIn()

        #expect(fake.signInCallCount == 1)
        #expect(fake.lastEmail == "test@example.com")
        #expect(fake.lastPassword == "hunter2")
        #expect(viewModel.errorMessage == nil)
    }

    @Test func signInSurfacesErrorMessageOnFailure() async {
        let fake = FakeAuthService()
        fake.errorToThrow = TestError()
        let viewModel = AuthViewModel(authService: fake)

        await viewModel.signIn()

        #expect(viewModel.errorMessage == "invalid credentials")
    }

    @Test func signUpCallsServiceWithEnteredCredentials() async {
        let fake = FakeAuthService()
        let viewModel = AuthViewModel(authService: fake)
        viewModel.email = "new@example.com"
        viewModel.password = "s3cretpw"

        await viewModel.signUp()

        #expect(fake.signUpCallCount == 1)
        #expect(fake.lastEmail == "new@example.com")
        #expect(viewModel.errorMessage == nil)
    }

    @Test func signUpSurfacesErrorMessageOnFailure() async {
        let fake = FakeAuthService()
        fake.errorToThrow = TestError()
        let viewModel = AuthViewModel(authService: fake)
        viewModel.email = "new@example.com"
        viewModel.password = "s3cretpw"

        await viewModel.signUp()

        #expect(viewModel.errorMessage == "invalid credentials")
    }

    @Test func signUpRejectsPasswordShorterThanMinimumWithoutCallingService() async {
        let fake = FakeAuthService()
        let viewModel = AuthViewModel(authService: fake)
        viewModel.email = "new@example.com"
        viewModel.password = "short7!"  // 7 chars, below the minimum

        await viewModel.signUp()

        #expect(fake.signUpCallCount == 0)
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.errorMessage?.contains("\(AuthViewModel.minimumPasswordLength)") == true)
    }

    @Test func signUpAcceptsPasswordMeetingMinimum() async {
        let fake = FakeAuthService()
        let viewModel = AuthViewModel(authService: fake)
        viewModel.email = "new@example.com"
        viewModel.password = String(repeating: "a", count: AuthViewModel.minimumPasswordLength)

        await viewModel.signUp()

        #expect(fake.signUpCallCount == 1)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func signInIsNotBlockedByPasswordLength() async {
        // Existing accounts may predate the minimum — sign-in must not gate on it.
        let fake = FakeAuthService()
        let viewModel = AuthViewModel(authService: fake)
        viewModel.email = "old@example.com"
        viewModel.password = "old"

        await viewModel.signIn()

        #expect(fake.signInCallCount == 1)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func signOutCallsService() async {
        let fake = FakeAuthService()
        let viewModel = AuthViewModel(authService: fake)

        await viewModel.signOut()

        #expect(fake.signOutCallCount == 1)
    }
}
