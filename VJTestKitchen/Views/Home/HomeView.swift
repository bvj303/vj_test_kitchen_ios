import SwiftUI

/// The dashboard content of the Home tab: a context-aware suggestion header and
/// a responsive grid of suggested recipes that rotates each time the screen
/// loads. Layout is size-class-gated like `RecipesTab`/`MealCalendarView` — the
/// grid widens to more columns on iPad so the space fills without any horizontal
/// scrolling.
struct HomeView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AppCommands.self) private var appCommands
    @State private var viewModel = HomeViewModel()
    /// The suggested grid's measured width, driving its (even) column count.
    @State private var gridWidth: CGFloat = 0

    /// Cap + center the content on very wide screens so a landscape iPad reads
    /// as a centered dashboard rather than a few stretched-out rows.
    private static let regularMaxWidth: CGFloat = 1200

    private var isRegular: Bool { horizontalSizeClass == .regular }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: isRegular ? 28 : 24) {
                searchShortcut
                suggestionHeader
                suggestedGrid
            }
            .frame(maxWidth: Self.regularMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(isRegular ? 24 : 16)
        }
        .screenBackground()
        .navigationTitle("Home")
        .task { await viewModel.load() }
        .refreshable { await viewModel.load(force: true) }
        // ⌘R reloads the dashboard when Home is the visible tab.
        .onChange(of: appCommands.refreshRequests) { _, _ in
            Task { await viewModel.load(force: true) }
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

    // MARK: - Search shortcut

    /// A tappable stand-in for the real search field — styled the same as
    /// `RecipeListView`'s search bar (glass capsule, magnifying glass,
    /// placeholder text) but non-editable here. Tapping it jumps straight to
    /// the Recipes tab with its search field focused, reusing the same
    /// `AppCommands.requestSearch()` plumbing the ⌘F shortcut already drives.
    private var searchShortcut: some View {
        Button {
            appCommands.requestSearch()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text("Search recipes")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassEffect(.regular, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search Recipes")
    }

    // MARK: - Suggestion header

    private var suggestionHeader: some View {
        HStack(spacing: 16) {
            Image(systemName: viewModel.suggestion.symbol)
                .font(isRegular ? .largeTitle : .title)
                .foregroundStyle(Color.brandPrimary)
                .frame(width: isRegular ? 56 : 44, height: isRegular ? 56 : 44)
            VStack(alignment: .leading, spacing: 3) {
                if let forecast = viewModel.todayForecast {
                    weatherContext(forecast)
                }
                Text(viewModel.suggestion.title)
                    .font(isRegular ? .title.bold() : .title2.bold())
                Text(viewModel.suggestion.subtitle)
                    .font(isRegular ? .body : .subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(isRegular ? Surface.Space.xLarge : Surface.Space.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(.elevated, radius: Surface.Radius.large)
    }

    /// A small live-weather overline shown above the suggestion title when a
    /// forecast is available — e.g. "Rainy · 52°" — so the header visibly
    /// reflects the real conditions it's reacting to. Temperature is localized
    /// via the same `WeatherFormatting` helper the calendar badges use.
    private func weatherContext(_ forecast: DailyForecast) -> some View {
        Label(
            "\(forecast.condition) · \(WeatherFormatting.temperatureLabel(forecast.highTemperature))",
            systemImage: forecast.symbolName
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(Color.brandPrimary)
        .labelStyle(.compact)
        .accessibilityLabel("Current weather: \(forecast.condition), \(WeatherFormatting.temperatureLabel(forecast.highTemperature))")
    }

    // MARK: - Suggested recipes grid

    @ViewBuilder
    private var suggestedGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Suggested for You", systemImage: "sparkles")
            if viewModel.suggestedRecipes.isEmpty {
                loadingOrEmpty("Finding recipes for you…")
            } else {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: gridSpacing) {
                    ForEach(viewModel.suggestedRecipes) { recipe in
                        NavigationLink(value: recipe.id) {
                            suggestedCard(recipe)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
            }
        }
    }

    private var gridSpacing: CGFloat { isRegular ? 20 : 16 }

    /// Flexible columns filling the available width with no horizontal scrolling
    /// — 2 on iPhone, 4 on iPad — always an EVEN count, so on a partially folded
    /// iPhone Duo the grid divides cleanly at the fold instead of putting a middle
    /// column on the crease (HIG "Designing for iPhone Duo").
    private var gridColumns: [GridItem] {
        let count = FoldLayout.evenColumnCount(
            availableWidth: gridWidth,
            minimumItemWidth: isRegular ? 200 : 150,
            spacing: gridSpacing
        )
        return Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: count)
    }

    private func suggestedCard(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            RecipeThumbnail(imageUrl: recipe.imageUrl)
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
            Text(recipe.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                // Always reserve two lines so every card is the same height,
                // whether its title is one line or two.
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 12) {
                // Prep time on every card (a dash when unknown) so the metadata
                // row is consistent card to card rather than appearing on some.
                Label(PrepTimeFormat.label(minutes: recipe.prepTime) ?? "—", systemImage: "clock")
                if let atkRating = recipe.atkRating {
                    Label(String(format: "%.1f", atkRating), systemImage: "star.fill")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.compact)
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
        .surface(.card)
    }

}
