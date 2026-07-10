import Foundation
import Testing
import Supabase
@testable import VJTestKitchen

struct ErrorPresenterTests {
    @Test func mapsNoInternetToFriendlyMessage() {
        let message = ErrorPresenter.message(for: URLError(.notConnectedToInternet))
        #expect(message.localizedCaseInsensitiveContains("internet"))
    }

    @Test func mapsTimeoutToFriendlyMessage() {
        let message = ErrorPresenter.message(for: URLError(.timedOut))
        #expect(message.localizedCaseInsensitiveContains("timed out"))
    }

    @Test func mapsUnreachableHostToFriendlyMessage() {
        let message = ErrorPresenter.message(for: URLError(.cannotConnectToHost))
        #expect(message.localizedCaseInsensitiveContains("server"))
    }

    @Test func fallsBackToLocalizedDescriptionForOtherErrors() {
        struct Custom: LocalizedError { var errorDescription: String? { "custom failure" } }
        #expect(ErrorPresenter.message(for: Custom()) == "custom failure")
    }

    // MARK: - Postgres (SQLSTATE) mapping

    @Test func mapsUniqueViolationWithoutLeakingSQL() {
        let error = PostgrestError(code: "23505", message: "duplicate key value violates unique constraint \"tags_name_key\"")
        let message = ErrorPresenter.message(for: error)
        #expect(message == "That name is already taken. Try a different one.")
        #expect(!message.contains("constraint"))
    }

    @Test func mapsRLSDenialToPermissionMessage() {
        let error = PostgrestError(code: "42501", message: "new row violates row-level security policy for table \"recipes\"")
        #expect(ErrorPresenter.message(for: error) == "You don't have permission to do that.")
    }

    @Test func unmappedPostgresCodeFallsBackToServerMessage() {
        let error = PostgrestError(code: "22P02", message: "invalid input syntax for type bigint")
        #expect(ErrorPresenter.message(for: error) == "invalid input syntax for type bigint")
    }

    // MARK: - Auth mapping

    private func authError(_ code: ErrorCode, message: String = "server text") -> AuthError {
        .api(
            message: message,
            errorCode: code,
            underlyingData: Data(),
            underlyingResponse: HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 400, httpVersion: nil, headerFields: nil)!
        )
    }

    @Test func mapsInvalidCredentials() {
        #expect(ErrorPresenter.message(for: authError(.invalidCredentials)) == "Incorrect email or password.")
    }

    @Test func mapsExistingAccountToSignInHint() {
        let message = ErrorPresenter.message(for: authError(.userAlreadyExists))
        #expect(message.localizedCaseInsensitiveContains("already exists"))
        #expect(message.localizedCaseInsensitiveContains("signing in"))
    }

    @Test func unmappedAuthCodeFallsBackToServerMessage() {
        #expect(ErrorPresenter.message(for: authError(.unknown, message: "something odd")) == "something odd")
    }
}
