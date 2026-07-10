import Foundation

/// Single source of truth for rendering a prep-time minute count as human time
/// (e.g. 90 → "1 hr 30 min") everywhere the app shows it — recipe rows, the
/// detail stat tile, the Home suggestions grid, and the filter chips. Prep time
/// is *stored and entered* as a plain minute Int (see `RecipeFormView`'s input);
/// this is display-only, so the model and DB stay minute-based.
enum PrepTimeFormat {
    /// Formats `minutes` as "X hr Y min", dropping a zero hours or minutes
    /// component: 30 → "30 min", 60 → "1 hr", 90 → "1 hr 30 min". Zero or
    /// negative input renders as "0 min".
    static func string(minutes: Int) -> String {
        guard minutes > 0 else { return "0 min" }
        let hours = minutes / 60
        let mins = minutes % 60
        switch (hours, mins) {
        case (0, _): return "\(mins) min"
        case (_, 0): return "\(hours) hr"
        default: return "\(hours) hr \(mins) min"
        }
    }

    /// Optional variant for display: returns `nil` when the prep time is unknown
    /// (`nil`, 0, or negative) so callers can omit the label entirely instead of
    /// showing a meaningless "0 min". Roughly a fifth of the imported ATK catalog
    /// (~2,900 of 14,601: drinks, salads, no-cook sauces) has no recorded prep
    /// time and stores it as 0 — those should read as "no prep time", not "0 min".
    static func label(minutes: Int?) -> String? {
        guard let minutes, minutes > 0 else { return nil }
        return string(minutes: minutes)
    }

    /// The inverse for *input*: parses user-typed prep time into minutes,
    /// accepting the ways people naturally write it — "45", "45 min",
    /// "1 hour", "1.5 hr", "1 hr 30 min", "1h30m". Returns nil for anything it
    /// can't confidently read (e.g. stray words), so the form can flag the
    /// field instead of silently saving no prep time (`Int("45 min")` is nil,
    /// which is exactly what the old form did).
    static func parseMinutes(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // The common case: a bare minute count.
        if let plain = Int(trimmed) { return plain >= 0 ? plain : nil }

        // `(?![a-z])` rather than \b so "1h30m" parses (h→3 is no \b boundary)
        // while "1 hello" still doesn't.
        let hours = #/(\d+(?:\.\d+)?)\s*(?:hours?|hrs?|h)(?![a-z])/#
        let minutes = #/(\d+(?:\.\d+)?)\s*(?:minutes?|mins?|m)(?![a-z])/#

        var remainder = trimmed.lowercased()
        var total: Double = 0
        var matchedAnything = false
        while let match = remainder.firstMatch(of: hours) {
            total += (Double(match.1) ?? 0) * 60
            remainder.removeSubrange(match.range)
            matchedAnything = true
        }
        while let match = remainder.firstMatch(of: minutes) {
            total += Double(match.1) ?? 0
            remainder.removeSubrange(match.range)
            matchedAnything = true
        }
        // Anything meaningful left over means we didn't understand the input —
        // refuse rather than guess ("45 foo" shouldn't quietly become 45).
        let leftovers = remainder.filter { $0.isLetter || $0.isNumber }
        guard matchedAnything, leftovers.isEmpty else { return nil }
        return Int(total.rounded())
    }
}
