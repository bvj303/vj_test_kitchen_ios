import Foundation

/// A display-ready, scalable ingredient quantity.
///
/// The imported ATK catalog has a mixed-number parsing bug: an amount written
/// as "1½ teaspoons paprika" was split so the whole number landed in `amount`
/// (1.0) but the fraction *and* unit stayed at the front of `name`
/// ("½ teaspoons paprika", `unit` empty). Left as-is the detail screen renders a
/// nonsensical "1   ½ teaspoons paprika", and — worse — scaling the recipe would
/// multiply the wrong number (1, not 1.5).
///
/// This type reunites the split-off fraction with the stored amount, peels the
/// unit back out of the name, and formats the result as a proper mixed fraction
/// ("1½ teaspoons"). Well-formed rows pass through untouched. Pure and
/// unit-tested — no network, mirrors `HolidayProvider`/`MealTypeStyle`.
struct IngredientAmount: Equatable {
    /// The corrected numeric quantity (e.g. 1.5 for "1½").
    var value: Double
    /// The unit ("teaspoons", "cup", …); may be empty ("3 eggs").
    var unit: String
    /// The ingredient name with any split-off quantity/unit removed.
    var name: String

    /// Reconstructs the true amount/unit/name from a stored ingredient row.
    init(amount: Double, unit: String, name: String) {
        var value = amount
        var unit = unit.trimmingCharacters(in: .whitespaces)
        var name = name.trimmingCharacters(in: .whitespaces)

        // Only reunite when the row has no unit of its own — that's the
        // signature of the import bug. If a unit is already present, a leading
        // glyph in the name is real content (e.g. "½-inch diced").
        if unit.isEmpty, let (fraction, remainder) = Self.leadingFraction(in: name) {
            value += fraction
            let (peeledUnit, cleanedName) = Self.peelUnit(from: remainder)
            unit = peeledUnit
            name = cleanedName
        }

        self.value = value
        self.unit = unit
        self.name = Self.tidyName(name)
    }

    private init(value: Double, unit: String, name: String) {
        self.value = value
        self.unit = unit
        self.name = name
    }

    /// This amount multiplied by `factor` (½, 2, 3, …). Only the quantity
    /// scales — unit and name are unchanged.
    func scaled(by factor: Double) -> IngredientAmount {
        IngredientAmount(value: value * factor, unit: unit, name: name)
    }

    /// The quantity + unit as a display string, e.g. "1½ teaspoons". The unit is
    /// omitted when empty ("3") and inflected to match the value ("1 cup" vs
    /// "2 cups").
    var formatted: String {
        let quantity = Self.format(value)
        let unitText = Self.pluralizedUnit(unit, for: value)
        return unitText.isEmpty ? quantity : "\(quantity) \(unitText)"
    }

    // MARK: - Formatting

    /// Common cooking fractions and their glyphs (halves, thirds, quarters,
    /// sixths, eighths — the ones cooks actually measure). Fifths are
    /// deliberately excluded so an odd scaled result like 0.4 reads as a plain
    /// decimal rather than the unfamiliar "⅖".
    private static let fractionGlyphs: [(value: Double, glyph: String)] = [
        (1.0 / 8.0, "⅛"), (1.0 / 6.0, "⅙"), (1.0 / 4.0, "¼"), (1.0 / 3.0, "⅓"),
        (3.0 / 8.0, "⅜"), (1.0 / 2.0, "½"), (5.0 / 8.0, "⅝"), (2.0 / 3.0, "⅔"),
        (3.0 / 4.0, "¾"), (5.0 / 6.0, "⅚"), (7.0 / 8.0, "⅞"),
    ]

    /// Renders a `Double` as a mixed-fraction string: 1.5 → "1½", 0.75 → "¾",
    /// 3 → "3". Amounts that aren't a common cooking fraction fall back to a
    /// trimmed decimal ("0.4").
    static func format(_ value: Double) -> String {
        let tolerance = 0.02
        let whole = value.rounded(.down)
        let fraction = value - whole

        if fraction < tolerance {
            return String(Int(whole))
        }
        if fraction > 1 - tolerance {
            return String(Int(whole) + 1)
        }
        if let match = fractionGlyphs.first(where: { abs($0.value - fraction) < tolerance }) {
            return whole == 0 ? match.glyph : "\(Int(whole))\(match.glyph)"
        }
        return trimmedDecimal(value)
    }

    private static func trimmedDecimal(_ value: Double) -> String {
        let s = String(format: "%.2f", value)
        // Strip trailing zeros and any dangling decimal point ("1.10" → "1.1").
        var trimmed = s
        while trimmed.hasSuffix("0") { trimmed.removeLast() }
        if trimmed.hasSuffix(".") { trimmed.removeLast() }
        return trimmed
    }

