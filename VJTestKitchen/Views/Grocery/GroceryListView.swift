import SwiftUI

struct GroceryListView: View {
    @Environment(AppCommands.self) private var appCommands
    @State private var viewModel = GroceryListViewModel()
    @State private var showingClearConfirmation = false
    @State private var showingAddItem = false

    /// Cap the checklist to a readable column so rows don't stretch edge-to-edge
    /// on a 1024pt+ iPad/Mac window (which leaves a cavernous gap between an
    /// item's name and its quantity).
    private static let contentMaxWidth: CGFloat = 680

    var body: some View {
        content
            .navigationTitle("Grocery List")
            .toolbar {
                // One Add button in the same place in every pose and width — the
                // old compact-only floating "+" turned into a toolbar button on
                // wide layouts, so it jumped when iPhone Duo opened or closed. A
                // standard toolbar item also moves into Duo's side controls column
                // with the other bars. High priority: it's this screen's main action.
                ToolbarItem(placement: .platformPrimaryAction) {
                    Button {
                        showingAddItem = true
                    } label: {
                        Label("Add Item", systemImage: "plus")
                    }
                }
                .platformVisibilityPriority(.high)
                // List-level actions go in the system overflow menu (HIG: move
                // your own overflow actions there, and reserve the ellipsis for it)
                // rather than a custom ellipsis menu.
                if !viewModel.isEmpty {
                    PlatformOverflowMenu {
                        Button {
                            Task { await viewModel.exportToReminders() }
                        } label: {
                            Label("Export to Apple Reminders", systemImage: "square.and.arrow.up")
                        }
                        Button(role: .destructive) {
                            showingClearConfirmation = true
                        } label: {
                            Label("Clear List", systemImage: "trash")
                        }
                    }
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
                        .surface(.card)
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
            // Menu-bar / keyboard-shortcut commands. Context-aware ⌘N lands here
            // when Grocery is the visible tab; ⌘R reloads the list.
            .onChange(of: appCommands.newGroceryItemRequests) { _, _ in
                showingAddItem = true
            }
            .onChange(of: appCommands.refreshRequests) { _, _ in
                Task { await viewModel.load() }
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isEmpty {
            if viewModel.isLoading {
                ProgressView()
            } else {
                ContentUnavailableView {
                    Label("Your List Is Empty", systemImage: "cart")
                } description: {
                    Text("Add items by hand, or open a recipe and tap \u{201C}Add All\u{201D} to pull its ingredients straight in.")
                } actions: {
                    Button {
                        showingAddItem = true
                    } label: {
                        Label("Add an Item", systemImage: "plus")
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Color.brandPrimary)
                }
            }
        } else {
            VStack(spacing: 0) {
                Picker("Group By", selection: $viewModel.grouping) {
                    ForEach(GroceryListViewModel.Grouping.allCases) { grouping in
                        Text(grouping.label).tag(grouping)
                    }
                }
                .pickerStyle(.segmented)
                // Keep the segmented control a natural width rather than letting
                // it stretch the full column.
                .frame(maxWidth: 420)
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
            // A readable, centered column on wide screens — and on a partially
            // folded iPhone Duo, wholly on one side of the fold so no row or the
            // Group By control sits on the crease.
            .foldAwareColumn(maxWidth: Self.contentMaxWidth)
        }
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
