@testable import PresenterDirector
@testable import PresenterDirectorApp
import CoreGraphics
import CoreImage
import Foundation
import Testing

@Test func emojiFaceOverlayReplacesDetectedFaceRegionWithoutTouchingBackground() throws {
    let input = CIImage.emojiOverlayTestFrame(size: CGSize(width: 120, height: 120))
    let portrait = MediaPipePortraitFrame(
        timestampMilliseconds: 1,
        faces: [
            MediaPipeFacePrediction(
                confidence: 0.94,
                boundingBox: MediaPipePortraitBoundingBox(x: 0.30, y: 0.25, width: 0.40, height: 0.46),
                landmarks: []
            )
        ]
    )

    let output = EmojiFaceOverlayProcessor().apply(
        to: input,
        portrait: portrait,
        emoji: "😀",
        opacity: 1,
        scale: 1
    )

    let beforeImage = try cgImage(from: input)
    let afterImage = try cgImage(from: output)
    let faceBefore = try #require(pixel(in: beforeImage, x: 60, y: 60))
    let faceAfter = try #require(pixel(in: afterImage, x: 60, y: 60))
    let backgroundBefore = try #require(pixel(in: beforeImage, x: 8, y: 8))
    let backgroundAfter = try #require(pixel(in: afterImage, x: 8, y: 8))

    #expect(colorDistance(faceBefore, faceAfter) > 20)
    #expect(colorDistance(backgroundBefore, backgroundAfter) < 3)
}

@Test func emojiFaceOverlayFallsBackWhenFaceIsMissing() throws {
    let input = CIImage.emojiOverlayTestFrame(size: CGSize(width: 120, height: 120))

    let output = EmojiFaceOverlayProcessor().apply(
        to: input,
        portrait: MediaPipePortraitFrame(timestampMilliseconds: 1),
        emoji: "😀",
        opacity: 1,
        scale: 1
    )

    let beforeImage = try cgImage(from: input)
    let afterImage = try cgImage(from: output)
    let faceBefore = try #require(pixel(in: beforeImage, x: 60, y: 60))
    let faceAfter = try #require(pixel(in: afterImage, x: 60, y: 60))

    #expect(colorDistance(faceBefore, faceAfter) == 0)
}

@Test func emojiFaceOverlayScaleControlsReplacementSize() throws {
    let input = CIImage.emojiOverlayTestFrame(size: CGSize(width: 160, height: 160))
    let portrait = MediaPipePortraitFrame(
        timestampMilliseconds: 1,
        faces: [
            MediaPipeFacePrediction(
                confidence: 0.94,
                boundingBox: MediaPipePortraitBoundingBox(x: 0.34, y: 0.30, width: 0.32, height: 0.36),
                landmarks: []
            )
        ]
    )

    let smallOutput = EmojiFaceOverlayProcessor().apply(
        to: input,
        portrait: portrait,
        emoji: "😎",
        opacity: 1,
        scale: 0.70
    )
    let largeOutput = EmojiFaceOverlayProcessor().apply(
        to: input,
        portrait: portrait,
        emoji: "😎",
        opacity: 1,
        scale: 1.45
    )

    let beforeImage = try cgImage(from: input)
    let smallImage = try cgImage(from: smallOutput)
    let largeImage = try cgImage(from: largeOutput)
    let sampleRect = CGRect(x: 42, y: 52, width: 76, height: 68)
    let smallChanged = changedSampleCount(before: beforeImage, after: smallImage, rect: sampleRect)
    let largeChanged = changedSampleCount(before: beforeImage, after: largeImage, rect: sampleRect)

    #expect(smallChanged > 0)
    #expect(largeChanged > smallChanged)
}

@Test func emojiFaceOverlayUsesSelectedEmojiGlyph() throws {
    let input = CIImage.emojiOverlayTestFrame(size: CGSize(width: 120, height: 120))
    let portrait = MediaPipePortraitFrame(
        timestampMilliseconds: 1,
        faces: [
            MediaPipeFacePrediction(
                confidence: 0.94,
                boundingBox: MediaPipePortraitBoundingBox(x: 0.30, y: 0.25, width: 0.40, height: 0.46),
                landmarks: []
            )
        ]
    )

    let sunglasses = EmojiFaceOverlayProcessor().apply(
        to: input,
        portrait: portrait,
        emoji: "😎",
        opacity: 1,
        scale: 1
    )
    let robot = EmojiFaceOverlayProcessor().apply(
        to: input,
        portrait: portrait,
        emoji: "🤖",
        opacity: 1,
        scale: 1
    )

    let sunglassesImage = try cgImage(from: sunglasses)
    let robotImage = try cgImage(from: robot)
    let sunglassesPixel = try #require(pixel(in: sunglassesImage, x: 60, y: 60))
    let robotPixel = try #require(pixel(in: robotImage, x: 60, y: 60))

    #expect(colorDistance(sunglassesPixel, robotPixel) > 6)
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

private func changedSampleCount(before: CGImage, after: CGImage, rect: CGRect) -> Int {
    let minX = max(0, Int(rect.minX))
    let maxX = min(before.width - 1, Int(rect.maxX))
    let minY = max(0, Int(rect.minY))
    let maxY = min(before.height - 1, Int(rect.maxY))
    var count = 0
    for y in stride(from: minY, through: maxY, by: 4) {
        for x in stride(from: minX, through: maxX, by: 4) {
            guard let beforePixel = pixel(in: before, x: x, y: y),
                  let afterPixel = pixel(in: after, x: x, y: y) else {
                continue
            }
            if colorDistance(beforePixel, afterPixel) > 8 {
                count += 1
            }
        }
    }
    return count
}

private func cgImage(from image: CIImage) throws -> CGImage {
    let context = CIContext()
    return try #require(context.createCGImage(image, from: image.extent))
}

private extension CIImage {
    static func emojiOverlayTestFrame(size: CGSize) -> CIImage {
        let extent = CGRect(origin: .zero, size: size)
        let background = CIImage(color: CIColor(red: 0.08, green: 0.11, blue: 0.15, alpha: 1))
            .cropped(to: extent)
        let face = CIImage(color: CIColor(red: 0.52, green: 0.34, blue: 0.25, alpha: 1))
            .cropped(to: CGRect(x: 36, y: 35, width: 48, height: 55))
        return face.composited(over: background).cropped(to: extent)
    }
}
