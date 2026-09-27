import Foundation
import Testing
@testable import VJTestKitchen

/// The concierge must know the user's LOCAL calendar day to resolve "Tuesday" /
/// "this week" — the ai-chat function otherwise falls back to the UTC date,
/// which is already tomorrow during US evenings.
struct AIChatRequestTests {
    private func encodedJSON(_ request: AIChatRequest) throws -> [String: Any] {
        let data = try SupabaseDecoding.encoder.encode(request)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func encodesMessagesAndTheLocalDay() throws {
        // 2026-09-28 02:30 UTC is still the evening of Sep 27 in Chicago.
        let now = Date(timeIntervalSince1970: 1_790_562_600)
        let request = AIChatRequest(
            messages: [.user("plan tuesday")],
            now: now,
            timeZone: try #require(TimeZone(identifier: "America/Chicago"))
        )

        let json = try encodedJSON(request)
        #expect(json["today"] as? String == "2026-09-27")
        let messages = try #require(json["messages"] as? [[String: String]])
        #expect(messages == [["role": "user", "content": "plan tuesday"]])
    }

    @Test func usesTheGivenTimeZoneNotUTC() throws {
        let now = Date(timeIntervalSince1970: 1_790_562_600) // 2026-09-28 02:30 UTC
        let utc = AIChatRequest(messages: [.user("hi")], now: now, timeZone: try #require(TimeZone(identifier: "UTC")))
        #expect(utc.today == "2026-09-28")
    }
}
