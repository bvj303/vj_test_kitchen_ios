import Foundation
import Testing
@testable import VJTestKitchen

struct RecipeInstructionsTests {
    @Test func splitsNewlineDelimitedStepsInOrder() {
        let text = "Preheat oven to 400.\nChop the onions.\nRoast for 20 minutes."
        #expect(RecipeInstructions.steps(from: text) == [
            "Preheat oven to 400.",
            "Chop the onions.",
            "Roast for 20 minutes."
        ])
    }

    @Test func singleParagraphIsOneStep() {
        #expect(RecipeInstructions.steps(from: "Just mix everything together.")
            == ["Just mix everything together."])
    }

    @Test func nilOrEmptyYieldsNoSteps() {
        #expect(RecipeInstructions.steps(from: nil).isEmpty)
        #expect(RecipeInstructions.steps(from: "").isEmpty)
        #expect(RecipeInstructions.steps(from: "\n\n  \n").isEmpty)
    }

    @Test func trimsWhitespaceAndDropsBlankLines() {
        let text = "  Step one.  \n\n   \n  Step two.  "
        #expect(RecipeInstructions.steps(from: text) == ["Step one.", "Step two."])
    }

    @Test func stripsPreExistingLeadingNumbering() {
        let text = "1. Preheat oven.\n2) Chop onions.\nStep 3: Roast."
        #expect(RecipeInstructions.steps(from: text) == [
            "Preheat oven.",
            "Chop onions.",
            "Roast."
        ])
    }

    @Test func doesNotStripNumbersThatArePartOfTheStep() {
        // A bare measurement like "2 cups" must survive — only leading step
        // numbering (followed by . ) : -) is removed.
        #expect(RecipeInstructions.steps(from: "2 cups flour, sifted")
            == ["2 cups flour, sifted"])
    }
}
