import SwiftUI

struct GroceryListView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AppCommands.self) private var appCommands
    @State private var viewModel = GroceryListViewModel()
    @State private var showingClearConfirmation = false
    @State private var showingAddItem = false

    /// Cap the checklist to a readable column so rows don't stretch edge-to-edge
    /// on a 1024pt+ iPad/Mac window (which leaves a cavernous gap between an
    /// item's name and its quantity).
    private static let contentMaxWidth: CGFloat = 680

    /// The floating "+" FAB is a one-handed reach affordance that only makes
    /// sense on a compact iPhone. On iPad (regular width) and macOS the add
    /// action lives in the toolbar instead.
    private var usesToolbarAdd: Bool {
        #if os(macOS)
        return true
        #else
        return horizontalSizeClass == .regular
        #endif
    }

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
                // A floating FAB only makes sense on a compact iPhone (one-handed
                // reach). On iPad (regular width) and macOS — where the FAB would
                // also anchor to the centered empty-state view, landing the "+"
                // mid-window — use a standard toolbar button, matching the
                // Recipes list.
                if usesToolbarAdd {
                    ToolbarItem(placement: .platformPrimaryAction) {
                        Button {
                            showingAddItem = true
                        } label: {
                            Label("Add Item", systemImage: "plus")
                        }
                    }
                }
            }
            #if os(iOS)
            .overlay(alignment: .bottomTrailing) {
                if !usesToolbarAdd { addButton }
            }
            #endif
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
                // Keep the segmented control a natural width rather than letting
                // it stretch the full window.
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
            // Center the whole checklist in a readable column on wide screens.
            .frame(maxWidth: Self.contentMaxWidth)
            .frame(maxWidth: .infinity)
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
