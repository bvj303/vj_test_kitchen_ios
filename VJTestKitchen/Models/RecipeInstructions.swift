import Foundation

/// Splits a recipe's free-text `instructions` into ordered steps for display.
///
/// The catalog import (and the old web app before it) stores instructions as a
/// single newline-delimited blob — one step per line — so the primary split is
/// on line breaks. Kept pure and separate from the view so it's unit-testable
/// and reused wherever steps are shown.
enum RecipeInstructions {
    /// Returns the trimmed, non-empty steps in order. If the text has no line
    /// breaks it's returned as a single step. Any pre-existing leading step
    /// numbering ("1.", "2)", "Step 3:") is stripped so the UI can render its
    /// own consistent numbering without doubling up.
    static func steps(from instructions: String?) -> [String] {
        guard let instructions else { return [] }
        return instructions
            .split(whereSeparator: \.isNewline)
            .map { stripLeadingNumber(String($0).trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
    }

    private static func stripLeadingNumber(_ line: String) -> String {
        // Matches "1. ", "2) ", "3 - ", "Step 4: " at the very start.
        let pattern = #"^(?:step\s*)?\d+\s*[.):\-]\s+"#
        guard let range = line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return line
        }
        return String(line[range.upperBound...])
    }
}
