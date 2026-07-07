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
}
