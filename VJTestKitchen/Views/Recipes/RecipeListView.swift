import SwiftUI

struct RecipeListView: View {
    @State private var viewModel = RecipeListViewModel()
    @State private var showingAddRecipe = false
    /// Changing this re-runs the initial load — the parent bumps it after a
    /// delete so the removed recipe drops out of the list.
    var reloadToken: UUID = UUID()
    let onSelect: (Recipe) -> Void

    var body: some View {
        @Bindable var viewModel = viewModel

        // The filter bar is a plain sibling stacked above the List rather than a
        // `.safeAreaInset(edge: .top)`: that inset silently fails to lay out when
        // the Recipes screen is entered as a *secondary* tab (a lazily-created
        // TabView tab), which is exactly how it's reached now that Home is the
        // first tab — the bar simply didn't appear. A VStack sibling always
        // renders, so the chips show regardless of how the tab is opened.
        VStack(spacing: 0) {
            RecipeFilterBar(viewModel: viewModel)
                .background(.bar)
            Divider()

            List(viewModel.items) { recipe in
                Button {
                    onSelect(recipe)
                } label: {
                    RecipeRowView(recipe: recipe, isFavorite: viewModel.isFavorite(recipe))
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    favoriteAction(recipe)
                }
                .contextMenu {
                    favoriteAction(recipe)
                }
                .onAppear { Task { await viewModel.loadMoreIfNeeded(currentItem: recipe) } }
            }
            .listStyle(.plain)
            .overlay {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    ProgressView()
                } else if !viewModel.isLoading && viewModel.items.isEmpty && viewModel.errorMessage == nil {
                    emptyState(viewModel: viewModel)
                }
            }
            .refreshable { await viewModel.load() }
        }
        .searchable(text: $viewModel.searchText, prompt: "Search recipes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddRecipe = true
                } label: {
                    Label("Add Recipe", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddRecipe) {
            NavigationStack {
                // Reload the list on save so the new recipe appears without a
                // manual pull-to-refresh; RecipeFormView dismisses itself.
                RecipeFormView(mode: .create, showsCancelButton: true, onSaved: {
                    Task { await viewModel.load() }
                })
            }
        }
        .task(id: reloadToken) { await viewModel.load() }
        .alert(
            "Couldn't Load Recipes",
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

    /// Favorite/unfavorite button used by both the leading swipe and the
    /// long-press context menu, so the action is discoverable two ways.
    @ViewBuilder
    private func favoriteAction(_ recipe: Recipe) -> some View {
        let isFavorite = viewModel.isFavorite(recipe)
        Button {
            Task { await viewModel.toggleFavorite(recipe) }
        } label: {
            Label(isFavorite ? "Unfavorite" : "Favorite",
                  systemImage: isFavorite ? "heart.slash" : "heart")
        }
        .tint(Color.brandPrimary)
    }

    // MARK: - Empty state

    @ViewBuilder
    private func emptyState(viewModel: RecipeListViewModel) -> some View {
        if viewModel.showFavoritesOnly {
            ContentUnavailableView(
                "No Favorites Yet",
                systemImage: "heart",
                description: Text("Tap the heart on a recipe (or swipe a row) to add it here.")
            )
        } else if viewModel.isFilteringOrSearching {
            ContentUnavailableView(
                "No Matching Recipes",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Try a different search or clear your filters.")
            )
        } else {
            ContentUnavailableView(
                "No Recipes Yet",
                systemImage: "fork.knife",
                description: Text("Recipes you add will show up here.")
            )
        }
    }
}
