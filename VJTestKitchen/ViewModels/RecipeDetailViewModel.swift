import Foundation
import Observation

@MainActor
@Observable
final class RecipeDetailViewModel {
    let recipeId: Int64
    private(set) var detail: RecipeDetail?
    private(set) var isLoading = false
    var errorMessage: String?

    var rating: Int?
    var notes = ""

    /// Transient per-session feedback for the ingredient "add to grocery list"
    /// buttons — which ingredients have been added this visit, and whether the
    /// "Add All" action has run. Not reloaded from the server (a standalone
    /// grocery snapshot has no lasting link back to the ingredient it came
    /// from), just enough to flip a "+" to a checkmark.
    private(set) var addedIngredientIds: Set<Int64> = []
    private(set) var didAddAllToGroceryList = false

    private let recipeService: RecipeServicing
    private let ratingService: RecipeRatingServicing
    private let groceryItemService: GroceryItemServicing

    init(
        recipeId: Int64,
        recipeService: RecipeServicing = RecipeService(),
        ratingService: RecipeRatingServicing = RecipeRatingService(),
        groceryItemService: GroceryItemServicing = GroceryItemService()
    ) {
        self.recipeId = recipeId
        self.recipeService = recipeService
        self.ratingService = ratingService
        self.groceryItemService = groceryItemService
    }

    func load() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            async let detailTask = recipeService.fetchDetail(id: recipeId)
            async let ratingTask = ratingService.fetchMine(recipeId: recipeId)
            let (detail, myRating) = try await (detailTask, ratingTask)
            self.detail = detail
            self.rating = myRating?.rating
            self.notes = myRating?.notes ?? ""
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// Adds a single ingredient to the account-synced grocery list as a
    /// standalone item, tagged with this recipe as its source so the grocery
    /// screen's "by recipe" view can group it. Category is auto-guessed.
    /// `scale` mirrors the detail screen's serving scaler so the shopping
    /// quantity matches what the user is actually cooking.
    func addIngredientToGroceryList(_ ingredient: Ingredient, scale: Double = 1) async {
        guard let detail else { return }
        do {
            _ = try await groceryItemService.add(draft(for: ingredient, in: detail, scale: scale))
            addedIngredientIds.insert(ingredient.id)
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// Adds every ingredient at once, each tagged to this recipe.
    func addAllIngredientsToGroceryList(scale: Double = 1) async {
        guard let detail, !detail.ingredients.isEmpty else { return }
        let drafts = detail.ingredients.map { draft(for: $0, in: detail, scale: scale) }
        do {
            _ = try await groceryItemService.addMany(drafts)
            didAddAllToGroceryList = true
            addedIngredientIds.formUnion(detail.ingredients.map(\.id))
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    private func draft(for ingredient: Ingredient, in detail: RecipeDetail, scale: Double) -> GroceryItemDraft {
        // Normalize through IngredientAmount so the imported mixed-number bug
        // (fraction + unit stuck in `name`) doesn't leak into the grocery list,
        // and categorization runs on the clean name.
        let amount = IngredientAmount(amount: ingredient.amount, unit: ingredient.unit, name: ingredient.name)
            .scaled(by: scale)
        return GroceryItemDraft(
            name: amount.name,
            amount: amount.value,
            unit: amount.unit,
            category: GroceryCategorizer.categorize(amount.name),
            sourceRecipeId: detail.id,
            sourceRecipeTitle: detail.title
        )
    }

    func saveRating() async {
        errorMessage = nil
        do {
            try await ratingService.upsertMine(recipeId: recipeId, rating: rating, notes: notes.isEmpty ? nil : notes)
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }
}
