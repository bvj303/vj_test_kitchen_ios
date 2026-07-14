import Foundation
import Supabase

/// The row shape POSTed to the `client_logs` table. Deliberately omits
/// `user_id` — the table DEFAULTs it to `auth.uid()`, so the server attributes
/// the row to the signed-in caller and RLS's WITH CHECK enforces it can't be
/// spoofed. `metadata` maps to the jsonb column; `occurredAt` is the on-device
/// event time (UTC), distinct from the server's `created_at` insert time.
struct RemoteLogPayload: Encodable, Sendable, Equatable {
    let level: String
    let category: String
    let message: String
    let metadata: [String: String]
    let platform: String
    let appVersion: String
    let occurredAt: Date

    init(event: LogEvent) {
        self.level = event.level.rawValue
        self.category = event.category
        self.message = event.message
        self.metadata = event.metadata
        self.platform = event.platform
        self.appVersion = event.appVersion
        self.occurredAt = event.occurredAt
    }
}

/// Abstracts the actual network write so `RemoteLogSink`'s gating logic can be
/// unit-tested against a spy instead of a live Supabase client.
protocol RemoteLogTransport: Sendable {
    func send(_ payload: RemoteLogPayload) async throws
}

/// Real transport: inserts one row into `client_logs` via PostgREST. Uses the
/// shared Supabase client so the insert carries the user's JWT (making
/// `auth.uid()` — and thus the row's `user_id` default — resolve to them).
///
/// The client is fetched through a provider closure, evaluated only inside
/// `send` after the configuration guard — so merely constructing this (e.g.
/// when `AppLogger.shared` is referenced from a unit test) never builds
/// `SupabaseManager.client`, which would `fatalError` without the app's config.
struct SupabaseLogTransport: RemoteLogTransport {
    private let clientProvider: @Sendable () -> SupabaseClient

    init(clientProvider: @escaping @Sendable () -> SupabaseClient = { SupabaseManager.client }) {
        self.clientProvider = clientProvider
    }

    func send(_ payload: RemoteLogPayload) async throws {
        guard AppConfig.isConfigured else { return }
        try await clientProvider()
            .from("client_logs")
            .insert(payload)
            .execute()
    }
}

/// Persists error-level events out to Supabase so failures are diagnosable
/// after the fact, not just while tethered to Console. Best-effort by design:
///
///  - Only `.error`/`.fault` cross the wire — verbose local logging stays local
///    (avoids cost/noise and needless writes).
///  - Skips entirely when signed out: the table requires an authenticated
///    session (no `auth.uid()` → the insert would fail anyway).
///  - Never throws and never logs its own failures — a logging path that could
///    itself error or recurse would be worse than a dropped log line.
struct RemoteLogSink: LogSink {
    private let transport: RemoteLogTransport
    private let minimumLevel: LogLevel
    private let isAuthenticated: @Sendable () -> Bool

    init(
        transport: RemoteLogTransport = SupabaseLogTransport(),
        minimumLevel: LogLevel = .error,
        isAuthenticated: @escaping @Sendable () -> Bool = {
            // Guard on config first so the test process (no Info.plist config)
            // never constructs the fatal-on-missing-config Supabase client.
            AppConfig.isConfigured && SupabaseManager.client.auth.currentUser != nil
        }
    ) {
        self.transport = transport
        self.minimumLevel = minimumLevel
        self.isAuthenticated = isAuthenticated
    }

    func write(_ event: LogEvent) {
        Task { await send(event) }
    }

    /// The async body of `write`, split out so tests can await it
    /// deterministically rather than racing a fire-and-forget `Task`.
    func send(_ event: LogEvent) async {
        guard shouldSend(event) else { return }
        try? await transport.send(RemoteLogPayload(event: event))
    }

    /// Pure gate: is this event severe enough, and are we in a session that can
    /// actually write it? Unit-tested directly.
    func shouldSend(_ event: LogEvent) -> Bool {
        event.level >= minimumLevel && isAuthenticated()
    }
}
