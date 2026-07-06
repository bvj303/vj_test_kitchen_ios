import Foundation

/// Parses a user-entered ingredient quantity into a `Double`. Recipes are
/// routinely written with fractions ("1/2 cup", "1 1/2 tsp"), which a bare
/// `Double(_:)` would silently turn into 0. This supports plain decimals,
/// simple fractions, and mixed numbers.
enum IngredientAmountParser {
    /// Returns the parsed amount, or `nil` for genuinely unparseable text so
    /// callers can decide how to handle it. Blank input is treated as `0`
    /// (a legitimate "to taste" amount).
    static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        if let value = Double(trimmed) { return value }

        let parts = trimmed.split(separator: " ")
        switch parts.count {
        case 1:
            return parseFraction(parts[0])
        case 2:
            guard let whole = Double(parts[0]), let fraction = parseFraction(parts[1]) else { return nil }
            return whole + fraction
        default:
            return nil
        }
    }

    private static func parseFraction(_ s: Substring) -> Double? {
        let components = s.split(separator: "/")
        guard components.count == 2,
              let numerator = Double(components[0]),
              let denominator = Double(components[1]),
              denominator != 0 else { return nil }
        return numerator / denominator
    }
}
