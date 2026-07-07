import Foundation
import UIKit
import Testing
@testable import VJTestKitchen

/// A 1x1 opaque image, enough to exercise store/retrieve without any real
/// image assets.
func makeTestImage() -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { context in
        UIColor.red.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}

@MainActor
struct ImageCacheTests {
    @Test func storesAndRetrievesByURL() {
        let cache = ImageCache()
        let url = URL(string: "https://example.com/a.jpg")!
        let image = makeTestImage()

        cache.insert(image, for: url)

        #expect(cache.image(for: url) === image)
    }

    @Test func missReturnsNil() {
        let cache = ImageCache()
        #expect(cache.image(for: URL(string: "https://example.com/missing.jpg")!) == nil)
    }

    @Test func distinctURLsDoNotCollide() {
        let cache = ImageCache()
        let a = URL(string: "https://example.com/a.jpg")!
        let b = URL(string: "https://example.com/b.jpg")!
        let imageA = makeTestImage()
        let imageB = makeTestImage()

        cache.insert(imageA, for: a)
        cache.insert(imageB, for: b)

        #expect(cache.image(for: a) === imageA)
        #expect(cache.image(for: b) === imageB)
    }
}
