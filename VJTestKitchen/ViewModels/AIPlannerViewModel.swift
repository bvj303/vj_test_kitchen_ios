import Foundation
import Observation

@MainActor
@Observable
final class AIPlannerViewModel {
    enum Role: String, Equatable, Codable {
        case user
        case assistant
    }

    struct ChatMessage: Identifiable, Equatable, Codable {
        var id = UUID()
        var role: Role
        var content: String
        /// Recipes the assistant named in this message — rendered as tappable
        /// cards. Empty for user messages and replies that don't cite a recipe.
        var recipes: [AIRecipeRef] = []
        /// Write actions the assistant proposed in this message — rendered as
        /// confirm-to-apply controls. Nothing is written until the user taps.
        var actions: [AIChatAction] = []
        /// Set on a user message whose send failed — shown inline under it with
        /// a Try Again button, instead of an alert that loses the context.
        var failureReason: String?
    }

    /// What's saved between launches: the conversation and which proposed
    /// actions were already applied (so a relaunch can't double-write).
    private struct SavedChat: Codable {
        var messages: [ChatMessage]
        var appliedActionIds: Set<String>
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
    /// True while "Add the whole plan" is writing (for its button's spinner).
    private(set) var isApplyingPlan = false
    /// Prep time / servings / rating / image for recipes the replies name, keyed
    /// by id — what makes the recipe cards more than a bare title. Best-effort:
    /// a card just stays plain if its details didn't load.
    private(set) var recipeInfo: [Int64: Recipe] = [:]

    private let aiService: AIServicing
    private let recipeService: RecipeServicing
    private let mealPlanService: MealPlanServicing
    private let groceryService: GroceryItemServicing
    private let snapshotStore: LocalSnapshotStoring
    private let logger: AppLogger

    init(
        aiService: AIServicing = AIService(),
        recipeService: RecipeServicing = RecipeService(),
        mealPlanService: MealPlanServicing = MealPlanService(),
        groceryService: GroceryItemServicing = GroceryItemService(),
        snapshotStore: LocalSnapshotStoring = FileSnapshotStore.shared,
        logger: AppLogger = .shared
    ) {
        self.aiService = aiService
        self.recipeService = recipeService
        self.mealPlanService = mealPlanService
        self.groceryService = groceryService
        self.snapshotStore = snapshotStore
        self.logger = logger
        // Pick the conversation back up where the user left it. Cleared with the
        // rest of the snapshots on sign-out (AuthViewModel), so it can't leak
        // into another account.
        if let saved = snapshotStore.load(SavedChat.self, key: .conciergeChat) {
            messages = saved.messages
            appliedActionIds = saved.appliedActionIds
        }
    }

    /// Sends the typed message.
    func send() async {
        await send(inputText)
    }

    /// Sends `text` as the user's next message — the typed input, or a starter /
    /// follow-up chip.
    func send(_ text: String) async {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isSending else { return }

        errorMessage = nil
        // A newer message supersedes an earlier failed one; it's still part of
        // the history, so the concierge sees what was asked.
        for index in messages.indices { messages[index].failureReason = nil }
        messages.append(ChatMessage(role: .user, content: prompt))
        inputText = ""
        await requestReply()
    }

    /// Re-sends the conversation after the last message failed to send.
    func retry() async {
        guard let last = messages.indices.last, messages[last].failureReason != nil, !isSending else { return }
        messages[last].failureReason = nil
        await requestReply()
    }

    /// Asks for a reply to the conversation as it stands (last turn = user).
    private func requestReply() async {
        isSending = true
        defer {
            isSending = false
            save()
        }
        do {
            // Send the whole conversation (the user turn is already appended),
            // not just this prompt, so the concierge can vary its answer when the
            // user asks again / for "something else" — see AIChatTurn.
            let response = try await aiService.sendMessage(Self.historyPayload(from: messages))
            let recipes = Self.recipesReferenced(in: response.text, from: response.recipes)
            messages.append(ChatMessage(
                role: .assistant,
                content: response.text,
                recipes: recipes,
                actions: response.actions
            ))
            await loadRecipeInfo(for: recipes.map(\.id))
        } catch {
            // Shown inline on the failed message, but logged raw — a failing Edge
            // Function (non-200, timeout, bad payload) is otherwise invisible to us.
            logger.error("AI planner request failed", category: "ai", error: error)
            if let last = messages.indices.last {
                messages[last].failureReason = ErrorPresenter.message(for: error)
            }
        }
    }

