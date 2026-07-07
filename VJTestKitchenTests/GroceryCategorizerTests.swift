import Testing
@testable import VJTestKitchen

struct GroceryCategorizerTests {
    @Test func categorizesCommonItemsIntoExpectedAisles() {
        #expect(GroceryCategorizer.categorize("Milk") == .dairy)
        #expect(GroceryCategorizer.categorize("cheddar cheese") == .dairy)
        #expect(GroceryCategorizer.categorize("eggs") == .dairy)
        #expect(GroceryCategorizer.categorize("Apples") == .produce)
        #expect(GroceryCategorizer.categorize("baby spinach") == .produce)
        #expect(GroceryCategorizer.categorize("Roma tomatoes") == .produce)
        #expect(GroceryCategorizer.categorize("boneless chicken thighs") == .meat)
        #expect(GroceryCategorizer.categorize("ground beef") == .meat)
        #expect(GroceryCategorizer.categorize("salmon fillet") == .seafood)
        #expect(GroceryCategorizer.categorize("jumbo shrimp") == .seafood)
        #expect(GroceryCategorizer.categorize("sourdough bread") == .bakery)
        #expect(GroceryCategorizer.categorize("rice") == .pantry)
        #expect(GroceryCategorizer.categorize("spaghetti") == .pantry)
        #expect(GroceryCategorizer.categorize("cinnamon") == .bakingSpices)
        #expect(GroceryCategorizer.categorize("vanilla extract") == .bakingSpices)
        #expect(GroceryCategorizer.categorize("ketchup") == .condiments)
        #expect(GroceryCategorizer.categorize("frozen pizza") == .frozen)
        #expect(GroceryCategorizer.categorize("ice cream") == .frozen)
        #expect(GroceryCategorizer.categorize("coffee") == .beverages)
        #expect(GroceryCategorizer.categorize("potato chips") == .snacks)
        #expect(GroceryCategorizer.categorize("paper towels") == .household)
        #expect(GroceryCategorizer.categorize("dish soap") == .household)
    }

    @Test func fallsBackToOtherForUnknownItems() {
        #expect(GroceryCategorizer.categorize("qwertyuiop") == .other)
        #expect(GroceryCategorizer.categorize("") == .other)
        #expect(GroceryCategorizer.categorize("   ") == .other)
    }

    @Test func matchesWholeWordsNotSubstrings() {
        // "butternut" contains the substring "butter", but token matching must
        // not miscategorize butternut squash as dairy.
        #expect(GroceryCategorizer.categorize("butternut squash") == .produce)
    }

    @Test func multiWordPhrasesBeatSingleTokenMatches() {
        // "orange" alone is produce, but "orange juice" as a phrase is a drink.
        #expect(GroceryCategorizer.categorize("orange juice") == .beverages)
        #expect(GroceryCategorizer.categorize("orange") == .produce)
    }

    @Test func isCaseInsensitive() {
        #expect(GroceryCategorizer.categorize("MILK") == .dairy)
        #expect(GroceryCategorizer.categorize("ChIcKeN") == .meat)
    }
}
