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

    // MARK: - Edge Function errors
    // ai-chat returns user-facing copy as {"error": "..."} (rate limit, message
    // too long, timeout). The SDK wraps a non-2xx as FunctionsError.httpError,
    // whose localizedDescription is just "Edge Function returned a non-2xx status
    // code" — so without this mapping the friendly text never reached the user.

    @Test func showsTheEdgeFunctionsOwnErrorMessage() {
        let body = Data(#"{"error":"You've reached the Kitchen Concierge's limit for now — please try again in about 40 minutes."}"#.utf8)
        let message = ErrorPresenter.message(for: FunctionsError.httpError(code: 429, data: body))
        #expect(message == "You've reached the Kitchen Concierge's limit for now — please try again in about 40 minutes.")
    }

    @Test func fallsBackToFriendlyCopyWhenTheFunctionBodyHasNoMessage() {
        let rateLimited = ErrorPresenter.message(for: FunctionsError.httpError(code: 429, data: Data("oops".utf8)))
        #expect(rateLimited.localizedCaseInsensitiveContains("try again"))
        #expect(!rateLimited.localizedCaseInsensitiveContains("non-2xx"))

        let serverError = ErrorPresenter.message(for: FunctionsError.httpError(code: 502, data: Data()))
        #expect(!serverError.localizedCaseInsensitiveContains("non-2xx"))
        #expect(serverError.localizedCaseInsensitiveContains("try again"))
    }

    @Test func ignoresAnOverlongOrBlankFunctionMessage() {
        let blank = ErrorPresenter.message(for: FunctionsError.httpError(code: 500, data: Data(#"{"error":"   "}"#.utf8)))
        #expect(!blank.trimmingCharacters(in: .whitespaces).isEmpty)
        let huge = String(repeating: "x", count: 2_000)
        let long = ErrorPresenter.message(for: FunctionsError.httpError(code: 500, data: Data("{\"error\":\"\(huge)\"}".utf8)))
        #expect(long.count < 300)
    }

    // Server-side length/size limits (migration 20260927020000): CHECK
    // constraints and save_recipe's tag/ingredient caps raise 23514 with raw SQL
    // text ("violates check constraint recipes_title_length") — show copy instead.
    @Test func mapsCheckViolationToFriendlyTooLongMessage() {
        let error = PostgrestError(code: "23514", message: "new row for relation \"recipes\" violates check constraint \"recipes_title_length\"")
        let message = ErrorPresenter.message(for: error)
        #expect(message.localizedCaseInsensitiveContains("too long") || message.localizedCaseInsensitiveContains("too many"))
        #expect(!message.contains("constraint"))
    }
}
