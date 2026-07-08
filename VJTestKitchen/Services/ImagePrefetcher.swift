import Foundation

/// Loads raw image bytes for a URL. Abstracted so `ImagePrefetcher` and
/// `CachedAsyncImage` can be unit-tested against a stub instead of the network —
/// same protocol-over-SDK pattern the Service layer uses (see `AuthServicing`).
protocol ImageDataLoading: Sendable {
    func data(for url: URL) async throws -> Data
}

struct URLSessionImageDataLoader: ImageDataLoading {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for url: URL) async throws -> Data {
        try await session.data(from: url).0
    }
}

/// Fire-and-forget prefetching of recipe images into `ImageCache`. Callers
/// (e.g. `RecipeListViewModel` after a page loads) hand over the URLs of rows
/// that are about to scroll into view; each not-already-cached, not-in-flight
/// URL is downloaded and decoded in the background so `CachedAsyncImage` finds
/// it warm. `URLSession`'s per-host connection cap self-throttles a big batch,
/// so there's no explicit concurrency limit here.
@MainActor
protocol ImagePrefetching {
    func prefetch(_ urls: [URL])
}

@MainActor
final class ImagePrefetcher: ImagePrefetching {
    static let shared = ImagePrefetcher()

    private let cache: ImageCache
    private let loader: ImageDataLoading
    /// URLs with a download Task currently running, so overlapping prefetch
    /// requests (adjacent pages, a reload) don't fetch the same image twice.
    private var inFlight: Set<URL> = []

    init(cache: ImageCache = .shared, loader: ImageDataLoading = URLSessionImageDataLoader()) {
        self.cache = cache
        self.loader = loader
    }

    func prefetch(_ urls: [URL]) {
        for url in urls where cache.image(for: url) == nil && !inFlight.contains(url) {
            inFlight.insert(url)
            Task { await load(url) }
        }
    }

    /// Awaitable core, exercised directly by tests. In production it's driven
    /// fire-and-forget by `prefetch(_:)`.
    func prefetchAwaiting(_ urls: [URL]) async {
        for url in urls where cache.image(for: url) == nil && !inFlight.contains(url) {
            inFlight.insert(url)
            await load(url)
        }
    }

    private func load(_ url: URL) async {
        defer { inFlight.remove(url) }
        guard let data = try? await loader.data(for: url),
              let image = PlatformImage(data: data) else { return }
        cache.insert(image, for: url)
    }
}
