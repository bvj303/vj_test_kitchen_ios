import WidgetKit
import SwiftUI

/// **Cook's Idea** — surfaces the app's context-aware cooking suggestion
/// (`RecipeSuggester`, published by `HomeViewModel`): a headline, a vibe symbol,
/// a one-line rationale, and a few matching recipe titles. Tapping opens Home.
struct CooksIdeaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSharedConfig.Kind.cooksIdea, provider: CooksIdeaProvider()) { entry in
            CooksIdeaView(snapshot: entry.snapshot)
                .containerBackground(WidgetBrand.gradient(WidgetBrand.saffron), for: .widget)
                .widgetURL(WidgetSharedConfig.DeepLink.home)
        }
        .configurationDisplayName("Cook's Idea")
        .description("A suggestion for what to cook, tuned to the day and weather.")
        // Lock-screen accessory families are iOS-only; macOS gets the desktop
        // system families.
        #if os(iOS)
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
        #else
        .supportedFamilies([.systemSmall, .systemMedium])
        #endif
    }
}

struct CooksIdeaEntry: TimelineEntry {
    let date: Date
    let snapshot: CooksIdeaSnapshot?
}

struct CooksIdeaProvider: TimelineProvider {
    func placeholder(in context: Context) -> CooksIdeaEntry {
        CooksIdeaEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (CooksIdeaEntry) -> Void) {
        let snapshot = context.isPreview ? .preview : WidgetDataStore.shared.cooksIdea
        completion(CooksIdeaEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CooksIdeaEntry>) -> Void) {
        let entry = CooksIdeaEntry(date: Date(), snapshot: WidgetDataStore.shared.cooksIdea)
        // The app republishes on every Home load; this is just a fallback so a
        // rarely-opened app still refreshes its (day/season-derived) idea.
        let next = Date().addingTimeInterval(6 * 3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct CooksIdeaView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: CooksIdeaSnapshot?

    var body: some View {
        if let snapshot {
            switch family {
            #if os(iOS)
            case .accessoryRectangular: accessory(snapshot)
            #endif
            case .systemMedium: medium(snapshot)
            default: small(snapshot)
            }
        } else {
            WidgetEmptyState(symbol: "lightbulb", message: "Open VJ Test Kitchen for today's idea")
        }
    }

    private func small(_ s: CooksIdeaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: s.symbol)
                .font(.title2)
                .foregroundStyle(WidgetBrand.saffron)
            Spacer(minLength: 0)
            Text(s.title)
                .font(.headline)
                .fontWeight(.semibold)
                .lineLimit(2)
            Text(s.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func medium(_ s: CooksIdeaSnapshot) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label { Text(s.title).font(.headline).fontWeight(.semibold) } icon: {
                    Image(systemName: s.symbol).foregroundStyle(WidgetBrand.saffron)
                }
                .lineLimit(2)
                Text(s.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Spacer(minLength: 0)
            }
            if !s.recipes.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Try tonight")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(s.recipes.prefix(3), id: \.id) { recipe in
                        Text(recipe.title)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    #if os(iOS)
    private func accessory(_ s: CooksIdeaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(s.title, systemImage: s.symbol)
                .font(.headline)
                .lineLimit(1)
            Text(s.subtitle)
                .font(.caption)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    #endif
}

extension CooksIdeaSnapshot {
    /// Sample content for the widget gallery / previews.
    static let preview = CooksIdeaSnapshot(
        title: "Quick Winter Warmers",
        subtitle: "Fast, cozy dinners for a chilly weeknight",
        symbol: "snowflake",
        recipes: [
            .init(id: 1, title: "Hearty Chicken Noodle Soup"),
            .init(id: 2, title: "Creamy Tomato Bisque"),
            .init(id: 3, title: "White Bean & Kale Stew"),
        ]
    )
}

#Preview("Cook's Idea — Small", as: .systemSmall) {
    CooksIdeaWidget()
} timeline: {
    CooksIdeaEntry(date: .now, snapshot: .preview)
}

#Preview("Cook's Idea — Medium", as: .systemMedium) {
    CooksIdeaWidget()
} timeline: {
    CooksIdeaEntry(date: .now, snapshot: .preview)
}
