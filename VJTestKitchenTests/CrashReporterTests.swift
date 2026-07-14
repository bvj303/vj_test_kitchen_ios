import Foundation
import Testing
@testable import VJTestKitchen

@Suite struct DiagnosticSummaryTests {
    @Test func crashAndCPUAreFaults() {
        #expect(DiagnosticSummary(kind: .crash, detail: "", metadata: [:]).level == .fault)
        #expect(DiagnosticSummary(kind: .cpuException, detail: "", metadata: [:]).level == .fault)
    }

    @Test func hangAndDiskWriteAreErrors() {
        #expect(DiagnosticSummary(kind: .hang, detail: "", metadata: [:]).level == .error)
        #expect(DiagnosticSummary(kind: .diskWriteException, detail: "", metadata: [:]).level == .error)
    }

    @Test func messageIncludesKindAndDetail() {
        let summary = DiagnosticSummary(kind: .crash, detail: "signal=11", metadata: [:])
        #expect(summary.message == "MetricKit crash diagnostic: signal=11")
    }
}

@Suite struct AppLoggerDiagnosticRoutingTests {
    @Test func recordsDiagnosticAtItsLevelWithKindMetadata() {
        let sink = SpyLogSink()
        let logger = AppLogger(sinks: [sink], context: LogContext(appVersion: "1", platform: "p"))
        logger.record(diagnostic: DiagnosticSummary(
            kind: .crash, detail: "signal=11", metadata: ["osVersion": "26.0"]))

        #expect(sink.events.count == 1)
        let event = sink.events[0]
        #expect(event.level == .fault)
        #expect(event.category == "crash")
        #expect(event.message == "MetricKit crash diagnostic: signal=11")
        #expect(event.metadata["diagnosticKind"] == "crash")
        #expect(event.metadata["osVersion"] == "26.0")
    }
}
