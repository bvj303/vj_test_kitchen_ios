import SwiftUI

struct GroceryListView: View {
    @State private var viewModel = GroceryListViewModel()
    @State private var showingClearConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if viewModel.aggregatedIngredients.isEmpty {
                    ContentUnavailableView(
                        "Your List Is Empty",
                        systemImage: "cart",
                        description: Text("Browse your recipes and tap \"Add to Grocery List\" to populate this view.")
                    )
                    .padding(.top, 40)
                } else {
                    ForEach(viewModel.aggregatedIngredients) { ingredient in
                        HStack {
                            Text(ingredient.name)
                            Spacer()
                            Text(Self.formattedAmount(ingredient))
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .glassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }

                Text("Items are aggregated from \(viewModel.selectedRecipeCount) selected \(viewModel.selectedRecipeCount == 1 ? "recipe" : "recipes").")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding()
            .padding(.bottom, 60)
        }
        .navigationTitle("Grocery List")
        .toolbar {
            if viewModel.selectedRecipeCount > 0 {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear List", role: .destructive) {
                        showingClearConfirmation = true
                    }
                }
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .confirmationDialog(
            "Clear all items from your grocery list?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear List", role: .destructive) { viewModel.clearList() }
            Button("Cancel", role: .cancel) {}
        }
        .safeAreaInset(edge: .bottom) {
            if !viewModel.aggregatedIngredients.isEmpty {
                Button {
                    Task { await viewModel.exportToReminders() }
                } label: {
                    Label(viewModel.isExporting ? "Exporting..." : "Export to Apple Reminders", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(viewModel.isExporting)
                .padding()
            }
        }
        .alert(
            "Something Went Wrong",
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

    private static func formattedAmount(_ ingredient: GroceryListViewModel.AggregatedIngredient) -> String {
        let amountText = ingredient.amount == ingredient.amount.rounded()
            ? String(Int(ingredient.amount))
            : String(format: "%.2f", ingredient.amount)
        return ingredient.unit.isEmpty ? amountText : "\(amountText) \(ingredient.unit)"
    }
}
