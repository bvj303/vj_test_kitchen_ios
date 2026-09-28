import Foundation
import Testing
@testable import VJTestKitchen

/// Recipe search used to match the whole query as ONE substring of the title, so
/// "spicy sausage" missed "Spicy Tomato Soup with Tortellini and Sausage" (the
/// words aren't adjacent). Now every search term must appear somewhere in the
/// title, in any order — each term becomes its own `ilike '%term%'` filter.
struct RecipeSearchTermsTests {
    /// Mirrors the server-side semantics (every term is a case-insensitive
    /// substring of the title) so the tests can state the user-visible outcome.
    private func titleMatches(_ title: String, _ query: String) -> Bool {
        let terms = RecipeSearchTerms.terms(from: query)
        return !terms.isEmpty && terms.allSatisfy { title.lowercased().contains($0) }
    }

    private let target = "Spicy Tomato Soup with Tortellini and Sausage"

    @Test func wordsMatchInAnyOrderAndNeedNotBeAdjacent() {
        #expect(titleMatches(target, "spicy sausage"))
        #expect(titleMatches(target, "sausage spicy"))
        #expect(titleMatches(target, "tortellini soup"))
        #expect(titleMatches(target, "Spicy Tomato")) // the old exact-phrase search still works
    }

    @Test func everyWordMustAppear() {
        #expect(!titleMatches(target, "spicy chicken"))
        #expect(!titleMatches("Sausage and Peppers", "spicy sausage"))
    }

    @Test func pluralsMatchTheSingular() {
        #expect(titleMatches(target, "spicy sausages"))
        #expect(titleMatches("Roasted Tomato Salsa", "tomatoes"))
        #expect(titleMatches("Grilled Peach Salad", "peaches"))
        #expect(titleMatches("Chocolate Chip Cookie Bars", "cookies"))
        #expect(RecipeSearchTerms.terms(from: "sausages") == ["sausage"])
        #expect(RecipeSearchTerms.terms(from: "tomatoes") == ["tomato"])
        #expect(RecipeSearchTerms.terms(from: "peaches") == ["peach"])
    }

    @Test func pluralTrimmingNeverDropsAMatchTheFullWordWouldFind() throws {
        // Each term is a prefix of the word typed, so trimming only ever widens.
        for word in ["glass", "swiss", "asparagus", "hummus", "gas", "bus", "beans", "dishes", "boxes"] {
            let term = try #require(RecipeSearchTerms.terms(from: word).first)
            #expect(word.hasPrefix(term), "\(word) → \(term)")
        }
        #expect(RecipeSearchTerms.terms(from: "swiss") == ["swiss"]) // double-s is not a plural
    }

    @Test func fillerWordsAreIgnored() {
        #expect(RecipeSearchTerms.terms(from: "soup with sausage") == ["soup", "sausage"])
        #expect(RecipeSearchTerms.terms(from: "the best chicken recipes") == ["best", "chicken"])
        #expect(titleMatches(target, "tomato soup and sausage"))
    }

    @Test func punctuationAndHyphensSplitWords() {
        #expect(RecipeSearchTerms.terms(from: "stir-fry") == ["stir", "fry"])
        #expect(titleMatches("Beef Stir-Fry with Broccoli", "stir fry beef"))
        #expect(RecipeSearchTerms.terms(from: "Mac & Cheese!") == ["mac", "cheese"])
    }

    @Test func blankAndFillerOnlyQueries() {
        #expect(RecipeSearchTerms.terms(from: "   ").isEmpty)
        #expect(RecipeSearchTerms.terms(from: "").isEmpty)
        // A query made only of filler words still searches for itself rather
        // than silently returning everything.
        #expect(RecipeSearchTerms.terms(from: "the") == ["the"])
    }

    @Test func duplicatesAreCollapsedAndTermsAreCapped() {
        #expect(RecipeSearchTerms.terms(from: "Chicken chicken CHICKEN") == ["chicken"])
        let long = "one two three four five six seven eight nine ten"
        #expect(RecipeSearchTerms.terms(from: long).count == RecipeSearchTerms.maxTerms)
    }
}
