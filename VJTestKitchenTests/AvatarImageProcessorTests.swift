import Foundation
import Testing
@testable import VJTestKitchen

@MainActor
struct AvatarImageProcessorTests {
    /// A solid-color PNG of the given pixel size — a stand-in for arbitrary
    /// picked-photo data. Cross-platform (see `PlatformTestImage`).
    private func makePNG(width: Int, height: Int) -> Data {
        PlatformTestImage.solidPNG(width: width, height: height)
    }

    @Test func downscalesLargeImageSoLongestSideFitsMaxDimension() throws {
        let input = makePNG(width: 2000, height: 1000)

        let output = try #require(AvatarImageProcessor.normalizedJPEG(from: input, maxDimension: 512))
        let size = try #require(PlatformTestImage.pixelSize(of: output))

        #expect(size.width == 512)
        #expect(size.height == 256)
    }

    @Test func doesNotUpscaleSmallImage() throws {
        let input = makePNG(width: 100, height: 80)

        let output = try #require(AvatarImageProcessor.normalizedJPEG(from: input, maxDimension: 512))
        let size = try #require(PlatformTestImage.pixelSize(of: output))

        #expect(size.width == 100)
        #expect(size.height == 80)
    }

    @Test func producesDecodableJPEGSmallerThanTheSourcePNG() throws {
        let input = makePNG(width: 1500, height: 1500)

        let output = try #require(AvatarImageProcessor.normalizedJPEG(from: input))

        #expect(PlatformTestImage.pixelSize(of: output) != nil)
        #expect(output.count < input.count)
    }

    @Test func returnsNilForNonImageData() {
        let notAnImage = Data("this is not an image".utf8)

        #expect(AvatarImageProcessor.normalizedJPEG(from: notAnImage) == nil)
    }
}
