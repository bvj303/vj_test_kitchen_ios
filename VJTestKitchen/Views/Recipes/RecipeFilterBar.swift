import SwiftUI

/// Filter controls shown directly under the Recipes search field. Rather than a
/// row of always-open dropdown chips plus a detached "clear" button (which read
/// as cluttered), this is a **single "Filters" menu** — a compact glass button
/// that opens Favorites / Prep Time / Course / Cuisine pickers and a "Clear All"
/// — followed by **removable pills for whatever is currently active**. So the
/// bar is minimal when nothing is set, shows exactly what's on at a glance, and
/// each active filter is dismissed by tapping its own ✕ (no floating button).
///
/// Course and Cuisine both bind to the single `selectedTag` (a recipe is filtered
/// by one tag at a time); their setters only clear `selectedTag` when *their own*
/// dimension is the active one, so picking "Any …" in one menu can't wipe a
/// selection made in the other.
struct RecipeFilterBar: View {
    @Bindable var viewModel: RecipeListViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filtersMenu
                activePills
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }

    /// Count of active filters, used for the "Filters · N" button label.
    private var activeCount: Int {
        var n = 0
        if viewModel.showFavoritesOnly { n += 1 }
        if viewModel.prepTimeFilter != nil { n += 1 }
        if viewModel.selectedTag != nil { n += 1 }
        return n
    }

    // MARK: - Filters menu

    private var filtersMenu: some View {
        Menu {
            Toggle(isOn: $viewModel.showFavoritesOnly) {
                Label("Favorites", systemImage: "heart")
            }

            Picker("Prep Time", selection: $viewModel.prepTimeFilter) {
                Text("Any Time").tag(PrepTimeFilter?.none)
                ForEach(PrepTimeFilter.allCases) { option in
                    Text(option.label).tag(PrepTimeFilter?.some(option))
                }
            }

            Picker("Course", selection: courseBinding) {
                Text("Any Course").tag(String?.none)
                ForEach(viewModel.courseTags, id: \.self) { course in
                    Text(course).tag(String?.some(course))
                }
            }

            if !viewModel.cuisineTags.isEmpty {
                Picker("Cuisine", selection: cuisineBinding) {
                    Text("Any Cuisine").tag(String?.none)
                    ForEach(viewModel.cuisineTags, id: \.self) { cuisine in
                        Text(cuisine).tag(String?.some(cuisine))
                    }
                }
            }

            if viewModel.hasActiveFilters {
                Divider()
                Button(role: .destructive) {
                    viewModel.clearFilters()
                } label: {
                    Label("Clear All Filters", systemImage: "xmark.circle")
                }
            }
        } label: {
            filtersButtonLabel
        }
    }

    private var filtersButtonLabel: some View {
        let isActive = activeCount > 0
        return HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.subheadline.weight(.semibold))
            Text(isActive ? "Filters · \(activeCount)" : "Filters")
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(isActive ? Color.brandPrimary : Color.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular.tint(Color.brandPrimary.opacity(isActive ? 0.30 : 0.12)), in: Capsule())
    }

    // MARK: - Active-filter pills

    /// One dismissible pill per active filter, in a stable order. Tapping a pill
    /// removes only that filter; the whole set is reset from the menu instead.
    @ViewBuilder
    private var activePills: some View {
        if viewModel.showFavoritesOnly {
            removablePill("Favorites", systemImage: "heart.fill", tint: .brandPrimary) {
                viewModel.showFavoritesOnly = false
            }
        }
        if let prep = viewModel.prepTimeFilter {
            removablePill(prep.chipLabel, systemImage: "clock", tint: .brandPrimary) {
                viewModel.prepTimeFilter = nil
            }
        }
        if let tag = viewModel.selectedTag {
            removablePill(tag, systemImage: nil, tint: .brandSage) {
                viewModel.selectedTag = nil
            }
        }
    }

    private func removablePill(_ title: String, systemImage: String?, tint: Color, remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage).font(.caption2)
                }
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular.tint(tint.opacity(0.30)), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(title) filter")
    }

    // MARK: - Tag bindings

    /// The active tag when it's a course (else nil), so the Course picker only
    /// reflects a course selection — not a chosen cuisine.
    private var courseBinding: Binding<String?> {
        Binding(
            get: { viewModel.selectedTag.flatMap { viewModel.courseTags.contains($0) ? $0 : nil } },
            set: { newValue in
                if let newValue {
                    viewModel.selectedTag = newValue
                } else if let tag = viewModel.selectedTag, viewModel.courseTags.contains(tag) {
                    viewModel.selectedTag = nil
                }
            }
        )
    }

    private var cuisineBinding: Binding<String?> {
        Binding(
            get: { viewModel.selectedTag.flatMap { viewModel.cuisineTags.contains($0) ? $0 : nil } },
            set: { newValue in
                if let newValue {
                    viewModel.selectedTag = newValue
                } else if let tag = viewModel.selectedTag, viewModel.cuisineTags.contains(tag) {
                    viewModel.selectedTag = nil
                }
            }
        )
    }
}
