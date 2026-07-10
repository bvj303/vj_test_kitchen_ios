import Foundation
import Testing
@testable import VJTestKitchen

/// Main-actor isolated: week navigation spawns `loadPlans()` tasks, so a
/// nonisolated fake's bookkeeping arrays would be mutated concurrently.
@MainActor
final class FakeMealPlanService: MealPlanServicing {
    var plansToReturn: [MealPlanWithRecipe] = []
    var errorToThrow: Error?
    private(set) var fetchedRanges: [(from: String, to: String)] = []
    private(set) var createdDrafts: [MealPlanDraft] = []
    private(set) var deletedIds: [Int64] = []
    /// The id and recipe title the next `create` returns; incremented per call.
    var nextCreatedId: Int64 = 100
    var createdRecipeTitle = "Created Recipe"

    func fetch(from startDate: String, to endDate: String) async throws -> [MealPlanWithRecipe] {
        if let errorToThrow { throw errorToThrow }
        fetchedRanges.append((startDate, endDate))
        return plansToReturn.filter { $0.date >= startDate && $0.date <= endDate }
    }

    @discardableResult
    func create(_ draft: MealPlanDraft) async throws -> MealPlanWithRecipe {
        if let errorToThrow { throw errorToThrow }
        createdDrafts.append(draft)
        let plan = MealPlanWithRecipe(
            id: nextCreatedId, userId: UUID(), date: draft.date, mealType: draft.mealType,
            recipeId: draft.recipeId, createdAt: Date(), recipes: .init(title: createdRecipeTitle)
        )
        nextCreatedId += 1
        return plan
    }

    func delete(id: Int64) async throws {
        if let errorToThrow { throw errorToThrow }
        deletedIds.append(id)
    }
}

@MainActor
final class FakeMealPlanRecipeService: RecipeServicing {
    var recipesToReturn: [Recipe] = []
    private(set) var fetchedPages: [(offset: Int, limit: Int, search: String?)] = []

    func fetchPage(offset: Int, limit: Int, matching search: String?, tag: String?, minPrepTime: Int?, maxPrepTime: Int?) async throws -> [Recipe] {
        fetchedPages.append((offset, limit, search))
        let filtered = search.map { term in
            recipesToReturn.filter { $0.title.localizedCaseInsensitiveContains(term) }
        } ?? recipesToReturn
        let start = min(offset, filtered.count)
        let end = min(offset + limit, filtered.count)
        return Array(filtered[start..<end])
    }

    func fetchDetail(id: Int64) async throws -> RecipeDetail { fatalError("not used") }
    func create(_ draft: RecipeDraft) async throws -> Recipe { fatalError("not used") }
    func update(id: Int64, with draft: RecipeDraft) async throws { fatalError("not used") }
    func delete(id: Int64) async throws { fatalError("not used") }
}

private func makePlan(id: Int64, date: String, title: String, mealType: String = "Dinner") -> MealPlanWithRecipe {
    MealPlanWithRecipe(id: id, userId: UUID(), date: date, mealType: mealType, recipeId: 1, createdAt: Date(), recipes: .init(title: title))
}

private struct TestError: Error, LocalizedError {
    var errorDescription: String? { "failed" }
}

private let utc = TimeZone(identifier: "UTC")!

/// Noon UTC on the given day — away from midnight so UTC-based expectations
/// aren't sensitive to sub-day arithmetic.
private func utcDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

/// A view model pinned to a fixed (mutable-by-reference) clock in UTC.
@MainActor
private func makeViewModel(
    now: Date = utcDate(2026, 7, 5),
    timeZone: TimeZone = utc,
    mealPlanService: FakeMealPlanService = FakeMealPlanService(),
    recipeService: FakeMealPlanRecipeService = FakeMealPlanRecipeService(),
    snapshotStore: FakeSnapshotStore = FakeSnapshotStore(),
    debounceDelay: Duration = .milliseconds(300)
) -> MealCalendarViewModel {
    MealCalendarViewModel(
        now: { now },
        timeZone: timeZone,
        mealPlanService: mealPlanService,
        recipeService: recipeService,
        snapshotStore: snapshotStore,
        debounceDelay: debounceDelay
    )
}

@MainActor
struct MealCalendarViewModelTests {
    @Test func weekDatesStartsAtTodayAndSpansSevenDays() {
        let viewModel = makeViewModel(now: utcDate(2026, 7, 5))

        #expect(viewModel.weekDates == ["2026-07-05", "2026-07-06", "2026-07-07", "2026-07-08", "2026-07-09", "2026-07-10", "2026-07-11"])
    }

