import Foundation
import Testing
@testable import VJTestKitchen

struct IngredientAmountTests {
    // MARK: - Formatting a Double as a mixed fraction

    @Test func formatsWholeNumbers() {
        #expect(IngredientAmount.format(0) == "0")
        #expect(IngredientAmount.format(1) == "1")
        #expect(IngredientAmount.format(12) == "12")
    }

    @Test func formatsCommonFractions() {
        #expect(IngredientAmount.format(0.5) == "½")
        #expect(IngredientAmount.format(0.25) == "¼")
        #expect(IngredientAmount.format(0.75) == "¾")
        #expect(IngredientAmount.format(1.0 / 3.0) == "⅓")
        #expect(IngredientAmount.format(2.0 / 3.0) == "⅔")
        #expect(IngredientAmount.format(0.125) == "⅛")
    }

    @Test func formatsMixedNumbers() {
        #expect(IngredientAmount.format(1.5) == "1½")
        #expect(IngredientAmount.format(2.25) == "2¼")
        #expect(IngredientAmount.format(4.5) == "4½")
    }

    @Test func formatsUnrepresentableFractionAsTrimmedDecimal() {
        // 0.4 isn't a common cooking fraction — fall back to a clean decimal.
        #expect(IngredientAmount.format(0.4) == "0.4")
        #expect(IngredientAmount.format(1.1) == "1.1")
    }

    // MARK: - Normalizing the mixed-number import bug

    @Test func reunitesFractionStuckInName() {
        // The classic bug: "1½ teaspoons paprika" imported as amount=1, unit="",
        // name="½ teaspoons paprika".
        let amt = IngredientAmount(amount: 1, unit: "", name: "½ teaspoons paprika")
        #expect(amt.value == 1.5)
        #expect(amt.unit == "teaspoons")
        #expect(amt.name == "paprika")
        #expect(amt.formatted == "1½ teaspoons")
    }

    @Test func reunitesWithLargerWholePart() {
        let amt = IngredientAmount(amount: 2, unit: "", name: "½ cups chicken broth")
        #expect(amt.value == 2.5)
        #expect(amt.unit == "cups")
        #expect(amt.name == "chicken broth")
    }

    @Test func handlesTwoWordFluidOunceUnit() {
        let amt = IngredientAmount(amount: 1, unit: "", name: "½ fluid ounces (3 tablespoons) gin")
        #expect(amt.value == 1.5)
        #expect(amt.unit == "fluid ounces")
        #expect(amt.name == "(3 tablespoons) gin")
    }

    @Test func leavesWellFormedRowUntouched() {
        // Non-buggy row: amount already correct, unit separate.
        let amt = IngredientAmount(amount: 0.5, unit: "cup", name: "granulated sugar")
        #expect(amt.value == 0.5)
        #expect(amt.unit == "cup")
        #expect(amt.name == "granulated sugar")
        #expect(amt.formatted == "½ cup")
    }

    @Test func doesNotTouchNameWithoutLeadingFraction() {
        let amt = IngredientAmount(amount: 2, unit: "pounds", name: "ripe tomatoes, cored")
        #expect(amt.value == 2)
        #expect(amt.unit == "pounds")
        #expect(amt.name == "ripe tomatoes, cored")
    }

    @Test func doesNotReuniteWhenUnitAlreadyPresent() {
        // If the row already has a unit, a leading glyph in the name is real
        // content, not the split-off fraction — leave it alone.
        let amt = IngredientAmount(amount: 1, unit: "cup", name: "½-inch diced onion")
        #expect(amt.value == 1)
        #expect(amt.unit == "cup")
        #expect(amt.name == "½-inch diced onion")
    }

    @Test func handlesAsciiFractionInName() {
        let amt = IngredientAmount(amount: 1, unit: "", name: "1/2 teaspoon table salt")
        #expect(amt.value == 1.5)
        #expect(amt.unit == "teaspoon")
        #expect(amt.name == "table salt")
    }

    @Test func unitlessRemainderStaysInName() {
        // A leading fraction with no recognizable unit word after it — still
        // reunite the number, just leave the rest as the name.
        let amt = IngredientAmount(amount: 1, unit: "", name: "½ recipe pie dough")
        #expect(amt.value == 1.5)
        #expect(amt.name == "recipe pie dough")
    }

    // MARK: - Name tidying (whitespace before punctuation)

    @Test func trimsSpaceBeforeCommaInName() {
        // The import left a stray space before the comma: "table salt , divided".
        let amt = IngredientAmount(amount: 1, unit: "teaspoon", name: "table salt , divided")
        #expect(amt.name == "table salt, divided")
    }

    @Test func tidyNameHandlesVariousPunctuation() {
        #expect(IngredientAmount.tidyName("table salt , divided") == "table salt, divided")
        #expect(IngredientAmount.tidyName("onion , diced ; peeled") == "onion, diced; peeled")
        // Normal punctuation-then-space is untouched, and internal runs collapse.
        #expect(IngredientAmount.tidyName("ripe tomatoes, cored") == "ripe tomatoes, cored")
        #expect(IngredientAmount.tidyName("flour   sifted") == "flour sifted")
    }

