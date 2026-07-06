import Foundation
import Supabase

protocol AIServicing: Sendable {
    /// Sends a prompt to the "ai-chat" Edge Function (Gemini-backed Kitchen
    /// Concierge) and returns its plain-text response.
    func sendMessage(_ prompt: String) async throws -> String
}

struct AIService: AIServicing {
    private struct RequestBody: Encodable {
        let prompt: String
    }

    private struct ResponseBody: Decodable {
        let response: String
    }

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseManager.client) {
        self.client = client
    }

    func sendMessage(_ prompt: String) async throws -> String {
        let result: ResponseBody = try await client.functions.invoke(
            "ai-chat",
            options: FunctionInvokeOptions(body: RequestBody(prompt: prompt))
        )
        return result.response
    }
}
