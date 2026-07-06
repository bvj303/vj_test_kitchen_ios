import Foundation
import EventKit

protocol ReminderExporting: Sendable {
    func export(items: [String], listName: String) async throws
}

enum ReminderExportError: Error, LocalizedError {
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "Reminders access was denied. Enable it in Settings > Privacy & Security > Reminders."
        }
    }
}

/// Native replacement for the old app's server-side AppleScript-into-Reminders
/// hack (see DECISIONS.md, 2026-07-06) — on-device EventKit, no server round-trip.
struct ReminderService: ReminderExporting {
    func export(items: [String], listName: String) async throws {
        guard !items.isEmpty else { return }

        let store = EKEventStore()
        let granted = try await store.requestFullAccessToReminders()
        guard granted else { throw ReminderExportError.accessDenied }

        let calendar: EKCalendar
        if let existing = store.calendars(for: .reminder).first(where: { $0.title == listName }) {
            calendar = existing
        } else {
            let newCalendar = EKCalendar(for: .reminder, eventStore: store)
            newCalendar.title = listName
            newCalendar.source = store.defaultCalendarForNewReminders()?.source
                ?? store.sources.first(where: { $0.sourceType == .local })
            try store.saveCalendar(newCalendar, commit: true)
            calendar = newCalendar
        }

        // Skip items already on the list so re-exporting the same grocery
        // list doesn't pile up duplicate reminders.
        let existingTitles = await incompleteReminderTitles(in: calendar, store: store)
        let toCreate = Self.itemsToCreate(desired: items, existingTitles: existingTitles)
        guard !toCreate.isEmpty else { return }

        for item in toCreate {
            let reminder = EKReminder(eventStore: store)
            reminder.title = item
            reminder.calendar = calendar
            try store.save(reminder, commit: false)
        }
        try store.commit()
    }

    /// Filters `desired` down to the titles not already present (comparing
    /// case- and whitespace-insensitively), also collapsing repeats within
    /// `desired` itself. Pure and side-effect-free so it can be unit-tested
    /// without EventKit.
    static func itemsToCreate(desired: [String], existingTitles: [String]) -> [String] {
        func key(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        var seen = Set(existingTitles.map(key))
        return desired.filter { item in
            let k = key(item)
            guard !seen.contains(k) else { return false }
            seen.insert(k)
            return true
        }
    }

    private func incompleteReminderTitles(in calendar: EKCalendar, store: EKEventStore) async -> [String] {
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: [calendar]
        )
        // Map to titles inside the callback so only [String] (Sendable)
        // crosses the continuation — EKReminder itself is non-Sendable.
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).compactMap(\.title))
            }
        }
    }
}