    @Test func todayIsTheLocalCalendarDayNotUTCs() {
        // 00:30 UTC on July 5 is still the evening of July 4 in New York —
        // "today" must follow the user's clock, not UTC's.
        let newYork = TimeZone(identifier: "America/New_York")!
        let viewModel = makeViewModel(now: utcDate(2026, 7, 5, hour: 0) + 1800, timeZone: newYork)

        #expect(viewModel.todayDate == "2026-07-04")
        #expect(viewModel.weekDates.first == "2026-07-04")
    }

    @Test func isTodayMatchesFirstWeekDateOnly() {
        let viewModel = makeViewModel(now: utcDate(2026, 7, 5))

        #expect(viewModel.todayDate == "2026-07-05")
        #expect(viewModel.isToday("2026-07-05"))
        #expect(!viewModel.isToday("2026-07-06"))
    }

    @Test func loadAfterDayRolloverRefreshesTodayAndWeekWindow() async {
        // The view model lives as long as the tab; iOS keeps apps suspended
        // for days. Simulate: created on July 5, `load()` runs again on July 7.
        var current = utcDate(2026, 7, 5)
        let viewModel = MealCalendarViewModel(
            now: { current },
            timeZone: utc,
            mealPlanService: FakeMealPlanService(),
            recipeService: FakeMealPlanRecipeService(),
            snapshotStore: FakeSnapshotStore()
        )
        #expect(viewModel.todayDate == "2026-07-05")

        current = utcDate(2026, 7, 7)
        await viewModel.load()

        #expect(viewModel.todayDate == "2026-07-07")
        #expect(viewModel.weekDates.first == "2026-07-07")
        #expect(viewModel.isToday("2026-07-07"))
        #expect(!viewModel.isToday("2026-07-05"))
        #expect(viewModel.weekDates.contains(viewModel.selectedPlanningDate))
    }

    @Test func weekNavigationShiftsWindowAndKeepsTodayFixed() {
        let viewModel = makeViewModel(now: utcDate(2026, 7, 5))

        viewModel.goToNextWeek()
        #expect(viewModel.weekOffset == 1)
        #expect(viewModel.weekDates.first == "2026-07-12")
        #expect(viewModel.weekDates.last == "2026-07-18")
        #expect(viewModel.isCurrentWeek == false)
        // "Today" stays the real day, now outside the visible window.
        #expect(viewModel.todayDate == "2026-07-05")
        #expect(viewModel.isToday("2026-07-12") == false)

        viewModel.goToPreviousWeek()
        viewModel.goToPreviousWeek()
        #expect(viewModel.weekOffset == -1)
        #expect(viewModel.weekDates.first == "2026-06-28")

        viewModel.goToThisWeek()
        #expect(viewModel.weekOffset == 0)
        #expect(viewModel.isCurrentWeek)
        #expect(viewModel.weekDates.first == "2026-07-05")
    }

    @Test func navigatingWeeksClampsPlanningDayIntoVisibleWeek() {
        let viewModel = makeViewModel(now: utcDate(2026, 7, 5))
        // Pick a day in the current week, then move weeks.
        viewModel.selectedPlanningDate = "2026-07-08"

        viewModel.goToNextWeek()

        // The old day isn't in the new week, so it snaps to the new week's start.
        #expect(viewModel.weekDates.contains(viewModel.selectedPlanningDate))
        #expect(viewModel.selectedPlanningDate == "2026-07-12")
    }

    @Test func navigatingWeeksFetchesTheNewWindow() async {
        let plans = FakeMealPlanService()
        let viewModel = makeViewModel(now: utcDate(2026, 7, 5), mealPlanService: plans)
        await viewModel.load()
        #expect(plans.fetchedRanges.count == 1)

        viewModel.goToNextWeek()
        // The fetch is spawned as a Task; give it a beat to land.
        try? await Task.sleep(for: .milliseconds(50))

        #expect(plans.fetchedRanges.count == 2)
        // The window spans the visible week and still reaches back to today so
        // the widget snapshot stays accurate.
        #expect(plans.fetchedRanges.last?.from == "2026-07-05")
        #expect(plans.fetchedRanges.last?.to == "2026-07-18")
    }

    @Test func holidayPassesThroughToHolidayProvider() {
        let viewModel = makeViewModel()

        #expect(viewModel.holiday(for: "2026-07-04")?.name == "Independence Day")
        #expect(viewModel.holiday(for: "2026-07-07") == nil)
    }

