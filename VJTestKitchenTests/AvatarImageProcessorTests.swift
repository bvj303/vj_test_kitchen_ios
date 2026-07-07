import Foundation
import UIKit
import Testing
@testable import VJTestKitchen

@MainActor
struct AvatarImageProcessorTests {
    /// Renders a solid-color image of the given point size at scale 1 and
    /// returns its PNG bytes — a stand-in for arbitrary picked-photo data.
    private func makePNG(width: CGFloat, height: CGFloat) -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let image = renderer.image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return image.pngData()!
    }

    @Test func downscalesLargeImageSoLongestSideFitsMaxDimension() throws {
        let input = makePNG(width: 2000, height: 1000)

        let output = try #require(AvatarImageProcessor.normalizedJPEG(from: input, maxDimension: 512))
        let resultImage = try #require(UIImage(data: output))

        // UIImage.size for a scale-1 JPEG is in pixels here.
        #expect(resultImage.size.width == 512)
        #expect(resultImage.size.height == 256)
    }

    @Test func doesNotUpscaleSmallImage() throws {
        let input = makePNG(width: 100, height: 80)

        let output = try #require(AvatarImageProcessor.normalizedJPEG(from: input, maxDimension: 512))
        let resultImage = try #require(UIImage(data: output))

        #expect(resultImage.size.width == 100)
        #expect(resultImage.size.height == 80)
    }

    @Test func producesDecodableJPEGSmallerThanTheSourcePNG() throws {
        let input = makePNG(width: 1500, height: 1500)

        let output = try #require(AvatarImageProcessor.normalizedJPEG(from: input))

        #expect(UIImage(data: output) != nil)
        #expect(output.count < input.count)
    }

    @Test func returnsNilForNonImageData() {
        let notAnImage = Data("this is not an image".utf8)

        #expect(AvatarImageProcessor.normalizedJPEG(from: notAnImage) == nil)
    }
}
