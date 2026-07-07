import Foundation

/// A holiday landing on a given day, with a name and an SF Symbol for display.
/// Pure value type so the calendar can annotate days without a network call —
/// see `HolidayProvider`.
struct Holiday: Equatable, Sendable {
    let name: String
    /// SF Symbol name used to render the holiday in the schedule view.
    let symbol: String
}
