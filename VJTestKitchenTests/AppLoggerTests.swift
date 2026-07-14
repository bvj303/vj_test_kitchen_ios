import Foundation
import Testing
@testable import VJTestKitchen

@Suite struct LogLevelTests {
    @Test func severityOrdering() {
        #expect(LogLevel.debug < .info)
        #expect(LogLevel.info < .notice)
        #expect(LogLevel.notice < .warning)
        #expect(LogLevel.warning < .error)
        #expect(LogLevel.error < .fault)
    }

    @Test func errorMeetsErrorThreshold() {
        #expect(LogLevel.error >= .error)
        #expect(LogLevel.fault >= .error)
        #expect(!(LogLevel.warning >= .error))
    }
}

@Suite struct AppLoggerTests {
    private func makeLogger(_ sink: SpyLogSink) -> AppLogger {
        AppLogger(
            sinks: [sink],
            context: LogContext(appVersion: "9.9 (99)", platform: "testos"),
            clock: { Date(timeIntervalSince1970: 1_000) }
        )
    }

    @Test func fansOutToSinkWithStampedContext() {
        let sink = SpyLogSink()
        makeLogger(sink).info("hello", category: "test", metadata: ["k": "v"])

        #expect(sink.events.count == 1)
        let event = sink.events[0]
        #expect(event.level == .info)
        #expect(event.category == "test")
        #expect(event.message == "hello")
        #expect(event.metadata == ["k": "v"])
        #expect(event.appVersion == "9.9 (99)")
        #expect(event.platform == "testos")
        #expect(event.occurredAt == Date(timeIntervalSince1970: 1_000))
    }

    @Test func convenienceMethodsSetLevel() {
        let sink = SpyLogSink()
        let logger = makeLogger(sink)
        logger.debug("d", category: "c")
        logger.notice("n", category: "c")
        logger.warning("w", category: "c")
        logger.fault("f", category: "c")

        #expect(sink.events.map(\.level) == [.debug, .notice, .warning, .fault])
    }

    @Test func errorFoldsErrorTypeAndDescriptionIntoMetadata() {
        struct SampleError: Error, LocalizedError {
            var errorDescription: String? { "boom" }
        }
        let sink = SpyLogSink()
        makeLogger(sink).error("op failed", category: "svc", error: SampleError(), metadata: ["endpoint": "x"])

        let event = sink.events[0]
        #expect(event.level == .error)
        #expect(event.metadata["endpoint"] == "x")
        #expect(event.metadata["errorType"] == "SampleError")
        #expect(event.metadata["errorDescription"] == "boom")
    }

    @Test func fansOutToEverySink() {
        let a = SpyLogSink()
        let b = SpyLogSink()
        AppLogger(sinks: [a, b], context: LogContext(appVersion: "1", platform: "p")).error("e", category: "c")
        #expect(a.events.count == 1)
        #expect(b.events.count == 1)
    }
}

@Suite struct OSLogSinkFormattingTests {
    private func event(_ level: LogLevel, _ message: String, metadata: [String: String] = [:]) -> LogEvent {
        LogEvent(level: level, category: "c", message: message, metadata: metadata,
                 occurredAt: Date(), appVersion: "1", platform: "p")
    }

    @Test func formatsLevelAndMessage() {
        #expect(OSLogSink.formatted(event(.error, "kaboom")) == "[ERROR] kaboom")
    }

    @Test func appendsSortedMetadata() {
        let line = OSLogSink.formatted(event(.warning, "msg", metadata: ["b": "2", "a": "1"]))
        #expect(line == "[WARNING] msg {a=1, b=2}")
    }
}