    /// Loads card details for every recipe in the conversation that doesn't have
    /// them yet — on appear, so a restored chat's cards fill in too.
    func loadMissingRecipeInfo() async {
        await loadRecipeInfo(for: messages.flatMap { $0.recipes.map(\.id) })
    }

    private func loadRecipeInfo(for ids: [Int64]) async {
        let missing = Array(Set(ids).subtracting(recipeInfo.keys))
        guard !missing.isEmpty else { return }
        do {
            for recipe in try await recipeService.fetchByIds(missing) {
                recipeInfo[recipe.id] = recipe
            }
        } catch {
            logger.warning("Loading concierge recipe card details failed", category: "ai", metadata: ["error": "\(error)"])
        }
    }

    /// Follow-up chips for `message` — only under the latest reply, and not while
    /// a new one is on its way.
    func followUps(for message: ChatMessage) -> [ConciergePrompts.Prompt] {
        guard message.role == .assistant, message.id == messages.last?.id, !isSending else { return [] }
        return ConciergePrompts.followUps(
            recipeCount: message.recipes.count,
            mealPlanActionCount: message.actions.filter(\.isMealPlan).count,
            groceryActionCount: message.actions.filter { !$0.isMealPlan }.count
        )
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
        recipeInfo = [:]
        save()
    }

    private func save() {
        snapshotStore.save(SavedChat(messages: messages, appliedActionIds: appliedActionIds), key: .conciergeChat)
    }

    func hasApplied(_ action: AIChatAction) -> Bool { appliedActionIds.contains(action.id) }

    /// Applies a user-confirmed proposed action by writing through the existing
    /// (RLS-scoped) services. Called ONLY from a confirm gesture in the UI — the
    /// concierge never triggers this itself, so no write happens without an
    /// explicit tap. Idempotent per action id.
    func apply(_ action: AIChatAction) async {
        guard !appliedActionIds.contains(action.id), applyingActionId == nil else { return }
        applyingActionId = action.id
        defer {
            applyingActionId = nil
            save()
        }
        do {
            switch action {
            case let .addToMealPlan(proposal):
                try await write(proposal)
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

    /// The meal-plan proposals in `message` that haven't been added yet — what
    /// "Add the whole plan" will write.
    func unappliedMealPlans(in message: ChatMessage) -> [AIMealPlanProposal] {
        message.actions.compactMap { action in
            guard case let .addToMealPlan(proposal) = action, !appliedActionIds.contains(action.id) else { return nil }
            return proposal
        }
    }

    /// Adds every not-yet-added meal in `message` to the calendar after ONE user
    /// confirmation (the UI's confirmation dialog), instead of a dialog per
    /// meal. Stops at the first failure, keeping what already landed, so tapping
    /// again picks up where it left off.
    func applyAllMealPlans(in message: ChatMessage) async {
        let proposals = unappliedMealPlans(in: message)
        guard !proposals.isEmpty, !isApplyingPlan, applyingActionId == nil else { return }
        isApplyingPlan = true
        defer {
            isApplyingPlan = false
            save()
        }
        var added = 0
        for proposal in proposals {
            do {
                try await write(proposal)
                appliedActionIds.insert(AIChatAction.addToMealPlan(proposal).id)
                added += 1
            } catch {
                logger.error("Adding a concierge meal plan failed", category: "ai", error: error)
                errorMessage = ErrorPresenter.message(for: error)
                return
            }
        }
        actionResultMessage = "Added \(added) meal\(added == 1 ? "" : "s") to your calendar."
    }

    private func write(_ proposal: AIMealPlanProposal) async throws {
        _ = try await mealPlanService.create(
            MealPlanDraft(date: proposal.date, mealType: proposal.mealType, recipeId: proposal.recipeId)
        )
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
