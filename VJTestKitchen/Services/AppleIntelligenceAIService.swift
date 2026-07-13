import Foundation
import FoundationModels

/// Kitchen Concierge, backed by Apple Intelligence's **on-device** Foundation
/// Model (`SystemLanguageModel.default`). This replaces the previous
/// Gemini-via-Supabase-Edge-Function implementation entirely (see DECISIONS.md,
/// 2026-07-13):
///
/// - **On-device / private:** the conversation never leaves the phone, there's
///   no API key, and it works with no network for the language-generation part.
/// - **RLS for free:** the `searchRecipes` tool runs *in-process* against the
///   user's own signed-in Supabase session via `RecipeService`, so recipe
///   search is Row-Level-Security-scoped exactly like the rest of the app —
///   no server-side auth plumbing like the Edge Function needed.
/// - **Availability-gated:** the on-device model only exists on
///   Apple-Intelligence-eligible hardware. `unavailableReason` is the
///   user-facing explanation the Planner shows instead of a broken chat when it
///   isn't; `sendMessage` throws the same copy so the Siri path degrades too.
///
/// Deployment target is already iOS/macOS 26 (when FoundationModels shipped),
/// so no `@available` gating is needed — the framework is unconditionally
/// present. Bumping to 27 later unlocks Private Cloud Compute + the unified
/// any-model protocol; see docs/IOS27.md.
struct AppleIntelligenceAIService: AIServicing {
    private let recipeService: RecipeServicing

    init(recipeService: RecipeServicing = RecipeService()) {
        self.recipeService = recipeService
    }

    var unavailableReason: String? {
        Self.unavailableReason(for: SystemLanguageModel.default.availability)
    }

    func sendMessage(_ history: [AIChatTurn]) async throws -> AIChatResponse {
        if let reason = unavailableReason {
            throw AppleIntelligenceUnavailableError(message: reason)
        }

        // A fresh session per turn: the view model already carries the whole
        // conversation, so we replay it into one prompt rather than relying on
        // the session's own transcript (which wouldn't survive relaunch). The
        // tool records what it surfaced into `sink` so we can build cards after.
        let sink = RecipeReferenceSink()
        let tool = SearchRecipesTool(recipeService: recipeService, sink: sink)
        let session = LanguageModelSession(
            tools: [tool],
            instructions: Self.instructions
        )
        let response = try await session.respond(to: Self.promptText(from: history))
        let refs = await sink.drain()
        return AIChatResponse(text: response.content, recipes: refs)
    }

    // MARK: - Pure helpers (unit-tested)

    /// The concierge persona. Kept deliberately tight so the small on-device
    /// model stays on-task and only recommends recipes the tool actually found.
    static let instructions = """
    You are Kitchen Concierge, a warm, concise cooking assistant inside the \
    VJ Test Kitchen app. You help the user plan meals and find recipes from \
    THEIR own collection.

    When the user wants a recipe or a meal plan, call the searchRecipes tool to \
    look in their collection, then recommend specific recipes BY NAME from the \
    results. Never invent recipes that aren't in the tool results — if nothing \
    matches, say so plainly and suggest what they might search for instead. \
    Keep replies short and friendly, and remind the user to double-check \
    cooking times when it matters.
    """

    /// Flattens the chat history into a single prompt. A lone user turn is
    /// passed through as-is; a multi-turn conversation is prefixed with the
    /// prior turns as context so follow-ups ("something else") make sense.
    static func promptText(from history: [AIChatTurn]) -> String {
        let trimmed = history.filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let last = trimmed.last else { return "" }
        let prior = trimmed.dropLast()
        guard !prior.isEmpty else { return last.content }

        let transcript = prior
            .map { "\($0.role == "assistant" ? "Assistant" : "User"): \($0.content)" }
            .joined(separator: "\n")
        return """
        Conversation so far:
        \(transcript)

        The user now says: \(last.content)

        Reply to the user's latest message.
        """
    }

