import Foundation
import Supabase

/// The signed-in resolution of an auth-state event, as consumed by
/// `AuthViewModel` to drive the root gate. A richer signal than a bare
/// `UUID?` specifically so the launch flow can distinguish "genuinely signed
/// out" from "we have a stored session that just needs a token refresh" —
/// without which an expired-but-refreshable session briefly flashes the login
/// screen on cold launch. See `AuthService.resolve`.
enum AuthResolution: Equatable, Sendable {
    case signedIn(userId: UUID)
    case signedOut
    /// An expired session was restored at launch (`emitLocalSessionAsInitialSession`)
    /// and a token refresh is in flight. The UI should hold the launch screen
    /// rather than drop to the login screen; the carried id backs an optimistic
    /// sign-in fallback if the refresh doesn't resolve promptly (e.g. offline).
    case refreshPending(userId: UUID)
}

/// Abstraction over Supabase Auth so AuthViewModel can be tested without a
/// real network/session — see AuthViewModelTests' FakeAuthService.
protocol AuthServicing: Sendable {
    /// firstName/lastName/username are stored as auth user metadata and
    /// copied into `profiles` by the `handle_new_user` trigger — see the
    /// profiles_first_last_username migration.
    ///
    /// Returns `true` when the project requires email confirmation
    /// (`enable_confirmations`, see config.toml) — the sign-up succeeded but no
    /// session is established until the user clicks the emailed link, so the
    /// caller should show a "check your email" state rather than expecting to
    /// land on the signed-in UI. Returns `false` when a session was created
    /// immediately (confirmations off).
    @discardableResult
    func signUp(email: String, password: String, firstName: String, lastName: String, username: String) async throws -> Bool
    func signIn(email: String, password: String) async throws
    func signOut() async throws
    /// Deletes the signed-in user's account (Edge Function, requires
    /// service_role — see supabase/functions/delete-account) and clears the
    /// local session. Required by App Store Guideline 5.1.1(v).
    func deleteAccount() async throws
    /// Completes an auth deep link opened from an email (e.g. the sign-up
    /// confirmation link redirecting to `vjtestkitchen://login-callback`): parses
    /// the tokens/`code` out of `url` and establishes a session, which flips
    /// `userIdChanges` to signed-in. No-op-safe to call with an unrelated URL
    /// (it throws, which the caller ignores).
    func handleAuthCallback(url: URL) async throws
    /// Proactively resolves (and refreshes, if stale) the stored session at
    /// launch. Accessing `client.auth.session` auto-refreshes an expired access
    /// token, which fires the SDK's `.tokenRefreshed` event and re-pushes the
    /// fresh token to the Functions client (`functions.setAuth`). Without this,
    /// the Functions client can keep serving a stale/anon token from the initial
    /// stored session until some *other* PostgREST call happens to trigger a
    /// refresh — which is why the AI Planner's server-side recipe search returned
    /// zero rows ("you have no recipes") until the Recipes tab was opened. See
    /// the per-call safety net in `AIService.sendMessage` too.
    func warmUpSession() async throws
    /// Emits the resolved auth state for each auth-state event, including the
    /// current state as its first value on subscription. See `AuthResolution`.
    var authResolutions: AsyncStream<AuthResolution> { get }
}

struct AuthService: AuthServicing {
    /// Where email confirmation (and any future magic-link/recovery) links
    /// redirect: a custom URL scheme registered in Info.plist so the OS routes
    /// the link back into the app. Must be on the hosted project's redirect
    /// allow-list (Auth settings) for GoTrue to honor it.
    static let emailRedirectURL = URL(string: "vjtestkitchen://login-callback")!

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseManager.client) {
        self.client = client
    }

    @discardableResult
    func signUp(email: String, password: String, firstName: String, lastName: String, username: String) async throws -> Bool {
        let response = try await client.auth.signUp(
            email: email,
            password: password,
            data: [
                "first_name": .string(firstName),
                "last_name": .string(lastName),
                "username": .string(username),
            ],
            // The confirmation email links here; the app handles it in
            // handleAuthCallback(url:) and establishes the session.
            redirectTo: Self.emailRedirectURL
        )
        // With email confirmation on, GoTrue returns the new user but no session
        // until the emailed link is clicked; a nil session is the signal that
        // the user must confirm before they can sign in.
        return response.session == nil
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
        // out explicitly so authResolutions emits signed-out and the UI returns to
        // AuthView, same as any other sign-out.
        try await client.auth.signOut()
    }

    func handleAuthCallback(url: URL) async throws {
        // Parses the code/tokens out of the redirect URL and stores the session;
        // handles both PKCE (code exchange) and implicit (fragment tokens).
        try await client.auth.session(from: url)
    }

    func warmUpSession() async throws {
        // Getting `session` refreshes an expired access token and, via the SDK's
        // `.tokenRefreshed` event, re-pushes it to the Functions client — see the
        // protocol doc comment. Discarded: we only want the side effect.
        _ = try await client.auth.session
    }

    /// Pure decision for how to resolve a given auth event, split out so it's
    /// unit-testable without a live `SupabaseClient`/`Session`.
    ///
    /// With `emitLocalSessionAsInitialSession` enabled (see SupabaseManager),
    /// the SDK emits the locally stored session on launch even when it's
    /// expired. An expired `.initialSession` is *not* signed-out — the refresh
    /// token is typically still valid, so a refresh is imminent; report
    /// `.refreshPending` so the UI holds the launch screen instead of flashing
    /// the login screen (and, symmetrically, doesn't flash the signed-in UI for
    /// a session that turns out to be dead — that only happens once a real
    /// signed-in/token-refreshed event lands). Only a truly empty
    /// `.initialSession` (no stored session) is `.signedOut`. Every other event
    /// maps straight to its session's user id (signed out when nil).
    static func resolve(event: AuthChangeEvent, userId: UUID?, isExpired: Bool) -> AuthResolution {
        if event == .initialSession, isExpired {
            return userId.map { .refreshPending(userId: $0) } ?? .signedOut
        }
        return userId.map { .signedIn(userId: $0) } ?? .signedOut
    }

    var authResolutions: AsyncStream<AuthResolution> {
        AsyncStream { continuation in
            let task = Task {
                for await (event, session) in client.auth.authStateChanges {
                    continuation.yield(
                        AuthService.resolve(
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
