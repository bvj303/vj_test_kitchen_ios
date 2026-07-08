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

protocol AIServicing: Sendable {
    /// Sends a prompt to the "ai-chat" Edge Function (Gemini-backed Kitchen
    /// Concierge) and returns its reply plus any recipes it referenced.
    func sendMessage(_ prompt: String) async throws -> AIChatResponse
}

struct AIService: AIServicing {
    private struct RequestBody: Encodable {
        let prompt: String
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

    func sendMessage(_ prompt: String) async throws -> AIChatResponse {
        let result: ResponseBody = try await client.functions.invoke(
            "ai-chat",
            options: FunctionInvokeOptions(body: RequestBody(prompt: prompt))
        )
        return AIChatResponse(text: result.response, recipes: result.recipes ?? [])
    }
}
