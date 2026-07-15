import Testing
@testable import VJTestKitchen

/// The servings stepper's pure math: stepping stays on whole servings, clamps at
/// 1, and the multiplier it produces scales ingredients through the shared
/// `IngredientAmount` formatter.
struct RecipeServingsScalerTests {
    @Test func displaysBaseAtOriginalScale() {
        #expect(RecipeServingsScaler.displayedServings(base: 4, scale: 1) == 4)
    }

    @Test func displaysScaledCount() {
        #expect(RecipeServingsScaler.displayedServings(base: 4, scale: 1.5) == 6)
        #expect(RecipeServingsScaler.displayedServings(base: 4, scale: 0.5) == 2)
    }

    @Test func steppingUpAddsOneServing() {
        // 4 servings +1 -> 5 -> multiplier 5/4.
        #expect(RecipeServingsScaler.steppedScale(base: 4, scale: 1, delta: 1) == 1.25)
        #expect(RecipeServingsScaler.displayedServings(base: 4, scale: 1.25) == 5)
    }

    @Test func steppingDownSubtractsOneServing() {
        #expect(RecipeServingsScaler.steppedScale(base: 4, scale: 1, delta: -1) == 0.75)
        #expect(RecipeServingsScaler.displayedServings(base: 4, scale: 0.75) == 3)
    }

    @Test func repeatedStepsStayOnWholeServings() {
        var scale = 1.0
        scale = RecipeServingsScaler.steppedScale(base: 3, scale: scale, delta: 1) // 4
        scale = RecipeServingsScaler.steppedScale(base: 3, scale: scale, delta: 1) // 5
        #expect(RecipeServingsScaler.displayedServings(base: 3, scale: scale) == 5)
    }

    @Test func neverGoesBelowOneServing() {
        let atOne = RecipeServingsScaler.steppedScale(base: 4, scale: 0.25, delta: -1) // already 1
        #expect(RecipeServingsScaler.displayedServings(base: 4, scale: atOne) == 1)
        #expect(RecipeServingsScaler.canDecrease(base: 4, scale: atOne) == false)
        #expect(RecipeServingsScaler.canDecrease(base: 4, scale: 1) == true)
    }

    @Test func scaledMultiplierFeedsIngredientFormatter() {
        // 2 cups at 6/4 servings -> 3 cups, via the same formatter grocery uses.
        let scale = RecipeServingsScaler.steppedScale(base: 4, scale: 1, delta: 2) // 6 servings, 1.5x
        let amount = IngredientAmount(amount: 2, unit: "cups", name: "flour").scaled(by: scale)
        #expect(amount.formatted == "3 cups")
    }

    @Test func zeroBaseIsInert() {
        #expect(RecipeServingsScaler.steppedScale(base: 0, scale: 1, delta: 1) == 1)
        #expect(RecipeServingsScaler.displayedServings(base: 0, scale: 1) == 0)
    }
}
