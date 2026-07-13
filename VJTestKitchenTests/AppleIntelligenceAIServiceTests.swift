import Foundation
import Testing
import FoundationModels
@testable import VJTestKitchen

private func makeRecipe(_ id: Int64, _ title: String, prep: Int? = nil, servings: Int? = nil) -> Recipe {
    Recipe(id: id, userId: nil, title: title, description: nil, instructions: nil,
           imagePath: nil, prepTime: prep, servings: servings, createdAt: Date())
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
        // Prior turns are labeled context; the latest user turn is the ask.
        #expect(prompt.contains("User: Suggest a pasta"))
        #expect(prompt.contains("Assistant: How about Spaghetti Carbonara?"))
        #expect(prompt.contains("The user now says: Something else"))
    }

    @Test func promptTextSkipsBlankTurns() {
        let prompt = AppleIntelligenceAIService.promptText(from: [.user("   "), .user("Real question")])
        #expect(prompt == "Real question")
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

    // MARK: - SearchRecipesTool.formatResults

    @Test func formatResultsStatesWhenNothingMatched() {
        let text = SearchRecipesTool.formatResults([], query: "unicorn stew")
        #expect(text.contains("unicorn stew"))
        #expect(text.localizedCaseInsensitiveContains("no recipes"))
    }

    @Test func formatResultsListsTitlesWithStats() {
        let text = SearchRecipesTool.formatResults(
            [makeRecipe(1, "Spaghetti Carbonara", prep: 20, servings: 4)],
            query: "carbonara"
        )
        #expect(text.contains("\"Spaghetti Carbonara\""))
        #expect(text.contains("prep 20 min"))
        #expect(text.contains("serves 4"))
    }

    @Test func formatResultsOmitsMissingStats() {
        let text = SearchRecipesTool.formatResults([makeRecipe(1, "Mystery Dish")], query: "x")
        #expect(text.contains("\"Mystery Dish\""))
        #expect(!text.contains("prep"))
        #expect(!text.contains("serves"))
    }

    // MARK: - RecipeReferenceSink

    @Test func sinkDedupesByIdAndDrains() async {
        let sink = RecipeReferenceSink()
        await sink.add([AIRecipeRef(id: 1, title: "A"), AIRecipeRef(id: 2, title: "B")])
        await sink.add([AIRecipeRef(id: 2, title: "B"), AIRecipeRef(id: 3, title: "C")])
        let drained = await sink.drain()
        #expect(drained.map(\.id) == [1, 2, 3])
        // Draining clears, so a second drain is empty.
        let again = await sink.drain()
        #expect(again.isEmpty)
    }
}
