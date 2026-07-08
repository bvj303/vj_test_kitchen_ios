import SwiftUI

/// Always-visible row of filter chips shown directly under the Recipes search
/// field. Consolidated to three dropdown chips — **Prep Time, Course, Cuisine**
/// — each a compact menu whose label reflects the current selection, plus a
/// Clear chip when any filter is active. All drive the same
/// `RecipeListViewModel` filter state, so paging/search behavior is unchanged.
///
/// Course and Cuisine both bind to the single `selectedTag` (a recipe is
/// filtered by one tag at a time); their setters only clear `selectedTag` when
/// *their own* dimension is the active one, so opening one menu and picking
/// "Any …" can't wipe a selection made in the other.
struct RecipeFilterBar: View {
    @Bindable var viewModel: RecipeListViewModel

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    favoritesChip
                    prepTimeMenu
                    courseMenu
                    if !viewModel.cuisineTags.isEmpty {
                        cuisineMenu
                    }
                }
                .padding(.horizontal)
            }

            // Pinned *outside* the scroll so it's always reachable — a long
            // selected cuisine name can't push it off the trailing edge.
            if viewModel.hasActiveFilters {
                clearButton
                    .padding(.trailing)
            }
        }
        .padding(.vertical, 8)
    }

    private var clearButton: some View {
        Button {
            viewModel.clearFilters()
        } label: {
            Image(systemName: "xmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .padding(8)
                .glassEffect(.regular.tint(Color.secondary.opacity(0.12)), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear filters")
    }

    // MARK: - Menu chips

    /// Toggle chip that narrows the list to the user's favorited recipes.
    private var favoritesChip: some View {
        Button {
            viewModel.showFavoritesOnly.toggle()
        } label: {
            chipLabel(
                "Favorites",
                systemImage: viewModel.showFavoritesOnly ? "heart.fill" : "heart",
                isOn: viewModel.showFavoritesOnly,
                tint: .brandPrimary
            )
        }
        .buttonStyle(.plain)
    }

    private var prepTimeMenu: some View {
        Menu {
            Picker("Prep Time", selection: Binding(
                get: { viewModel.prepTimeFilter },
                set: { viewModel.prepTimeFilter = $0 }
            )) {
                Text("Any Time").tag(PrepTimeFilter?.none)
                ForEach(PrepTimeFilter.allCases) { option in
                    Text(option.label).tag(PrepTimeFilter?.some(option))
                }
            }
        } label: {
            chipLabel(
                viewModel.prepTimeFilter?.chipLabel ?? "Prep Time",
                systemImage: "clock",
                isOn: viewModel.prepTimeFilter != nil,
                tint: .brandPrimary
            )
        }
    }

    /// The active tag when it's a course (else nil), so the Course chip
    /// highlights only for course selections — not a chosen cuisine.
    private var selectedCourse: String? {
        guard let tag = viewModel.selectedTag, viewModel.courseTags.contains(tag) else { return nil }
        return tag
    }

    private var courseMenu: some View {
        Menu {
            Picker("Course", selection: Binding(
                get: { selectedCourse },
                set: { newValue in
                    if let newValue { viewModel.selectedTag = newValue }
                    else if selectedCourse != nil { viewModel.selectedTag = nil }
                }
            )) {
                Text("Any Course").tag(String?.none)
                ForEach(viewModel.courseTags, id: \.self) { course in
                    Text(course).tag(String?.some(course))
                }
            }
        } label: {
            chipLabel(
                selectedCourse ?? "Course",
                systemImage: "chevron.down",
                isOn: selectedCourse != nil,
                tint: .brandSage
            )
        }
    }

    private var selectedCuisine: String? {
        guard let tag = viewModel.selectedTag, viewModel.cuisineTags.contains(tag) else { return nil }
        return tag
    }

    private var cuisineMenu: some View {
        Menu {
            Picker("Cuisine", selection: Binding(
                get: { selectedCuisine },
                set: { newValue in
                    if let newValue { viewModel.selectedTag = newValue }
                    else if selectedCuisine != nil { viewModel.selectedTag = nil }
                }
            )) {
                Text("Any Cuisine").tag(String?.none)
                ForEach(viewModel.cuisineTags, id: \.self) { cuisine in
                    Text(cuisine).tag(String?.some(cuisine))
                }
            }
        } label: {
            chipLabel(
                selectedCuisine ?? "Cuisine",
                systemImage: "chevron.down",
                isOn: selectedCuisine != nil,
                tint: .brandSage
            )
        }
    }

    // MARK: - Chip styling

    /// A single glass capsule chip. When `isOn`, it takes a stronger brand tint
    /// and a leading checkmark; otherwise a faint tint over the material — the
    /// same Liquid-Glass tag-chip look established in `RecipeDetailView`.
    private func chipLabel(_ title: String, systemImage: String? = nil, isOn: Bool, tint: Color) -> some View {
        HStack(spacing: 4) {
            if isOn {
                Image(systemName: "checkmark").font(.caption2.weight(.bold))
            } else if let systemImage {
                Image(systemName: systemImage).font(.caption2)
            }
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(isOn ? tint : Color.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular.tint(tint.opacity(isOn ? 0.35 : 0.12)), in: Capsule())
    }
}
