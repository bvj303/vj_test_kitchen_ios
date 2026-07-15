import SwiftUI

struct RecipeListView: View {
    @Environment(AppCommands.self) private var appCommands
    // recipes is account-synced via Supabase, so re-sync when the app returns
    // to the foreground — a recipe added/edited/deleted on another device
    // then shows up here without a manual pull-to-refresh.
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = RecipeListViewModel()
    @State private var showingAddRecipe = false
    @FocusState private var searchFieldFocused: Bool
    /// Changing this re-runs the initial load — the parent bumps it after a
    /// delete so the removed recipe drops out of the list.
    var reloadToken: UUID = UUID()
    let onSelect: (Recipe) -> Void

    var body: some View {
        @Bindable var viewModel = viewModel

        // Both the search field and the filter bar are plain siblings stacked
        // above the List rather than nav-bar chrome (`.searchable` /
        // `.safeAreaInset(edge: .top)`): those hoist into the navigation bar via
        // a mechanism that silently fails to install when the Recipes screen is
        // entered as a *secondary* tab (a lazily-created TabView tab), which is
        // exactly how it's reached now that Home is the first tab — the search
        // field simply never appeared on iPhone. A VStack sibling always renders,
        // so search + filters show regardless of how the tab is opened.
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal)
                .padding(.top, 8)
                .background(.bar)
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
                #if os(iOS)
                // Touch affordance; the same favorite action lives in the
                // context menu below, so macOS/iPad pointer reach it too.
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    favoriteAction(recipe)
                }
                #endif
                .contextMenu {
                    favoriteAction(recipe)
                }
                .onAppear { Task { await viewModel.loadMoreIfNeeded(currentItem: recipe) } }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .overlay {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    ProgressView()
                } else if !viewModel.isLoading && viewModel.items.isEmpty && viewModel.errorMessage == nil {
                    emptyState(viewModel: viewModel)
                }
            }
            .refreshable { await viewModel.load() }
            .scrollDismissesKeyboard(.interactively)
        }
        .screenBackground()
        .dismissesKeyboardOnBackgroundTap()
        .keyboardDoneButton()
        .toolbar {
            ToolbarItem(placement: .platformPrimaryAction) {
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
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await viewModel.load() }
            }
        }
        // Menu-bar / keyboard-shortcut commands (⌘N new recipe, ⌘F find, ⌘R reload).
        .onChange(of: appCommands.newRecipeRequests) { _, _ in
            showingAddRecipe = true
        }
        .onChange(of: appCommands.searchRequests) { _, _ in
            // A tiny delay so this survives a concurrent tab switch/nav-stack
            // pop (e.g. Home's search shortcut, which does both at once):
            // setting @FocusState synchronously during that transition is a
            // known SwiftUI race that can silently fail to raise the keyboard.
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                searchFieldFocused = true
            }
        }
        .onChange(of: appCommands.refreshRequests) { _, _ in
            Task { await viewModel.load() }
        }
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

    // MARK: - Search field

    /// A custom glass search field rendered inline above the list, replacing the
    /// nav-bar `.searchable` (which didn't install on the secondary Recipes tab —
    /// see the body comment). Binds straight to `viewModel.searchText`, whose
    /// `didSet` debounces the reload, so typing behaves exactly as before.
    private var searchField: some View {
        @Bindable var viewModel = viewModel
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search recipes", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .focused($searchFieldFocused)
                .submitLabel(.search)
                .platformAutocapitalization(.never)
                .autocorrectionDisabled()
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassEffect(.regular, in: Capsule())
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
            ContentUnavailableView {
                Label("No Matching Recipes", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Nothing matched that. Try a different search, or clear what you've got set.")
            } actions: {
                Button {
                    viewModel.searchText = ""
                    viewModel.clearFilters()
                } label: {
                    Text("Clear Search & Filters")
                }
                .buttonStyle(.glassProminent)
                .tint(Color.brandPrimary)
            }
        } else {
            ContentUnavailableView {
                Label("No Recipes Yet", systemImage: "fork.knife")
            } description: {
                Text("Add your first recipe and it'll show up here.")
            } actions: {
                Button {
                    showingAddRecipe = true
                } label: {
                    Label("Add a Recipe", systemImage: "plus")
                }
                .buttonStyle(.glassProminent)
                .tint(Color.brandPrimary)
            }
        }
    }
}
