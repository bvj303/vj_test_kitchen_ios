import WidgetKit
import SwiftUI

/// **Today's Meals** — the current day's planned meals with their meal-type
/// icons, published by `MealCalendarViewModel`. Tapping opens the Calendar tab.
struct TodaysMealsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSharedConfig.Kind.todaysMeals, provider: TodaysMealsProvider()) { entry in
            TodaysMealsView(snapshot: entry.snapshot, today: entry.today)
                .containerBackground(WidgetBrand.gradient(WidgetBrand.primary), for: .widget)
                .widgetURL(WidgetSharedConfig.DeepLink.calendar)
        }
        .configurationDisplayName("Today's Meals")
        .description("What you've planned to cook today.")
        #if os(iOS)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
        #else
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        #endif
    }
}

struct TodaysMealsEntry: TimelineEntry {
    let date: Date
    let snapshot: TodaysMealsSnapshot?
    /// The real "today" for this entry, so a snapshot published for a *previous*
    /// day (app not opened since) reads as "no meals today" rather than showing
    /// yesterday's plan.
    let today: String
}

struct TodaysMealsProvider: TimelineProvider {
    /// **Local** "yyyy-MM-dd", matching how `MealCalendarViewModel` keys days —
    /// the user's calendar day, not UTC's (which rolls over at 7–8pm in US time
    /// zones and made the widget show tomorrow's plan during dinner prep).
    private func todayString(_ date: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func placeholder(in context: Context) -> TodaysMealsEntry {
        TodaysMealsEntry(date: Date(), snapshot: .preview, today: TodaysMealsSnapshot.preview.date)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodaysMealsEntry) -> Void) {
        if context.isPreview {
            completion(TodaysMealsEntry(date: Date(), snapshot: .preview, today: TodaysMealsSnapshot.preview.date))
        } else {
            completion(TodaysMealsEntry(date: Date(), snapshot: WidgetDataStore.shared.todaysMeals, today: todayString()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodaysMealsEntry>) -> Void) {
        let now = Date()
        let entry = TodaysMealsEntry(date: now, snapshot: WidgetDataStore.shared.todaysMeals, today: todayString(now))
        // Refresh at the next midnight so a stale snapshot rolls over to an empty
        // "today" even if the app isn't opened.
        let startOfTomorrow = Calendar.current.nextDate(
            after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(startOfTomorrow)))
    }
}

struct TodaysMealsView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: TodaysMealsSnapshot?
    let today: String

    /// Meals only when the snapshot is actually for today; otherwise empty.
    private var meals: [TodaysMealsSnapshot.Meal] {
        guard let snapshot, snapshot.date == today else { return [] }
        return snapshot.meals
    }

    var body: some View {
        if meals.isEmpty {
            switch family {
            #if os(iOS)
            case .accessoryRectangular:
                Label("No meals planned", systemImage: "calendar")
                    .font(.headline).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            #endif
            default:
                WidgetEmptyState(symbol: "calendar.badge.plus", message: "No meals planned today")
            }
        } else {
            switch family {
            #if os(iOS)
            case .accessoryRectangular: accessory
            #endif
            case .systemSmall: small
            default: list
            }
        }
    }

    private var header: some View {
        Label("Today", systemImage: "calendar")
            .font(.caption.weight(.semibold))
            .foregroundStyle(WidgetBrand.primary)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Spacer(minLength: 0)
            if let first = meals.first {
                mealRow(first, showType: true)
            }
            if meals.count > 1 {
                Text("+\(meals.count - 1) more")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 12 : 8) {
            header
            ForEach(Array(meals.enumerated()), id: \.offset) { _, meal in
                mealRow(meal, showType: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    #if os(iOS)
    private var accessory: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let first = meals.first {
                Label(first.recipeTitle, systemImage: first.iconSymbol)
                    .font(.headline).lineLimit(1)
            }
            if meals.count > 1 {
                Text("+\(meals.count - 1) more today")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    #endif

    private func mealRow(_ meal: TodaysMealsSnapshot.Meal, showType: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: meal.iconSymbol)
                .font(.subheadline)
                .foregroundStyle(WidgetBrand.primary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                if showType {
                    Text(meal.mealType.capitalized)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(meal.recipeTitle)
                    .font(.subheadline)
                    .lineLimit(1)
            }
        }
    }
}

extension TodaysMealsSnapshot {
    static let preview = TodaysMealsSnapshot(
        date: {
            var c = Calendar(identifier: .gregorian); c.timeZone = .current
            let d = c.dateComponents([.year, .month, .day], from: Date())
            return String(format: "%04d-%02d-%02d", d.year ?? 0, d.month ?? 0, d.day ?? 0)
        }(),
        meals: [
            .init(mealType: "Breakfast", recipeTitle: "Blueberry Buttermilk Pancakes", recipeId: 1, iconSymbol: "sunrise.fill"),
            .init(mealType: "Lunch", recipeTitle: "Grilled Chicken Caesar", recipeId: 2, iconSymbol: "sun.max.fill"),
            .init(mealType: "Dinner", recipeTitle: "Sheet-Pan Salmon & Vegetables", recipeId: 3, iconSymbol: "moon.stars.fill"),
        ]
    )
}

#Preview("Today's Meals — Medium", as: .systemMedium) {
    TodaysMealsWidget()
} timeline: {
    TodaysMealsEntry(date: .now, snapshot: .preview, today: TodaysMealsSnapshot.preview.date)
}

#Preview("Today's Meals — Large", as: .systemLarge) {
    TodaysMealsWidget()
} timeline: {
    TodaysMealsEntry(date: .now, snapshot: .preview, today: TodaysMealsSnapshot.preview.date)
}
