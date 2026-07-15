import Foundation
import Testing
@testable import VJTestKitchen

// Reuses the module-level `FakeMealPlanService` defined in
// MealCalendarViewModelTests (records `createdDrafts`, supports `errorToThrow`).

@MainActor
struct AddToCalendarViewModelTests {
    private static func referenceDate() -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 5
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components)!
    }

    @Test func daysSpanRangeWithFriendlyLabels() {
        let viewModel = AddToCalendarViewModel(
            recipeId: 42,
            recipeTitle: "Carbonara",
            referenceDate: Self.referenceDate(),
            timeZone: TimeZone(identifier: "UTC")!,
            mealPlanService: FakeMealPlanService()
        )

        #expect(viewModel.days.count == AddToCalendarViewModel.dayRange)
        #expect(viewModel.days.first?.date == "2026-07-05")
        #expect(viewModel.days.first?.label == "Today")
        #expect(viewModel.days[1].label == "Tomorrow")
        #expect(viewModel.days[1].date == "2026-07-06")
        // Third day onward uses the "Wed, Jul 9" style label, not Today/Tomorrow.
        #expect(viewModel.days[2].date == "2026-07-07")
        #expect(viewModel.days[2].label == "Tue, Jul 7")
        #expect(viewModel.days.last?.date == "2026-07-18")
    }

    @Test func todayIsTheLocalCalendarDayNotUTCs() {
        // 00:30 UTC on July 5 is still the evening of July 4 in New York — the
        // "Today" option must be the user's calendar day, not UTC's.
        let halfPastMidnightUTC = Self.referenceDate().addingTimeInterval(1800)
        let viewModel = AddToCalendarViewModel(
            recipeId: 42,
            recipeTitle: "Carbonara",
            referenceDate: halfPastMidnightUTC,
            timeZone: TimeZone(identifier: "America/New_York")!,
            mealPlanService: FakeMealPlanService()
        )

        #expect(viewModel.days.first?.date == "2026-07-04")
        #expect(viewModel.days.first?.label == "Today")
    }

    @Test func defaultsToFirstDayAndDinner() {
        let viewModel = AddToCalendarViewModel(
            recipeId: 1,
            recipeTitle: "Tacos",
            referenceDate: Self.referenceDate(),
            timeZone: TimeZone(identifier: "UTC")!,
            mealPlanService: FakeMealPlanService()
        )

        #expect(viewModel.selectedDate == "2026-07-05")
        #expect(viewModel.selectedMealType == "Dinner")
        #expect(!viewModel.didAdd)
    }

    @Test func addCreatesDraftFromSelection() async {
        let service = FakeMealPlanService()
        let viewModel = AddToCalendarViewModel(
            recipeId: 7,
            recipeTitle: "Pasta",
            referenceDate: Self.referenceDate(),
            timeZone: TimeZone(identifier: "UTC")!,
            mealPlanService: service
        )
        viewModel.selectedMealType = "Lunch"
        viewModel.selectedDate = "2026-07-08"

        await viewModel.add()

        #expect(service.createdDrafts.count == 1)
        let draft = service.createdDrafts.first
        #expect(draft?.recipeId == 7)
        #expect(draft?.date == "2026-07-08")
        #expect(draft?.mealType == "Lunch")
        #expect(viewModel.didAdd)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func addLogsErrorOnFailure() async {
        struct AddError: Error {}
        let service = FakeMealPlanService()
        service.errorToThrow = AddError()
        let sink = SpyLogSink()
        let logger = AppLogger(sinks: [sink], context: LogContext(appVersion: "1", platform: "test"))
        let viewModel = AddToCalendarViewModel(
            recipeId: 7,
            recipeTitle: "Pasta",
            referenceDate: Self.referenceDate(),
            timeZone: TimeZone(identifier: "UTC")!,
            mealPlanService: service,
            logger: logger
        )
        viewModel.selectedDate = "2026-07-08"

        await viewModel.add()

        #expect(sink.events.contains { $0.level == .error && $0.category == "calendar" })
    }

    @Test func addSurfacesErrorAndDoesNotMarkAdded() async {
        let service = FakeMealPlanService()
        service.errorToThrow = TestFailure()
        let viewModel = AddToCalendarViewModel(
            recipeId: 3,
            recipeTitle: "Soup",
            referenceDate: Self.referenceDate(),
            timeZone: TimeZone(identifier: "UTC")!,
            mealPlanService: service
        )

        await viewModel.add()

        #expect(!viewModel.didAdd)
        #expect(viewModel.errorMessage != nil)
    }
}

private struct TestFailure: Error, LocalizedError {
    var errorDescription: String? { "failed" }
}
