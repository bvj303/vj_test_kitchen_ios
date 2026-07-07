import Foundation
import Observation

/// Backs the "Add to Calendar" sheet opened from a recipe's detail screen:
/// pick an upcoming day and a meal type, then write a `meal_plans` row for the
/// recipe. Reuses `MealPlanService` (and its `MealPlanDraft`) so this shares
/// exactly the code path the Calendar tab's Quick Planner uses — the only new
/// thing here is offering a rolling range of upcoming days (the Calendar's own
/// planner is scoped to the visible week) with friendly Today/Tomorrow labels.
@MainActor
@Observable
final class AddToCalendarViewModel {
    /// One selectable day: the Postgres `date` string plus its display label.
    struct PlannerDay: Identifiable, Sendable, Equatable {
        var date: String
        var label: String
        var id: String { date }
    }

    /// Meal types offered — shared with the Calendar tab so the two planners
    /// can't drift apart.
    static let mealTypes = MealCalendarViewModel.mealTypes

    /// How many days ahead the day picker offers, starting today.
    static let dayRange = 14

    let recipeId: Int64
    let recipeTitle: String
    let days: [PlannerDay]

    var selectedDate: String
    var selectedMealType = "Dinner"
    /// Set once the row is written, so the sheet can show a confirmation and
    /// dismiss instead of leaving the user on the picker.
    private(set) var didAdd = false
    var errorMessage: String?

    private let mealPlanService: MealPlanServicing

    init(
        recipeId: Int64,
        recipeTitle: String,
        referenceDate: Date = Date(),
        mealPlanService: MealPlanServicing = MealPlanService()
    ) {
        self.recipeId = recipeId
        self.recipeTitle = recipeTitle
        self.mealPlanService = mealPlanService
        let days = Self.upcomingDays(from: referenceDate, count: Self.dayRange)
        self.days = days
        self.selectedDate = days.first?.date ?? MealPlan.dateFormatter.string(from: referenceDate)
    }

    func add() async {
        errorMessage = nil
        do {
            try await mealPlanService.create(
                MealPlanDraft(date: selectedDate, mealType: selectedMealType, recipeId: recipeId)
            )
            didAdd = true
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// Builds `count` consecutive days starting at `referenceDate`, each as a
    /// "yyyy-MM-dd" string (UTC, matching `MealPlan.dateFormatter` — see its
    /// note on why a local time zone can shift the shown day). Offsets 0 and 1
    /// get "Today"/"Tomorrow" labels; the rest get "Wed, Jul 9" style labels.
    private static func upcomingDays(from referenceDate: Date, count: Int) -> [PlannerDay] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return (0..<count).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: referenceDate)!
            let dateString = MealPlan.dateFormatter.string(from: day)
            let label: String
            switch offset {
            case 0: label = "Today"
            case 1: label = "Tomorrow"
            default: label = Self.labelFormatter.string(from: day)
            }
            return PlannerDay(date: dateString, label: label)
        }
    }

    /// "Wed, Jul 9" — UTC to match how the day strings above are computed.
    private static let labelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
