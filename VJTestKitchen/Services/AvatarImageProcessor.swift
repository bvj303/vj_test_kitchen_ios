import UIKit

/// Turns arbitrary picked-photo bytes (HEIC, PNG, large JPEG, …) into a small,
/// square-ish JPEG suitable for an avatar. Keeps uploads well under the bucket's
/// size limit and guarantees the stored bytes actually match the `image/jpeg`
/// content type we declare on upload (a full-res HEIC mislabeled as JPEG would
/// fail to render in some clients).
enum AvatarImageProcessor {
    /// Decodes `data`, scales it down so its longest side is at most
    /// `maxDimension` points (never upscales), and re-encodes as JPEG.
    /// Returns nil if the data isn't a decodable image.
    static func normalizedJPEG(
        from data: Data,
        maxDimension: CGFloat = 512,
        quality: CGFloat = 0.8
    ) -> Data? {
        guard let image = UIImage(data: data) else { return nil }

        let longestSide = max(image.size.width, image.size.height)
        let scale = longestSide > maxDimension ? maxDimension / longestSide : 1
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1 // targetSize is already in pixels; don't multiply by screen scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return resized.jpegData(compressionQuality: quality)
    }
}
