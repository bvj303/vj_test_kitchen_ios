import SwiftUI

/// Placeholder thumbnail — wired up to real Supabase Storage URLs in Stage 6
/// once the image bucket exists. Every recipe is imageless until then.
struct RecipeThumbnail: View {
    let imagePath: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thinMaterial)
                .glassEffect(.regular.tint(Color.brandPrimary.opacity(0.22)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Image(systemName: "fork.knife")
                .foregroundStyle(Color.brandPrimary)
        }
    }
}
