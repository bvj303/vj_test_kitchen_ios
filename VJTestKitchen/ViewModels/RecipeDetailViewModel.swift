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
    private(set) var isInGroceryList = false
    /// Ingredient ids added to the grocery list this session, purely for
    /// transient checkmark feedback in the ingredients list — not reloaded
    /// from the store, since a standalone snapshot has no lasting link back
    /// to the ingredient it came from.
    private(set) var addedIngredientIds: Set<Int64> = []

    private let recipeService: RecipeServicing
    private let ratingService: RecipeRatingServicing
    private let groceryListStore: GroceryListStoring

    init(
        recipeId: Int64,
        recipeService: RecipeServicing = RecipeService(),
        ratingService: RecipeRatingServicing = RecipeRatingService(),
        groceryListStore: GroceryListStoring = UserDefaultsGroceryListStore()
    ) {
        self.recipeId = recipeId
        self.recipeService = recipeService
        self.ratingService = ratingService
        self.groceryListStore = groceryListStore
    }

    func load() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        isInGroceryList = groceryListStore.loadSelectedRecipeIds().contains(recipeId)
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

    func toggleGroceryList() {
        var ids = groceryListStore.loadSelectedRecipeIds()
        if let index = ids.firstIndex(of: recipeId) {
            ids.remove(at: index)
        } else {
            ids.append(recipeId)
        }
        groceryListStore.saveSelectedRecipeIds(ids)
        isInGroceryList = ids.contains(recipeId)
    }

    /// Adds a single ingredient to the grocery list as a standalone snapshot,
    /// independent of whether the whole recipe is also on the list.
    func addIngredientToGroceryList(_ ingredient: Ingredient) {
        var items = groceryListStore.loadCustomItems()
        items.append(GroceryItem(name: ingredient.name, amount: ingredient.amount, unit: ingredient.unit))
        groceryListStore.saveCustomItems(items)
        addedIngredientIds.insert(ingredient.id)
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
