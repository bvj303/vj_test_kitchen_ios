import SwiftUI

struct GroceryListView: View {
    @State private var viewModel = GroceryListViewModel()
    @State private var showingClearConfirmation = false
    @State private var showingAddItem = false

    private var isListEmpty: Bool {
        viewModel.aggregatedIngredients.isEmpty && viewModel.customItems.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isListEmpty {
                    ContentUnavailableView(
                        "Your List Is Empty",
                        systemImage: "cart",
                        description: Text("Tap + to add an item, or browse your recipes and tap \"Add to Grocery List\" to populate this view.")
                    )
                    .padding(.top, 40)
                } else {
                    if !viewModel.customItems.isEmpty {
                        sectionHeader("Added Items")
                        ForEach(viewModel.customItems) { item in
                            HStack {
                                Text(item.name)
                                Spacer()
                                Text(Self.formattedAmount(amount: item.amount, unit: item.unit))
                                    .foregroundStyle(.secondary)
                                Button {
                                    viewModel.removeCustomItem(item)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding()
                            .glassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }

                    if !viewModel.aggregatedIngredients.isEmpty {
                        sectionHeader("From Recipes")
                        ForEach(viewModel.aggregatedIngredients) { ingredient in
                            HStack {
                                Text(ingredient.name)
                                Spacer()
                                Text(Self.formattedAmount(amount: ingredient.amount, unit: ingredient.unit))
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .glassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
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
            if viewModel.selectedRecipeCount > 0 || !viewModel.customItems.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear List", role: .destructive) {
                        showingClearConfirmation = true
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddItem = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Item")
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .sheet(isPresented: $showingAddItem) {
            AddGroceryItemSheet { name, amount, unit in
                viewModel.addCustomItem(name: name, amount: amount, unit: unit)
            }
        }
        .confirmationDialog(
            "Clear all items from your grocery list?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear List", role: .destructive) { viewModel.clearList() }
            Button("Cancel", role: .cancel) {}
        }
        .safeAreaInset(edge: .bottom) {
            if !isListEmpty {
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .foregroundStyle(Color.brandPrimary)
    }

    private static func formattedAmount(amount: Double, unit: String) -> String {
        let amountText = amount == amount.rounded()
            ? String(Int(amount))
            : String(format: "%.2f", amount)
        return unit.isEmpty ? amountText : "\(amountText) \(unit)"
    }
}
