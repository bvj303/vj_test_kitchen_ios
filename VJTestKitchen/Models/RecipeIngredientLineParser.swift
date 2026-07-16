import Foundation

/// Splits a free-text ingredient line ("2 cups all-purpose flour") into the
/// amount / unit / name the recipe form uses. Pure and unit-tested — shared by
/// the recipe-photo scanner (`RecipePhotoImportService`) and anywhere else a
/// human-written ingredient string needs structuring.
///
/// Heuristic, not a full grammar: leading number-ish tokens ("1", "1/2",
/// "1 1/2", "½", "2-3", "0.5") become the amount; the immediately following
/// token becomes the unit *only if* it's a recognized measurement word (so
/// "3 large eggs" keeps "large eggs" as the name with no unit); the remainder is
/// the name. A line with no leading number ("Salt to taste") is all name.
enum RecipeIngredientLineParser {
    struct Parsed: Equatable {
        var amount: String
        var unit: String
        var name: String
    }

    /// Recognized measurement words (singular + common plurals/abbreviations),
    /// lowercased. Anything not here after the amount is treated as part of the
    /// name, so descriptors like "large" or "ripe" aren't mistaken for units.
    static let units: Set<String> = [
        "cup", "cups", "c",
        "tablespoon", "tablespoons", "tbsp", "tbsps", "tbs", "tb",
        "teaspoon", "teaspoons", "tsp", "tsps",
        "ounce", "ounces", "oz",
        "pound", "pounds", "lb", "lbs",
        "gram", "grams", "g",
        "kilogram", "kilograms", "kg",
        "milliliter", "milliliters", "ml",
        "liter", "liters", "l",
        "pint", "pints", "quart", "quarts", "gallon", "gallons",
        "clove", "cloves", "can", "cans", "jar", "jars",
        "package", "packages", "pkg", "stick", "sticks",
        "slice", "slices", "pinch", "pinches", "dash", "dashes",
        "sprig", "sprigs", "bunch", "bunches", "head", "heads",
    ]

    static func parse(_ line: String) -> Parsed {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Parsed(amount: "", unit: "", name: "") }

        var tokens = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)

        // Collect leading amount tokens ("1", "1/2", "1 1/2", "2-3", "½", "0.5").
        var amountTokens: [String] = []
        while let first = tokens.first, isAmountToken(first) {
            amountTokens.append(first)
            tokens.removeFirst()
        }
        let amount = amountTokens.joined(separator: " ")

        // A unit only if the next token is a known measurement word.
        var unit = ""
        if !amount.isEmpty, let next = tokens.first {
            let normalized = next.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
            if units.contains(normalized) {
                unit = next.trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
                tokens.removeFirst()
            }
        }

        let name = tokens.joined(separator: " ")
        return Parsed(amount: amount, unit: unit, name: name)
    }

    /// Whether a token reads as a quantity: an integer/decimal ("2", "0.5"), a
    /// simple fraction ("1/2"), a numeric range ("2-3"), or a single unicode
    /// vulgar fraction ("½").
    private static func isAmountToken(_ token: String) -> Bool {
        if token.count == 1, let scalar = token.unicodeScalars.first,
           unicodeFractions.contains(scalar) {
            return true
        }
        // Plain number, fraction, decimal, or hyphen range of numbers.
        return token.range(of: #"^[0-9]+([./\-][0-9]+)?$"#, options: .regularExpression) != nil
    }

    private static let unicodeFractions: Set<Unicode.Scalar> = [
        "¼", "½", "¾", "⅓", "⅔", "⅛", "⅜", "⅝", "⅞", "⅕", "⅖", "⅗", "⅘",
    ]
}
