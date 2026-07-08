import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation
@testable import VJTestKitchen

/// Cross-platform test-image helpers built on Core Graphics / ImageIO (no
/// UIKit/AppKit), so the image-touching test files compile unchanged for both
/// the iOS and macOS test targets.
enum PlatformTestImage {
    /// A solid opaque CGImage of the given pixel size.
    static func solidCGImage(width: Int, height: Int) -> CGImage {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.2, green: 0.6, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// Solid opaque PNG bytes of the given pixel size — a stand-in for arbitrary
    /// picked-photo data.
    static func solidPNG(width: Int, height: Int) -> Data {
        encode(solidCGImage(width: width, height: height), as: UTType.png)
    }

    /// Pixel dimensions of encoded image data, read via ImageIO — robust across
    /// platforms regardless of the decoded image's DPI/point-size quirks.
    static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        else { return nil }
        return (width, height)
    }

    /// A platform image instance for cache identity/storage tests.
    static func platformImage(width: Int = 1, height: Int = 1) -> PlatformImage {
        let cg = solidCGImage(width: width, height: height)
        #if canImport(UIKit)
        return PlatformImage(cgImage: cg)
        #else
        return PlatformImage(cgImage: cg, size: CGSize(width: width, height: height))
        #endif
    }

    private static func encode(_ image: CGImage, as type: UTType) -> Data {
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }
}
