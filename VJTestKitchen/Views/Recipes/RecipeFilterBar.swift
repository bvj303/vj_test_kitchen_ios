import SwiftUI

/// Always-visible horizontal row of filter chips shown directly under the
/// Recipes search field. Replaces the old tucked-away toolbar filter `Menu` so
/// filtering is one tap away — especially on iPad, where the wide list column
/// has ample room and a hidden menu icon was easy to miss.
///
/// Course tags (few, fixed order) are direct toggle chips; the longer Cuisine
/// list and the Prep Time options stay behind compact menu chips whose labels
/// reflect the current selection. All of these drive the same
/// `RecipeListViewModel` filter state the toolbar menu used, so paging/search
/// behavior is unchanged.
struct RecipeFilterBar: View {
    @Bindable var viewModel: RecipeListViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.courseTags, id: \.self) { tag in
                    Button {
                        viewModel.selectedTag = (viewModel.selectedTag == tag) ? nil : tag
                    } label: {
                        chipLabel(tag, isOn: viewModel.selectedTag == tag, tint: .brandSage)
                    }
                    .buttonStyle(.plain)
                }

                if !viewModel.cuisineTags.isEmpty {
                    cuisineMenu
                }

                prepTimeMenu

                if viewModel.hasActiveFilters {
                    Button {
                        viewModel.clearFilters()
                    } label: {
                        chipLabel("Clear", systemImage: "xmark", isOn: false, tint: .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Menu chips

    /// Whether the current `selectedTag` is a cuisine (vs a course), so the
    /// cuisine chip highlights only when the active tag is actually one of its
    /// options — a selected course must not make Cuisine look active.
    private var selectedCuisine: String? {
        guard let tag = viewModel.selectedTag, viewModel.cuisineTags.contains(tag) else { return nil }
        return tag
    }

    private var cuisineMenu: some View {
        Menu {
            Picker("Cuisine", selection: Binding(
                get: { selectedCuisine },
                set: { viewModel.selectedTag = $0 }
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

    private var prepTimeMenu: some View {
        Menu {
            Picker("Max Prep Time", selection: Binding(
                get: { viewModel.maxPrepTime },
                set: { viewModel.maxPrepTime = $0 }
            )) {
                Text("Any").tag(Int?.none)
                ForEach(RecipeListViewModel.prepTimeOptions, id: \.self) { minutes in
                    Text("\(minutes) min or less").tag(Int?.some(minutes))
                }
            }
        } label: {
            chipLabel(
                viewModel.maxPrepTime.map { "≤ \($0) min" } ?? "Prep Time",
                systemImage: "clock",
                isOn: viewModel.maxPrepTime != nil,
                tint: .brandPrimary
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
