@testable import WonderShow
@testable import WonderShowApp
import CoreGraphics
import CoreImage
import Foundation
import Testing

@Test func portraitBackgroundProcessorReplacesBackgroundUsingSegmentationMask() throws {
    let input = CIImage.portraitBackgroundTestFrame(size: CGSize(width: 4, height: 4))
    let mask = MediaPipePortraitSegmentationMask(
        width: 2,
        height: 2,
        maskData: Data([
            0, 255,
            0, 255
        ])
    )
    let processor = PortraitBackgroundProcessor()

    let output = processor.apply(
        to: input,
        segmentation: mask,
        effects: PresenterVideoEffects(
            portraitSegmentationEnabled: true,
            backgroundEffect: .replacement(colorHex: "#203040", strength: 1)
        )
    )

    let image = try cgImage(from: output)
    let leftPixel = try #require(pixel(in: image, x: 0, y: 1))
    let rightPixel = try #require(pixel(in: image, x: 3, y: 1))

    #expect(abs(Int(leftPixel.red) - 32) < 4)
    #expect(abs(Int(leftPixel.green) - 48) < 4)
    #expect(abs(Int(leftPixel.blue) - 64) < 4)
    #expect(rightPixel.red > 190)
    #expect(rightPixel.green < 80)
    #expect(rightPixel.blue < 80)
}

@Test func portraitBackgroundProcessorLeavesFrameUnchangedWithoutSegmentation() throws {
    let input = CIImage.portraitBackgroundTestFrame(size: CGSize(width: 4, height: 4))
    let processor = PortraitBackgroundProcessor()

    let output = processor.apply(
        to: input,
        segmentation: nil,
        effects: PresenterVideoEffects(
            portraitSegmentationEnabled: true,
            backgroundEffect: .replacement(colorHex: "#203040", strength: 1)
        )
    )

    let inputImage = try cgImage(from: input)
    let outputImage = try cgImage(from: output)
    let before = try #require(pixel(in: inputImage, x: 0, y: 1))
    let after = try #require(pixel(in: outputImage, x: 0, y: 1))

    #expect(colorDistance(before, after) == 0)
}

private struct Pixel {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8
}

private func pixel(in image: CGImage, x: Int, y: Int) -> Pixel? {
    guard x >= 0, y >= 0, x < image.width, y < image.height else {
        return nil
    }
    let bytesPerPixel = 4
    let bytesPerRow = image.width * bytesPerPixel
    var data = [UInt8](repeating: 0, count: image.height * bytesPerRow)
    guard let context = CGContext(
        data: &data,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let offset = y * bytesPerRow + x * bytesPerPixel
    return Pixel(
        red: data[offset],
        green: data[offset + 1],
        blue: data[offset + 2],
        alpha: data[offset + 3]
    )
}

private func colorDistance(_ lhs: Pixel, _ rhs: Pixel) -> Int {
    abs(Int(lhs.red) - Int(rhs.red))
        + abs(Int(lhs.green) - Int(rhs.green))
        + abs(Int(lhs.blue) - Int(rhs.blue))
}

private func cgImage(from image: CIImage) throws -> CGImage {
    let context = CIContext()
    return try #require(context.createCGImage(image, from: image.extent))
}

private extension CIImage {
    static func portraitBackgroundTestFrame(size: CGSize) -> CIImage {
        let extent = CGRect(origin: .zero, size: size)
        let background = CIImage(color: CIColor(red: 0.05, green: 0.10, blue: 0.15, alpha: 1))
            .cropped(to: extent)
        let subject = CIImage(color: CIColor(red: 0.82, green: 0.22, blue: 0.18, alpha: 1))
            .cropped(to: CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height))
        return subject.composited(over: background).cropped(to: extent)
    }
}
