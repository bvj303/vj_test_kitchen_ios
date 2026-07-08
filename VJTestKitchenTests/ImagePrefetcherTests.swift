import Foundation
import Testing
@testable import VJTestKitchen

/// Records which URLs were asked for and hands back a fixed PNG payload, so the
/// prefetcher can be driven without touching the network.
final class StubImageDataLoader: ImageDataLoading, @unchecked Sendable {
    private(set) var requestedURLs: [URL] = []
    let payload: Data
    var errorToThrow: Error?

    init() {
        payload = PlatformTestImage.solidPNG(width: 1, height: 1)
    }

    func data(for url: URL) async throws -> Data {
        requestedURLs.append(url)
        if let errorToThrow { throw errorToThrow }
        return payload
    }
}

@MainActor
struct ImagePrefetcherTests {
    @Test func prefetchLoadsUncachedURLIntoCache() async {
        let cache = ImageCache()
        let loader = StubImageDataLoader()
        let prefetcher = ImagePrefetcher(cache: cache, loader: loader)
        let url = URL(string: "https://example.com/a.jpg")!

        await prefetcher.prefetchAwaiting([url])

        #expect(loader.requestedURLs == [url])
        #expect(cache.image(for: url) != nil)
    }

    @Test func prefetchSkipsAlreadyCachedURL() async {
        let cache = ImageCache()
        let loader = StubImageDataLoader()
        let prefetcher = ImagePrefetcher(cache: cache, loader: loader)
        let url = URL(string: "https://example.com/a.jpg")!
        cache.insert(makeTestImage(), for: url)

        await prefetcher.prefetchAwaiting([url])

        #expect(loader.requestedURLs.isEmpty)
    }

    @Test func prefetchDoesNotRefetchAcrossCalls() async {
        let cache = ImageCache()
        let loader = StubImageDataLoader()
        let prefetcher = ImagePrefetcher(cache: cache, loader: loader)
        let url = URL(string: "https://example.com/a.jpg")!

        await prefetcher.prefetchAwaiting([url])
        await prefetcher.prefetchAwaiting([url])

        // Second pass finds it cached and skips the load.
        #expect(loader.requestedURLs == [url])
    }

    @Test func loaderFailureLeavesCacheEmpty() async {
        let cache = ImageCache()
        let loader = StubImageDataLoader()
        loader.errorToThrow = URLError(.notConnectedToInternet)
        let prefetcher = ImagePrefetcher(cache: cache, loader: loader)
        let url = URL(string: "https://example.com/a.jpg")!

        await prefetcher.prefetchAwaiting([url])

        #expect(cache.image(for: url) == nil)
    }
}
