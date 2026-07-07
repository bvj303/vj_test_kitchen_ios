import UIKit

/// In-memory cache of *decoded* images, keyed by URL, shared across every
/// `RemoteImage` in the app.
///
/// This is the piece `AsyncImage` lacks: when a list row scrolls off-screen and
/// back on, `AsyncImage` re-fetches and re-decodes from scratch (the flicker /
/// "slow to load" the recipe list showed). Holding the decoded `UIImage` here
/// means a re-appearing row paints instantly with no network round-trip. Disk
/// persistence across launches is handled separately by the process-wide
/// `URLCache` (configured in `VJTestKitchenApp`); this layer is the fast,
/// in-memory tier on top of it.
final class ImageCache: @unchecked Sendable {
    /// App-wide shared instance used by `RemoteImage` by default; tests inject
    /// their own instance to stay isolated.
    static let shared = ImageCache()

    private let cache = NSCache<NSURL, UIImage>()

    init(countLimit: Int = 200) {
        cache.countLimit = countLimit
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func insert(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}
