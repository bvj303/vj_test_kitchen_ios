import Foundation
import Supabase
import Testing
@testable import VJTestKitchen

/// Covers AuthService.resolveUserId — the pure decision extracted from
/// userIdChanges so the emitLocalSessionAsInitialSession guard is testable
/// without a live SupabaseClient/Session. See SupabaseManager for why the
/// opt-in flag is set (supabase-swift PR #822).
struct AuthServiceTests {
    private let userId = UUID()

    @Test("Expired initial session resolves to signed-out (nil)")
    func expiredInitialSessionIsSignedOut() {
        let resolved = AuthService.resolveUserId(
            event: .initialSession,
            userId: userId,
            isExpired: true
        )
        #expect(resolved == nil)
    }

    @Test("Valid initial session emits its user id")
    func validInitialSessionEmitsUser() {
        let resolved = AuthService.resolveUserId(
            event: .initialSession,
            userId: userId,
            isExpired: false
        )
        #expect(resolved == userId)
    }

    @Test("Signed-out initial session (no session) stays nil")
    func signedOutInitialSessionStaysNil() {
        // No stored session -> userId nil, isExpired defaults to true upstream.
        let resolved = AuthService.resolveUserId(
            event: .initialSession,
            userId: nil,
            isExpired: true
        )
        #expect(resolved == nil)
    }

    @Test("Non-initial events pass the user id through even if expired")
    func nonInitialEventsPassThrough() {
        // The isExpired guard only applies to .initialSession; a live
        // signIn/tokenRefreshed/etc. event is trusted as-is.
        for event: AuthChangeEvent in [.signedIn, .tokenRefreshed, .userUpdated] {
            #expect(
                AuthService.resolveUserId(event: event, userId: userId, isExpired: true) == userId
            )
        }
    }

    @Test("Sign-out event emits nil")
    func signOutEmitsNil() {
        let resolved = AuthService.resolveUserId(
            event: .signedOut,
            userId: nil,
            isExpired: true
        )
        #expect(resolved == nil)
    }
}
