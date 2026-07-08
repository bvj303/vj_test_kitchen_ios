import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns arbitrary picked-photo bytes (HEIC, PNG, large JPEG, …) into a small,
/// square-ish JPEG suitable for an avatar. Keeps uploads well under the bucket's
/// size limit and guarantees the stored bytes actually match the `image/jpeg`
/// content type we declare on upload (a full-res HEIC mislabeled as JPEG would
/// fail to render in some clients).
///
/// Implemented with ImageIO (Core Graphics) rather than UIKit/AppKit, so a
/// single code path serves both iOS and macOS with no platform image type.
enum AvatarImageProcessor {
    /// Decodes `data`, scales it down so its longest side is at most
    /// `maxDimension` pixels (never upscales), and re-encodes as JPEG.
    /// Returns nil if the data isn't a decodable image.
    static func normalizedJPEG(
        from data: Data,
        maxDimension: CGFloat = 512,
        quality: CGFloat = 0.8
    ) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let pixelHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue
        else { return nil }

        // Cap the thumbnail's longest side at maxDimension, but never above the
        // source's own longest side (matches the "never upscales" contract).
        let longestSide = max(pixelWidth, pixelHeight)
        let thumbnailMax = min(longestSide, Double(maxDimension))

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, // respect EXIF orientation
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMax,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination,
            thumbnail,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
