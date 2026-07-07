import SwiftUI
import UIKit

/// Abstracts the "download bytes for a URL" step so `RemoteImageLoader` can be
/// unit-tested against canned data instead of the network.
protocol ImageDataFetching: Sendable {
    func data(from url: URL) async throws -> Data
}

/// Production fetcher — goes through `URLSession` (whose `URLCache` gives the
/// on-disk tier configured at app launch).
struct URLSessionImageFetcher: ImageDataFetching {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(from url: URL) async throws -> Data {
        try await session.data(from: url).0
    }
}

/// Drives a single `RemoteImage`: checks the in-memory `ImageCache` first
/// (instant, flicker-free on scroll-back), otherwise fetches + decodes once and
/// caches the result.
@MainActor
@Observable
final class RemoteImageLoader {
    private(set) var image: UIImage?

    private let cache: ImageCache
    private let fetcher: ImageDataFetching

    init(cache: ImageCache = .shared, fetcher: ImageDataFetching = URLSessionImageFetcher()) {
        self.cache = cache
        self.fetcher = fetcher
    }

    /// Loads `url` into `image`. A cache hit sets it synchronously (no fade —
    /// already-seen images should feel instant); a network load fades in via
    /// the caller's transition. A nil URL, a fetch error, or undecodable data
    /// all leave `image` untouched so the placeholder stays visible.
    func load(_ url: URL?) async {
        guard let url else {
            image = nil
            return
        }
        if let cached = cache.image(for: url) {
            image = cached
            return
        }
        do {
            let data = try await fetcher.data(from: url)
            guard !Task.isCancelled, let decoded = UIImage(data: data) else { return }
            cache.insert(decoded, for: url)
            withAnimation(.easeIn(duration: 0.25)) {
                image = decoded
            }
        } catch {
            // Network/decoding failure: leave `image` nil so the placeholder shows.
        }
    }
}

/// A caching, fade-in replacement for `AsyncImage`. Loads lazily via `.task`
/// (i.e. only once the view is actually on-screen — so a long list only fetches
/// the rows the user scrolls to) and re-uses the shared decoded-image cache so
/// scrolling back is instant. The `placeholder` stays behind the image so the
/// fade reveals over it rather than over blank space.
struct RemoteImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var loader = RemoteImageLoader()

    var body: some View {
        ZStack {
            placeholder()
            if let uiImage = loader.image {
                content(Image(uiImage: uiImage))
                    .transition(.opacity)
            }
        }
        .task(id: url) { await loader.load(url) }
    }
}
