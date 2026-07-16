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
        /// Write actions the assistant proposed in this message — rendered as
        /// confirm-to-apply controls. Nothing is written until the user taps.
        var actions: [AIChatAction] = []
    }

    private(set) var messages: [ChatMessage] = []
    var inputText = ""
    private(set) var isSending = false
    var errorMessage: String?
    /// A transient success banner shown after a confirmed action is applied.
    var actionResultMessage: String?
    /// Ids of proposed actions the user has already applied (for a persistent
    /// "Added ✓" state on the control), so re-tapping can't double-write.
    private(set) var appliedActionIds: Set<String> = []
    /// The action id currently being written (for a per-control spinner).
    private(set) var applyingActionId: String?

    private let aiService: AIServicing
    private let mealPlanService: MealPlanServicing
    private let groceryService: GroceryItemServicing
    private let logger: AppLogger

    init(
        aiService: AIServicing = AIService(),
        mealPlanService: MealPlanServicing = MealPlanService(),
        groceryService: GroceryItemServicing = GroceryItemService(),
        logger: AppLogger = .shared
    ) {
        self.aiService = aiService
        self.mealPlanService = mealPlanService
        self.groceryService = groceryService
        self.logger = logger
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
                recipes: Self.recipesReferenced(in: response.text, from: response.recipes),
                actions: response.actions
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
        appliedActionIds = []
        actionResultMessage = nil
    }

    func hasApplied(_ action: AIChatAction) -> Bool { appliedActionIds.contains(action.id) }

    /// Applies a user-confirmed proposed action by writing through the existing
    /// (RLS-scoped) services. Called ONLY from a confirm gesture in the UI — the
    /// concierge never triggers this itself, so no write happens without an
    /// explicit tap. Idempotent per action id.
    func apply(_ action: AIChatAction) async {
        guard !appliedActionIds.contains(action.id), applyingActionId == nil else { return }
        applyingActionId = action.id
        defer { applyingActionId = nil }
        do {
            switch action {
            case let .addToMealPlan(proposal):
                _ = try await mealPlanService.create(
                    MealPlanDraft(date: proposal.date, mealType: proposal.mealType, recipeId: proposal.recipeId)
                )
                appliedActionIds.insert(action.id)
                actionResultMessage = "Added \(proposal.recipeTitle) to your calendar."
            case let .addToGroceryList(proposal):
                let drafts = proposal.items.map { item in
                    GroceryItemDraft(
                        name: item.name,
                        amount: item.amount ?? 0,
                        unit: item.unit ?? "",
                        category: GroceryCategorizer.categorize(item.name),
                        sourceRecipeId: proposal.recipeId,
                        sourceRecipeTitle: proposal.recipeTitle
                    )
                }
                _ = try await groceryService.addMany(drafts)
                appliedActionIds.insert(action.id)
                let n = drafts.count
                actionResultMessage = "Added \(n) item\(n == 1 ? "" : "s") to your grocery list."
            case .unknown:
                break
            }
        } catch {
            logger.error("Applying a concierge action failed", category: "ai", error: error)
            errorMessage = ErrorPresenter.message(for: error)
        }
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
