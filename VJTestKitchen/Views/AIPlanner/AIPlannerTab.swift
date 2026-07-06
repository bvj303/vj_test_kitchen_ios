import SwiftUI

struct AIPlannerTab: View {
    var body: some View {
        NavigationStack {
            AIPlannerView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        AccountButton()
                    }
                }
        }
    }
}
