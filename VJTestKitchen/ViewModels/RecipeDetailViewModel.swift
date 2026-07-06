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

    func saveRating() async {
        errorMessage = nil
        do {
            try await ratingService.upsertMine(recipeId: recipeId, rating: rating, notes: notes.isEmpty ? nil : notes)
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }
}
