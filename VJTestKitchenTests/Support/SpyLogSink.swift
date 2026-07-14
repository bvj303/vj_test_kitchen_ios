import Foundation
@testable import VJTestKitchen

/// Captures every event written to it so tests can assert what was logged.
/// Lock-guarded (not an actor) because `LogSink.write` is a synchronous,
/// non-isolated requirement; the lock keeps it `Sendable`-safe when a sink is
/// hit from more than one context.
final class SpyLogSink: LogSink, @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [LogEvent] = []

    var events: [LogEvent] {
        lock.lock(); defer { lock.unlock() }
        return _events
    }

    func write(_ event: LogEvent) {
        lock.lock(); defer { lock.unlock() }
        _events.append(event)
    }
}

/// Spy `RemoteLogTransport`: records the payloads it's asked to send, and can be
/// primed to throw so the sink's swallow-on-failure behavior is testable. An
/// actor so `send` (the only mutation point) is race-free without a lock.
actor SpyLogTransport: RemoteLogTransport {
    private(set) var sent: [RemoteLogPayload] = []
    var errorToThrow: Error?

    init(errorToThrow: Error? = nil) {
        self.errorToThrow = errorToThrow
    }

    func send(_ payload: RemoteLogPayload) async throws {
        sent.append(payload)
        if let errorToThrow { throw errorToThrow }
    }
}
