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
        .overlay {
            if viewModel.isLoading && viewModel.items.isEmpty {
                ProgressView()
            } else if !viewModel.isLoading && viewModel.items.isEmpty && viewModel.errorMessage == nil {
                ContentUnavailableView(
                    "No Recipes Yet",
                    systemImage: "fork.knife",
                    description: Text("Recipes you add will show up here.")
                )
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
}
