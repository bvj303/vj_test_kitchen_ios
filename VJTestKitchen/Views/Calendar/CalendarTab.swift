import SwiftUI

struct CalendarTab: View {
    var body: some View {
        NavigationStack {
            MealCalendarView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        AccountButton()
                    }
                }
        }
    }
}
