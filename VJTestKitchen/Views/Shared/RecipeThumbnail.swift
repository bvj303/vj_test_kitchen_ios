import SwiftUI

/// Small square recipe image for list rows. Loads a remote `imageUrl` (the
/// catalog import's Cloudinary URLs) via `CachedAsyncImage`, falling back to a
/// brand-tinted glass placeholder while loading, on failure, or when a recipe
/// has no image yet. Using `CachedAsyncImage` (not `AsyncImage`) means images
/// prefetched by `RecipeListViewModel` render immediately instead of popping in
/// as the row scrolls into view. Supabase Storage cover photos (`image_path`,
/// Stage 6) will resolve to a URL upstream and flow through this same path.
struct RecipeThumbnail: View {
    let imageUrl: String?

    private var url: URL? {
        guard let imageUrl, !imageUrl.isEmpty else { return nil }
        return URL(string: imageUrl)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.thinMaterial)
            .glassEffect(.regular.tint(Color.brandPrimary.opacity(0.22)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                if let url {
                    CachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            placeholderIcon
                        case .empty:
                            ProgressView()
                        @unknown default:
                            placeholderIcon
                        }
                    }
                } else {
                    placeholderIcon
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var placeholderIcon: some View {
        Image(systemName: "fork.knife")
            .foregroundStyle(Color.brandPrimary)
    }
}
