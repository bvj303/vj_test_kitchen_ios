import Foundation
import os

/// Severity of a log event, ordered from most verbose to most severe. The
/// ordering (`Comparable`) is what lets a sink filter — e.g. the remote sink
/// only persists `.error` and above.
enum LogLevel: String, Comparable, Sendable, CaseIterable {
    case debug, info, notice, warning, error, fault

    private var severity: Int {
        switch self {
        case .debug:   return 0
        case .info:    return 1
        case .notice:  return 2
        case .warning: return 3
        case .error:   return 4
        case .fault:   return 5
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.severity < rhs.severity }

    /// Maps onto Apple's unified-logging levels for `OSLogSink`.
    var osLogType: OSLogType {
        switch self {
        case .debug:            return .debug
        case .info:             return .info
        case .notice:           return .default
        case .warning:          return .default
        case .error:            return .error
        case .fault:            return .fault
        }
    }
}

/// Ambient context stamped onto every event — the app build and platform the
/// event came from, so a persisted log row is self-describing. Read from
/// `Bundle.main` by default; injectable for tests.
struct LogContext: Sendable {
    let appVersion: String
    let platform: String

    init(appVersion: String, platform: String) {
        self.appVersion = appVersion
        self.platform = platform
    }

    static func current(bundle: Bundle = .main) -> LogContext {
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        #if os(macOS)
        let platform = "macos"
        #else
        let platform = "ios"
        #endif
        return LogContext(appVersion: "\(short) (\(build))", platform: platform)
    }
}

/// A single structured log record. Immutable and `Sendable` so it can cross
/// actor/thread boundaries into an async sink. Timestamps are UTC (`Date` is
/// zone-agnostic; only the display/encoding layer localizes).
struct LogEvent: Sendable {
    let level: LogLevel
    let category: String
    let message: String
    let metadata: [String: String]
    let occurredAt: Date
    let appVersion: String
    let platform: String
}

/// A destination for log events. Implementations must be non-blocking and
/// best-effort — a logging call is fire-and-forget and must never throw or
/// stall a caller (matches the WidgetPublisher/SnapshotStore ethos).
protocol LogSink: Sendable {
    func write(_ event: LogEvent)
}

/// The service-layer logging facade. Fans an event out to every configured
/// sink after stamping it with ambient context. Used app-wide via `.shared`;
/// tests construct their own instance with a spy sink.
///
/// Deliberately synchronous and non-throwing at the call site: logging is
/// observability plumbing, never something a feature waits on or handles.
struct AppLogger: Sendable {
    private let sinks: [any LogSink]
    private let context: LogContext
    private let clock: @Sendable () -> Date

    init(
        sinks: [any LogSink],
        context: LogContext = .current(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.sinks = sinks
        self.context = context
        self.clock = clock
    }

    func log(
        _ level: LogLevel,
        _ message: String,
        category: String,
        metadata: [String: String] = [:]
    ) {
        let event = LogEvent(
            level: level,
            category: category,
            message: message,
            metadata: metadata,
            occurredAt: clock(),
            appVersion: context.appVersion,
            platform: context.platform
        )
        for sink in sinks { sink.write(event) }
    }

    func debug(_ message: String, category: String, metadata: [String: String] = [:]) {
        log(.debug, message, category: category, metadata: metadata)
    }

    func info(_ message: String, category: String, metadata: [String: String] = [:]) {
        log(.info, message, category: category, metadata: metadata)
    }

    func notice(_ message: String, category: String, metadata: [String: String] = [:]) {
        log(.notice, message, category: category, metadata: metadata)
    }

    func warning(_ message: String, category: String, metadata: [String: String] = [:]) {
        log(.warning, message, category: category, metadata: metadata)
    }

    /// Logs an error-level event. When an `Error` is supplied its type and
    /// description are folded into the metadata — deliberately not the friendly
    /// `ErrorPresenter` copy (that's for humans in the UI; this is for
    /// diagnosis). Callers should avoid interpolating user input / secrets into
    /// `message`.
    func error(
        _ message: String,
        category: String,
        error: Error? = nil,
        metadata: [String: String] = [:]
    ) {
        var meta = metadata
        if let error {
            meta["errorType"] = String(describing: type(of: error))
            meta["errorDescription"] = error.localizedDescription
        }
        log(.error, message, category: category, metadata: meta)
    }

    func fault(_ message: String, category: String, metadata: [String: String] = [:]) {
        log(.fault, message, category: category, metadata: metadata)
    }
}

extension AppLogger {
    /// App-wide shared logger: an os.Logger console sink plus a remote sink that
    /// persists `.error`+ events to Supabase for the signed-in user. Constructed
    /// lazily so it isn't built during unit-test type loading.
    static let shared = AppLogger(sinks: [
        OSLogSink(),
        RemoteLogSink(),
    ])
}
