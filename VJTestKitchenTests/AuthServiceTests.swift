import Foundation
import Supabase
import Testing
@testable import VJTestKitchen

/// Covers AuthService.resolve — the pure decision extracted from
/// authResolutions so the emitLocalSessionAsInitialSession guard is testable
/// without a live SupabaseClient/Session. See SupabaseManager for why the
/// opt-in flag is set (supabase-swift PR #822).
struct AuthServiceTests {
    private let userId = UUID()

    @Test("Expired initial session with a stored session is refresh-pending, not signed-out")
    func expiredInitialSessionIsRefreshPending() {
        // The refresh token is typically still valid, so a refresh is imminent —
        // resolving to .refreshPending lets the UI hold the launch screen rather
        // than flash the login screen (the bug this replaced).
        let resolved = AuthService.resolve(
            event: .initialSession,
            userId: userId,
            isExpired: true
        )
        #expect(resolved == .refreshPending(userId: userId))
    }

    @Test("Valid initial session emits its user id")
    func validInitialSessionEmitsUser() {
        let resolved = AuthService.resolve(
            event: .initialSession,
            userId: userId,
            isExpired: false
        )
        #expect(resolved == .signedIn(userId: userId))
    }

    @Test("Signed-out initial session (no stored session) is signed-out")
    func signedOutInitialSessionIsSignedOut() {
        // No stored session -> userId nil, isExpired defaults to true upstream.
        // Distinguished from the expired-session case above so a genuinely
        // logged-out user sees the login screen immediately, not the splash.
        let resolved = AuthService.resolve(
            event: .initialSession,
            userId: nil,
            isExpired: true
        )
        #expect(resolved == .signedOut)
    }

    @Test("Non-initial events pass the user id through even if expired")
    func nonInitialEventsPassThrough() {
        // The isExpired guard only applies to .initialSession; a live
        // signIn/tokenRefreshed/etc. event is trusted as-is.
        for event: AuthChangeEvent in [.signedIn, .tokenRefreshed, .userUpdated] {
            #expect(
                AuthService.resolve(event: event, userId: userId, isExpired: true)
                    == .signedIn(userId: userId)
            )
        }
    }

    @Test("Sign-out event resolves to signed-out")
    func signOutIsSignedOut() {
        let resolved = AuthService.resolve(
            event: .signedOut,
            userId: nil,
            isExpired: true
        )
        #expect(resolved == .signedOut)
    }
}