    @Test func selectedPlanningDateDefaultsToFirstDayOfWeek() {
        let viewModel = makeViewModel(now: utcDate(2026, 7, 5))

        #expect(viewModel.selectedPlanningDate == "2026-07-05")
        #expect(viewModel.selectedPlanningDate == viewModel.weekDates.first)
    }

    @Test func loadGroupsMealPlansByDate() async {
        let plans = FakeMealPlanService()
        plans.plansToReturn = [
            makePlan(id: 1, date: "2026-07-05", title: "Tacos"),
            makePlan(id: 2, date: "2026-07-05", title: "Salad"),
            makePlan(id: 3, date: "2026-07-06", title: "Pasta"),
        ]
        let viewModel = makeViewModel(now: utcDate(2026, 7, 5), mealPlanService: plans)

        await viewModel.load()

        #expect(viewModel.mealPlans(for: "2026-07-05").count == 2)
        #expect(viewModel.mealPlans(for: "2026-07-06").count == 1)
        #expect(viewModel.mealPlans(for: "2026-07-07").isEmpty)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func loadFetchesOnlyTheVisibleWindow() async {
        let plans = FakeMealPlanService()
        let viewModel = makeViewModel(now: utcDate(2026, 7, 5), mealPlanService: plans)

        await viewModel.load()

        #expect(plans.fetchedRanges.count == 1)
        #expect(plans.fetchedRanges.first?.from == "2026-07-05")
        #expect(plans.fetchedRanges.first?.to == "2026-07-11")
    }

    @Test func mealPlansAreOrderedByMealTypeWithSnackLast() async {
        let plans = FakeMealPlanService()
        // Intentionally out of order (and snack not last) as returned by the DB.
        plans.plansToReturn = [
            makePlan(id: 1, date: "2026-07-05", title: "Trail Mix", mealType: "Snack"),
            makePlan(id: 2, date: "2026-07-05", title: "Steak", mealType: "Dinner"),
            makePlan(id: 3, date: "2026-07-05", title: "Pancakes", mealType: "Breakfast"),
            makePlan(id: 4, date: "2026-07-05", title: "Sandwich", mealType: "Lunch"),
        ]
        let viewModel = makeViewModel(now: utcDate(2026, 7, 5), mealPlanService: plans)

        await viewModel.load()

        #expect(viewModel.mealPlans(for: "2026-07-05").map(\.mealType) == ["Breakfast", "Lunch", "Dinner", "Snack"])
    }

    @Test func mealPlansOrderIsStableForSameMealType() async {
        let plans = FakeMealPlanService()
        plans.plansToReturn = [
            makePlan(id: 3, date: "2026-07-05", title: "Late Dinner", mealType: "Dinner"),
            makePlan(id: 1, date: "2026-07-05", title: "Early Dinner", mealType: "Dinner"),
            makePlan(id: 2, date: "2026-07-05", title: "Mid Dinner", mealType: "Dinner"),
        ]
        let viewModel = makeViewModel(now: utcDate(2026, 7, 5), mealPlanService: plans)

        await viewModel.load()

        // Same meal type keeps a deterministic order (by id) rather than DB order.
        #expect(viewModel.mealPlans(for: "2026-07-05").map(\.id) == [1, 2, 3])
    }

    @Test func loadSurfacesErrorMessage() async {
        let plans = FakeMealPlanService()
        plans.errorToThrow = TestError()
        let viewModel = makeViewModel(mealPlanService: plans)

        await viewModel.load()

        #expect(viewModel.errorMessage == "failed")
    }

    @Test func loadPaintsCachedPlansBeforeTheFetchResolves() async {
        // Offline: the fetch fails, but the last-persisted window still shows.
        let store = FakeSnapshotStore()
        store.save([makePlan(id: 1, date: "2026-07-05", title: "Cached Tacos")], key: .mealPlansWindow)
        let plans = FakeMealPlanService()
        plans.errorToThrow = TestError()
        let viewModel = makeViewModel(now: utcDate(2026, 7, 5), mealPlanService: plans, snapshotStore: store)

        await viewModel.load()

        #expect(viewModel.mealPlans(for: "2026-07-05").map(\.recipeTitle) == ["Cached Tacos"])
        #expect(viewModel.errorMessage == "failed")
    }

