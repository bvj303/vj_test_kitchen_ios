import SwiftUI

/// The dashboard content of the Home tab: a context-aware suggestion header, a
/// row of glanceable stats, and a responsive grid of suggested recipes. Layout
/// is size-class-gated like `RecipesTab`/`MealCalendarView` — the grid widens to
/// more columns on iPad so the space fills without any horizontal scrolling.
struct HomeView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var selection: AppTab
    @State private var viewModel = HomeViewModel()

    /// Cap + center the content on very wide screens so a landscape iPad reads
    /// as a centered dashboard rather than a few stretched-out rows.
    private static let regularMaxWidth: CGFloat = 1200

    private var isRegular: Bool { horizontalSizeClass == .regular }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: isRegular ? 28 : 24) {
                suggestionHeader
                suggestedGrid
                statsRow
            }
            .frame(maxWidth: Self.regularMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(isRegular ? 24 : 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Home")
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
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

    // MARK: - Suggestion header

    private var suggestionHeader: some View {
        HStack(spacing: 16) {
            Image(systemName: viewModel.suggestion.symbol)
                .font(isRegular ? .largeTitle : .title)
                .foregroundStyle(Color.brandPrimary)
                .frame(width: isRegular ? 56 : 44, height: isRegular ? 56 : 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.suggestion.title)
                    .font(isRegular ? .title.bold() : .title2.bold())
                Text(viewModel.suggestion.subtitle)
                    .font(isRegular ? .body : .subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(isRegular ? 24 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(Color.brandPrimary.opacity(0.18)), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Stats

    /// Three compact summary tiles at the foot of the screen that double as
    /// jumps to their tabs.
    private var statsRow: some View {
        HStack(spacing: 10) {
            statTile(
                value: viewModel.totalRecipeCount.map(Self.compactNumber) ?? "—",
                label: "Recipes", systemImage: "book.pages", tint: .brandPrimary
            ) { selection = .recipes }
            statTile(
                value: "\(viewModel.mealsThisWeekCount)",
                label: "This Week", systemImage: "calendar", tint: .brandSage
            ) { selection = .calendar }
            statTile(
                value: "\(viewModel.uncheckedGroceryCount)",
                label: "To Buy", systemImage: "cart", tint: .brandSaffron
            ) { selection = .grocery }
        }
    }

    private func statTile(value: String, label: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.footnote)
                    .foregroundStyle(tint)
                Text(value)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .glassEffect(.regular.tint(tint.opacity(0.14)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Suggested recipes grid

    @ViewBuilder
    private var suggestedGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Suggested for You", systemImage: "sparkles")
            if viewModel.suggestedRecipes.isEmpty {
                loadingOrEmpty("Finding recipes for you…")
            } else {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: isRegular ? 20 : 16) {
                    ForEach(viewModel.suggestedRecipes) { recipe in
                        NavigationLink(value: recipe.id) {
                            suggestedCard(recipe)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Adaptive columns so the grid fills the available width — ~2 columns on
    /// iPhone, ~4–5 on iPad — with no horizontal scrolling.
    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: isRegular ? 200 : 150), spacing: isRegular ? 20 : 16)]
    }

    private func suggestedCard(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            RecipeThumbnail(imageUrl: recipe.imageUrl)
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
            Text(recipe.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let prep = recipe.prepTime {
                Label(PrepTimeFormat.string(minutes: prep), systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.compact)
            }
        }
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

    /// Compact, human count for the recipe stat (e.g. 14601 → "14.6K").
    private static func compactNumber(_ value: Int) -> String {
        if value >= 1000 {
            let thousands = Double(value) / 1000
            return String(format: thousands >= 100 ? "%.0fK" : "%.1fK", thousands)
        }
        return "\(value)"
    }
}
