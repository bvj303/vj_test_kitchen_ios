import WidgetKit
import SwiftUI

/// **Grocery List** — how many items are left to buy, plus a preview of them,
/// published by `GroceryListViewModel`. Tapping opens the Groceries tab.
struct GroceryListWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSharedConfig.Kind.grocery, provider: GroceryProvider()) { entry in
            GroceryListView(snapshot: entry.snapshot)
                .containerBackground(WidgetBrand.gradient(WidgetBrand.sage), for: .widget)
                .widgetURL(WidgetSharedConfig.DeepLink.grocery)
        }
        .configurationDisplayName("Grocery List")
        .description("How many items are left to buy.")
        #if os(iOS)
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
        #else
        .supportedFamilies([.systemSmall, .systemMedium])
        #endif
    }
}

struct GroceryEntry: TimelineEntry {
    let date: Date
    let snapshot: GrocerySnapshot?
}

struct GroceryProvider: TimelineProvider {
    func placeholder(in context: Context) -> GroceryEntry {
        GroceryEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (GroceryEntry) -> Void) {
        let snapshot = context.isPreview ? .preview : WidgetDataStore.shared.grocery
        completion(GroceryEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GroceryEntry>) -> Void) {
        let entry = GroceryEntry(date: Date(), snapshot: WidgetDataStore.shared.grocery)
        completion(Timeline(entries: [entry], policy: .atEnd))
    }
}

struct GroceryListView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: GrocerySnapshot?

    var body: some View {
        let s = snapshot ?? GrocerySnapshot(toBuyCount: 0, checkedCount: 0, totalCount: 0, preview: [])
        switch family {
        #if os(iOS)
        case .accessoryCircular: circular(s)
        case .accessoryRectangular: accessory(s)
        #endif
        case .systemMedium: medium(s)
        default: small(s)
        }
    }

    private var isDone: Bool { (snapshot?.toBuyCount ?? 0) == 0 }

    private func header(_ s: GrocerySnapshot) -> some View {
        Label("Groceries", systemImage: "cart.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(WidgetBrand.sage)
    }

    private func countBlock(_ s: GrocerySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(s.toBuyCount)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(WidgetBrand.sage)
            Text(s.toBuyCount == 1 ? "item to buy" : "items to buy")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func small(_ s: GrocerySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header(s)
            Spacer(minLength: 0)
            if s.totalCount == 0 {
                Text("List is empty").font(.subheadline).foregroundStyle(.secondary)
            } else if isDone {
                Label("All done!", systemImage: "checkmark.circle.fill")
                    .font(.headline).foregroundStyle(WidgetBrand.sage)
            } else {
                countBlock(s)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func medium(_ s: GrocerySnapshot) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                header(s)
                Spacer(minLength: 0)
                if s.totalCount == 0 {
                    Text("List is empty").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    countBlock(s)
                }
            }
            .frame(width: 120, alignment: .leading)

            if !s.preview.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(s.preview.prefix(4).enumerated()), id: \.offset) { _, name in
                        Label {
                            Text(name).font(.caption).lineLimit(1)
                        } icon: {
                            Image(systemName: "circle").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    if s.toBuyCount > 4 {
                        Text("+\(s.toBuyCount - 4) more")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    #if os(iOS)
    private func accessory(_ s: GrocerySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("\(s.toBuyCount) to buy", systemImage: "cart.fill")
                .font(.headline).lineLimit(1)
            if let first = s.preview.first {
                Text(first).font(.caption).lineLimit(1).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func circular(_ s: GrocerySnapshot) -> some View {
        VStack(spacing: 0) {
            Image(systemName: "cart.fill").font(.caption2)
            Text("\(s.toBuyCount)").font(.title3.bold())
        }
    }
    #endif
}

extension GrocerySnapshot {
    static let preview = GrocerySnapshot(
        toBuyCount: 7,
        checkedCount: 3,
        totalCount: 10,
        preview: ["Whole milk", "Baby spinach", "Chicken thighs", "Lemons", "Parmesan"]
    )
}

#Preview("Grocery — Small", as: .systemSmall) {
    GroceryListWidget()
} timeline: {
    GroceryEntry(date: .now, snapshot: .preview)
}

#Preview("Grocery — Medium", as: .systemMedium) {
    GroceryListWidget()
} timeline: {
    GroceryEntry(date: .now, snapshot: .preview)
}
