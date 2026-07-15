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

    /// Whether the current user has favorited this recipe (heart beside the
    /// rating). Optimistically flipped by `toggleFavorite()`.
    private(set) var isFavorite = false

    /// Every household member's rating/notes for this recipe (including the
    /// current user's). `communitySummary` aggregates them; `otherReviews`
    /// filters out the signed-in user's own row (shown in the personal editor).
    private(set) var reviews: [RecipeReview] = []

    /// Set by the view from the signed-in auth state so `otherReviews` can omit
    /// the current user's own review from the community list.
    var currentUserId: UUID?

    var communitySummary: CommunityRatingSummary { CommunityRatingSummary.from(reviews) }

    /// Other members' reviews (not the current user's), newest first — already
    /// ordered by the service.
    var otherReviews: [RecipeReview] {
        reviews.filter { $0.userId != currentUserId }
    }

    /// Transient per-session feedback for the ingredient "add to grocery list"
    /// buttons — maps each added ingredient's id to the grocery item it
    /// created, so an accidental add can be undone (deleted) right from the
    /// recipe screen. Not reloaded from the server (a standalone grocery
    /// snapshot has no lasting link back to the ingredient it came from), just
    /// enough to flip a "+" to a checkmark and back for this visit.
    private(set) var addedIngredientGroceryItemIds: [Int64: UUID] = [:]

    /// Which ingredients currently have a grocery-list entry from this visit —
    /// kept for call sites that only need the "added?" check, not the
    /// underlying item id.
    var addedIngredientIds: Set<Int64> { Set(addedIngredientGroceryItemIds.keys) }

    /// True once every ingredient has been added, and false again if any one
    /// of them is individually removed afterward — so "Add All" becomes
    /// available again rather than staying permanently disabled.
    var didAddAllToGroceryList: Bool {
        guard let detail, !detail.ingredients.isEmpty else { return false }
        return detail.ingredients.allSatisfy { addedIngredientGroceryItemIds[$0.id] != nil }
    }

    /// Whether this ingredient currently has a grocery-list entry from this
    /// recipe — drives the "+" vs. checkmark icon and which action a tap
    /// performs (add vs. remove).
    func isInGroceryList(_ ingredient: Ingredient) -> Bool {
        addedIngredientGroceryItemIds[ingredient.id] != nil
    }

    private let recipeService: RecipeServicing
    private let ratingService: RecipeRatingServicing
    private let groceryItemService: GroceryItemServicing
    private let favoritesService: FavoritesServicing
    private let logger: AppLogger

    init(
        recipeId: Int64,
        recipeService: RecipeServicing = RecipeService(),
        ratingService: RecipeRatingServicing = RecipeRatingService(),
        groceryItemService: GroceryItemServicing = GroceryItemService(),
        favoritesService: FavoritesServicing = FavoritesService(),
        logger: AppLogger = .shared
    ) {
        self.recipeId = recipeId
        self.recipeService = recipeService
        self.ratingService = ratingService
        self.groceryItemService = groceryItemService
        self.favoritesService = favoritesService
        self.logger = logger
    }

    func load() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            async let detailTask = recipeService.fetchDetail(id: recipeId)
            async let ratingTask = ratingService.fetchMine(recipeId: recipeId)
            async let reviewsTask = ratingService.fetchReviews(recipeId: recipeId)
            let (detail, myRating, reviews) = try await (detailTask, ratingTask, reviewsTask)
            self.detail = detail
            self.rating = myRating?.rating
            self.notes = myRating?.notes ?? ""
            self.reviews = reviews
        } catch {
            logger.error("Recipe detail load failed", category: "recipes", error: error)
            errorMessage = ErrorPresenter.message(for: error)
        }
        // Favorites load independently — a favorites failure shouldn't blank the
        // recipe (it just leaves the heart unfilled).
        if let ids = try? await favoritesService.fetchMyFavoriteIds() {
            isFavorite = ids.contains(recipeId)
        }
    }

    /// Toggles this recipe's favorite state (heart beside the rating).
    /// Optimistic — reverts on failure.
    func toggleFavorite() async {
        let newValue = !isFavorite
        isFavorite = newValue
        do {
            try await favoritesService.setFavorite(recipeId: recipeId, isFavorite: newValue)
        } catch {
            isFavorite = !newValue
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
            let item = try await groceryItemService.add(draft(for: ingredient, in: detail, scale: scale))
            addedIngredientGroceryItemIds[ingredient.id] = item.id
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// Undoes an accidental add — deletes the grocery-list row this ingredient
    /// created and flips its icon back to "+". No-op if it was never added (or
    /// was already removed).
    func removeIngredientFromGroceryList(_ ingredient: Ingredient) async {
        guard let itemId = addedIngredientGroceryItemIds[ingredient.id] else { return }
        do {
            try await groceryItemService.delete(id: itemId)
            addedIngredientGroceryItemIds.removeValue(forKey: ingredient.id)
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// Adds every not-yet-added ingredient at once, each tagged to this
    /// recipe. Skips ingredients already on the list so re-tapping "Add All"
    /// after removing a few individually doesn't create duplicates.
    func addAllIngredientsToGroceryList(scale: Double = 1) async {
        guard let detail, !detail.ingredients.isEmpty else { return }
        let pending = detail.ingredients.filter { addedIngredientGroceryItemIds[$0.id] == nil }
        guard !pending.isEmpty else { return }
        let drafts = pending.map { draft(for: $0, in: detail, scale: scale) }
        do {
            let created = try await groceryItemService.addMany(drafts)
            for (ingredient, item) in zip(pending, created) {
                addedIngredientGroceryItemIds[ingredient.id] = item.id
            }
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
            // Refresh the community list so the household average + my own row
            // reflect the just-saved rating without a full reload.
            if let refreshed = try? await ratingService.fetchReviews(recipeId: recipeId) {
                reviews = refreshed
            }
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }
}
