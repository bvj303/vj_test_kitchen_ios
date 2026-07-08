import SwiftUI

struct GroceryListView: View {
    @State private var viewModel = GroceryListViewModel()
    @State private var showingClearConfirmation = false
    @State private var showingAddItem = false

    var body: some View {
        content
            .navigationTitle("Grocery List")
            .toolbar {
                ToolbarItem(placement: .platformLeading) {
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
            }
            .overlay(alignment: .bottomTrailing) { addButton }
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
                            ForEach(group.rows) { row in
                                rowView(row)
                            }
                        } header: {
                            Label(group.title, systemImage: group.systemImage)
                                .foregroundStyle(Color.brandPrimary)
                        }
                    }
                }
                .platformInsetGroupedListStyle()
            }
        }
    }

    /// Large, thumb-reachable floating "add" button pinned to the bottom-trailing
    /// corner — replaces the old top-bar "+" so it's easy to reach one-handed.
    private var addButton: some View {
        Button {
            showingAddItem = true
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .frame(width: 60, height: 60)
        }
        .buttonStyle(.glassProminent)
        .tint(Color.brandPrimary)
        .clipShape(Circle())
        .padding(20)
        .accessibilityLabel("Add Item")
    }

    private func rowView(_ row: GroceryDisplayRow) -> some View {
        Button {
            Task { await viewModel.toggleChecked(row) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: row.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(row.isChecked ? Color.brandSage : Color.secondary)
                Text(row.name)
                    .strikethrough(row.isChecked)
                    .foregroundStyle(row.isChecked ? .secondary : .primary)
                Spacer()
                Text(row.quantityText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #if os(iOS)
        // Touch affordance; the same Delete lives in the context menu below, so
        // macOS (right-click) and iPad (pointer) reach it without swipe.
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task { await viewModel.delete(row) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        #endif
        .contextMenu {
            Menu {
                ForEach(GroceryCategory.allCases) { category in
                    Button {
                        Task { await viewModel.setCategory(row, to: category) }
                    } label: {
                        Label(category.displayName, systemImage: category.systemImage)
                    }
                }
            } label: {
                Label("Move to Category", systemImage: "tray.full")
            }
            Button(role: .destructive) {
                Task { await viewModel.delete(row) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityLabel("\(row.name), \(row.isChecked ? "checked" : "not checked")")
    }
}
