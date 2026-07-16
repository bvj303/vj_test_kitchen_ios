import Foundation
import Testing
@testable import VJTestKitchen

private func makeRecipe(_ id: Int64, _ title: String) -> Recipe {
    Recipe(id: id, userId: nil, title: title, description: nil, instructions: nil,
           imagePath: nil, prepTime: nil, servings: nil, createdAt: Date())
}

struct FindRecipeIntentDialogTests {

    @Test func noMatchesReadsBackTheQuery() {
        let dialog = FindRecipeIntent.dialog(for: [], query: "sushi")
        #expect(dialog.contains("sushi"))
        #expect(dialog.localizedCaseInsensitiveContains("couldn't find"))
    }

    @Test func singleMatchNamesIt() {
        let dialog = FindRecipeIntent.dialog(for: [makeRecipe(1, "Spaghetti Carbonara")], query: "carbonara")
        #expect(dialog == "I found Spaghetti Carbonara in your collection.")
    }

    @Test func multipleMatchesAreListedWithCountAndOxfordAnd() {
        let dialog = FindRecipeIntent.dialog(
            for: [makeRecipe(1, "A"), makeRecipe(2, "B"), makeRecipe(3, "C")],
            query: "x"
        )
        #expect(dialog.contains("3 recipes"))
        #expect(dialog.contains("A, B, and C"))
    }
}

struct RecipeFormMergeTagsTests {

    @Test func appendsOnlyNewTagsCaseInsensitively() {
        let merged = RecipeFormViewModel.mergeTags(into: "Dinner, Italian", adding: ["italian", "Quick"])
        #expect(merged == "Dinner, Italian, Quick")
    }

    @Test func mergingIntoEmptyKeepsSuggestions() {
        let merged = RecipeFormViewModel.mergeTags(into: "", adding: ["Dinner", "  ", "Vegan"])
        #expect(merged == "Dinner, Vegan")
    }

    @Test func dropsBlankSuggestionsAndTrims() {
        let merged = RecipeFormViewModel.mergeTags(into: "Dinner", adding: [" Dinner ", ""])
        #expect(merged == "Dinner") // nothing new to add
    }
}
