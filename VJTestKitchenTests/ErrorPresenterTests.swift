import Foundation
import Testing
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
}
