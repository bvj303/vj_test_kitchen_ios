import Foundation
import Testing
@testable import VJTestKitchen

@MainActor
struct RecipePhotoImportTests {

    private func makeForm() -> RecipeFormViewModel {
        RecipeFormViewModel(
            mode: .create,
            recipeService: FakeRecipeFormRecipeService(),
            saveService: FakeRecipeSaveService()
        )
    }

    @Test func applyFillsEveryFieldFromScan() {
        let vm = makeForm()
        vm.apply(ScannedRecipe(
            title: "Weeknight Chili",
            summary: "A quick pot of chili.",
            ingredients: ["1 lb ground beef", "2 cans kidney beans", "Salt to taste"],
            instructions: "Brown the beef.\nAdd everything else.\nSimmer.",
            totalMinutes: 45,
            servings: 6
        ))
        #expect(vm.title == "Weeknight Chili")
        #expect(vm.description == "A quick pot of chili.")
        #expect(vm.instructions.contains("Simmer"))
        #expect(vm.prepTimeText == "45")
        #expect(vm.servingsText == "6")
        #expect(vm.ingredientRows.count == 3)
        #expect(vm.ingredientRows[0].amount == "1")
        #expect(vm.ingredientRows[0].unit == "lb")
        #expect(vm.ingredientRows[0].name == "ground beef")
        #expect(vm.ingredientRows[2].name == "Salt to taste")
    }

    @Test func applyKeepsExistingValuesWhenScanFieldEmpty() {
        let vm = makeForm()
        vm.title = "My Title"
        vm.description = "My description"
        vm.apply(ScannedRecipe(
            title: "   ",         // blank → don't clobber
            summary: "",          // empty → don't clobber
            ingredients: [],
            instructions: "",
            totalMinutes: 0,
            servings: 0
        ))
        #expect(vm.title == "My Title")
        #expect(vm.description == "My description")
        // Empty ingredient list leaves the form's default single blank row.
        #expect(vm.ingredientRows.count == 1)
    }

    @Test func applyIgnoresZeroTimeAndServings() {
        let vm = makeForm()
        vm.prepTimeText = "30"
        vm.servingsText = "2"
        vm.apply(ScannedRecipe(title: "X", summary: "", ingredients: [],
                               instructions: "", totalMinutes: 0, servings: 0))
        #expect(vm.prepTimeText == "30")
        #expect(vm.servingsText == "2")
    }

    @Test func applyDropsUnparseableIngredientLines() {
        let vm = makeForm()
        vm.apply(ScannedRecipe(title: "X", summary: "", ingredients: ["", "   ", "2 eggs"],
                               instructions: "", totalMinutes: 0, servings: 0))
        #expect(vm.ingredientRows.count == 1)
        #expect(vm.ingredientRows[0].name == "eggs")
    }

    @Test func promptIncludesOCRText() {
        let prompt = RecipePhotoImportService.prompt(for: "2 cups flour\nBake at 350")
        #expect(prompt.contains("2 cups flour"))
        #expect(prompt.contains("Bake at 350"))
    }
}
