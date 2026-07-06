import Foundation
import Observation

@MainActor
@Observable
final class RecipeListViewModel {
    private(set) var recipes: [Recipe] = []
    var searchText = ""
    private(set) var isLoading = false
    var errorMessage: String?

    private let recipeService: RecipeServicing

    init(recipeService: RecipeServicing = RecipeService()) {
        self.recipeService = recipeService
    }

    var filteredRecipes: [Recipe] {
        guard !searchText.isEmpty else { return recipes }
        return recipes.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    func load() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            recipes = try await recipeService.fetchAll()
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }
}
