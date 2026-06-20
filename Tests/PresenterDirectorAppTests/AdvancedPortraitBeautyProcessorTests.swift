@testable import PresenterDirector
@testable import PresenterDirectorApp
import CoreGraphics
import CoreImage
import Foundation
import Testing

@Test func advancedPortraitBeautyUsesMediaPipeFaceRegionWithoutTouchingBackground() throws {
    let input = CIImage.advancedBeautyTestFrame(size: CGSize(width: 100, height: 100))
    let portrait = MediaPipePortraitFrame(
        timestampMilliseconds: 1,
        faces: [
            MediaPipeFacePrediction(
                confidence: 0.92,
                boundingBox: MediaPipePortraitBoundingBox(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
                landmarks: []
            )
        ]
    )
    let effects = PresenterVideoEffects(
        isSubjectAwareBeautyEnabled: true,
        skinBrightening: 0.55,
        skinWhitening: 0.35,
        complexion: 0.25,
        advancedBeautyEnabled: true,
        faceLandmarkBeautyEnabled: true
    )

    let output = AdvancedPortraitBeautyProcessor().apply(to: input, portrait: portrait, effects: effects)

    let beforeImage = try cgImage(from: input)
    let afterImage = try cgImage(from: output)
    let faceBefore = try #require(pixel(in: beforeImage, x: 50, y: 50))
    let faceAfter = try #require(pixel(in: afterImage, x: 50, y: 50))
    let backgroundBefore = try #require(pixel(in: beforeImage, x: 8, y: 8))
    let backgroundAfter = try #require(pixel(in: afterImage, x: 8, y: 8))

    #expect(faceAfter.red > faceBefore.red + 8)
    #expect(faceAfter.green > faceBefore.green + 6)
    #expect(colorDistance(backgroundBefore, backgroundAfter) < 4)
}

@Test func advancedPortraitBeautyFallsBackWhenNoMediaPipeFaceExists() throws {
    let input = CIImage.advancedBeautyTestFrame(size: CGSize(width: 100, height: 100))
    let effects = PresenterVideoEffects(
        isSubjectAwareBeautyEnabled: true,
        skinBrightening: 0.55,
        advancedBeautyEnabled: true,
        faceLandmarkBeautyEnabled: true
    )

    let output = AdvancedPortraitBeautyProcessor().apply(
        to: input,
        portrait: MediaPipePortraitFrame(timestampMilliseconds: 1),
        effects: effects
    )

    let beforeImage = try cgImage(from: input)
    let afterImage = try cgImage(from: output)
    let faceBefore = try #require(pixel(in: beforeImage, x: 50, y: 50))
    let faceAfter = try #require(pixel(in: afterImage, x: 50, y: 50))

    #expect(colorDistance(faceBefore, faceAfter) == 0)
}

@Test func advancedPortraitBeautyAppliesFaceSlimmingAndEyeEnlargementWarp() throws {
    let input = CIImage.landmarkWarpTestFrame(size: CGSize(width: 120, height: 120))
    let portrait = MediaPipePortraitFrame(
        timestampMilliseconds: 1,
        faces: [
            MediaPipeFacePrediction(
                confidence: 0.92,
                boundingBox: MediaPipePortraitBoundingBox(x: 0.25, y: 0.20, width: 0.50, height: 0.58),
                landmarks: faceMeshLandmarksForWarpTest()
            )
        ]
    )
    let effects = PresenterVideoEffects(
        advancedBeautyEnabled: true,
        faceLandmarkBeautyEnabled: true,
        faceSlimming: 0.75,
        eyeEnlargement: 0.65
    )

    let output = AdvancedPortraitBeautyProcessor().apply(to: input, portrait: portrait, effects: effects)

    let beforeImage = try cgImage(from: input)
    let afterImage = try cgImage(from: output)
    let eyeRegionDistance = regionMaxDistance(
        beforeImage,
        afterImage,
        rect: CGRect(x: 32, y: 60, width: 24, height: 18)
    )
    let leftCheekBefore = try #require(pixel(in: beforeImage, x: 32, y: 50))
    let leftCheekAfter = try #require(pixel(in: afterImage, x: 32, y: 50))
    let backgroundBefore = try #require(pixel(in: beforeImage, x: 8, y: 8))
    let backgroundAfter = try #require(pixel(in: afterImage, x: 8, y: 8))

    #expect(eyeRegionDistance > 18)
    #expect(colorDistance(leftCheekBefore, leftCheekAfter) > 8)
    #expect(colorDistance(backgroundBefore, backgroundAfter) < 4)
}

private func faceMeshLandmarksForWarpTest() -> [MediaPipeNormalizedLandmark] {
    var landmarks = Array(repeating: MediaPipeNormalizedLandmark(x: 0.5, y: 0.5, z: 0), count: 455)
    for index in [33, 133, 159, 145] {
        landmarks[index] = MediaPipeNormalizedLandmark(x: 0.36, y: 0.43, z: 0)
    }
    for index in [263, 362, 386, 374] {
        landmarks[index] = MediaPipeNormalizedLandmark(x: 0.64, y: 0.43, z: 0)
    }
    landmarks[234] = MediaPipeNormalizedLandmark(x: 0.31, y: 0.58, z: 0)
    landmarks[454] = MediaPipeNormalizedLandmark(x: 0.69, y: 0.58, z: 0)
    return landmarks
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

private func regionMaxDistance(_ lhs: CGImage, _ rhs: CGImage, rect: CGRect) -> Int {
    let minX = max(0, Int(rect.minX))
    let maxX = min(lhs.width - 1, Int(rect.maxX))
    let minY = max(0, Int(rect.minY))
    let maxY = min(lhs.height - 1, Int(rect.maxY))
    var maximum = 0
    for y in minY...maxY {
        for x in minX...maxX {
            guard let before = pixel(in: lhs, x: x, y: y),
                  let after = pixel(in: rhs, x: x, y: y) else {
                continue
            }
            maximum = max(maximum, colorDistance(before, after))
        }
    }
    return maximum
}

private func cgImage(from image: CIImage) throws -> CGImage {
    let context = CIContext()
    return try #require(context.createCGImage(image, from: image.extent))
}

private extension CIImage {
    static func advancedBeautyTestFrame(size: CGSize) -> CIImage {
        let extent = CGRect(origin: .zero, size: size)
        let background = CIImage(color: CIColor(red: 0.07, green: 0.10, blue: 0.13, alpha: 1))
            .cropped(to: extent)
        let face = CIImage(color: CIColor(red: 0.48, green: 0.31, blue: 0.24, alpha: 1))
            .cropped(to: CGRect(x: 25, y: 25, width: 50, height: 50))
        return face.composited(over: background).cropped(to: extent)
    }

    static func landmarkWarpTestFrame(size: CGSize) -> CIImage {
        let extent = CGRect(origin: .zero, size: size)
        let background = CIImage(color: CIColor(red: 0.06, green: 0.09, blue: 0.13, alpha: 1))
            .cropped(to: extent)
        let face = CIImage(color: CIColor(red: 0.54, green: 0.35, blue: 0.27, alpha: 1))
            .cropped(to: CGRect(x: 30, y: 28, width: 60, height: 70))
        let leftEye = CIImage(color: CIColor(red: 0.02, green: 0.03, blue: 0.04, alpha: 1))
            .cropped(to: CGRect(x: 38, y: 63, width: 10, height: 8))
        let rightEye = CIImage(color: CIColor(red: 0.02, green: 0.03, blue: 0.04, alpha: 1))
            .cropped(to: CGRect(x: 72, y: 63, width: 10, height: 8))
        return rightEye
            .composited(over: leftEye)
            .composited(over: face)
            .composited(over: background)
            .cropped(to: extent)
    }
}
