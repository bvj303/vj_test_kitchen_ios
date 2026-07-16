import Foundation
import Testing
import FoundationModels
@testable import VJTestKitchen

private func makeRecipe(_ id: Int64, _ title: String, prep: Int? = nil, servings: Int? = nil) -> Recipe {
    Recipe(id: id, userId: nil, title: title, description: nil, instructions: nil,
           imagePath: nil, prepTime: prep, servings: servings, createdAt: Date())
}

/// Records the filters of each `fetchPage` and returns canned pages in order, so
/// the retrieval ladder can be exercised without a network or the model. An
/// actor (Sendable) rather than an @unchecked class — the mac test host has
/// crashed on the latter (see memory: @MainActor test fakes).
private actor StubRecipeService: RecipeServicing {
    private var responses: [[Recipe]]
    private let total: Int
    private(set) var callFilters: [(query: String?, tag: String?, maxPrepTime: Int?)] = []
    private(set) var callOffsets: [Int] = []

    init(responses: [[Recipe]], total: Int = 0) {
        self.responses = responses
        self.total = total
    }

    func fetchPage(offset: Int, limit: Int, matching search: String?, tag: String?, minPrepTime: Int?, maxPrepTime: Int?, minAtkRating: Double?) async throws -> [Recipe] {
        callFilters.append((search, tag, maxPrepTime))
        callOffsets.append(offset)
        return responses.isEmpty ? [] : responses.removeFirst()
    }

    func totalCount() async throws -> Int { total }

    func fetchDetail(id: Int64) async throws -> RecipeDetail { fatalError("not used") }
    func create(_ draft: RecipeDraft) async throws -> Recipe { fatalError("not used") }
    func update(id: Int64, with draft: RecipeDraft) async throws { fatalError("not used") }
    func delete(id: Int64) async throws { fatalError("not used") }
}

struct AppleIntelligenceAIServiceTests {

    // MARK: - promptText(from:)

    @Test func promptTextPassesSingleTurnThrough() {
        let prompt = AppleIntelligenceAIService.promptText(from: [.user("Find me a carbonara")])
        #expect(prompt == "Find me a carbonara")
    }

    @Test func promptTextEmptyForEmptyHistory() {
        #expect(AppleIntelligenceAIService.promptText(from: []).isEmpty)
    }

    @Test func promptTextIncludesPriorTurnsAsContext() {
        let prompt = AppleIntelligenceAIService.promptText(from: [
            .user("Suggest a pasta"),
            .assistant("How about Spaghetti Carbonara?"),
            .user("Something else"),
        ])
        #expect(prompt.contains("User: Suggest a pasta"))
        #expect(prompt.contains("Assistant: How about Spaghetti Carbonara?"))
        #expect(prompt.contains("The user now says: Something else"))
    }

    // MARK: - latestUserText

    @Test func latestUserTextPicksLastUserTurn() {
        let text = AppleIntelligenceAIService.latestUserText(from: [
            .user("first"),
            .assistant("reply"),
            .user("  second  "),
        ])
        #expect(text == "second")
    }

    @Test func latestUserTextEmptyWhenNoUserTurn() {
        #expect(AppleIntelligenceAIService.latestUserText(from: [.assistant("hi")]).isEmpty)
    }

    // MARK: - normalize

    @Test func normalizeTreatsEmptyAndZeroAsUnspecified() {
        let params = AppleIntelligenceAIService.normalize(
            AppleIntelligenceAIService.RecipeQuery(query: "  ", tag: "", maxPrepTime: 0)
        )
        #expect(params == AppleIntelligenceAIService.SearchParams(query: nil, tag: nil, maxPrepTime: nil))
    }

    @Test func normalizeKeepsRealValues() {
        let params = AppleIntelligenceAIService.normalize(
            AppleIntelligenceAIService.RecipeQuery(query: "chicken", tag: "Dinner", maxPrepTime: 30)
        )
        #expect(params == AppleIntelligenceAIService.SearchParams(query: "chicken", tag: "Dinner", maxPrepTime: 30))
    }

    // MARK: - retrieve (the grounding ladder)

    @Test func retrieveReturnsSpecificMatchWithoutWidening() async throws {
        let stub = StubRecipeService(responses: [[makeRecipe(1, "Chicken Soup")]])
        let service = AppleIntelligenceAIService(recipeService: stub)
        let recipes = try await service.retrieve(query: "chicken", tag: "Dinner", maxPrepTime: 30)
        #expect(recipes.map(\.id) == [1])
        let calls = await stub.callFilters
        #expect(calls.count == 1) // no widening needed
        #expect(calls[0].tag == "Dinner")
    }

    @Test func retrieveDropsFiltersWhenSpecificSearchIsEmpty() async throws {
        // First (filtered) call empty, second (filters dropped) returns a match.
        let stub = StubRecipeService(responses: [[], [makeRecipe(2, "Quick Pasta")]])
        let service = AppleIntelligenceAIService(recipeService: stub)
        let recipes = try await service.retrieve(query: "pasta", tag: "Italian", maxPrepTime: 15)
        #expect(recipes.map(\.id) == [2])
        let calls = await stub.callFilters
        #expect(calls.count == 2)
        #expect(calls[0].tag == "Italian")   // first tried with filters
        #expect(calls[1].tag == nil)          // then dropped them
        #expect(calls[1].query == "pasta")    // but kept the query
    }

