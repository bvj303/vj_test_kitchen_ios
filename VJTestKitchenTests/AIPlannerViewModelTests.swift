import Foundation
import Testing
@testable import VJTestKitchen

final class FakeAIService: AIServicing, @unchecked Sendable {
    /// The full conversation sent on each call.
    private(set) var receivedHistories: [[AIChatTurn]] = []
    /// Convenience view: the latest user message content of each call, so existing
    /// assertions that only care about "what did the user ask" stay simple.
    var receivedPrompts: [String] { receivedHistories.map { $0.last?.content ?? "" } }
    var responseToReturn = "Here's a plan!"
    var recipesToReturn: [AIRecipeRef] = []
    var actionsToReturn: [AIChatAction] = []
    var errorToThrow: Error?

    func sendMessage(_ history: [AIChatTurn]) async throws -> AIChatResponse {
        receivedHistories.append(history)
        if let errorToThrow { throw errorToThrow }
        return AIChatResponse(text: responseToReturn, recipes: recipesToReturn, actions: actionsToReturn)
    }
}

// Reuses the existing test-target spies FakeMealPlanService (records
// `createdDrafts` / `errorToThrow`) and FakeGroceryItemService (records
// `addedDrafts` / `addError`) rather than redeclaring them.

private struct TestError: Error, LocalizedError {
    var errorDescription: String? { "failed" }
}

@MainActor
struct AIPlannerViewModelTests {
    @Test func startsWithNoMessages() {
        let viewModel = AIPlannerViewModel(aiService: FakeAIService())
        #expect(viewModel.messages.isEmpty)
    }

    @Test func sendAppendsUserMessageThenAssistantReply() async {
        let ai = FakeAIService()
        ai.responseToReturn = "Try the Carbonara!"
        let viewModel = AIPlannerViewModel(aiService: ai)
        viewModel.inputText = "What should I cook tonight?"

        await viewModel.send()

        #expect(viewModel.messages.count == 2)
        #expect(viewModel.messages[0].role == .user)
        #expect(viewModel.messages[0].content == "What should I cook tonight?")
        #expect(viewModel.messages[1].role == .assistant)
        #expect(viewModel.messages[1].content == "Try the Carbonara!")
        #expect(viewModel.inputText.isEmpty)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func sendLogsErrorWhenRequestFails() async {
        struct SendError: Error {}
        let ai = FakeAIService()
        ai.errorToThrow = SendError()
        let sink = SpyLogSink()
        let logger = AppLogger(sinks: [sink], context: LogContext(appVersion: "1", platform: "test"))
        let viewModel = AIPlannerViewModel(aiService: ai, logger: logger)
        viewModel.inputText = "What should I cook?"

        await viewModel.send()

        // A failing Edge Function is surfaced via errorMessage AND logged raw.
        #expect(sink.events.contains { $0.level == .error && $0.category == "ai" })
    }