    @Test func tidiesNameOnTheReunitePath() {
        // Fraction reunited *and* the trailing name cleaned in one pass.
        let amt = IngredientAmount(amount: 1, unit: "", name: "½ teaspoon table salt , divided")
        #expect(amt.value == 1.5)
        #expect(amt.unit == "teaspoon")
        #expect(amt.name == "table salt, divided")
        #expect(amt.formatted == "1½ teaspoons")
    }

    // MARK: - Distinct amounts across a set and across serving scales

    @Test func distinctIngredientsKeepDistinctAmounts() {
        // A spice blend where several rows legitimately share "1½ tsp" must not
        // flatten *other* rows to the same value — each reflects its own source
        // amount (guards against the "every ingredient shows 1½" report).
        let rows: [(Double, String, String)] = [
            (2, "teaspoons", "paprika"),
            (1, "teaspoon", "table salt"),
            (1, "", "½ teaspoon pepper"),   // reunites to 1.5
            (0.5, "teaspoon", "dried thyme"),
            (0.25, "teaspoon", "dried oregano"),
        ]
        let amounts = rows.map { IngredientAmount(amount: $0.0, unit: $0.1, name: $0.2) }
        #expect(amounts.map(\.value) == [2, 1, 1.5, 0.5, 0.25])
        #expect(amounts.map(\.formatted) == [
            "2 teaspoons", "1 teaspoon", "1½ teaspoons", "½ teaspoon", "¼ teaspoon",
        ])
    }

    @Test func amountsScaleIndependentlyAcrossServings() {
        let paprika = IngredientAmount(amount: 2, unit: "teaspoons", name: "paprika")
        let thyme = IngredientAmount(amount: 0.5, unit: "teaspoon", name: "dried thyme")
        // Doubling the recipe doubles each amount by its own value, not a shared one.
        #expect(paprika.scaled(by: 2).formatted == "4 teaspoons")
        #expect(thyme.scaled(by: 2).formatted == "1 teaspoon")
        // Halving keeps them distinct too.
        #expect(paprika.scaled(by: 0.5).formatted == "1 teaspoon")
        #expect(thyme.scaled(by: 0.5).formatted == "¼ teaspoon")
    }

    // MARK: - Scaling

    @Test func scalingMultipliesOnlyTheValue() {
        let amt = IngredientAmount(amount: 1, unit: "", name: "½ teaspoons paprika")
        let doubled = amt.scaled(by: 2)
        #expect(doubled.value == 3)
        #expect(doubled.unit == "teaspoons")
        #expect(doubled.name == "paprika")
        #expect(doubled.formatted == "3 teaspoons")
    }

    @Test func halvingProducesFraction() {
        let amt = IngredientAmount(amount: 0.5, unit: "cup", name: "sugar")
        #expect(amt.scaled(by: 0.5).formatted == "¼ cup")
    }

    @Test func triplingAcrossFraction() {
        let amt = IngredientAmount(amount: 0.75, unit: "cup", name: "milk")
        // 0.75 * 3 = 2.25 -> "2¼ cups" (plural, since the value is above one)
        #expect(amt.scaled(by: 3).formatted == "2¼ cups")
    }

    @Test func formattedOmitsUnitWhenEmpty() {
        let amt = IngredientAmount(amount: 3, unit: "", name: "eggs")
        #expect(amt.formatted == "3")
    }

    // MARK: - Unit pluralization

    @Test func pluralizesUnitsAboveOne() {
        #expect(IngredientAmount.pluralizedUnit("cup", for: 2) == "cups")
        #expect(IngredientAmount.pluralizedUnit("clove", for: 3) == "cloves")
        #expect(IngredientAmount.pluralizedUnit("pinch", for: 2) == "pinches")
        #expect(IngredientAmount.pluralizedUnit("box", for: 2) == "boxes")
        #expect(IngredientAmount.pluralizedUnit("leaf", for: 4) == "leaves")
        #expect(IngredientAmount.pluralizedUnit("cup", for: 1.5) == "cups")
    }

    @Test func keepsUnitsSingularAtOneOrBelow() {
        #expect(IngredientAmount.pluralizedUnit("cups", for: 1) == "cup")
        #expect(IngredientAmount.pluralizedUnit("cloves", for: 0.5) == "clove")
        #expect(IngredientAmount.pluralizedUnit("leaves", for: 1) == "leaf")
        // A pure fraction stays singular, matching how recipes read.
        #expect(IngredientAmount.pluralizedUnit("cup", for: 0.25) == "cup")
    }

    @Test func abbreviatedAndEmptyUnitsNeverInflect() {
        #expect(IngredientAmount.pluralizedUnit("g", for: 200) == "g")
        #expect(IngredientAmount.pluralizedUnit("tbsp", for: 3) == "tbsp")
        #expect(IngredientAmount.pluralizedUnit("oz", for: 12) == "oz")
        #expect(IngredientAmount.pluralizedUnit("", for: 5) == "")
    }
}
