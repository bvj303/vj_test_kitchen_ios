import Foundation

/// Turns what the user typed into recipe-search terms. `RecipeService.fetchPage`
/// requires EVERY term to appear somewhere in the title (one trigram-indexed
/// `ilike '%term%'` per term), in any order — so "spicy sausage" finds "Spicy
/// Tomato Soup with Tortellini and Sausage", which the old single-phrase match
/// missed because the words aren't adjacent. Pure, so it's unit-tested.
enum RecipeSearchTerms {
    /// Bounds the number of `ilike` filters one search can add to the query.
    static let maxTerms = 8

    /// Words that carry no search meaning and would otherwise exclude titles that
    /// happen not to contain them ("soup with sausage", "chicken recipes").
    private static let fillerWords: Set<String> = [
        "a", "an", "and", "the", "with", "of", "in", "on", "for", "to", "or", "recipe", "recipes",
    ]

    static func terms(from query: String) -> [String] {
        let words = query.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        guard !words.isEmpty else { return [] }

        var seen = Set<String>()
        var terms: [String] = []
        for word in words where !fillerWords.contains(word) {
            let term = singularStem(word)
            if seen.insert(term).inserted { terms.append(term) }
            if terms.count == maxTerms { break }
        }
        // A query that's ONLY filler ("the") still searches for itself rather
        // than silently matching everything.
        if terms.isEmpty { return [words.joined(separator: " ")] }
        return terms
    }

    /// Trims an English plural so "sausages" also matches "Sausage" and
    /// "tomatoes" matches "Tomato". The result is always a PREFIX of the word, so
    /// against a substring match it can only widen results, never lose one.
    private static func singularStem(_ word: String) -> String {
        if word.count > 4, ["oes", "ches", "shes", "xes", "zes", "sses"].contains(where: word.hasSuffix) {
            return String(word.dropLast(2))
        }
        if word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") {
            return String(word.dropLast())
        }
        return word
    }
}
