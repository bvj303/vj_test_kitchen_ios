import SwiftUI

struct GroceryListTab: View {
    var body: some View {
        NavigationStack {
            GroceryListView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        AccountButton()
                    }
                }
        }
    }
}
