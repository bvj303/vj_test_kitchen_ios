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
        let viewModel = AIPlannerViewModel(aiService: FakeAIService(), recipeService: FakeRecipeService(), snapshotStore: FakeSnapshotStore())
        #expect(viewModel.messages.isEmpty)
    }

    @Test func sendAppendsUserMessageThenAssistantReply() async {
        let ai = FakeAIService()
        ai.responseToReturn = "Try the Carbonara!"
        let viewModel = AIPlannerViewModel(aiService: ai, recipeService: FakeRecipeService(), snapshotStore: FakeSnapshotStore())
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
        let viewModel = AIPlannerViewModel(aiService: ai, recipeService: FakeRecipeService(), snapshotStore: FakeSnapshotStore(), logger: logger)
        viewModel.inputText = "What should I cook?"

        await viewModel.send()

        // A failing Edge Function is surfaced via errorMessage AND logged raw.
        #expect(sink.events.contains { $0.level == .error && $0.category == "ai" })
    }

    @Test func sendPassesFullConversationHistorySoFollowUpsHaveContext() async {
        let ai = FakeAIService()
        ai.responseToReturn = "Try the Kale Salad."
        let viewModel = AIPlannerViewModel(aiService: ai, recipeService: FakeRecipeService(), snapshotStore: FakeSnapshotStore())

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
        let viewModel = AIPlannerViewModel(aiService: ai, recipeService: FakeRecipeService(), snapshotStore: FakeSnapshotStore())
        viewModel.inputText = "   "

        await viewModel.send()

        #expect(viewModel.messages.isEmpty)
        #expect(ai.receivedPrompts.isEmpty)
    }

    @Test func sendSurfacesErrorMessageButKeepsUserMessage() async {
        let ai = FakeAIService()
        ai.errorToThrow = TestError()
        let viewModel = AIPlannerViewModel(aiService: ai, recipeService: FakeRecipeService(), snapshotStore: FakeSnapshotStore())
        viewModel.inputText = "Plan my week"

        await viewModel.send()

        #expect(viewModel.messages.count == 1)
        #expect(viewModel.messages[0].role == .user)
        #expect(viewModel.messages[0].failureReason == "failed")
        #expect(viewModel.errorMessage == nil) // inline, not an alert
    }

    @Test func assistantReplyAttachesOnlyRecipesItNames() async {
        let ai = FakeAIService()
        ai.responseToReturn = "I'd go with the Beef Tacos tonight."
        ai.recipesToReturn = [
            AIRecipeRef(id: 2, title: "Beef Tacos"),      // named in the reply
            AIRecipeRef(id: 9, title: "Chicken Alfredo"), // searched but not named
        ]
        let viewModel = AIPlannerViewModel(aiService: ai, recipeService: FakeRecipeService(), snapshotStore: FakeSnapshotStore())
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
        let viewModel = AIPlannerViewModel(aiService: ai, recipeService: FakeRecipeService(), snapshotStore: FakeSnapshotStore())
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
        let viewModel = AIPlannerViewModel(aiService: ai, recipeService: FakeRecipeService(), mealPlanService: meal, groceryService: grocery, snapshotStore: FakeSnapshotStore())
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
        let viewModel = AIPlannerViewModel(aiService: FakeAIService(), recipeService: FakeRecipeService(), mealPlanService: meal, groceryService: FakeGroceryItemService(), snapshotStore: FakeSnapshotStore())
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
        let viewModel = AIPlannerViewModel(aiService: FakeAIService(), recipeService: FakeRecipeService(), mealPlanService: FakeMealPlanService(), groceryService: grocery, snapshotStore: FakeSnapshotStore())
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
        let viewModel = AIPlannerViewModel(aiService: FakeAIService(), recipeService: FakeRecipeService(), mealPlanService: meal, groceryService: FakeGroceryItemService(), snapshotStore: FakeSnapshotStore())
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
        let viewModel = AIPlannerViewModel(aiService: FakeAIService(), recipeService: FakeRecipeService(), mealPlanService: meal, groceryService: FakeGroceryItemService(), snapshotStore: FakeSnapshotStore())
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

    // MARK: - Retry

    @Test func retryResendsTheFailedMessageAndClearsTheFailure() async {
        let ai = FakeAIService()
        ai.errorToThrow = TestError()
        let viewModel = AIPlannerViewModel(aiService: ai, recipeService: FakeRecipeService(), snapshotStore: FakeSnapshotStore())
        viewModel.inputText = "Plan my week"
        await viewModel.send()

        ai.errorToThrow = nil
        ai.responseToReturn = "Here's your week."
        await viewModel.retry()

        #expect(viewModel.messages.count == 2)
        #expect(viewModel.messages[0].content == "Plan my week")
        #expect(viewModel.messages[0].failureReason == nil)
        #expect(viewModel.messages[1].content == "Here's your week.")
        // The same conversation went out again — no duplicated user turn.
        #expect(ai.receivedHistories.count == 2)
        #expect(ai.receivedHistories[1] == [.user("Plan my week")])
    }

    @Test func retryDoesNothingWhenTheLastMessageDidNotFail() async {
        let ai = FakeAIService()
        let viewModel = AIPlannerViewModel(aiService: ai, recipeService: FakeRecipeService(), snapshotStore: FakeSnapshotStore())
        viewModel.inputText = "Hi"
        await viewModel.send()

        await viewModel.retry()

        #expect(ai.receivedHistories.count == 1)
    }

    @Test func sendingANewMessageDropsTheFailedFlagFromAnEarlierOne() async {
        let ai = FakeAIService()
        ai.errorToThrow = TestError()
        let viewModel = AIPlannerViewModel(aiService: ai, recipeService: FakeRecipeService(), snapshotStore: FakeSnapshotStore())
        viewModel.inputText = "First"
        await viewModel.send()

        ai.errorToThrow = nil
        viewModel.inputText = "Second"
        await viewModel.send()

        #expect(viewModel.messages.allSatisfy { $0.failureReason == nil })
        #expect(ai.receivedHistories[1].map(\.content) == ["First", "Second"])
    }

    // MARK: - Add the whole plan

    private static let weekPlan: [AIChatAction] = [
        .addToMealPlan(AIMealPlanProposal(recipeId: 1, recipeTitle: "Tacos", date: "2026-10-26", mealType: "dinner")),
        .addToMealPlan(AIMealPlanProposal(recipeId: 2, recipeTitle: "Ragu", date: "2026-10-27", mealType: "dinner")),
        .addToMealPlan(AIMealPlanProposal(recipeId: 3, recipeTitle: "Stew", date: "2026-10-28", mealType: "dinner")),
    ]

    @Test func applyAllMealPlansWritesEveryUnappliedMealOnce() async {
        let ai = FakeAIService()
        ai.actionsToReturn = Self.weekPlan
        let meal = FakeMealPlanService()
        let viewModel = AIPlannerViewModel(aiService: ai, recipeService: FakeRecipeService(), mealPlanService: meal, groceryService: FakeGroceryItemService(), snapshotStore: FakeSnapshotStore())
        viewModel.inputText = "Plan three dinners"
        await viewModel.send()
        let reply = viewModel.messages[1]
        // One meal was already added individually.
        await viewModel.apply(Self.weekPlan[0])

        #expect(viewModel.unappliedMealPlans(in: reply).count == 2)
        await viewModel.applyAllMealPlans(in: reply)

        #expect(meal.createdDrafts.map(\.recipeId) == [1, 2, 3])
        #expect(Self.weekPlan.allSatisfy(viewModel.hasApplied))
        #expect(viewModel.unappliedMealPlans(in: reply).isEmpty)
        #expect(viewModel.actionResultMessage == "Added 2 meals to your calendar.")
    }

    @Test func applyAllMealPlansStopsOnAFailureAndKeepsWhatLanded() async {
        let ai = FakeAIService()
        ai.actionsToReturn = Self.weekPlan
        let meal = FakeMealPlanService()
        let viewModel = AIPlannerViewModel(aiService: ai, recipeService: FakeRecipeService(), mealPlanService: meal, groceryService: FakeGroceryItemService(), snapshotStore: FakeSnapshotStore())
        viewModel.inputText = "Plan three dinners"
        await viewModel.send()
        meal.failAfter = 1

        await viewModel.applyAllMealPlans(in: viewModel.messages[1])

        #expect(viewModel.hasApplied(Self.weekPlan[0]))
        #expect(!viewModel.hasApplied(Self.weekPlan[1]))
        #expect(viewModel.errorMessage != nil)
        // Tapping again picks up where it stopped.
        #expect(viewModel.unappliedMealPlans(in: viewModel.messages[1]).count == 2)
    }

    // MARK: - Recipe card details

    @Test func namedRecipesGetTheirDetailsFetchedForTheCards() async {
        let ai = FakeAIService()
        ai.responseToReturn = "Try the Beef Tacos."
        ai.recipesToReturn = [AIRecipeRef(id: 2, title: "Beef Tacos")]
        let recipes = FakeRecipeService()
        recipes.recipesToReturn = [
            Recipe(id: 2, userId: nil, title: "Beef Tacos", description: nil, instructions: nil, imagePath: nil, prepTime: 25, servings: 4, createdAt: Date(), atkRating: 4.6),
        ]
        let viewModel = AIPlannerViewModel(aiService: ai, recipeService: recipes, snapshotStore: FakeSnapshotStore())
        viewModel.inputText = "Taco night?"

        await viewModel.send()

        #expect(viewModel.recipeInfo[2]?.prepTime == 25)
        #expect(viewModel.recipeInfo[2]?.atkRating == 4.6)
    }

    @Test func aFailedDetailFetchStillShowsTheReply() async {
        let ai = FakeAIService()
        ai.responseToReturn = "Try the Beef Tacos."
        ai.recipesToReturn = [AIRecipeRef(id: 2, title: "Beef Tacos")]
        let recipes = FakeRecipeService()
        recipes.errorToThrow = TestError()
        let viewModel = AIPlannerViewModel(aiService: ai, recipeService: recipes, snapshotStore: FakeSnapshotStore())
        viewModel.inputText = "Taco night?"

        await viewModel.send()

        #expect(viewModel.messages.count == 2)
        #expect(viewModel.messages[1].recipes.map(\.id) == [2])
        #expect(viewModel.recipeInfo.isEmpty)
        #expect(viewModel.errorMessage == nil) // cards just stay plain
    }

    // MARK: - Persistence

    @Test func theConversationSurvivesARelaunch() async {
        let store = FakeSnapshotStore()
        let ai = FakeAIService()
        ai.responseToReturn = "Try the Beef Tacos."
        ai.recipesToReturn = [AIRecipeRef(id: 2, title: "Beef Tacos")]
        ai.actionsToReturn = [Self.weekPlan[0]]
        let first = AIPlannerViewModel(aiService: ai, recipeService: FakeRecipeService(), mealPlanService: FakeMealPlanService(), groceryService: FakeGroceryItemService(), snapshotStore: store)
        first.inputText = "Taco night?"
        await first.send()
        await first.apply(Self.weekPlan[0])

        let relaunched = AIPlannerViewModel(aiService: FakeAIService(), recipeService: FakeRecipeService(), snapshotStore: store)

        #expect(relaunched.messages.map(\.content) == ["Taco night?", "Try the Beef Tacos."])
        #expect(relaunched.messages[1].recipes.map(\.id) == [2])
        #expect(relaunched.messages[1].actions == [Self.weekPlan[0]])
        #expect(relaunched.hasApplied(Self.weekPlan[0])) // can't be added twice after a relaunch
    }

    @Test func newChatClearsTheSavedConversation() async {
        let store = FakeSnapshotStore()
        let viewModel = AIPlannerViewModel(aiService: FakeAIService(), recipeService: FakeRecipeService(), snapshotStore: store)
        viewModel.inputText = "Hi"
        await viewModel.send()

        viewModel.clearChat()

        #expect(AIPlannerViewModel(aiService: FakeAIService(), recipeService: FakeRecipeService(), snapshotStore: store).messages.isEmpty)
    }

    // MARK: - Follow-ups

    @Test func followUpsShowOnlyUnderTheLatestReply() async {
        let ai = FakeAIService()
        ai.responseToReturn = "Try the Beef Tacos."
        ai.recipesToReturn = [AIRecipeRef(id: 2, title: "Beef Tacos")]
        let viewModel = AIPlannerViewModel(aiService: ai, recipeService: FakeRecipeService(), snapshotStore: FakeSnapshotStore())
        viewModel.inputText = "One"
        await viewModel.send()
        viewModel.inputText = "Two"
        await viewModel.send()

        #expect(viewModel.followUps(for: viewModel.messages[1]).isEmpty)
        #expect(!viewModel.followUps(for: viewModel.messages[3]).isEmpty)
        #expect(viewModel.followUps(for: viewModel.messages[2]).isEmpty) // user turn
    }

    @Test func sendingAFollowUpSendsItsPrompt() async {
        let ai = FakeAIService()
        let viewModel = AIPlannerViewModel(aiService: ai, recipeService: FakeRecipeService(), snapshotStore: FakeSnapshotStore())

        await viewModel.send(ConciergePrompts.starters[0].prompt)

        #expect(ai.receivedPrompts == [ConciergePrompts.starters[0].prompt])
    }
}

