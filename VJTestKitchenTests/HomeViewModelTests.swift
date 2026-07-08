import Foundation
import Testing
@testable import VJTestKitchen

/// Records the filters each `fetchPage` was called with so tests can assert the
/// suggestion's keyword/prep-time actually reach the query, plus the empty-result
/// fallback to an unfiltered page.
final class FakeHomeRecipeService: RecipeServicing, @unchecked Sendable {
    /// Keyed by the `matching` term (nil → ""), so a test can return matches for
    /// the keyword query and/or the fallback independently.
    var pagesByKeyword: [String: [Recipe]] = [:]
    var errorToThrow: Error?
    private(set) var fetchedPages: [(offset: Int, limit: Int, search: String?, tag: String?, maxPrepTime: Int?)] = []

    func fetchPage(offset: Int, limit: Int, matching search: String?, tag: String?, minPrepTime: Int?, maxPrepTime: Int?) async throws -> [Recipe] {
        if let errorToThrow { throw errorToThrow }
        fetchedPages.append((offset, limit, search, tag, maxPrepTime))
        return pagesByKeyword[search ?? "", default: []]
    }

    func totalCount() async throws -> Int { 0 }
    func fetchDetail(id: Int64) async throws -> RecipeDetail { fatalError("not used") }
    func create(_ draft: RecipeDraft) async throws -> Recipe { fatalError("not used") }
    func update(id: Int64, with draft: RecipeDraft) async throws { fatalError("not used") }
    func delete(id: Int64) async throws { fatalError("not used") }
}

private func makeRecipe(_ id: Int64, _ title: String) -> Recipe {
    Recipe(id: id, userId: nil, title: title, description: nil, instructions: nil, imagePath: nil, prepTime: 25, servings: 4, createdAt: Date())
}

private struct TestError: Error, LocalizedError {
    var errorDescription: String? { "failed" }
}

@MainActor
struct HomeViewModelTests {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// A Tuesday in July → summer weeknight; suggestion keyword is "salad".
    private var referenceDate: Date {
        utcCalendar.date(from: DateComponents(year: 2026, month: 7, day: 7))!
    }

    private func makeViewModel(recipes: FakeHomeRecipeService = FakeHomeRecipeService()) -> HomeViewModel {
        HomeViewModel(referenceDate: referenceDate, calendar: utcCalendar, recipeService: recipes)
    }

    @Test func suggestionReflectsReferenceDate() {
        let viewModel = makeViewModel()
        #expect(viewModel.suggestion.title == "Light Summer Suppers")
        #expect(viewModel.suggestion.keyword == "salad")
        #expect(viewModel.suggestion.maxPrepTime == 30)
    }

    @Test func loadPassesSuggestionFiltersToQuery() async {
        let recipes = FakeHomeRecipeService()
        recipes.pagesByKeyword = ["salad": [makeRecipe(1, "Greek Salad")]]
        let viewModel = makeViewModel(recipes: recipes)

        await viewModel.load()

        #expect(viewModel.suggestedRecipes.map(\.title) == ["Greek Salad"])
        let first = recipes.fetchedPages.first
        #expect(first?.search == "salad")
        #expect(first?.maxPrepTime == 30)
    }

    @Test func loadFallsBackToUnfilteredPageWhenKeywordMatchesNothing() async {
        let recipes = FakeHomeRecipeService()
        // Keyword ("salad") returns nothing; the unfiltered fallback (nil) does.
        recipes.pagesByKeyword = ["": [makeRecipe(9, "Anything")]]
        let viewModel = makeViewModel(recipes: recipes)

        await viewModel.load()

        #expect(viewModel.suggestedRecipes.map(\.title) == ["Anything"])
        // Two calls: the keyword query, then the unfiltered fallback.
        #expect(recipes.fetchedPages.count == 2)
        #expect(recipes.fetchedPages.last?.search == nil)
    }

    @Test func loadRotatesShelfToADisplaySizedSubsetOfThePool() async {
        // A pool larger than the display count is sliced down; every shown
        // recipe comes from the pool (the rotation only reorders/samples).
        let pool = (1...20).map { makeRecipe(Int64($0), "Salad \($0)") }
        let recipes = FakeHomeRecipeService()
        recipes.pagesByKeyword = ["salad": pool]
        let viewModel = makeViewModel(recipes: recipes)

        await viewModel.load()

        #expect(viewModel.suggestedRecipes.count == 8)
        let poolIds = Set(pool.map(\.id))
        #expect(viewModel.suggestedRecipes.allSatisfy { poolIds.contains($0.id) })
        // No duplicates in the shown slice.
        #expect(Set(viewModel.suggestedRecipes.map(\.id)).count == viewModel.suggestedRecipes.count)
    }

    @Test func loadSurfacesRecipeError() async {
        let recipes = FakeHomeRecipeService()
        recipes.errorToThrow = TestError()
        let viewModel = makeViewModel(recipes: recipes)

        await viewModel.load()

        #expect(viewModel.errorMessage == "failed")
        #expect(viewModel.suggestedRecipes.isEmpty)
    }
}
