import Foundation
import Observation

/// Backs the Home tab: a context-aware suggested-recipes shelf. Follows the
/// Service/`@Observable` pattern used across the app — all data comes through an
/// injected service so the whole thing is unit-testable without a network or a
/// session.
///
/// The shelf **rotates**: each `load()` (tab switch or pull-to-refresh) pulls a
/// larger pool matching the day's suggestion, shuffles it, and shows a slice —
/// so the Home screen feels alive rather than a static list of the same recipes.
@MainActor
@Observable
final class HomeViewModel {
    /// The calendar-derived cooking suggestion (weeknight/weekend + season).
    /// Computed once from the reference date, since the Home screen is
    /// re-created on tab switch anyway.
    let suggestion: RecipeSuggestion

    private(set) var suggestedRecipes: [Recipe] = []
    private(set) var isLoading = false
    var errorMessage: String?

    private let recipeService: RecipeServicing

    /// How many recipes the shelf shows at once…
    private static let displayCount = 8
    /// …drawn (and shuffled) from a larger pool, so repeat visits surface a
    /// different slice instead of the same first-N every time.
    private static let poolSize = 40

    init(
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        recipeService: RecipeServicing = RecipeService()
    ) {
        self.recipeService = recipeService
        self.suggestion = RecipeSuggester.suggestion(for: referenceDate, calendar: calendar)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        await loadSuggestedRecipes()
    }

    private func loadSuggestedRecipes() async {
        do {
            var pool = try await recipeService.fetchPage(
                offset: 0, limit: Self.poolSize,
                matching: suggestion.keyword, tag: nil, maxPrepTime: suggestion.maxPrepTime
            )
            // The seasonal keyword might match nothing in a small/partial
            // catalog — fall back to a plain page so the shelf is never empty
            // just because "grilled" isn't in the imported subset.
            if pool.isEmpty {
                pool = try await recipeService.fetchPage(offset: 0, limit: Self.poolSize, matching: nil)
            }
            // Shuffle then slice so the shelf rotates on each load/refresh.
            suggestedRecipes = Array(pool.shuffled().prefix(Self.displayCount))
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }
}
