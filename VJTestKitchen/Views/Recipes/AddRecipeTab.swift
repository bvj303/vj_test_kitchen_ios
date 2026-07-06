import SwiftUI

/// Hosts RecipeFormView in create mode as this tab's root. Since there's no
/// sheet/stack to dismiss back to here, a successful save instead forces a
/// fresh form via `.id(_:)` so the tab is ready for the next quick add.
struct AddRecipeTab: View {
    @State private var formInstanceId = UUID()

    var body: some View {
        NavigationStack {
            RecipeFormView(mode: .create, showsCancelButton: false, onSaved: { formInstanceId = UUID() })
                .id(formInstanceId)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        AccountButton()
                    }
                }
        }
    }
}
