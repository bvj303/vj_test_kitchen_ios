import SwiftUI

/// A drop-in replacement for `AsyncImage` that reads `ImageCache` first: if the
/// image was prefetched (see `ImagePrefetcher`) it renders on the very first
/// layout as `.success`, with no `.empty` ProgressView flash and no fade-in as
/// the row scrolls into view. On a cache miss it downloads once, stores the
/// result, and reports the usual `AsyncImagePhase` sequence — so call sites keep
/// the same `switch phase { … }` shape they used with `AsyncImage`.
struct CachedAsyncImage<Content: View>: View {
    let url: URL?
    private let loader: ImageDataLoading
    private let cache: ImageCache
    @ViewBuilder private let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase

    init(
        url: URL?,
        loader: ImageDataLoading = URLSessionImageDataLoader(),
        cache: ImageCache = .shared,
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        self.url = url
        self.loader = loader
        self.cache = cache
        self.content = content
        // Seed synchronously from the cache so a prefetched image is already
        // `.success` on first render — this is what removes the pop-in.
        if let url, let cached = cache.image(for: url) {
            _phase = State(initialValue: .success(Image(platformImage: cached)))
        } else {
            _phase = State(initialValue: .empty)
        }
    }

    var body: some View {
        content(phase)
            // Re-run when the URL changes (rows are recycled in a List).
            .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else {
            phase = .empty
            return
        }
        if let cached = cache.image(for: url) {
            phase = .success(Image(platformImage: cached))
            return
        }
        do {
            let data = try await loader.data(for: url)
            guard let image = PlatformImage(data: data) else {
                phase = .failure(URLError(.cannotDecodeContentData))
                return
            }
            cache.insert(image, for: url)
            phase = .success(Image(platformImage: image))
        } catch {
            phase = .failure(error)
        }
    }
}
