import UIKit

/// A tiny in-memory image cache keyed by URL, backed by `NSCache` (thread-safe,
/// automatically evicts under memory pressure). Warmed ahead of time by
/// `ImagePrefetcher` and read synchronously by `CachedAsyncImage` so a
/// prefetched image renders on first layout instead of fading in after the row
/// scrolls into view. Memory-only by design — the underlying HTTP responses are
/// still disk-cached by `URLSession`/`URLCache`, so this only front-runs the
/// decode, not the download, across launches.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let cache = NSCache<NSURL, UIImage>()

    /// `countLimit` is a soft cap; `NSCache` still evicts early under real
    /// memory pressure. Sized for a few screens' worth of catalog thumbnails.
    init(countLimit: Int = 300) {
        cache.countLimit = countLimit
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func insert(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}