    @Test func sendPassesFullConversationHistorySoFollowUpsHaveContext() async {
        let ai = FakeAIService()
        ai.responseToReturn = "Try the Kale Salad."
        let viewModel = AIPlannerViewModel(aiService: ai)

        viewModel.inputText = "something healthy"
        await viewModel.send()

        viewModel.inputText = "something else"
        await viewModel.send()

        // First call carries just the opening user turn…
        #expect(ai.receivedHistories[0] == [.user("something healthy")])
        // …the second carries the whole conversation so far, ending on the new
        // user turn — this is what lets the concierge avoid repeating itself.
        #expect(ai.receivedHistories[1] == [
            .user("something healthy"),
            .assistant("Try the Kale Salad."),
            .user("something else"),
        ])
    }

    @Test func historyPayloadCapsToMostRecentTurns() {
        let messages = (1...20).map { i in
            AIPlannerViewModel.ChatMessage(role: .user, content: "msg \(i)")
        }
        let payload = AIPlannerViewModel.historyPayload(from: messages, maxTurns: 12)
        #expect(payload.count == 12)
        #expect(payload.first == .user("msg 9"))
        #expect(payload.last == .user("msg 20"))
    }

    @Test func sendIgnoresBlankInput() async {
        let ai = FakeAIService()
        let viewModel = AIPlannerViewModel(aiService: ai)
        viewModel.inputText = "   "

        await viewModel.send()

        #expect(viewModel.messages.isEmpty)
        #expect(ai.receivedPrompts.isEmpty)
    }

    @Test func sendSurfacesErrorMessageButKeepsUserMessage() async {
        let ai = FakeAIService()
        ai.errorToThrow = TestError()
        let viewModel = AIPlannerViewModel(aiService: ai)
        viewModel.inputText = "Plan my week"

        await viewModel.send()

        #expect(viewModel.messages.count == 1)
        #expect(viewModel.messages[0].role == .user)
        #expect(viewModel.errorMessage == "failed")
    }

    @Test func assistantReplyAttachesOnlyRecipesItNames() async {
        let ai = FakeAIService()
        ai.responseToReturn = "I'd go with the Beef Tacos tonight."
        ai.recipesToReturn = [
            AIRecipeRef(id: 2, title: "Beef Tacos"),      // named in the reply
            AIRecipeRef(id: 9, title: "Chicken Alfredo"), // searched but not named
        ]
        let viewModel = AIPlannerViewModel(aiService: ai)
        viewModel.inputText = "tacos please"

        await viewModel.send()

        #expect(viewModel.messages[1].recipes == [AIRecipeRef(id: 2, title: "Beef Tacos")])
    }

    @Test func recipesReferencedIsCaseInsensitiveAndDeduped() {
        let text = "The beef TACOS are great, and beef tacos again."
        let refs = [
            AIRecipeRef(id: 2, title: "Beef Tacos"),
            AIRecipeRef(id: 2, title: "Beef Tacos"),
            AIRecipeRef(id: 5, title: "Sushi"),
        ]
        let result = AIPlannerViewModel.recipesReferenced(in: text, from: refs)
        #expect(result == [AIRecipeRef(id: 2, title: "Beef Tacos")])
    }

    @Test func clearChatRemovesAllMessages() async {
        let ai = FakeAIService()
        let viewModel = AIPlannerViewModel(aiService: ai)
        viewModel.inputText = "Hi"
        await viewModel.send()
        #expect(!viewModel.messages.isEmpty)

        viewModel.clearChat()

        #expect(viewModel.messages.isEmpty)
    }

    // ── Slice 3: proposed write actions require explicit confirmation ──

    @Test func proposedActionsAttachToAssistantMessageButNothingIsWrittenYet() async {
        let ai = FakeAIService()
        let meal = FakeMealPlanService()
        let grocery = FakeGroceryItemService()
        let action = AIChatAction.addToMealPlan(
            AIMealPlanProposal(recipeId: 2, recipeTitle: "Beef Tacos", date: "2026-07-20", mealType: "dinner")
        )
        ai.responseToReturn = "I've proposed Beef Tacos for Monday — tap to add it."
        ai.actionsToReturn = [action]
        let viewModel = AIPlannerViewModel(aiService: ai, mealPlanService: meal, groceryService: grocery)
        viewModel.inputText = "add tacos to monday dinner"

        await viewModel.send()

        // The proposal is surfaced for the user...
        #expect(viewModel.messages[1].actions == [action])
        // ...but merely receiving it writes NOTHING (never silent).
        #expect(meal.createdDrafts.isEmpty)
        #expect(!viewModel.hasApplied(action))
    }

    @Test func applyMealPlanWritesThroughTheServiceOnlyWhenConfirmed() async {
        let meal = FakeMealPlanService()
        let viewModel = AIPlannerViewModel(aiService: FakeAIService(), mealPlanService: meal, groceryService: FakeGroceryItemService())
        let action = AIChatAction.addToMealPlan(
            AIMealPlanProposal(recipeId: 7, recipeTitle: "Coq au Vin", date: "2026-07-21", mealType: "dinner")
        )

        await viewModel.apply(action)

        #expect(meal.createdDrafts.count == 1)
        #expect(meal.createdDrafts[0].recipeId == 7)
        #expect(meal.createdDrafts[0].date == "2026-07-21")
        #expect(meal.createdDrafts[0].mealType == "dinner")
        #expect(viewModel.hasApplied(action))
        #expect(viewModel.actionResultMessage?.contains("Coq au Vin") == true)
    }

    @Test func applyGroceryMapsItemsAndCategorizesThem() async {
        let grocery = FakeGroceryItemService()
        let viewModel = AIPlannerViewModel(aiService: FakeAIService(), mealPlanService: FakeMealPlanService(), groceryService: grocery)
        let action = AIChatAction.addToGroceryList(
            AIGroceryProposal(recipeId: 7, recipeTitle: "Coq au Vin", items: [
                AIGroceryProposalItem(name: "chicken thighs", amount: 2, unit: "lb"),
                AIGroceryProposalItem(name: "red wine", amount: nil, unit: nil),
            ])
        )

        await viewModel.apply(action)

        let drafts = grocery.addedDrafts
        #expect(drafts.count == 2)
        #expect(drafts[0].name == "chicken thighs")
        #expect(drafts[0].amount == 2)
        #expect(drafts[0].unit == "lb")
        #expect(drafts[0].sourceRecipeId == 7)
        // A missing amount/unit defaults cleanly rather than failing.
        #expect(drafts[1].amount == 0)
        #expect(drafts[1].unit == "")
        // Category is derived, not required from the model.
        #expect(drafts[0].category == GroceryCategorizer.categorize("chicken thighs"))
        #expect(viewModel.hasApplied(action))
    }

    @Test func applyIsIdempotentAndWontDoubleWrite() async {
        let meal = FakeMealPlanService()
        let viewModel = AIPlannerViewModel(aiService: FakeAIService(), mealPlanService: meal, groceryService: FakeGroceryItemService())
        let action = AIChatAction.addToMealPlan(
            AIMealPlanProposal(recipeId: 3, recipeTitle: "Ragu", date: "2026-07-22", mealType: "dinner")
        )

        await viewModel.apply(action)
        await viewModel.apply(action) // second tap is a no-op

        #expect(meal.createdDrafts.count == 1)
    }

    @Test func applyFailureSurfacesErrorAndLeavesActionUnapplied() async {
        struct WriteError: Error {}
        let meal = FakeMealPlanService()
        meal.errorToThrow = WriteError()
        let viewModel = AIPlannerViewModel(aiService: FakeAIService(), mealPlanService: meal, groceryService: FakeGroceryItemService())
        let action = AIChatAction.addToMealPlan(
            AIMealPlanProposal(recipeId: 4, recipeTitle: "Stew", date: "2026-07-23", mealType: "dinner")
        )

        await viewModel.apply(action)

        #expect(viewModel.errorMessage != nil)
        #expect(!viewModel.hasApplied(action)) // a failed write can be retried
    }

    @Test func actionsDecodeKnownTypesAndTolerateUnknownFutureTypes() throws {
        // Mirrors the wire shape the Edge Function emits (camelCase keys), incl. a
        // future action type this build doesn't know — which must not break decoding.
        let json = """
        [
          { "type": "add_to_meal_plan", "recipeId": 2, "recipeTitle": "Beef Tacos", "date": "2026-07-20", "mealType": "dinner" },
          { "type": "add_to_grocery_list", "recipeId": 7, "recipeTitle": "Coq au Vin", "items": [ { "name": "chicken", "amount": 2, "unit": "lb" }, { "name": "wine" } ] },
          { "type": "some_future_action", "foo": "bar" }
        ]
        """.data(using: .utf8)!

        let actions = try JSONDecoder().decode([AIChatAction].self, from: json)
        #expect(actions.count == 3)
        #expect(actions[0] == .addToMealPlan(AIMealPlanProposal(recipeId: 2, recipeTitle: "Beef Tacos", date: "2026-07-20", mealType: "dinner")))
        if case let .addToGroceryList(p) = actions[1] {
            #expect(p.items.count == 2)
            #expect(p.items[1].amount == nil)
        } else {
            Issue.record("expected a grocery action")
        }
        #expect(actions[2] == .unknown) // gracefully tolerated; AIService filters it out
    }
}
