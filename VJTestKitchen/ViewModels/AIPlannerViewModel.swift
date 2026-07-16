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
        /// Recipes the assistant named in this message — rendered as tappable
        /// cards. Empty for user messages and replies that don't cite a recipe.
        var recipes: [AIRecipeRef] = []
    }

    private(set) var messages: [ChatMessage] = []
    var inputText = ""
    private(set) var isSending = false
    var errorMessage: String?
    /// Non-`nil` when the on-device assistant can't run on this device — the
    /// view shows this copy instead of the chat. Refreshed from the service in
    /// `refreshAvailability()` (called from the view's `.task`) since Apple
    /// Intelligence can finish setting up, or be enabled, after launch.
    private(set) var unavailableReason: String?

    private let aiService: AIServicing
    private let logger: AppLogger

    init(aiService: AIServicing = AppleIntelligenceAIService(), logger: AppLogger = .shared) {
        self.aiService = aiService
        self.logger = logger
    }

    func refreshAvailability() {
        unavailableReason = aiService.unavailableReason
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
            // Send the whole conversation (the user turn was just appended above),
            // not just this prompt, so the concierge can vary its answer when the
            // user asks again / for "something else" — see AIChatTurn.
            let response = try await aiService.sendMessage(Self.historyPayload(from: messages))
            messages.append(ChatMessage(
                role: .assistant,
                content: response.text,
                recipes: Self.recipesReferenced(in: response.text, from: response.recipes)
            ))
        } catch {
            // Surfaced via errorMessage, but logged raw — a failing Edge Function
            // (non-200, timeout, bad payload) is otherwise invisible to us.
            logger.error("AI planner request failed", category: "ai", error: error)
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// Most recent turns of the chat, mapped to the wire format. Capped to bound
    /// token cost on long conversations (the server also enforces its own cap).
    static func historyPayload(from messages: [ChatMessage], maxTurns: Int = 12) -> [AIChatTurn] {
        messages.suffix(maxTurns).map { message in
            switch message.role {
            case .user: return .user(message.content)
            case .assistant: return .assistant(message.content)
            }
        }
    }

    func clearChat() {
        messages = []
    }

    /// Filters the tool-surfaced recipes down to the ones the assistant actually
    /// names in its reply (case-insensitive title match), so the cards match the
    /// recommendation rather than everything the tool happened to return.
    static func recipesReferenced(in text: String, from recipes: [AIRecipeRef]) -> [AIRecipeRef] {
        guard !recipes.isEmpty else { return [] }
        var seen = Set<Int64>()
        return recipes.filter { recipe in
            guard !recipe.title.isEmpty,
                  text.localizedCaseInsensitiveContains(recipe.title),
                  !seen.contains(recipe.id) else { return false }
            seen.insert(recipe.id)
            return true
        }
    }
}
