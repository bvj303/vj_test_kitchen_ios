import Foundation
import Testing
@testable import VJTestKitchen

final class FakeAIService: AIServicing, @unchecked Sendable {
    /// The full conversation sent on each call.
    private(set) var receivedHistories: [[AIChatTurn]] = []
    /// Convenience view: the latest user message content of each call, so existing
    /// assertions that only care about "what did the user ask" stay simple.
    var receivedPrompts: [String] { receivedHistories.map { $0.last?.content ?? "" } }
    var responseToReturn = "Here's a plan!"
    var recipesToReturn: [AIRecipeRef] = []
    var errorToThrow: Error?

    func sendMessage(_ history: [AIChatTurn]) async throws -> AIChatResponse {
        receivedHistories.append(history)
        if let errorToThrow { throw errorToThrow }
        return AIChatResponse(text: responseToReturn, recipes: recipesToReturn)
    }
}

private struct TestError: Error, LocalizedError {
    var errorDescription: String? { "failed" }
}

@MainActor
struct AIPlannerViewModelTests {
    @Test func startsWithNoMessages() {
        let viewModel = AIPlannerViewModel(aiService: FakeAIService())
        #expect(viewModel.messages.isEmpty)
    }

    @Test func sendAppendsUserMessageThenAssistantReply() async {
        let ai = FakeAIService()
        ai.responseToReturn = "Try the Carbonara!"
        let viewModel = AIPlannerViewModel(aiService: ai)
        viewModel.inputText = "What should I cook tonight?"

        await viewModel.send()

        #expect(viewModel.messages.count == 2)
        #expect(viewModel.messages[0].role == .user)
        #expect(viewModel.messages[0].content == "What should I cook tonight?")
        #expect(viewModel.messages[1].role == .assistant)
        #expect(viewModel.messages[1].content == "Try the Carbonara!")
        #expect(viewModel.inputText.isEmpty)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func sendLogsErrorWhenRequestFails() async {
        struct SendError: Error {}
        let ai = FakeAIService()
        ai.errorToThrow = SendError()
        let sink = SpyLogSink()
        let logger = AppLogger(sinks: [sink], context: LogContext(appVersion: "1", platform: "test"))
        let viewModel = AIPlannerViewModel(aiService: ai, logger: logger)
        viewModel.inputText = "What should I cook?"

        await viewModel.send()

        // A failing Edge Function is surfaced via errorMessage AND logged raw.
        #expect(sink.events.contains { $0.level == .error && $0.category == "ai" })
    }

    @Test func sendPassesFullConversationHistorySoFollowUpsHaveContext() async {
        let ai = FakeAIService()
        ai.responseToReturn = "Try the Kale Salad."
        let viewModel = AIPlannerViewModel(aiService: ai)

        viewModel.inputText = "something healthy"
        await viewModel.send()

        viewModel.inputText = "something else"
        await viewModel.send()

        // First call carries just the opening user turn…
        #expect(ai.receivedHistories[0] == [.user("something healthy")])
        // …the second carries the whole conversation so far, ending on the new
        // user turn — this is what lets the concierge avoid repeating itself.
        #expect(ai.receivedHistories[1] == [
            .user("something healthy"),
            .assistant("Try the Kale Salad."),
            .user("something else"),
        ])
    }

    @Test func historyPayloadCapsToMostRecentTurns() {
        let messages = (1...20).map { i in
            AIPlannerViewModel.ChatMessage(role: .user, content: "msg \(i)")
        }
        let payload = AIPlannerViewModel.historyPayload(from: messages, maxTurns: 12)
        #expect(payload.count == 12)
        #expect(payload.first == .user("msg 9"))
        #expect(payload.last == .user("msg 20"))
    }

    @Test func sendIgnoresBlankInput() async {
        let ai = FakeAIService()
        let viewModel = AIPlannerViewModel(aiService: ai)
        viewModel.inputText = "   "

        await viewModel.send()

        #expect(viewModel.messages.isEmpty)
        #expect(ai.receivedPrompts.isEmpty)
    }

    @Test func sendSurfacesErrorMessageButKeepsUserMessage() async {
        let ai = FakeAIService()
        ai.errorToThrow = TestError()
        let viewModel = AIPlannerViewModel(aiService: ai)
        viewModel.inputText = "Plan my week"

        await viewModel.send()

        #expect(viewModel.messages.count == 1)
        #expect(viewModel.messages[0].role == .user)
        #expect(viewModel.errorMessage == "failed")
    }

    @Test func assistantReplyAttachesOnlyRecipesItNames() async {
        let ai = FakeAIService()
        ai.responseToReturn = "I'd go with the Beef Tacos tonight."
        ai.recipesToReturn = [
            AIRecipeRef(id: 2, title: "Beef Tacos"),      // named in the reply
            AIRecipeRef(id: 9, title: "Chicken Alfredo"), // searched but not named
        ]
        let viewModel = AIPlannerViewModel(aiService: ai)
        viewModel.inputText = "tacos please"

        await viewModel.send()

        #expect(viewModel.messages[1].recipes == [AIRecipeRef(id: 2, title: "Beef Tacos")])
    }

    @Test func recipesReferencedIsCaseInsensitiveAndDeduped() {
        let text = "The beef TACOS are great, and beef tacos again."
        let refs = [
            AIRecipeRef(id: 2, title: "Beef Tacos"),
            AIRecipeRef(id: 2, title: "Beef Tacos"),
            AIRecipeRef(id: 5, title: "Sushi"),
        ]
        let result = AIPlannerViewModel.recipesReferenced(in: text, from: refs)
        #expect(result == [AIRecipeRef(id: 2, title: "Beef Tacos")])
    }

    @Test func clearChatRemovesAllMessages() async {
        let ai = FakeAIService()
        let viewModel = AIPlannerViewModel(aiService: ai)
        viewModel.inputText = "Hi"
        await viewModel.send()
        #expect(!viewModel.messages.isEmpty)

        viewModel.clearChat()

        #expect(viewModel.messages.isEmpty)
    }
}
