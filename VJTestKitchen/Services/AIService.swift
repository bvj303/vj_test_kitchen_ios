import Foundation
import Supabase

/// A recipe the assistant surfaced (from its `search_recipes` tool). The Planner
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

/// One turn of the Kitchen Concierge conversation, as sent to the Edge Function.
/// `role` is `"user"` or `"assistant"`. Sending the whole history (not just the
/// latest prompt) is what lets follow-ups like "give me a different one" be
/// answered with context of what was already suggested.
struct AIChatTurn: Encodable, Sendable, Equatable {
    let role: String
    let content: String

    static func user(_ content: String) -> AIChatTurn { AIChatTurn(role: "user", content: content) }
    static func assistant(_ content: String) -> AIChatTurn { AIChatTurn(role: "assistant", content: content) }
}

protocol AIServicing: Sendable {
    /// Sends the conversation history to the "ai-chat" Edge Function (Gemini-backed
    /// Kitchen Concierge) and returns its reply plus any recipes it referenced.
    /// The last turn must be the user's current message.
    func sendMessage(_ history: [AIChatTurn]) async throws -> AIChatResponse
}

extension AIServicing {
    /// Single-turn convenience for callers with no conversation to carry (e.g.
    /// the Siri intent), which just wraps the prompt as one user turn.
    func sendMessage(_ prompt: String) async throws -> AIChatResponse {
        try await sendMessage([.user(prompt)])
    }
}

struct AIService: AIServicing {
    private struct RequestBody: Encodable {
        let messages: [AIChatTurn]
    }

    private struct ResponseBody: Decodable {
        let response: String
        // Optional so an older deployed function (no `recipes` field) still
        // decodes — the actionable-cards feature just stays dormant until the
        // updated function is deployed.
        let recipes: [AIRecipeRef]?
    }

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseManager.client) {
        self.client = client
    }

    func sendMessage(_ history: [AIChatTurn]) async throws -> AIChatResponse {
        // Attach a freshly-resolved access token explicitly, rather than relying
        // on the token the Functions client cached from the last auth event.
        // Unlike PostgREST (which pulls a fresh token per request), the Functions
        // client only updates its token via `functions.setAuth` on auth events,
        // so at cold launch it can still hold a stale/expired token from the
        // initial stored session — which made this function's server-side recipe
        // search (RLS-gated to `authenticated`) run as anon and return zero rows,
        // i.e. the Planner insisting the user has no recipes until the Recipes tab
        // forced a refresh. Reading `session` auto-refreshes if needed, and the
        // custom Authorization header overrides the client default (see
        // FunctionInvokeOptions header merging). Belt-and-suspenders with the
        // launch-time AuthViewModel.warmUpSession.
        let accessToken = try await client.auth.session.accessToken
        let result: ResponseBody = try await client.functions.invoke(
            "ai-chat",
            options: FunctionInvokeOptions(
                headers: ["Authorization": "Bearer \(accessToken)"],
                body: RequestBody(messages: history)
            )
        )
        return AIChatResponse(text: result.response, recipes: result.recipes ?? [])
    }
}
