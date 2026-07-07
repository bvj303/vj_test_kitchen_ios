import SwiftUI

struct RecipeListView: View {
    @State private var viewModel = RecipeListViewModel()
    @State private var showingAddRecipe = false
    let onSelect: (Recipe) -> Void

    var body: some View {
        @Bindable var viewModel = viewModel

        List(viewModel.items) { recipe in
            Button {
                onSelect(recipe)
            } label: {
                RecipeRowView(recipe: recipe)
            }
            .buttonStyle(.plain)
            .onAppear { Task { await viewModel.loadMoreIfNeeded(currentItem: recipe) } }
        }
        .listStyle(.plain)
        .searchable(text: $viewModel.searchText, prompt: "Search recipes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddRecipe = true
                } label: {
                    Label("Add Recipe", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                filterMenu(viewModel: viewModel)
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
        .overlay {
            if viewModel.isLoading && viewModel.items.isEmpty {
                ProgressView()
            } else if !viewModel.isLoading && viewModel.items.isEmpty && viewModel.errorMessage == nil {
                emptyState(viewModel: viewModel)
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
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

    // MARK: - Filter menu

    @ViewBuilder
    private func filterMenu(viewModel: RecipeListViewModel) -> some View {
        Menu {
            if !viewModel.courseTags.isEmpty {
                Section("Course") {
                    ForEach(viewModel.courseTags, id: \.self) { tag in
                        tagButton(tag, viewModel: viewModel)
                    }
                }
            }
            if !viewModel.cuisineTags.isEmpty {
                Section("Cuisine") {
                    ForEach(viewModel.cuisineTags, id: \.self) { tag in
                        tagButton(tag, viewModel: viewModel)
                    }
                }
            }
            Section("Max Prep Time") {
                Picker("Max Prep Time", selection: Binding(
                    get: { viewModel.maxPrepTime },
                    set: { viewModel.maxPrepTime = $0 }
                )) {
                    Text("Any").tag(Int?.none)
                    ForEach(RecipeListViewModel.prepTimeOptions, id: \.self) { minutes in
                        Text("\(minutes) min or less").tag(Int?.some(minutes))
                    }
                }
            }
            if viewModel.hasActiveFilters {
                Section {
                    Button(role: .destructive) {
                        viewModel.clearFilters()
                    } label: {
                        Label("Clear Filters", systemImage: "xmark.circle")
                    }
                }
            }
        } label: {
            Label(
                "Filter",
                systemImage: viewModel.hasActiveFilters
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
    }

    /// A single tappable category row: tapping the active tag clears it (toggle),
    /// so the menu doubles as its own "off" switch without a separate control.
    @ViewBuilder
    private func tagButton(_ tag: String, viewModel: RecipeListViewModel) -> some View {
        Button {
            viewModel.selectedTag = (viewModel.selectedTag == tag) ? nil : tag
        } label: {
            if viewModel.selectedTag == tag {
                Label(tag, systemImage: "checkmark")
            } else {
                Text(tag)
            }
        }
    }

    // MARK: - Empty state

    @ViewBuilder
    private func emptyState(viewModel: RecipeListViewModel) -> some View {
        if viewModel.isFilteringOrSearching {
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
