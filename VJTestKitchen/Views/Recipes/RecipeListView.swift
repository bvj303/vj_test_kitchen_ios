import SwiftUI

struct RecipeListView: View {
    @State private var viewModel = RecipeListViewModel()
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
        .safeAreaInset(edge: .top, spacing: 0) {
            RecipeFilterBar(viewModel: viewModel)
                .background(.bar)
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
