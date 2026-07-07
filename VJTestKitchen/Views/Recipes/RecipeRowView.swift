import SwiftUI

struct RecipeRowView: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 12) {
            RecipeThumbnail(imageUrl: recipe.imageUrl)
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 12) {
                    if let prepTime = recipe.prepTime {
                        Label("\(prepTime) min", systemImage: "clock")
                    }
                    if let servings = recipe.servings {
                        Label("\(servings)", systemImage: "person.2")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
