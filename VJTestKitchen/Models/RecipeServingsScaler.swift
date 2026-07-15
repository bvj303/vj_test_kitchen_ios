import Foundation

/// Pure math behind Recipe Detail's interactive servings stepper.
///
/// Scaling is stored as a multiplier (`scale`, 1 = original) because that's what
/// flows straight into the shared `IngredientAmount` formatter and Cook Mode.
/// This converts between that multiplier and the whole-servings count the stepper
/// shows and nudges, so stepping stays on clean serving counts (4 → 5 → 6) rather
/// than drifting multipliers. Pure and unit-tested, same shape as
/// `HolidayProvider` / `MealTypeStyle`.
enum RecipeServingsScaler {
    /// The whole-servings count shown for a recipe whose original yield is
    /// `base`, at the given `scale`. Never below 1.
    static func displayedServings(base: Int, scale: Double) -> Int {
        guard base > 0 else { return 0 }
        return max(1, Int((Double(base) * scale).rounded()))
    }

    /// The new multiplier after nudging the shown servings by `delta` (+1 / −1),
    /// clamped so servings never drops below 1. Derived from the *displayed*
    /// count so repeated steps land on whole servings.
    static func steppedScale(base: Int, scale: Double, delta: Int) -> Double {
        guard base > 0 else { return scale }
        let target = max(1, displayedServings(base: base, scale: scale) + delta)
        return Double(target) / Double(base)
    }

    /// Whether the − button is meaningful (false once already at 1 serving).
    static func canDecrease(base: Int, scale: Double) -> Bool {
        displayedServings(base: base, scale: scale) > 1
    }
}
