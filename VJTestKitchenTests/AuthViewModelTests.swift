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
    private(set) var deleteAccountCallCount = 0
    private(set) var lastEmail: String?
    private(set) var lastPassword: String?
    private(set) var lastFirstName: String?
    private(set) var lastLastName: String?
    private(set) var lastUsername: String?
    var errorToThrow: Error?
    /// Controls the value `signUp` reports back — `true` simulates a project
    /// with email confirmation on (no session until the link is clicked).
    var signUpNeedsEmailConfirmation = false

    let userIdChanges: AsyncStream<UUID?>
    private let continuation: AsyncStream<UUID?>.Continuation

    init() {
        var continuation: AsyncStream<UUID?>.Continuation!
        userIdChanges = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    @discardableResult
    func signUp(email: String, password: String, firstName: String, lastName: String, username: String) async throws -> Bool {
        signUpCallCount += 1
        lastEmail = email
        lastPassword = password
        lastFirstName = firstName
        lastLastName = lastName
        lastUsername = username
        if let errorToThrow { throw errorToThrow }
        return signUpNeedsEmailConfirmation
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

    func deleteAccount() async throws {
        deleteAccountCallCount += 1
        if let errorToThrow { throw errorToThrow }
    }

    func emit(userId: UUID?) {
        continuation.yield(userId)
    }
}

private struct TestError: Error, LocalizedError {
    var errorDescription: String? { "invalid credentials" }
}

/// Fake ProfileServicing conformer — lets tests control the username
/// availability result, the profile returned by `fetchMine`, or force a
/// failure, without a real network call. Shared by AuthViewModelTests and
/// ProfileViewModelTests.
final class FakeProfileService: ProfileServicing, @unchecked Sendable {
    var takenUsernames: Set<String> = []
    var errorToThrow: Error?
    var profileToReturn = Profile(id: UUID(), displayName: nil, firstName: nil, lastName: nil, username: nil, createdAt: Date())
    private(set) var checkedUsernames: [String] = []
    private(set) var updateCallCount = 0
    private(set) var lastUpdateFirstName: String?
    private(set) var lastUpdateLastName: String?
    private(set) var lastUpdateUsername: String?
    var avatarUrlToReturn = "https://storage.example.com/avatars/user/avatar.jpg?v=1"
    private(set) var uploadedAvatarData: [Data] = []

    func isUsernameAvailable(_ username: String) async throws -> Bool {
        checkedUsernames.append(username)
        if let errorToThrow { throw errorToThrow }
        return !takenUsernames.contains(username)
    }

    func fetchMine() async throws -> Profile {
        if let errorToThrow { throw errorToThrow }
        return profileToReturn
    }

    func updateMine(firstName: String, lastName: String, username: String) async throws {
        updateCallCount += 1
        lastUpdateFirstName = firstName
        lastUpdateLastName = lastName
        lastUpdateUsername = username
        if let errorToThrow { throw errorToThrow }
    }

    func uploadAvatar(_ imageData: Data) async throws -> String {
        uploadedAvatarData.append(imageData)
        if let errorToThrow { throw errorToThrow }
        return avatarUrlToReturn
    }
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
        viewModel.firstName = "  Ada  "
        viewModel.lastName = "  Lovelace  "
        viewModel.username = "ada_l"

        await viewModel.signUp()

        #expect(fake.signUpCallCount == 1)
        #expect(fake.lastEmail == "new@example.com")
        #expect(fake.lastFirstName == "Ada")
        #expect(fake.lastLastName == "Lovelace")
        #expect(fake.lastUsername == "ada_l")
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

    @Test func signUpFlagsAwaitingConfirmationWhenProjectRequiresIt() async {
        let fake = FakeAuthService()
        fake.signUpNeedsEmailConfirmation = true
        let viewModel = AuthViewModel(authService: fake)
        viewModel.email = "new@example.com"
        viewModel.password = "s3cretpw"

        await viewModel.signUp()

        #expect(viewModel.awaitingEmailConfirmation)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func signUpDoesNotAwaitConfirmationWhenSessionIsImmediate() async {
        let fake = FakeAuthService()
        fake.signUpNeedsEmailConfirmation = false
        let viewModel = AuthViewModel(authService: fake)
        viewModel.email = "new@example.com"
        viewModel.password = "s3cretpw"

        await viewModel.signUp()

        #expect(viewModel.awaitingEmailConfirmation == false)
    }

    @Test func signUpFailureDoesNotFlagAwaitingConfirmation() async {
        let fake = FakeAuthService()
        fake.signUpNeedsEmailConfirmation = true  // ignored — the call throws first
        fake.errorToThrow = TestError()
        let viewModel = AuthViewModel(authService: fake)
        viewModel.email = "new@example.com"
        viewModel.password = "s3cretpw"

        await viewModel.signUp()

        #expect(viewModel.awaitingEmailConfirmation == false)
        #expect(viewModel.errorMessage != nil)
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

    @Test func deleteAccountCallsService() async {
        let fake = FakeAuthService()
        let viewModel = AuthViewModel(authService: fake)

        await viewModel.deleteAccount()

        #expect(fake.deleteAccountCallCount == 1)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func deleteAccountSurfacesErrorMessageOnFailure() async {
        let fake = FakeAuthService()
        fake.errorToThrow = TestError()
        let viewModel = AuthViewModel(authService: fake)

        await viewModel.deleteAccount()

        #expect(fake.deleteAccountCallCount == 1)
        #expect(viewModel.errorMessage == "invalid credentials")
    }

    @Test func usernameShorterThanMinimumIsMarkedInvalidWithoutCallingService() async {
        let fakeProfile = FakeProfileService()
        let viewModel = AuthViewModel(authService: FakeAuthService(), profileService: fakeProfile, usernameDebounceDelay: .zero)

        viewModel.username = "ab"
        try? await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.usernameAvailability == .invalidFormat)
        #expect(fakeProfile.checkedUsernames.isEmpty)
    }

    @Test func emptyUsernameHasNoAvailabilityStateYet() async {
        let viewModel = AuthViewModel(authService: FakeAuthService(), profileService: FakeProfileService(), usernameDebounceDelay: .zero)

        viewModel.username = "abc"
        try? await Task.sleep(for: .milliseconds(50))
        viewModel.username = ""
        try? await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.usernameAvailability == nil)
    }

    @Test func validUsernameIsCheckedAndMarkedAvailable() async {
        let fakeProfile = FakeProfileService()
        let viewModel = AuthViewModel(authService: FakeAuthService(), profileService: fakeProfile, usernameDebounceDelay: .zero)

        viewModel.username = "newchef"
        try? await Task.sleep(for: .milliseconds(50))

        #expect(fakeProfile.checkedUsernames == ["newchef"])
        #expect(viewModel.usernameAvailability == .available)
    }

    @Test func takenUsernameIsMarkedTaken() async {
        let fakeProfile = FakeProfileService()
        fakeProfile.takenUsernames = ["chef"]
        let viewModel = AuthViewModel(authService: FakeAuthService(), profileService: fakeProfile, usernameDebounceDelay: .zero)

        viewModel.username = "chef"
        try? await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.usernameAvailability == .taken)
    }

    @Test func availabilityCheckFailureIsMarkedUnknownRatherThanTaken() async {
        let fakeProfile = FakeProfileService()
        fakeProfile.errorToThrow = TestError()
        let viewModel = AuthViewModel(authService: FakeAuthService(), profileService: fakeProfile, usernameDebounceDelay: .zero)

        viewModel.username = "chef"
        try? await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.usernameAvailability == .unknown)
    }

    @Test func canProceedToAccountStepRequiresNamesAndAnAvailableUsername() async {
        let fakeProfile = FakeProfileService()
        let viewModel = AuthViewModel(authService: FakeAuthService(), profileService: fakeProfile, usernameDebounceDelay: .zero)

        #expect(viewModel.canProceedToAccountStep == false)

        viewModel.firstName = "Ada"
        viewModel.lastName = "Lovelace"
        #expect(viewModel.canProceedToAccountStep == false, "username not yet checked")

        viewModel.username = "adalovelace"
        try? await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.canProceedToAccountStep == true)
    }
}
