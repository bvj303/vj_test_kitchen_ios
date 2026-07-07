import SwiftUI

struct GroceryListView: View {
    @State private var viewModel = GroceryListViewModel()
    @State private var showingClearConfirmation = false
    @State private var showingAddItem = false

    var body: some View {
        content
            .navigationTitle("Grocery List")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !viewModel.isEmpty {
                        Menu {
                            Button {
                                Task { await viewModel.exportToReminders() }
                            } label: {
                                Label("Export to Apple Reminders", systemImage: "square.and.arrow.up")
                            }
                            Divider()
                            Button(role: .destructive) {
                                showingClearConfirmation = true
                            } label: {
                                Label("Clear List", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("List Options")
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
                AddGroceryItemSheet { name, amount, unit, category in
                    Task { await viewModel.addManualItem(name: name, amount: amount, unit: unit, category: category) }
                }
            }
            .confirmationDialog(
                "Clear all items from your grocery list?",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear List", role: .destructive) { Task { await viewModel.clearList() } }
                Button("Cancel", role: .cancel) {}
            }
            .overlay {
                if viewModel.isExporting {
                    ProgressView("Exporting…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

    @ViewBuilder
    private var content: some View {
        if viewModel.isEmpty {
            if viewModel.isLoading {
                ProgressView()
            } else {
                ContentUnavailableView(
                    "Your List Is Empty",
                    systemImage: "cart",
                    description: Text("Tap + to add an item, or open a recipe and add its ingredients.")
                )
            }
        } else {
            VStack(spacing: 0) {
                Picker("Group By", selection: $viewModel.grouping) {
                    ForEach(GroceryListViewModel.Grouping.allCases) { grouping in
                        Text(grouping.label).tag(grouping)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                List {
                    ForEach(viewModel.groups) { group in
                        Section {
                            ForEach(group.items) { item in
                                row(item)
                            }
                        } header: {
                            Label(group.title, systemImage: group.systemImage)
                                .foregroundStyle(Color.brandPrimary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private func row(_ item: GroceryItem) -> some View {
        Button {
            Task { await viewModel.toggleChecked(item) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isChecked ? Color.brandSage : Color.secondary)
                Text(item.name)
                    .strikethrough(item.isChecked)
                    .foregroundStyle(item.isChecked ? .secondary : .primary)
                Spacer()
                Text(GroceryListViewModel.formattedQuantity(amount: item.amount, unit: item.unit))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task { await viewModel.delete(item) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Menu {
                ForEach(GroceryCategory.allCases) { category in
                    Button {
                        Task { await viewModel.setCategory(item, to: category) }
                    } label: {
                        Label(category.displayName, systemImage: category.systemImage)
                    }
                }
            } label: {
                Label("Move to Category", systemImage: "tray.full")
            }
            Button(role: .destructive) {
                Task { await viewModel.delete(item) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityLabel("\(item.name), \(item.isChecked ? "checked" : "not checked")")
    }
}
