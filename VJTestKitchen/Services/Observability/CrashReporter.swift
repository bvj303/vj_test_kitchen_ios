import Foundation
import MetricKit

/// A distilled, `Sendable` snapshot of one MetricKit diagnostic. MetricKit's
/// own payload types (`MXCrashDiagnostic` et al.) can't be constructed in
/// tests, so the MX-specific extraction is kept in a thin adapter
/// (`CrashReporter`) while everything unit-testable — how a diagnostic maps to
/// a log level and message — lives here as pure logic (same split as the Edge
/// Function's `search.ts`).
struct DiagnosticSummary: Sendable, Equatable {
    enum Kind: String, Sendable {
        case crash
        case hang
        case cpuException
        case diskWriteException
    }

    let kind: Kind
    /// One-line human-readable description (exception type/signal, hang
    /// duration, etc.) built by the adapter from the MX payload.
    let detail: String
    let metadata: [String: String]

    /// A crash/CPU spike is a fault; a hang or runaway disk write is a
    /// (recoverable) error. Drives which severity the event is logged at.
    var level: LogLevel {
        switch kind {
        case .crash, .cpuException: return .fault
        case .hang, .diskWriteException: return .error
        }
    }

    var message: String {
        "MetricKit \(kind.rawValue) diagnostic: \(detail)"
    }
}

extension AppLogger {
    /// Records a MetricKit diagnostic through the normal logging pipeline, so it
    /// lands in Console and (being `.error`/`.fault`) is persisted remotely.
    func record(diagnostic summary: DiagnosticSummary) {
        var metadata = summary.metadata
        metadata["diagnosticKind"] = summary.kind.rawValue
        log(summary.level, summary.message, category: "crash", metadata: metadata)
    }
}

/// Subscribes to MetricKit and turns delivered crash/hang/CPU/disk diagnostics
/// into logged, remotely-persisted events. MetricKit batches these and delivers
/// them on a later launch (crashes can arrive up to ~24h afterward), so this is
/// after-the-fact diagnostics, not live alerting — the deliberate trade for
/// using Apple's built-in pipeline instead of a third-party crash SDK (see the
/// observability decision in DECISIONS.md).
// @unchecked Sendable: the only stored state is an immutable, Sendable
// `AppLogger`; MetricKit delivers `didReceive` on a background queue, so this
// can't be main-actor-isolated. No mutable state means no data race.
final class CrashReporter: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = CrashReporter()

    private let logger: AppLogger

    init(logger: AppLogger = .shared) {
        self.logger = logger
        super.init()
    }

    /// Registers with MetricKit. Call once, early in app launch. Idempotent
    /// enough for our use (a duplicate `add` would just double-deliver, but we
    /// only call it from the App entry point).
    func start() {
        MXMetricManager.shared.add(self)
    }

    // MARK: MXMetricManagerSubscriber

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for summary in payloads.flatMap(Self.summaries(from:)) {
            logger.record(diagnostic: summary)
        }
    }

    /// Extracts our `DiagnosticSummary` values from a MetricKit payload. Touches
    /// MX types (hence not unit-tested — they're unconstructable in tests); the
    /// tested logic is `DiagnosticSummary`'s level/message mapping.
    static func summaries(from payload: MXDiagnosticPayload) -> [DiagnosticSummary] {
        var summaries: [DiagnosticSummary] = []

        for crash in payload.crashDiagnostics ?? [] {
            let meta = crash.metaData
            var detailParts: [String] = []
            if let type = crash.exceptionType { detailParts.append("exceptionType=\(type)") }
            if let code = crash.exceptionCode { detailParts.append("exceptionCode=\(code)") }
            if let signal = crash.signal { detailParts.append("signal=\(signal)") }
            if let reason = crash.terminationReason { detailParts.append("reason=\(reason)") }
            summaries.append(DiagnosticSummary(
                kind: .crash,
                detail: detailParts.isEmpty ? "unknown" : detailParts.joined(separator: " "),
                metadata: [
                    "osVersion": meta.osVersion,
                    "appBuild": meta.applicationBuildVersion,
                ]
            ))
        }

        for hang in payload.hangDiagnostics ?? [] {
            summaries.append(DiagnosticSummary(
                kind: .hang,
                detail: "duration=\(hang.hangDuration)",
                metadata: [
                    "osVersion": hang.metaData.osVersion,
                    "appBuild": hang.metaData.applicationBuildVersion,
                ]
            ))
        }

        for cpu in payload.cpuExceptionDiagnostics ?? [] {
            summaries.append(DiagnosticSummary(
                kind: .cpuException,
                detail: "totalCPUTime=\(cpu.totalCPUTime) sampledTime=\(cpu.totalSampledTime)",
                metadata: [
                    "osVersion": cpu.metaData.osVersion,
                    "appBuild": cpu.metaData.applicationBuildVersion,
                ]
            ))
        }

        for disk in payload.diskWriteExceptionDiagnostics ?? [] {
            summaries.append(DiagnosticSummary(
                kind: .diskWriteException,
                detail: "writesCaused=\(disk.totalWritesCaused)",
                metadata: [
                    "osVersion": disk.metaData.osVersion,
                    "appBuild": disk.metaData.applicationBuildVersion,
                ]
            ))
        }

        return summaries
    }
}
