import Foundation

/// A recipe the assistant surfaced (from its `searchRecipes` tool). The Planner
/// renders tappable cards for the ones actually named in the reply.
struct AIRecipeRef: Decodable, Sendable, Hashable, Identifiable {
    let id: Int64
    let title: String
}

/// The assistant's reply plus any recipes it referenced this turn.
struct AIChatResponse: Sendable {
    let text: String
    let recipes: [AIRecipeRef]
}

/// One turn of the Kitchen Concierge conversation. `role` is `"user"` or
/// `"assistant"`. Carrying the whole history (not just the latest prompt) is
/// what lets follow-ups like "give me a different one" be answered with context
/// of what was already suggested.
struct AIChatTurn: Encodable, Sendable, Equatable {
    let role: String
    let content: String

    static func user(_ content: String) -> AIChatTurn { AIChatTurn(role: "user", content: content) }
    static func assistant(_ content: String) -> AIChatTurn { AIChatTurn(role: "assistant", content: content) }
}

/// The Kitchen Concierge back end. As of the iOS 27 line this is Apple
/// Intelligence's **on-device** Foundation Model (`AppleIntelligenceAIService`)
/// — the Gemini Supabase Edge Function it replaced is gone. See
/// DECISIONS.md (2026-07-13) and the AI Planner conventions bullet.
protocol AIServicing: Sendable {
    /// Sends the conversation history to the assistant and returns its reply
    /// plus any recipes it referenced. The last turn must be the user's current
    /// message.
    func sendMessage(_ history: [AIChatTurn]) async throws -> AIChatResponse

    /// Non-`nil` when the assistant can't run on this device — a user-facing
    /// explanation to show *instead* of the chat (e.g. the on-device model
    /// isn't supported here, or Apple Intelligence is turned off). `nil` means
    /// the concierge is usable. Defaulted so test fakes needn't implement it.
    var unavailableReason: String? { get }
}

extension AIServicing {
    var unavailableReason: String? { nil }

    /// Single-turn convenience for callers with no conversation to carry (e.g.
    /// the Siri intent), which just wraps the prompt as one user turn.
    func sendMessage(_ prompt: String) async throws -> AIChatResponse {
        try await sendMessage([.user(prompt)])
    }
}
