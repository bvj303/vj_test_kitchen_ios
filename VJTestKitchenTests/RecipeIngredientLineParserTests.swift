import Foundation
import Testing
@testable import VJTestKitchen

struct RecipeIngredientLineParserTests {
    private typealias Parsed = RecipeIngredientLineParser.Parsed

    @Test func splitsAmountUnitName() {
        #expect(RecipeIngredientLineParser.parse("2 cups all-purpose flour")
            == Parsed(amount: "2", unit: "cups", name: "all-purpose flour"))
    }

    @Test func handlesMixedNumberAmount() {
        #expect(RecipeIngredientLineParser.parse("1 1/2 cups sugar")
            == Parsed(amount: "1 1/2", unit: "cups", name: "sugar"))
    }

    @Test func handlesDecimalAmount() {
        #expect(RecipeIngredientLineParser.parse("0.5 tsp salt")
            == Parsed(amount: "0.5", unit: "tsp", name: "salt"))
    }

    @Test func handlesUnicodeFraction() {
        #expect(RecipeIngredientLineParser.parse("½ cup milk")
            == Parsed(amount: "½", unit: "cup", name: "milk"))
    }

    @Test func handlesRange() {
        #expect(RecipeIngredientLineParser.parse("2-3 cloves garlic")
            == Parsed(amount: "2-3", unit: "cloves", name: "garlic"))
    }

    @Test func descriptorAfterAmountIsNotAUnit() {
        // "large" isn't a measurement word, so it stays part of the name.
        #expect(RecipeIngredientLineParser.parse("3 large eggs")
            == Parsed(amount: "3", unit: "", name: "large eggs"))
    }

    @Test func noAmountIsAllName() {
        #expect(RecipeIngredientLineParser.parse("Salt and pepper to taste")
            == Parsed(amount: "", unit: "", name: "Salt and pepper to taste"))
    }

    @Test func stripsPunctuationOnUnit() {
        #expect(RecipeIngredientLineParser.parse("2 tbsp. olive oil")
            == Parsed(amount: "2", unit: "tbsp", name: "olive oil"))
    }

    @Test func emptyLineIsEmpty() {
        #expect(RecipeIngredientLineParser.parse("   ") == Parsed(amount: "", unit: "", name: ""))
    }
}
