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
    @State private var spatchViewModel = SpatchBuddyViewModel(startsVisible: false)

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
        .background(Color.platformGroupedBackground)
        .overlay(alignment: spatchViewModel.corner.alignment) {
            SpatchBuddyView(
                viewModel: spatchViewModel,
                onRequestNewLine: { Self.randomSpatchLine(recipes: viewModel.suggestedRecipes) }
            )
            .padding(spatchViewModel.corner.edgeInsets)
        }
        .navigationTitle("Home")
        .task { await viewModel.load() }
        .refreshable { await viewModel.load(force: true) }
        // ⌘R reloads the dashboard when Home is the visible tab.
        .onChange(of: appCommands.refreshRequests) { _, _ in
            Task { await viewModel.load(force: true) }
        }
        // First pop-in a few beats after the shelf's actual suggestion is in —
        // referencing the real recommended recipe rather than a placeholder.
        // Held off longer than a bare load-complete beat so he doesn't read as
        // pouncing on the dashboard the instant it appears.
        .task(id: viewModel.suggestedRecipes.isEmpty) {
            guard !viewModel.suggestedRecipes.isEmpty else { return }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            spatchViewModel.show(
                message: SpatchContent.recommendationLine(recipeTitle: viewModel.suggestedRecipes.first?.title),
                mood: .happy
            )
        }
        // "Every now and again" — Spatch pops back in with a fresh line for as
        // long as Home stays on screen, rather than being a permanent fixture.
        // A longer, wider gap than earlier drafts — frequent recipe pitches on
        // the main dashboard read as pushy rather than helpful.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(.random(in: 100...160)))
                guard !Task.isCancelled, !viewModel.suggestedRecipes.isEmpty else { continue }
                let (message, mood) = Self.randomSpatchLine(recipes: viewModel.suggestedRecipes)
                spatchViewModel.show(message: message, mood: mood)
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
        .padding(isRegular ? 24 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(Color.brandPrimary.opacity(0.18)), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Spatch's Home pop-in line. A recipe recommendation is only one option
    /// among several (roughly a third of the time) rather than the default —
    /// the rest of the time it's a joke or a catchphrase, so repeat pop-ins
    /// read as company, not a recurring pitch.
    private static func randomSpatchLine(recipes: [Recipe]) -> (String, SpatchMood) {
        switch Double.random(in: 0..<1) {
        case ..<0.3:
            guard let title = recipes.randomElement()?.title else { fallthrough }
            return (SpatchContent.recommendationLine(recipeTitle: title), .happy)
        case ..<0.65:
            return (SpatchContent.randomJoke(), [.laughing, .surprised].randomElement() ?? .laughing)
        default:
            return (SpatchContent.randomCatchphrase(), .happy)
        }
    }
}
