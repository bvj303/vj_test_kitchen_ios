import Foundation

/// Splits a recipe's free-text `instructions` into ordered steps for display.
///
/// The catalog import (and the old web app before it) stores instructions as a
/// single newline-delimited blob — one step per line — so the primary split is
/// on line breaks. Kept pure and separate from the view so it's unit-testable
/// and reused wherever steps are shown.
///
/// ATK recipes additionally mark a recipe's *components* with a bold header at
/// the very start of a step's line — `**FOR THE BURGERS:** Divide the beef…` —
/// where the header prefixes (and shares a line with) that section's first step.
/// `elements(from:)` surfaces those as `.header` elements so the UI can render a
/// subheading and restart step numbering per section, instead of showing a
/// numbered step full of literal asterisks.
enum RecipeInstructions {
    /// One rendered piece of an instructions blob: either a section header
    /// (`.header`, e.g. "For the Sauce") or a numbered step (`.step`).
    enum Element: Equatable {
        case header(String)
        case step(String)
    }

    /// Returns the ordered elements — section headers and steps interleaved as
    /// they appear. A leading `**…**` marker on a line becomes its own
    /// `.header`; any step text sharing that line follows as a `.step`.
    static func elements(from instructions: String?) -> [Element] {
        guard let instructions else { return [] }
        var result: [Element] = []
        for rawLine in instructions.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if let (header, remainder) = splitLeadingHeader(line) {
                result.append(.header(header))
                let step = stripLeadingNumber(remainder.trimmingCharacters(in: .whitespaces))
                if !step.isEmpty { result.append(.step(step)) }
            } else {
                result.append(.step(stripLeadingNumber(line)))
            }
        }
        return result
    }

    /// Returns the trimmed, non-empty steps in order (header markers removed).
    /// If the text has no line breaks it's returned as a single step. Any
    /// pre-existing leading step numbering ("1.", "2)", "Step 3:") is stripped
    /// so the UI can render its own consistent numbering without doubling up.
    static func steps(from instructions: String?) -> [String] {
        elements(from: instructions).compactMap {
            if case let .step(text) = $0 { return text } else { return nil }
        }
    }

    /// If `line` begins with a `**HEADER**` marker, returns the display-ready
    /// header (title-cased, trailing colon dropped) and the remaining text.
    private static func splitLeadingHeader(_ line: String) -> (header: String, remainder: String)? {
        // ATK headers are ALL CAPS and colon-terminated inside the bold marker,
        // e.g. "**FOR THE FILLING:**". The marker is always at the line start.
        let pattern = #"^\*\*\s*(.+?)\s*\*\*"#
        guard let match = line.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        var inner = String(line[match])
        inner = String(inner.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
        inner = inner.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        let remainder = String(line[match.upperBound...])
        let header = titleCased(inner)
        guard !header.isEmpty else { return nil }
        return (header, remainder)
    }

    /// Title-cases an ALL-CAPS header while keeping connective small words
    /// ("the", "for", "of", …) lowercase unless they lead the phrase.
    private static func titleCased(_ text: String) -> String {
        let small: Set<String> = ["a", "an", "and", "the", "for", "of", "to", "in", "on", "with"]
        let words = text.split(separator: " ").map(String.init)
        return words.enumerated().map { index, word in
            let lower = word.lowercased()
            if index != 0 && small.contains(lower) { return lower }
            return lower.prefix(1).uppercased() + lower.dropFirst()
        }.joined(separator: " ")
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
