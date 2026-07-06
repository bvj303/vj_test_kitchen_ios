import Foundation

/// Cancellation-safe debounce: each `run` call cancels any previously
/// scheduled operation and schedules a new one after `delay`, so rapid-fire
/// calls (e.g. every keystroke in a search field) only execute once input
/// settles. Used by `RecipeListViewModel`/`MealCalendarViewModel` to avoid
/// firing a server round-trip on every keystroke.
@MainActor
final class Debouncer {
    private var task: Task<Void, Never>?
    private let delay: Duration

    init(delay: Duration = .milliseconds(300)) {
        self.delay = delay
    }

    func run(_ operation: @escaping @MainActor @Sendable () async -> Void) {
        task?.cancel()
        task = Task { [delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await operation()
        }
    }
}
