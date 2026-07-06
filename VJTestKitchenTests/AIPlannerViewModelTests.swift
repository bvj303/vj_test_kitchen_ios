import Foundation
import Testing
@testable import VJTestKitchen

final class FakeAIService: AIServicing, @unchecked Sendable {
    private(set) var receivedPrompts: [String] = []
    var responseToReturn = "Here's a plan!"
    var errorToThrow: Error?

    func sendMessage(_ prompt: String) async throws -> String {
        receivedPrompts.append(prompt)
        if let errorToThrow { throw errorToThrow }
        return responseToReturn
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
