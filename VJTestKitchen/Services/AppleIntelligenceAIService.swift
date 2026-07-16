import Foundation
import FoundationModels

/// Kitchen Concierge, backed by Apple Intelligence's **on-device** Foundation
/// Model (`SystemLanguageModel.default`). Replaces the previous
/// Gemini-via-Supabase-Edge-Function implementation (see DECISIONS.md,
/// 2026-07-13/15):
///
/// - **On-device / private:** the conversation never leaves the phone, there's
///   no API key, and generation works with no network.
/// - **Grounded in the user's own recipes, deterministically.** The small
///   on-device model is *not* reliable at deciding to call a search tool
///   (unlike the larger Gemini model this replaced — that's why the first cut
///   answered generically without naming the user's recipes). So instead of
///   relying on tool-calling, every turn we **retrieve first**: search the
///   user's collection (`RecipeService`, in-process → RLS-scoped for free),
///   inject the matches into the prompt, and instruct the model to recommend
///   BY NAME from that list. Retrieval falls back to a general page so the
///   concierge is never left empty-handed on a vague ask.
/// - **Availability-gated:** the on-device model only exists on
///   Apple-Intelligence-eligible hardware. `unavailableReason` is the
///   user-facing explanation the Planner shows instead of a broken chat when it
///   isn't; `sendMessage` throws the same copy so the Siri path degrades too.
struct AppleIntelligenceAIService: AIServicing {
    private let recipeService: RecipeServicing

    init(recipeService: RecipeServicing = RecipeService()) {
        self.recipeService = recipeService
    }

    var unavailableReason: String? {
        Self.unavailableReason(for: SystemLanguageModel.default.availability)
    }

    /// How many recipes to hand the model as grounding context per turn. Enough
    /// to choose from for real variety, small enough not to blow the on-device
    /// context window (~a few hundred tokens for the list).
    static let groundingLimit = 24

    /// How many candidates to *fetch* before sampling `groundingLimit` of them.
    /// A wider pool that's then shuffled means repeated/open-ended asks don't
    /// keep surfacing the same recipes — the model effectively sees across the
    /// whole catalog over time, not a fixed first page. Mirrors the old Gemini
    /// `search_recipes` pool-then-shuffle behavior.
    static let poolLimit = 75

    func sendMessage(_ history: [AIChatTurn]) async throws -> AIChatResponse {
        if let reason = unavailableReason {
            throw AppleIntelligenceUnavailableError(message: reason)
        }

        // 1. Turn the latest user message into search parameters. Structured
        //    generation is far more reliable on the small model than free-form
        //    tool-calling; if it fails, fall back to searching the raw message.
        let latest = Self.latestUserText(from: history)
        let params = await extractSearchParams(from: latest)

        // 2. Retrieve real recipes from the user's collection to ground on.
        let recipes = try await retrieve(
            query: params.query,
            tag: params.tag,
            maxPrepTime: params.maxPrepTime
        )

        // 3. Answer, grounded in those recipes (no tools — the list is in the
        //    prompt, and the model is told to recommend only from it). Escalates
        //    to Apple's Private Cloud Compute model on iOS/macOS 27 when it's
        //    available; on-device otherwise (see makeAnswerSession).
        let session = Self.makeAnswerSession()
        let response = try await session.respond(
            to: Self.groundedPrompt(history: history, recipes: recipes)
        )

        // Hand back every retrieved recipe as a candidate; the view model keeps
        // only the ones the reply actually names as tappable cards.
        return AIChatResponse(
            text: response.content,
            recipes: recipes.map { AIRecipeRef(id: $0.id, title: $0.title) }
        )
    }

    // MARK: - Retrieval

    /// Gather grounding recipes, then **shuffle and sample** `groundingLimit` of
    /// them so the concierge draws widely and varies between asks (rather than
    /// re-suggesting the same fixed page):
    ///
    /// - A **filtered** ask (query/tag/prep) fetches a wide pool of matches,
    ///   widening (drop tag/prep, then a random catalog slice) if empty.
    /// - An **open-ended** ask (no filters — "plan me some dinners") samples a
    ///   **random slice of the whole catalog**, so it spans everything over
    ///   repeated asks instead of always the first page.
    func retrieve(query: String?, tag: String?, maxPrepTime: Int?) async throws -> [Recipe] {
        let hasFilter = query != nil || tag != nil || maxPrepTime != nil
        var pool: [Recipe]

        if hasFilter {
            pool = try await recipeService.fetchPage(
                offset: 0, limit: Self.poolLimit, matching: query, tag: tag, maxPrepTime: maxPrepTime
            )
            if pool.isEmpty, tag != nil || maxPrepTime != nil {
                pool = try await recipeService.fetchPage(
                    offset: 0, limit: Self.poolLimit, matching: query, tag: nil, maxPrepTime: nil
                )
            }
            if pool.isEmpty {
                pool = try await fetchRandomCatalogPool()
            }
        } else {
            pool = try await fetchRandomCatalogPool()
        }

        return Array(pool.shuffled().prefix(Self.groundingLimit))
    }

    /// A pool of recipes from a **random offset** across the whole catalog, so
    /// open-ended asks (and unmatched fallbacks) sample the entire collection
    /// over time instead of always the first page. Uses the HEAD-count so the
    /// offset stays in range; falls back to the first page if the count is
    /// unknown (e.g. test fakes default `totalCount` to 0).
    private func fetchRandomCatalogPool() async throws -> [Recipe] {
        let total = (try? await recipeService.totalCount()) ?? 0
        let maxOffset = max(0, total - Self.poolLimit)
        let offset = maxOffset > 0 ? Int.random(in: 0...maxOffset) : 0
        return try await recipeService.fetchPage(offset: offset, limit: Self.poolLimit, matching: nil)
    }

