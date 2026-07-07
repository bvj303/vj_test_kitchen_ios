import Foundation
import Testing
import UIKit
@testable import VJTestKitchen

/// Builds a tiny solid-color UIImage for cache/loader tests without hitting the
/// network — enough to exercise decode/cache behavior.
private func makeImage(_ color: UIColor = .red) -> UIImage {
    let size = CGSize(width: 2, height: 2)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { ctx in
        color.setFill()
        ctx.fill(CGRect(origin: .zero, size: size))
    }
}

private func makePNGData(_ color: UIColor = .red) -> Data {
    makeImage(color).pngData()!
}

@MainActor
struct ImageCacheTests {
    @Test func returnsNilForMissingURL() {
        let cache = ImageCache(countLimit: 10)
        #expect(cache.image(for: URL(string: "https://example.com/missing.png")!) == nil)
    }

    @Test func insertsAndRetrievesByURL() {
        let cache = ImageCache(countLimit: 10)
        let url = URL(string: "https://example.com/a.png")!
        let image = makeImage()

        cache.insert(image, for: url)

        #expect(cache.image(for: url) === image)
    }

    @Test func distinctURLsAreKeptSeparately() {
        let cache = ImageCache(countLimit: 10)
        let a = URL(string: "https://example.com/a.png")!
        let b = URL(string: "https://example.com/b.png")!
        let imageA = makeImage(.red)
        let imageB = makeImage(.blue)

        cache.insert(imageA, for: a)
        cache.insert(imageB, for: b)

        #expect(cache.image(for: a) === imageA)
        #expect(cache.image(for: b) === imageB)
    }

    @Test func insertOverwritesExistingEntry() {
        let cache = ImageCache(countLimit: 10)
        let url = URL(string: "https://example.com/a.png")!
        let first = makeImage(.red)
        let second = makeImage(.blue)

        cache.insert(first, for: url)
        cache.insert(second, for: url)

        #expect(cache.image(for: url) === second)
    }

    @Test func removeAllClearsCache() {
        let cache = ImageCache(countLimit: 10)
        let url = URL(string: "https://example.com/a.png")!
        cache.insert(makeImage(), for: url)

        cache.removeAll()

        #expect(cache.image(for: url) == nil)
    }
}

/// A fetcher that returns canned data (or throws) so the loader can be tested
/// without any real networking.
private final class FakeImageFetcher: ImageDataFetching, @unchecked Sendable {
    var dataToReturn: Data?
    var errorToThrow: Error?
    private(set) var fetchCount = 0
    private(set) var requestedURLs: [URL] = []

    func data(from url: URL) async throws -> Data {
        fetchCount += 1
        requestedURLs.append(url)
        if let errorToThrow { throw errorToThrow }
        return dataToReturn ?? Data()
    }
}

private struct FetchError: Error {}

@MainActor
struct RemoteImageLoaderTests {
    @Test func nilURLLeavesImageNilAndDoesNotFetch() async {
        let fetcher = FakeImageFetcher()
        let loader = RemoteImageLoader(cache: ImageCache(countLimit: 10), fetcher: fetcher)

        await loader.load(nil)

        #expect(loader.image == nil)
        #expect(fetcher.fetchCount == 0)
    }

    @Test func fetchesDecodesAndExposesImage() async {
        let fetcher = FakeImageFetcher()
        fetcher.dataToReturn = makePNGData()
        let loader = RemoteImageLoader(cache: ImageCache(countLimit: 10), fetcher: fetcher)
        let url = URL(string: "https://example.com/a.png")!

        await loader.load(url)

        #expect(loader.image != nil)
        #expect(fetcher.fetchCount == 1)
    }

    @Test func storesFetchedImageInSharedCache() async {
        let cache = ImageCache(countLimit: 10)
        let fetcher = FakeImageFetcher()
        fetcher.dataToReturn = makePNGData()
        let loader = RemoteImageLoader(cache: cache, fetcher: fetcher)
        let url = URL(string: "https://example.com/a.png")!

        await loader.load(url)

        #expect(cache.image(for: url) != nil)
    }

    @Test func cacheHitSkipsNetworkFetch() async {
        let cache = ImageCache(countLimit: 10)
        let url = URL(string: "https://example.com/a.png")!
        cache.insert(makeImage(), for: url)
        let fetcher = FakeImageFetcher()
        let loader = RemoteImageLoader(cache: cache, fetcher: fetcher)

        await loader.load(url)

        #expect(loader.image != nil)
        #expect(fetcher.fetchCount == 0)
    }

    @Test func fetchFailureLeavesImageNil() async {
        let fetcher = FakeImageFetcher()
        fetcher.errorToThrow = FetchError()
        let loader = RemoteImageLoader(cache: ImageCache(countLimit: 10), fetcher: fetcher)

        await loader.load(URL(string: "https://example.com/a.png")!)

        #expect(loader.image == nil)
    }

    @Test func undecodableDataLeavesImageNil() async {
        let fetcher = FakeImageFetcher()
        fetcher.dataToReturn = Data([0x00, 0x01, 0x02])  // not a valid image
        let loader = RemoteImageLoader(cache: ImageCache(countLimit: 10), fetcher: fetcher)

        await loader.load(URL(string: "https://example.com/a.png")!)

        #expect(loader.image == nil)
    }
}
