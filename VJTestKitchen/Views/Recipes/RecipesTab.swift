import SwiftUI

/// The one tab with a real list+detail shape. A single `NavigationSplitView`
/// serves every width: it collapses to a list → detail push on compact widths
/// (iPhone, the iPhone Duo outer display, narrow Split View) and expands to
/// side-by-side columns on regular widths (iPad, the iPhone Duo inner display),
/// adapting its columns to the fold on its own.
///
/// Deliberately NOT an `if horizontalSizeClass == .regular { split } else { stack }`
/// switch (the previous design): swapping the whole navigation container
/// whenever the size class flips — which iPhone Duo does every time it opens or
/// closes — tore down the list's view model (search, filters, loaded pages,
/// scroll position), the pushed recipe, and any Cook Mode presented from it.
struct RecipesTab: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AppCommands.self) private var appCommands
    @State private var selectedRecipe: Recipe?
    /// Which column a collapsed (compact) split view shows. Tapping a recipe
    /// moves it to the detail; the system sets it back to the sidebar when the
    /// user navigates back.
    @State private var compactColumn: NavigationSplitViewColumn = .sidebar
    // Bumped after a delete to re-run the list's load, so the removed recipe
    // stops appearing (and can't be tapped back into a now-broken detail).
    @State private var listReloadToken = UUID()

    /// A recipe was deleted from its detail screen. Clear the selection (the
    /// detail falls back to the placeholder, or a collapsed split view returns
    /// to the list) and reload the list so the removed recipe drops out.
    private func handleRecipeDeleted() {
        selectedRecipe = nil
        compactColumn = .sidebar
        listReloadToken = UUID()
    }

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            RecipeListView(reloadToken: listReloadToken) { recipe in
                selectedRecipe = recipe
                compactColumn = .detail
            }
            .navigationTitle("Recipes")
            // Without an explicit width the sidebar collapses far too narrow on
            // macOS (and the roomy Mac window makes it obvious), truncating
            // recipe titles and cramping them against the thumbnails. Give it a
            // readable default that still resizes.
            .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 460)
            // Collapsed, the list IS the screen, so the account button lives
            // here. Expanded, it moves to the detail column's toolbar instead —
            // the sidebar's trailing slot holds the system sidebar toggle.
            .toolbar {
                if horizontalSizeClass != .regular { accountToolbarItem }
            }
        } detail: {
            Group {
                if let selectedRecipe {
                    // Per-recipe identity so selecting a different recipe
                    // rebuilds the detail (fresh @State + re-run .task) instead
                    // of keeping the first recipe tapped.
                    RecipeDetailView(recipeId: selectedRecipe.id, onDeleted: handleRecipeDeleted)
                        .id(selectedRecipe.id)
                } else {
                    // A titled bar on the placeholder too, so the account
                    // button reads as part of a coherent toolbar.
                    ContentUnavailableView("Select a Recipe", systemImage: "fork.knife")
                        .navigationTitle("Recipes")
                }
            }
            .toolbar {
                if horizontalSizeClass == .regular { accountToolbarItem }
            }
        }
        // A search request (Home's search shortcut, ⌘F) should land on the
        // list's search field — so a collapsed split view returns to the list
        // first; otherwise the field would be buried under the pushed detail.
        .onChange(of: appCommands.searchRequests) { _, _ in
            compactColumn = .sidebar
        }
    }

    private var accountToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .platformPrimaryAction) {
            AccountButton()
        }
        .platformVisibilityPriority(.low)
    }
}
