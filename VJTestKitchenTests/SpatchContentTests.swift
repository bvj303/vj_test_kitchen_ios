import Foundation
import Testing
@testable import VJTestKitchen

struct SpatchContentTests {
    // MARK: - Pools

    @Test func jokePoolIsNonEmptyAndReturnsAJoke() {
        #expect(!SpatchContent.jokes.isEmpty)
        #expect(SpatchContent.jokes.contains(SpatchContent.randomJoke()))
    }

    @Test func encouragementPoolIsNonEmptyAndReturnsALine() {
        #expect(!SpatchContent.encouragements.isEmpty)
        #expect(SpatchContent.encouragements.contains(SpatchContent.randomEncouragement()))
    }

    @Test func catchphrasePoolIsNonEmptyAndReturnsALine() {
        #expect(!SpatchContent.catchphrases.isEmpty)
        #expect(SpatchContent.catchphrases.contains(SpatchContent.randomCatchphrase()))
    }

    @Test func recommendationLinesAvoidPushyLanguage() {
        // Softer nudges, not a hard sell — no "trust me", guilt, or urgency framing.
        let lines = SpatchContent.recommendationTemplates(for: "Test Recipe").map { $0.lowercased() }
        let pushyPhrases = ["trust me", "the move tonight", "might change your whole week"]
        for phrase in pushyPhrases {
            #expect(!lines.contains { $0.contains(phrase) })
        }
    }

    // MARK: - Home recommendation line

    @Test func recommendationLineFallsBackToEncouragementWithoutATitle() {
        let line = SpatchContent.recommendationLine(recipeTitle: nil)
        #expect(SpatchContent.encouragements.contains(line))
    }

    @Test func recommendationLineReferencesTheGivenTitle() {
        let line = SpatchContent.recommendationLine(recipeTitle: "Spaghetti Carbonara")
        #expect(line.contains("Spaghetti Carbonara"))
    }

    // MARK: - Recipe Detail cameo line

    @Test func recipeCameoLineReferencesAShortPrepTime() {
        let line = SpatchContent.recipeCameoLine(prepTime: 15, tag: nil)
        #expect(line.contains("15"))
    }

    @Test func recipeCameoLineReferencesALongPrepTime() {
        let line = SpatchContent.recipeCameoLine(prepTime: 90, tag: nil)
        #expect(line.contains("90"))
    }

    @Test func recipeCameoLineReferencesTheTag() {
        let line = SpatchContent.recipeCameoLine(prepTime: nil, tag: "Dessert")
        #expect(line.contains("dessert"))
    }

    @Test func recipeCameoLineFallsBackToAJokeWithoutContext() {
        let line = SpatchContent.recipeCameoLine(prepTime: nil, tag: nil)
        #expect(SpatchContent.jokes.contains(line))
    }

    // MARK: - Cook Mode lines

    @Test func cookModeEncouragementVariesByProgressBucket() {
        #expect(!SpatchContent.cookModeEncouragement(progress: 0).isEmpty)
        #expect(!SpatchContent.cookModeEncouragement(progress: 0.5).isEmpty)
        #expect(!SpatchContent.cookModeEncouragement(progress: 0.9).isEmpty)
    }

    @Test func completionLinePoolIsNonEmptyAndReturnsALine() {
        #expect(!SpatchContent.cookModeCompletionLines.isEmpty)
        #expect(SpatchContent.cookModeCompletionLines.contains(SpatchContent.randomCompletionLine()))
    }

    // MARK: - Tutorial

    @Test func tutorialHasAtLeastOneStepPerCoreTab() {
        // Home, Recipes, Calendar, Grocery, AI Planner, plus an intro + outro.
        #expect(SpatchContent.tutorialSteps.count >= 6)
    }

    @Test func tutorialStepsAreNonEmpty() {
        for step in SpatchContent.tutorialSteps {
            #expect(!step.title.isEmpty)
            #expect(!step.message.isEmpty)
            #expect(!step.symbol.isEmpty)
        }
    }
}
