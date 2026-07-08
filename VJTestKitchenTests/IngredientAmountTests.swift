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
        // 0.75 * 3 = 2.25 -> "2¼ cup"
        #expect(amt.scaled(by: 3).formatted == "2¼ cup")
    }

    @Test func formattedOmitsUnitWhenEmpty() {
        let amt = IngredientAmount(amount: 3, unit: "", name: "eggs")
        #expect(amt.formatted == "3")
    }
}
