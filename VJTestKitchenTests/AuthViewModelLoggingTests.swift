import Foundation
import Testing
@testable import VJTestKitchen

/// Verifies the observability instrumentation on AuthViewModel's error paths —
/// especially the ones that are intentionally silent to the user (warm-up,
/// auth callback), which would otherwise fail invisibly.
@Suite @MainActor struct AuthViewModelLoggingTests {
    private func makeLogger() -> (AppLogger, SpyLogSink) {
        let sink = SpyLogSink()
        return (AppLogger(sinks: [sink], context: LogContext(appVersion: "1", platform: "test")), sink)
    }

    @Test func logsErrorWhenSignInFails() async {
        let (logger, sink) = makeLogger()
        let fake = FakeAuthService()
        fake.errorToThrow = URLError(.notConnectedToInternet)
        let vm = AuthViewModel(authService: fake, logger: logger)

        await vm.signIn()

        let errors = sink.events.filter { $0.level == .error }
        #expect(errors.count == 1)
        #expect(errors[0].category == "auth")
        #expect(errors[0].metadata["errorType"] != nil)
    }

    @Test func logsWarningWhenSilentWarmUpFails() async {
        let (logger, sink) = makeLogger()
        let fake = FakeAuthService()
        fake.errorToThrow = URLError(.timedOut)
        let vm = AuthViewModel(authService: fake, logger: logger)

        await vm.warmUpSession()

        // Failure is not surfaced to the user, but must be logged.
        #expect(vm.errorMessage == nil)
        #expect(sink.events.contains { $0.level == .warning && $0.category == "auth" })
    }

    @Test func logsNoticeWhenAuthCallbackFails() async {
        let (logger, sink) = makeLogger()
        let fake = FakeAuthService()
        fake.errorToThrow = URLError(.badURL)
        let vm = AuthViewModel(authService: fake, logger: logger)

        await vm.handleAuthCallback(url: URL(string: "vjtestkitchen://login-callback")!)

        #expect(sink.events.contains { $0.level == .notice && $0.category == "auth" })
    }

    @Test func successfulWarmUpLogsNothing() async {
        let (logger, sink) = makeLogger()
        let vm = AuthViewModel(authService: FakeAuthService(), logger: logger)

        await vm.warmUpSession()

        #expect(sink.events.isEmpty)
    }
}