    /// Maps the on-device model's availability to friendly copy, or `nil` when
    /// it's usable. Pure so it's testable without an eligible device.
    static func unavailableReason(for availability: SystemLanguageModel.Availability) -> String? {
        switch availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "Kitchen Concierge needs Apple Intelligence, which isn't supported on this device."
            case .appleIntelligenceNotEnabled:
                return "Turn on Apple Intelligence in Settings to chat with Kitchen Concierge."
            case .modelNotReady:
                return "Apple Intelligence is still getting set up. Please try again in a little while."
            @unknown default:
                return "Kitchen Concierge isn't available on this device right now."
            }
        @unknown default:
            return "Kitchen Concierge isn't available on this device right now."
        }
    }
}

/// Thrown when `sendMessage` is called but the on-device model can't run. Its
/// `errorDescription` is already user-facing, so `ErrorPresenter` surfaces it
/// verbatim (via its `localizedDescription` fallback).
struct AppleIntelligenceUnavailableError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Collects the recipes surfaced by the `searchRecipes` tool during a single
/// concierge turn, so the service can build tappable cards afterward. An actor
/// because the tool's `call` runs off the main actor and may fire more than
/// once per turn (multiple tool rounds). Dedupes by id.
actor RecipeReferenceSink {
    private var recipes: [AIRecipeRef] = []

    func add(_ refs: [AIRecipeRef]) {
        for ref in refs where !recipes.contains(where: { $0.id == ref.id }) {
            recipes.append(ref)
        }
    }

    /// Returns everything collected and clears, so the sink can be reused.
    func drain() -> [AIRecipeRef] {
        defer { recipes = [] }
        return recipes
    }
}

/// The on-device model's one tool: search the user's recipe collection. Mirrors
/// what the old Gemini Edge Function's `search_recipes` did, but runs in-process
/// under the user's Supabase session (so it's RLS-scoped for free). It returns a
/// plain-text summary for the model to read and, as a side effect, records the
/// matches into `sink` for the UI's recipe cards.
struct SearchRecipesTool: Tool {
    let name = "searchRecipes"
    let description = "Search the user's own recipe collection by keyword, with an optional category tag or maximum prep time. Returns matching recipes with their prep time and servings."

    @Generable
    struct Arguments {
        @Guide(description: "Keywords to search recipe titles for, e.g. 'carbonara' or 'chicken soup'.")
        var query: String
        @Guide(description: "Optional category or cuisine tag to filter by, e.g. 'Dinner' or 'Italian'. Omit if the user didn't specify one.")
        var tag: String?
        @Guide(description: "Optional maximum prep time in minutes. Omit unless the user asked for something quick or gave a time limit.")
        var maxPrepTime: Int?
    }

    let recipeService: RecipeServicing
    let sink: RecipeReferenceSink

    /// How many matches to hand the model per search. Kept modest so the small
    /// on-device context window isn't blown by a long tool result.
    static let resultLimit = 12

    func call(arguments: Arguments) async throws -> String {
        let recipes = try await recipeService.fetchPage(
            offset: 0,
            limit: Self.resultLimit,
            matching: arguments.query,
            tag: arguments.tag?.trimmedNonEmpty,
            maxPrepTime: arguments.maxPrepTime.flatMap { $0 > 0 ? $0 : nil }
        )
        await sink.add(recipes.map { AIRecipeRef(id: $0.id, title: $0.title) })
        return Self.formatResults(recipes, query: arguments.query)
    }

    /// A compact, model-readable list of the matches. Deliberately omits
    /// ingredients (the list query doesn't fetch them) — the assistant is told
    /// to say so rather than invent them.
    static func formatResults(_ recipes: [Recipe], query: String) -> String {
        guard !recipes.isEmpty else {
            return "No recipes in the user's collection matched \"\(query)\"."
        }
        let lines = recipes.map { recipe -> String in
            var parts = ["\"\(recipe.title)\""]
            if let prep = recipe.prepTime { parts.append("prep \(prep) min") }
            if let servings = recipe.servings { parts.append("serves \(servings)") }
            return "- " + parts.joined(separator: ", ")
        }
        return "Matching recipes from the user's collection:\n" + lines.joined(separator: "\n")
    }
}

private extension String {
    /// Trimmed, or `nil` if empty after trimming — so the tool doesn't pass an
    /// empty tag/query down to the recipe query as a real filter.
    var trimmedNonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
