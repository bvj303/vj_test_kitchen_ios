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

    // MARK: - Section headers (**FOR THE X:** markers, from the ATK catalog)

    @Test func extractsBoldLeadingHeaderAsItsOwnElement() {
        // ATK marks a recipe component with a **HEADER:** at the start of the
        // line, immediately followed by that section's first step on the same
        // line. The marker must become a header element and the step must
        // survive without the literal asterisks.
        let text = "**FOR THE BURGERS:** Divide the beef into 4 pieces.\nSmash each ball flat."
        #expect(RecipeInstructions.elements(from: text) == [
            .header("For the Burgers"),
            .step("Divide the beef into 4 pieces."),
            .step("Smash each ball flat.")
        ])
    }

    @Test func headerWithoutTrailingTextIsStillAHeader() {
        let text = "**FOR THE SAUCE:**\nWhisk everything together."
        #expect(RecipeInstructions.elements(from: text) == [
            .header("For the Sauce"),
            .step("Whisk everything together.")
        ])
    }

    @Test func stepsDropsHeaderMarkersButKeepsStepText() {
        // The plain steps(from:) API stays step-only, with the marker stripped
        // from the step text so no literal asterisks ever leak into a caller.
        let text = "**FOR THE FILLING:** Combine the fruit and sugar.\nBake 40 minutes."
        #expect(RecipeInstructions.steps(from: text) == [
            "Combine the fruit and sugar.",
            "Bake 40 minutes."
        ])
    }

    @Test func plainInstructionsHaveOnlyStepElements() {
        let text = "Preheat oven to 400.\nChop the onions."
        #expect(RecipeInstructions.elements(from: text) == [
            .step("Preheat oven to 400."),
            .step("Chop the onions.")
        ])
    }

    @Test func headerTitleCasesShoutyMarkersButKeepsSmallWordsLower() {
        // ATK headers are ALL CAPS ("FOR THE WHIPPED CREAM:"); rendering them
        // verbatim shouts. Title-case them, keeping connective small words down.
        #expect(RecipeInstructions.elements(from: "**FOR THE WHIPPED CREAM:** Whip it.")
            == [.header("For the Whipped Cream"), .step("Whip it.")])
        #expect(RecipeInstructions.elements(from: "**TO SERVE:** Plate it up.")
            == [.header("To Serve"), .step("Plate it up.")])
    }

    @Test func nilOrEmptyYieldsNoElements() {
        #expect(RecipeInstructions.elements(from: nil).isEmpty)
        #expect(RecipeInstructions.elements(from: "").isEmpty)
    }
}