    // MARK: - Model selection (on-device vs Private Cloud Compute)

    /// Builds the session for the *answer* turn.
    ///
    /// **Currently on-device only.** Escalation to Apple's Private Cloud Compute
    /// model (`PrivateCloudComputeLanguageModel`) is implemented in git history
    /// but **reverted** because PCC is **entitlement-gated**: it requires the
    /// `com.apple.developer.private-cloud-compute` capability *and* App Store
    /// Small Business Program enrollment (<2M downloads). Without the
    /// entitlement, merely *touching* the PCC type at runtime **traps** (a hard
    /// crash, not a catchable error) on an iOS-27 device — which is exactly what
    /// happened on the beta. Re-enable only after the entitlement is granted and
    /// the signed build actually carries it (see docs/IOS27.md). Keeping the
    /// on-device grounded path (the build-7 behavior) is the safe default.
    private static func makeAnswerSession() -> LanguageModelSession {
        LanguageModelSession(instructions: instructions)
    }

    // MARK: - Query extraction (on-device)

    /// Search parameters the model may not fill in — nils mean "no constraint".
    struct SearchParams: Equatable {
        var query: String?
        var tag: String?
        var maxPrepTime: Int?
    }

    /// What the model fills in. Not `private`: the `@Generable` macro synthesizes
    /// a conformance extension at file scope. 0 / "" mean "unspecified" (the
    /// schema is happier with concrete values than optionals — same choice as
    /// `ScannedRecipe`).
    @Generable
    struct RecipeQuery {
        @Guide(description: "Keywords from the user's request to search recipe TITLES for, e.g. 'carbonara' or 'chicken soup'. Empty string if the user isn't naming a dish or ingredient.")
        var query: String
        @Guide(description: "A single course or cuisine tag the user named, e.g. 'Dinner' or 'Italian'. Empty string if none.")
        var tag: String
        @Guide(description: "Maximum prep time in minutes if the user asked for something quick or gave a limit, else 0.")
        var maxPrepTime: Int

        init(query: String = "", tag: String = "", maxPrepTime: Int = 0) {
            self.query = query
            self.tag = tag
            self.maxPrepTime = maxPrepTime
        }
    }

    /// Runs the extraction model call; on any failure, falls back to searching
    /// the raw message text. Always returns usable params.
    private func extractSearchParams(from message: String) async -> SearchParams {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return SearchParams(query: nil, tag: nil, maxPrepTime: nil)
        }
        do {
            let session = LanguageModelSession(instructions: Self.extractionInstructions)
            let q = try await session.respond(
                to: "User request: \(message)",
                generating: RecipeQuery.self
            ).content
            return Self.normalize(q)
        } catch {
            // Extraction failed — search the raw message rather than nothing.
            return SearchParams(query: message.trimmedNonEmpty, tag: nil, maxPrepTime: nil)
        }
    }

    /// Maps the model's `@Generable` output to `SearchParams`, treating empty/0
    /// as "unspecified". Pure/tested. An empty extracted query means "no title
    /// filter", which the retrieval ladder handles with a general page.
    static func normalize(_ q: RecipeQuery) -> SearchParams {
        SearchParams(
            query: q.query.trimmedNonEmpty,
            tag: q.tag.trimmedNonEmpty,
            maxPrepTime: q.maxPrepTime > 0 ? q.maxPrepTime : nil
        )
    }

    // MARK: - Prompts (pure, unit-tested)

    static let instructions = """
    You are Kitchen Concierge, a warm, concise cooking assistant inside the \
    VJ Test Kitchen app. You help the user plan meals and pick recipes from \
    THEIR own collection. You are given a list of recipes from their \
    collection; recommend specific recipes BY NAME from that list, with a short \
    reason for each. Never invent recipes that aren't in the provided list — if \
    none fit, say so plainly and suggest what they might search for instead. \
    Keep replies short and friendly, and remind the user to double-check \
    cooking times when it matters.
    """

    static let extractionInstructions = """
    Extract recipe-search parameters from the user's request. Fill in `query` \
    with the dish or ingredient keywords to search recipe titles for (empty if \
    the user isn't naming one), `tag` with a course/cuisine if they named one, \
    and `maxPrepTime` in minutes only if they asked for something quick or gave \
    a time limit. Do not invent constraints the user didn't state.
    """

    /// The latest user turn's text (what to search on). Empty if none.
    static func latestUserText(from history: [AIChatTurn]) -> String {
        history.last(where: { $0.role == "user" })?.content
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Flattens the chat history into the conversation portion of a prompt. A
    /// lone user turn is passed through as-is; a multi-turn conversation is
    /// prefixed with the prior turns as context so follow-ups ("something else")
    /// make sense.
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

    /// The full prompt: the grounding recipe list, then the conversation. The
    /// model is instructed (via `instructions`) to recommend only from the list.
    static func groundedPrompt(history: [AIChatTurn], recipes: [Recipe]) -> String {
        """
        \(formatResults(recipes, query: latestUserText(from: history)))

        \(promptText(from: history))
        """
    }

    /// A compact, model-readable list of the grounding recipes. Deliberately
    /// omits ingredients (the list query doesn't fetch them) — the assistant is
    /// told to say so rather than invent them.
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
        return "Recipes from the user's collection:\n" + lines.joined(separator: "\n")
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

private extension String {
    /// Trimmed, or `nil` if empty after trimming.
    var trimmedNonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
