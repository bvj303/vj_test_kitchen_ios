import Foundation
import Testing
@testable import VJTestKitchen

/// The Kitchen Concierge's tap-to-send prompts: starters on an empty chat, and
/// follow-ups under the latest reply chosen from what that reply contains, so
/// the conversation always has an obvious next step instead of a blank field.
struct ConciergePromptsTests {
    @Test func startersAreDistinctAndTiedToPlanningTheWeek() {
        let starters = ConciergePrompts.starters
        #expect(starters.count == 4)
        #expect(Set(starters.map(\.label)).count == starters.count)
        #expect(Set(starters.map(\.prompt)).count == starters.count)
        #expect(starters.contains { $0.prompt.localizedCaseInsensitiveContains("this week") })
    }

    @Test func aPlannedMenuOffersTheGroceryListAndASwap() {
        let followUps = ConciergePrompts.followUps(recipeCount: 3, mealPlanActionCount: 3, groceryActionCount: 0)
        let labels = followUps.map(\.label)
        #expect(labels.contains("Make a grocery list"))
        #expect(labels.contains("Swap a meal"))
    }

    @Test func recipeSuggestionsWithoutAPlanOfferToPlanThemOrNarrowDown() {
        let labels = ConciergePrompts.followUps(recipeCount: 2, mealPlanActionCount: 0, groceryActionCount: 0).map(\.label)
        #expect(labels.contains("Plan these this week"))
        #expect(labels.contains("Something quicker"))
        #expect(labels.contains("Show different ones"))
    }

    @Test func aGroceryProposalOffersToPlanTheMeal() {
        let labels = ConciergePrompts.followUps(recipeCount: 1, mealPlanActionCount: 0, groceryActionCount: 1).map(\.label)
        #expect(labels.contains("Add it to my calendar"))
        #expect(!labels.contains("Make a grocery list")) // already proposed
    }

    @Test func aReplyWithNothingActionableSuggestsGettingStarted() {
        let labels = ConciergePrompts.followUps(recipeCount: 0, mealPlanActionCount: 0, groceryActionCount: 0).map(\.label)
        #expect(labels.contains("Suggest some recipes"))
        #expect(labels.contains("Plan this week's dinners"))
    }

    @Test func followUpsAreCappedAtThreeAndUnique() {
        for recipes in 0...3 {
            for plans in 0...3 {
                for grocery in 0...1 {
                    let followUps = ConciergePrompts.followUps(recipeCount: recipes, mealPlanActionCount: plans, groceryActionCount: grocery)
                    #expect(!followUps.isEmpty)
                    #expect(followUps.count <= 3)
                    #expect(Set(followUps.map(\.label)).count == followUps.count)
                }
            }
        }
    }
}
