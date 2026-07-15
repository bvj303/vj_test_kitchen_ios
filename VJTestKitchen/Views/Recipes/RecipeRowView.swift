import SwiftUI

struct RecipeRowView: View {
    let recipe: Recipe
    /// Shows a small heart beside the title when the recipe is favorited.
    var isFavorite: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            RecipeThumbnail(imageUrl: recipe.imageUrl)
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(recipe.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(Color.brandPrimary)
                            .accessibilityLabel("Favorite")
                    }
                }

                HStack(spacing: 12) {
                    // Always show the prep-time field (a dash when unknown) so the
                    // metadata row starts at the same place on every row — a
                    // time-less recipe like "Aperol Flip" then lines up with the
                    // rest instead of leading with its servings. Matches the Home
                    // suggested cards.
                    Label(PrepTimeFormat.label(minutes: recipe.prepTime) ?? "—", systemImage: "clock")
                    if let servings = recipe.servings {
                        Label("\(servings)", systemImage: "person.2")
                    }
                    if let atkRating = recipe.atkRating {
                        Label(String(format: "%.1f", atkRating), systemImage: "star.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.compact)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
