import Foundation
import os

/// Writes every event to Apple's unified logging system (`os.Logger`),
/// retrievable via Console.app or the `log` CLI. One `Logger` per category,
/// all under the app's bundle-id subsystem, so logs can be filtered by
/// subsystem/category. This is the always-on local tier; it never drops events
/// and needs no session or network.
struct OSLogSink: LogSink {
    private let subsystem: String

    init(subsystem: String = Bundle.main.bundleIdentifier ?? "com.bvj303.vjtestkitchen") {
        self.subsystem = subsystem
    }

    func write(_ event: LogEvent) {
        let logger = Logger(subsystem: subsystem, category: event.category)
        let line = Self.formatted(event)
        // The message is developer-authored (not user secrets), so log it
        // public — a redacted "<private>" log is useless for diagnosis.
        logger.log(level: event.level.osLogType, "\(line, privacy: .public)")
    }

    /// Renders an event as a single console line: `[LEVEL] message {k=v, …}`.
    /// Pure and static so it's unit-testable without touching the log store.
    static func formatted(_ event: LogEvent) -> String {
        var line = "[\(event.level.rawValue.uppercased())] \(event.message)"
        if !event.metadata.isEmpty {
            let pairs = event.metadata
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ", ")
            line += " {\(pairs)}"
        }
        return line
    }
}
