import SwiftUI

/// Circular profile picture. Loads a remote `avatarUrl` via `AsyncImage`,
/// falling back to a brand-tinted glass circle with the user's initials (or a
/// person glyph) while loading, on failure, or when no avatar is set. The same
/// view renders your own avatar and — since avatars are publicly readable —
/// any other user's.
struct AvatarView: View {
    let avatarUrl: String?
    /// Used to derive initials for the placeholder; falls back to a person
    /// glyph when empty/nil.
    var name: String?
    var size: CGFloat = 96

    private var url: URL? {
        guard let avatarUrl, !avatarUrl.isEmpty else { return nil }
        return URL(string: avatarUrl)
    }

    private var initials: String? {
        guard let name else { return nil }
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        let joined = letters.joined().uppercased()
        return joined.isEmpty ? nil : joined
    }

    var body: some View {
        Circle()
            .fill(.thinMaterial)
            .glassEffect(.regular.tint(Color.brandPrimary.opacity(0.22)), in: Circle())
            .overlay {
                if let url {
                    AsyncImage(url: url, transaction: Transaction(animation: .default)) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            placeholder
                        case .empty:
                            ProgressView()
                        @unknown default:
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .clipShape(Circle())
            .frame(width: size, height: size)
    }

    @ViewBuilder
    private var placeholder: some View {
        if let initials {
            Text(initials)
                .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.brandPrimary)
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .padding(size * 0.18)
                .foregroundStyle(Color.brandPrimary)
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        AvatarView(avatarUrl: nil, name: "Ada Lovelace")
        AvatarView(avatarUrl: nil, name: nil, size: 60)
    }
    .padding()
}
