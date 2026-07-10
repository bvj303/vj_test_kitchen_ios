import SwiftUI

/// The speech-bubble callout used everywhere Spatch talks — the tutorial, the
/// Home companion, and his Recipe/Cook Mode cameos. A sage-tinted glass card,
/// matching the house pattern for custom Liquid Glass surfaces
/// (`.glassEffect(.regular.tint(...), in:)`, see `RecipeDetailView`'s tag chips).
struct SpatchBubbleView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: 240, alignment: .leading)
            .glassEffect(.regular.tint(Color.brandSage.opacity(0.18)), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    SpatchBubbleView(text: SpatchContent.randomJoke())
        .padding()
}
