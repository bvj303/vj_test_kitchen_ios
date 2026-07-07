import SwiftUI

/// The dashboard content of the Home tab: a context-aware "suggested recipes"
/// shelf plus glanceable stats, this-week's meals, and quick actions. Layout is
/// size-class-gated like `RecipesTab`/`MealCalendarView` — iPhone (compact)
/// stacks everything in one scroll and stays lean; iPad (regular) puts the
/// suggestions beside a sidebar of stats/week/actions and shows more of each.
struct HomeView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var selection: AppTab
    @State private var viewModel = HomeViewModel()
    @State private var showingAddRecipe = false

    /// Cap + center the content on wide screens so a landscape iPad reads as a
    /// centered dashboard rather than edge-to-edge rows (mirrors the Calendar).
    private static let regularMaxWidth: CGFloat = 900

    private var isRegular: Bool { horizontalSizeClass == .regular }

    var body: some View {
        ScrollView {
            Group {
                if isRegular {
                    regularLayout
                } else {
                    compactLayout
                }
            }
            .frame(maxWidth: Self.regularMaxWidth)
            .frame(maxWidth: .infinity)
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Home")
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .sheet(isPresented: $showingAddRecipe) {
            NavigationStack {
                RecipeFormView(mode: .create, showsCancelButton: true, onSaved: {
                    Task { await viewModel.load() }
                })
            }
        }
        .alert(
            "Couldn't Load Home",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Layouts

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 24) {
            suggestionHeader
            suggestedShelf
            statsRow
            weekSection(limit: 3)
            quickActions
        }
    }

    private var regularLayout: some View {
        VStack(alignment: .leading, spacing: 28) {
            suggestionHeader
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 24) {
                    suggestedShelf
                    weekSection(limit: 7)
                }
                VStack(alignment: .leading, spacing: 24) {
                    statsColumn
                    quickActions
                }
                .frame(width: 300)
            }
        }
    }

    // MARK: - Suggestion header

    private var suggestionHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: viewModel.suggestion.symbol)
                .font(.title)
                .foregroundStyle(Color.brandPrimary)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.suggestion.title)
                    .font(.title2.bold())
                Text(viewModel.suggestion.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(Color.brandPrimary.opacity(0.18)), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Suggested recipes

    @ViewBuilder
    private var suggestedShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Suggested for You", systemImage: "sparkles")
            if viewModel.suggestedRecipes.isEmpty {
                loadingOrEmpty("Finding recipes for you…")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(viewModel.suggestedRecipes) { recipe in
                            NavigationLink(value: recipe.id) {
                                suggestedCard(recipe)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func suggestedCard(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            RecipeThumbnail(imageUrl: recipe.imageUrl)
                .frame(width: 150, height: 110)
            Text(recipe.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let prep = recipe.prepTime {
                Label("\(prep) min", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 150, height: 190, alignment: .topLeading)
    }

    // MARK: - Stats

    /// iPhone: three tiles in a row. iPad uses `statsColumn` instead.
    private var statsRow: some View {
        HStack(spacing: 12) {
            recipeStatTile
            weekStatTile
            groceryStatTile
        }
    }

    /// iPad sidebar: the same tiles stacked full-width.
    private var statsColumn: some View {
        VStack(spacing: 12) {
            recipeStatTile
            weekStatTile
            groceryStatTile
        }
    }

    private var recipeStatTile: some View {
        statTile(
            value: viewModel.totalRecipeCount.map(Self.compactNumber) ?? "—",
            label: "Recipes",
            systemImage: "book.pages",
            tint: .brandPrimary
        ) { selection = .recipes }
    }

    private var weekStatTile: some View {
        statTile(
            value: "\(viewModel.mealsThisWeekCount)",
            label: "This Week",
            systemImage: "calendar",
            tint: .brandSage
        ) { selection = .calendar }
    }

    private var groceryStatTile: some View {
        statTile(
            value: "\(viewModel.uncheckedGroceryCount)",
            label: "To Buy",
            systemImage: "cart",
            tint: .brandSaffron
        ) { selection = .grocery }
    }

    private func statTile(value: String, label: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(tint)
                Text(value)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .glassEffect(.regular.tint(tint.opacity(0.14)), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - This week's meals

    private func weekSection(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("This Week", systemImage: "calendar")
            if viewModel.weekMeals.isEmpty {
                emptyWeekCard
            } else {
                VStack(spacing: 0) {
                    let meals = Array(viewModel.weekMeals.prefix(limit))
                    ForEach(Array(meals.enumerated()), id: \.element.id) { index, plan in
                        NavigationLink(value: plan.recipeId) {
                            mealRow(plan)
                        }
                        .buttonStyle(.plain)
                        if index < meals.count - 1 {
                            Divider().padding(.leading, 52)
                        }
                    }
                    if viewModel.weekMeals.count > limit {
                        Divider().padding(.leading, 52)
                        Button { selection = .calendar } label: {
                            Text("View all \(viewModel.weekMeals.count) meals")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.brandPrimary)
                    }
                }
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func mealRow(_ plan: MealPlanWithRecipe) -> some View {
        HStack(spacing: 12) {
            Image(systemName: MealTypeStyle.icon(for: plan.mealType))
                .foregroundStyle(MealTypeStyle.tint(for: plan.mealType))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.recipeTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(dayLabel(plan.date)) · \(plan.mealType)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }

    private var emptyWeekCard: some View {
        VStack(spacing: 10) {
            Text("No meals planned this week.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button { selection = .calendar } label: {
                Label("Plan Meals", systemImage: "calendar.badge.plus")
            }
            .buttonStyle(.glassProminent)
            .tint(Color.brandPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Quick actions

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Quick Actions", systemImage: "bolt.fill")
            VStack(spacing: 10) {
                Button { showingAddRecipe = true } label: {
                    quickActionLabel("Add Recipe", systemImage: "plus.circle.fill", tint: .brandPrimary)
                }
                Button { selection = .planner } label: {
                    quickActionLabel("Plan with AI", systemImage: "sparkles", tint: .brandSage)
                }
                Button { selection = .grocery } label: {
                    quickActionLabel("Grocery List", systemImage: "cart.fill", tint: .brandSaffron)
                }
            }
        }
    }

    private func quickActionLabel(_ title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 28)
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.tint(tint.opacity(0.12)), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }

    // MARK: - Shared bits

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(Color.brandPrimary)
    }

    private func loadingOrEmpty(_ text: String) -> some View {
        HStack {
            if viewModel.isLoading { ProgressView() }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Formats "yyyy-MM-dd" to a short weekday like "Tue" using a UTC formatter,
    /// so the day never shifts by one in non-UTC time zones (same rule the
    /// Calendar view follows for its UTC "yyyy-MM-dd" strings).
    private func dayLabel(_ dateString: String) -> String {
        guard let date = MealPlan.dateFormatter.date(from: dateString) else { return dateString }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    /// Compact, human count for the recipe stat (e.g. 14601 → "14.6K").
    private static func compactNumber(_ value: Int) -> String {
        if value >= 1000 {
            let thousands = Double(value) / 1000
            return String(format: thousands >= 100 ? "%.0fK" : "%.1fK", thousands)
        }
        return "\(value)"
    }
}