    /// Cleans up an ingredient name for display: collapses runs of whitespace
    /// and removes any space that crept in *before* punctuation, so an imported
    /// "table salt , divided" reads as "table salt, divided". Punctuation-then-
    /// space (the normal case) is left untouched.
    static func tidyName(_ name: String) -> String {
        var result = ""
        result.reserveCapacity(name.count)
        var pendingSpace = false
        for character in name {
            if character == " " || character == "\t" {
                pendingSpace = true
                continue
            }
            // Drop a buffered space when the next character is punctuation that
            // should hug the preceding word.
            if pendingSpace, !",.;:!?".contains(character), !result.isEmpty {
                result.append(" ")
            }
            pendingSpace = false
            result.append(character)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Parsing helpers

    /// Maps a single Unicode vulgar-fraction glyph to its value.
    private static let glyphValues: [Character: Double] = [
        "½": 1.0 / 2.0, "⅓": 1.0 / 3.0, "⅔": 2.0 / 3.0, "¼": 1.0 / 4.0, "¾": 3.0 / 4.0,
        "⅕": 1.0 / 5.0, "⅖": 2.0 / 5.0, "⅗": 3.0 / 5.0, "⅘": 4.0 / 5.0,
        "⅙": 1.0 / 6.0, "⅚": 5.0 / 6.0, "⅛": 1.0 / 8.0, "⅜": 3.0 / 8.0, "⅝": 5.0 / 8.0, "⅞": 7.0 / 8.0,
    ]

    /// Units the import may have left at the front of `name`. Longest-first and
    /// including two-word units so "fluid ounce" is peeled before "ounce".
    private static let knownUnits = [
        "fluid ounces", "fluid ounce", "tablespoons", "tablespoon", "teaspoons", "teaspoon",
        "pounds", "pound", "ounces", "ounce", "cups", "cup", "quarts", "quart", "pints", "pint",
        "kilograms", "kilogram", "grams", "gram", "milliliters", "milliliter", "liters", "liter",
        "cloves", "clove", "sticks", "stick", "cans", "can", "packages", "package",
        "pinches", "pinch", "sprigs", "sprig", "slices", "slice", "heads", "head",
        "bunches", "bunch", "stalks", "stalk", "sheets", "sheet", "strips", "strip",
    ]

    /// If `name` begins with a fraction (glyph like "½" or ascii "1/2"), returns
    /// its value plus the remaining text. Returns `nil` otherwise.
    private static func leadingFraction(in name: String) -> (value: Double, remainder: String)? {
        guard let first = name.first else { return nil }

        if let glyphValue = glyphValues[first] {
            let remainder = name.dropFirst().trimmingCharacters(in: .whitespaces)
            return (glyphValue, remainder)
        }

        // ascii "a/b …"
        let parts = name.split(separator: " ", maxSplits: 1)
        guard let token = parts.first else { return nil }
        let fractionParts = token.split(separator: "/")
        if fractionParts.count == 2,
           let numerator = Double(fractionParts[0]),
           let denominator = Double(fractionParts[1]),
           denominator != 0 {
            let remainder = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
            return (numerator / denominator, remainder)
        }
        return nil
    }

    /// Splits a known leading unit word off the front of `text`, if present.
    private static func peelUnit(from text: String) -> (unit: String, name: String) {
        let lower = text.lowercased()
        for unit in knownUnits where lower == unit || lower.hasPrefix(unit + " ") {
            let name = String(text.dropFirst(unit.count)).trimmingCharacters(in: .whitespaces)
            return (unit, name)
        }
        return ("", text)
    }

    // MARK: - Unit pluralization

    /// Abbreviated units that read the same whether one or many — never
    /// inflected ("200 g", not "200 gs"; "1 tbsp", not "1 tbsps").
    private static let nonInflectingUnits: Set<String> = [
        "g", "kg", "mg", "ml", "l", "cl", "dl", "oz", "lb", "lbs", "fl oz",
        "tsp", "tbsp", "tbs", "c", "qt", "pt", "gal", "in", "cm", "mm", "pkg", "ct",
    ]

    /// A few units whose plural/singular isn't the naive +s / −s rule.
    private static let irregularUnitSingulars: [String: String] = [
        "leaves": "leaf", "loaves": "loaf", "halves": "half",
    ]
    private static let irregularUnitPlurals: [String: String] = [
        "leaf": "leaves", "loaf": "loaves", "half": "halves",
    ]

    /// Renders `unit` in its singular or plural form to match `value` — so a
    /// summed or scaled quantity reads naturally ("1 clove" vs "3 cloves"). Pure
    /// fractions below one stay singular, the way recipes are written ("½ cup",
    /// not "½ cups"). Abbreviations never inflect, and an empty unit passes
    /// through unchanged.
    static func pluralizedUnit(_ unit: String, for value: Double) -> String {
        let trimmed = unit.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        let lower = trimmed.lowercased()
        if nonInflectingUnits.contains(lower) { return trimmed }

        let singular = singularUnit(lower)
        // Plural only above one; exactly one and fractions under one stay
        // singular ("1 cup", "½ cup", but "1½ cups", "2 cups").
        return value > 1.0001 ? pluralUnit(singular) : singular
    }

    /// Naive singularization of a (lowercased) unit word — enough to normalize
    /// "cups"→"cup", "cloves"→"clove", "pinches"→"pinch" before re-inflecting.
    private static func singularUnit(_ unit: String) -> String {
        if let irregular = irregularUnitSingulars[unit] { return irregular }
        if unit.hasSuffix("ies"), unit.count > 3 { return String(unit.dropLast(3)) + "y" }
        for suffix in ["oes", "ches", "shes", "xes", "ses", "zes"] where unit.hasSuffix(suffix) {
            return String(unit.dropLast(2))
        }
        if unit.hasSuffix("s"), !unit.hasSuffix("ss"), unit.count > 1 { return String(unit.dropLast()) }
        return unit
    }

    /// Naive pluralization of a singular (lowercased) unit word.
    private static func pluralUnit(_ unit: String) -> String {
        if let irregular = irregularUnitPlurals[unit] { return irregular }
        if unit.hasSuffix("y"), unit.count > 1, let secondLast = unit.dropLast().last,
           !"aeiou".contains(secondLast) {
            return String(unit.dropLast()) + "ies"
        }
        for suffix in ["s", "sh", "ch", "x", "z"] where unit.hasSuffix(suffix) {
            return unit + "es"
        }
        return unit + "s"
    }
}
