import SwiftUI

/// Small square recipe image for list rows. Loads a remote `imageUrl` (the
/// catalog import's Cloudinary URLs) via the caching `RemoteImage`, falling back
/// to a brand-tinted glass placeholder while loading, on failure, or when a
/// recipe has no image yet. Using `RemoteImage` (not `AsyncImage`) means an
/// image re-appearing on scroll paints instantly from the shared cache instead
/// of re-fetching. Supabase Storage cover photos (`image_path`, Stage 6) will
/// resolve to a URL upstream and flow through this same `imageUrl` path.
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
                RemoteImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
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
