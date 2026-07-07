import Foundation
import Supabase

/// Abstraction over Supabase Auth so AuthViewModel can be tested without a
/// real network/session — see AuthViewModelTests' FakeAuthService.
protocol AuthServicing: Sendable {
    /// firstName/lastName/username are stored as auth user metadata and
    /// copied into `profiles` by the `handle_new_user` trigger — see the
    /// profiles_first_last_username migration.
    func signUp(email: String, password: String, firstName: String, lastName: String, username: String) async throws
    func signIn(email: String, password: String) async throws
    func signOut() async throws
    /// Deletes the signed-in user's account (Edge Function, requires
    /// service_role — see supabase/functions/delete-account) and clears the
    /// local session. Required by App Store Guideline 5.1.1(v).
    func deleteAccount() async throws
    /// Emits the signed-in user's id (nil when signed out), including the
    /// current state as its first value on subscription.
    var userIdChanges: AsyncStream<UUID?> { get }
}

struct AuthService: AuthServicing {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseManager.client) {
        self.client = client
    }

    func signUp(email: String, password: String, firstName: String, lastName: String, username: String) async throws {
        try await client.auth.signUp(
            email: email,
            password: password,
            data: [
                "first_name": .string(firstName),
                "last_name": .string(lastName),
                "username": .string(username),
            ]
        )
    }

    func signIn(email: String, password: String) async throws {
        try await client.auth.signIn(email: email, password: password)
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    func deleteAccount() async throws {
        try await client.functions.invoke("delete-account")
        // The Edge Function deletes the auth.users row server-side, which
        // doesn't by itself invalidate the SDK's local session state — sign
        // out explicitly so userIdChanges emits nil and the UI returns to
        // AuthView, same as any other sign-out.
        try await client.auth.signOut()
    }

    /// Pure decision for which user id to emit for a given auth event, split
    /// out so it's unit-testable without a live `SupabaseClient`/`Session`.
    ///
    /// With `emitLocalSessionAsInitialSession` enabled (see SupabaseManager),
    /// the SDK emits the locally stored session on launch even when it's
    /// expired. Treat an expired `.initialSession` as signed-out so a stale
    /// session doesn't briefly flash the signed-in UI; every other event maps
    /// straight to its session's user id (nil when signed out).
    static func resolveUserId(event: AuthChangeEvent, userId: UUID?, isExpired: Bool) -> UUID? {
        if event == .initialSession, isExpired {
            return nil
        }
        return userId
    }

    var userIdChanges: AsyncStream<UUID?> {
        AsyncStream { continuation in
            let task = Task {
                for await (event, session) in client.auth.authStateChanges {
                    continuation.yield(
                        AuthService.resolveUserId(
                            event: event,
                            userId: session?.user.id,
                            isExpired: session?.isExpired ?? true
                        )
                    )
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
