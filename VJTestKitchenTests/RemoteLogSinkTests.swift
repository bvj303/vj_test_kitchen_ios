import Foundation
import Testing
@testable import VJTestKitchen

@Suite struct RemoteLogPayloadTests {
    @Test func mapsEventFields() {
        let event = LogEvent(
            level: .error, category: "svc", message: "down",
            metadata: ["a": "1"], occurredAt: Date(timeIntervalSince1970: 42),
            appVersion: "1.2 (4)", platform: "ios"
        )
        let payload = RemoteLogPayload(event: event)
        #expect(payload.level == "error")
        #expect(payload.category == "svc")
        #expect(payload.message == "down")
        #expect(payload.metadata == ["a": "1"])
        #expect(payload.platform == "ios")
        #expect(payload.appVersion == "1.2 (4)")
        #expect(payload.occurredAt == Date(timeIntervalSince1970: 42))
    }

    @Test func encodesWithoutUserId() throws {
        // user_id is DEFAULTed to auth.uid() server-side, so the client must not
        // send it — encoding must not emit a user_id key.
        let payload = RemoteLogPayload(event: LogEvent(
            level: .error, category: "c", message: "m", metadata: [:],
            occurredAt: Date(), appVersion: "1", platform: "ios"))
        let data = try JSONEncoder().encode(payload)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("user_id"))
        #expect(!json.contains("userId"))
    }
}

@Suite struct RemoteLogSinkTests {
    private func event(_ level: LogLevel) -> LogEvent {
        LogEvent(level: level, category: "c", message: "m", metadata: [:],
                 occurredAt: Date(), appVersion: "1", platform: "ios")
    }

    @Test func onlyErrorAndAboveMeetTheThreshold() {
        let sink = RemoteLogSink(transport: SpyLogTransport(), minimumLevel: .error, isAuthenticated: { true })
        #expect(!sink.shouldSend(event(.debug)))
        #expect(!sink.shouldSend(event(.info)))
        #expect(!sink.shouldSend(event(.notice)))
        #expect(!sink.shouldSend(event(.warning)))
        #expect(sink.shouldSend(event(.error)))
        #expect(sink.shouldSend(event(.fault)))
    }

    @Test func skipsWhenSignedOut() {
        let sink = RemoteLogSink(transport: SpyLogTransport(), minimumLevel: .error, isAuthenticated: { false })
        #expect(!sink.shouldSend(event(.error)))
    }

    @Test func sendsQualifyingEventToTransport() async {
        let transport = SpyLogTransport()
        let sink = RemoteLogSink(transport: transport, isAuthenticated: { true })
        await sink.send(event(.error))
        let sent = await transport.sent
        #expect(sent.count == 1)
        #expect(sent[0].level == "error")
    }

    @Test func doesNotSendBelowThresholdOrSignedOut() async {
        let transport = SpyLogTransport()
        let signedOut = RemoteLogSink(transport: transport, isAuthenticated: { false })
        await signedOut.send(event(.error))
        let authedBelow = RemoteLogSink(transport: transport, isAuthenticated: { true })
        await authedBelow.send(event(.warning))
        let sent = await transport.sent
        #expect(sent.isEmpty)
    }

    @Test func swallowsTransportFailure() async {
        struct Boom: Error {}
        let transport = SpyLogTransport(errorToThrow: Boom())
        let sink = RemoteLogSink(transport: transport, isAuthenticated: { true })
        // Must not throw — a failing log write can't propagate to the caller.
        await sink.send(event(.error))
        let sent = await transport.sent
        #expect(sent.count == 1)
    }
}