    @Test func retrieveFallsBackToGeneralPageWhenNothingMatches() async throws {
        // Every filtered attempt empty; the general page (matching nil) returns.
        let stub = StubRecipeService(responses: [[], [makeRecipe(3, "Anything")]])
        let service = AppleIntelligenceAIService(recipeService: stub)
        let recipes = try await service.retrieve(query: "zzzznomatch", tag: nil, maxPrepTime: nil)
        #expect(recipes.map(\.id) == [3])
        let calls = await stub.callFilters
        #expect(calls.count == 2)
        #expect(calls.last?.query == nil) // general page has no title filter
    }

    @Test func retrieveOpenEndedSamplesTheCatalog() async throws {
        // No query/tag/prep → should sample the catalog (a general, matching:nil
        // fetch), not try a filtered search first.
        let stub = StubRecipeService(responses: [[makeRecipe(9, "Something Good")]])
        let service = AppleIntelligenceAIService(recipeService: stub)
        let recipes = try await service.retrieve(query: nil, tag: nil, maxPrepTime: nil)
        #expect(recipes.map(\.id) == [9])
        let calls = await stub.callFilters
        #expect(calls.count == 1)
        #expect(calls[0].query == nil) // straight to the general catalog sample
    }

    @Test func retrieveShufflesAndCapsToGroundingLimit() async throws {
        // A pool larger than the grounding limit is sampled down to it, and
        // every returned recipe comes from the pool (order may differ — shuffled).
        let pool = (1...60).map { makeRecipe(Int64($0), "Recipe \($0)") }
        let stub = StubRecipeService(responses: [pool])
        let service = AppleIntelligenceAIService(recipeService: stub)
        let recipes = try await service.retrieve(query: "anything", tag: nil, maxPrepTime: nil)
        #expect(recipes.count == AppleIntelligenceAIService.groundingLimit)
        let poolIds = Set(pool.map(\.id))
        #expect(recipes.allSatisfy { poolIds.contains($0.id) })
        #expect(Set(recipes.map(\.id)).count == recipes.count) // no dupes
    }

    @Test func retrieveRandomOffsetStaysWithinCatalog() async throws {
        // With a known large catalog, the open-ended sample's offset must land in
        // [0, total - poolLimit] so the page is always full/valid.
        let total = 10_000
        let stub = StubRecipeService(responses: [[makeRecipe(1, "X")]], total: total)
        let service = AppleIntelligenceAIService(recipeService: stub)
        _ = try await service.retrieve(query: nil, tag: nil, maxPrepTime: nil)
        let offsets = await stub.callOffsets
        #expect(offsets.count == 1)
        #expect(offsets[0] >= 0)
        #expect(offsets[0] <= total - AppleIntelligenceAIService.poolLimit)
    }

    // MARK: - groundedPrompt

    @Test func groundedPromptListsRealRecipesAndTheAsk() {
        let prompt = AppleIntelligenceAIService.groundedPrompt(
            history: [.user("what can I make with chicken?")],
            recipes: [makeRecipe(1, "Roast Chicken", prep: 60, servings: 4)]
        )
        #expect(prompt.contains("\"Roast Chicken\""))
        #expect(prompt.contains("prep 60 min"))
        #expect(prompt.contains("what can I make with chicken?"))
    }

    @Test func groundedPromptStatesWhenCollectionEmpty() {
        let prompt = AppleIntelligenceAIService.groundedPrompt(
            history: [.user("dinner ideas")],
            recipes: []
        )
        #expect(prompt.localizedCaseInsensitiveContains("no recipes"))
    }

    // MARK: - unavailableReason(for:)

    @Test func availableModelHasNoReason() {
        #expect(AppleIntelligenceAIService.unavailableReason(for: .available) == nil)
    }

    @Test func ineligibleDeviceMentionsAppleIntelligence() {
        let reason = AppleIntelligenceAIService.unavailableReason(for: .unavailable(.deviceNotEligible))
        #expect(reason?.contains("Apple Intelligence") == true)
    }

    @Test func disabledIntelligencePointsToSettings() {
        let reason = AppleIntelligenceAIService.unavailableReason(for: .unavailable(.appleIntelligenceNotEnabled))
        #expect(reason?.localizedCaseInsensitiveContains("Settings") == true)
    }

    @Test func modelNotReadyAsksToRetry() {
        let reason = AppleIntelligenceAIService.unavailableReason(for: .unavailable(.modelNotReady))
        #expect(reason != nil)
    }

    // MARK: - formatResults

    @Test func formatResultsStatesWhenNothingMatched() {
        let text = AppleIntelligenceAIService.formatResults([], query: "unicorn stew")
        #expect(text.contains("unicorn stew"))
        #expect(text.localizedCaseInsensitiveContains("no recipes"))
    }

    @Test func formatResultsListsTitlesWithStats() {
        let text = AppleIntelligenceAIService.formatResults(
            [makeRecipe(1, "Spaghetti Carbonara", prep: 20, servings: 4)],
            query: "carbonara"
        )
        #expect(text.contains("\"Spaghetti Carbonara\""))
        #expect(text.contains("prep 20 min"))
        #expect(text.contains("serves 4"))
    }
}
