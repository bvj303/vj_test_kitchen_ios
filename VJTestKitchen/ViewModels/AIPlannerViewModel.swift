import Foundation
import Observation

@MainActor
@Observable
final class AIPlannerViewModel {
    enum Role: Equatable {
        case user
        case assistant
    }

    struct ChatMessage: Identifiable, Equatable {
        let id = UUID()
        var role: Role
        var content: String
    }

    private(set) var messages: [ChatMessage] = []
    var inputText = ""
    private(set) var isSending = false
    var errorMessage: String?

    private let aiService: AIServicing

    init(aiService: AIServicing = AIService()) {
        self.aiService = aiService
    }

    func send() async {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isSending else { return }

        errorMessage = nil
        messages.append(ChatMessage(role: .user, content: prompt))
        inputText = ""
        isSending = true
        defer { isSending = false }

        do {
            let response = try await aiService.sendMessage(prompt)
            messages.append(ChatMessage(role: .assistant, content: response))
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    func clearChat() {
        messages = []
    }
}