    @Test func loadPersistsTheFetchedWindowForNextLaunch() async {
        let store = FakeSnapshotStore()
        let plans = FakeMealPlanService()
        plans.plansToReturn = [makePlan(id: 1, date: "2026-07-05", title: "Tacos")]
        let viewModel = makeViewModel(now: utcDate(2026, 7, 5), mealPlanService: plans, snapshotStore: store)

        await viewModel.load()

        #expect(store.hasValue(for: .mealPlansWindow))
    }

    @Test func matchingRecipesFiltersBySearchTextCaseInsensitivelyViaServerSideSearch() async {
        let recipes = FakeMealPlanRecipeService()
        recipes.recipesToReturn = [
            Recipe(id: 1, userId: nil, title: "Carbonara", description: nil, instructions: nil, imagePath: nil, prepTime: nil, servings: nil, createdAt: Date()),
            Recipe(id: 2, userId: nil, title: "Beef Tacos", description: nil, instructions: nil, imagePath: nil, prepTime: nil, servings: nil, createdAt: Date()),
        ]
        let viewModel = makeViewModel(recipeService: recipes, debounceDelay: .zero)
        await viewModel.load()

        #expect(viewModel.matchingRecipes.isEmpty)

        viewModel.recipeSearchText = "taco"
        try? await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.matchingRecipes.map(\.title) == ["Beef Tacos"])
        #expect(recipes.fetchedPages.last?.search == "taco")
        #expect(recipes.fetchedPages.last?.limit == 5)
    }

    @Test func addMealPlanCallsServiceAndPatchesTheDayLocally() async {
        let plans = FakeMealPlanService()
        plans.createdRecipeTitle = "Ramen"
        let viewModel = makeViewModel(now: utcDate(2026, 7, 5), mealPlanService: plans)
        await viewModel.load()
        viewModel.selectedMealType = "Lunch"

        await viewModel.addMealPlan(date: "2026-07-05", recipeId: 9)

        #expect(plans.createdDrafts.count == 1)
        #expect(plans.createdDrafts.first?.date == "2026-07-05")
        #expect(plans.createdDrafts.first?.mealType == "Lunch")
        #expect(plans.createdDrafts.first?.recipeId == 9)
        // No second fetch — the created row is patched into the day directly.
        #expect(plans.fetchedRanges.count == 1)
        #expect(viewModel.mealPlans(for: "2026-07-05").map(\.recipeTitle) == ["Ramen"])
        #expect(viewModel.errorMessage == nil)
    }

    @Test func deleteMealPlanCallsServiceAndRemovesTheRowLocally() async {
        let plans = FakeMealPlanService()
        plans.plansToReturn = [makePlan(id: 5, date: "2026-07-05", title: "Tacos")]
        let viewModel = makeViewModel(now: utcDate(2026, 7, 5), mealPlanService: plans)
        await viewModel.load()
        #expect(viewModel.mealPlans(for: "2026-07-05").count == 1)

        await viewModel.deleteMealPlan(5)

        #expect(plans.deletedIds == [5])
        #expect(viewModel.mealPlans(for: "2026-07-05").isEmpty)
        // No second fetch — removed locally.
        #expect(plans.fetchedRanges.count == 1)
    }
}

struct MealTypeStyleTests {
    @Test func iconMapsKnownMealTypesCaseInsensitively() {
        #expect(MealTypeStyle.icon(for: "Breakfast") == "sunrise.fill")
        #expect(MealTypeStyle.icon(for: "lunch") == "sun.max.fill")
        #expect(MealTypeStyle.icon(for: "DINNER") == "moon.stars.fill")
        #expect(MealTypeStyle.icon(for: "Snack") == "carrot.fill")
    }

    @Test func iconFallsBackForUnknownMealType() {
        #expect(MealTypeStyle.icon(for: "Brunch") == "fork.knife")
        #expect(MealTypeStyle.icon(for: "") == "fork.knife")
    }

    @Test func sortOrderRunsBreakfastLunchDinnerThenSnackLast() {
        let ordered = ["Snack", "Dinner", "Breakfast", "Lunch"]
            .sorted { MealTypeStyle.sortOrder(for: $0) < MealTypeStyle.sortOrder(for: $1) }
        #expect(ordered == ["Breakfast", "Lunch", "Dinner", "Snack"])
    }

    @Test func sortOrderIsCaseInsensitiveAndPlacesUnknownAfterSnack() {
        #expect(MealTypeStyle.sortOrder(for: "BREAKFAST") == MealTypeStyle.sortOrder(for: "breakfast"))
        #expect(MealTypeStyle.sortOrder(for: "Brunch") > MealTypeStyle.sortOrder(for: "Snack"))
    }
}
