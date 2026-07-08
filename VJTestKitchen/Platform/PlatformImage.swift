import SwiftUI

#if canImport(UIKit)
import UIKit
/// The platform's concrete bitmap image type (`UIImage` on iOS, `NSImage` on
/// macOS). Both expose `init?(data:)`, which is all the cache/prefetch path uses.
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

extension Image {
    /// Cross-platform bridge from a decoded `PlatformImage` to a SwiftUI `Image`.
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #elseif canImport(AppKit)
        self.init(nsImage: platformImage)
        #endif
    }
}
