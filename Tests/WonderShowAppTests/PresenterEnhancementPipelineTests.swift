@testable import WonderShow
@testable import WonderShowApp
import CoreGraphics
import CoreImage
import Foundation
import Testing

@Test func presenterEnhancementPipelineFallbackAppliesEmojiWithoutMediaPipePortrait() throws {
    let input = CIImage.pipelineFallbackTestFrame(size: CGSize(width: 160, height: 160))
    let effects = PresenterVideoEffects(
        emojiFaceReplacementEnabled: true,
        emojiFaceReplacementSymbol: "🤖",
        emojiFaceReplacementStrength: 1,
        emojiFaceReplacementScale: 1.25
    )

    let output = PresenterEnhancementPipeline().apply(
        to: input,
        effects: effects,
        targetRect: input.extent,
        fallbackPortrait: true
    )

    let beforeImage = try cgImage(from: input)
    let afterImage = try cgImage(from: output)
    let centerBefore = try #require(pixel(in: beforeImage, x: 80, y: 80))
    let centerAfter = try #require(pixel(in: afterImage, x: 80, y: 80))

    #expect(colorDistance(centerBefore, centerAfter) > 10)
}

@Test func presenterEnhancementPipelineLivePreviewSkipsEmojiFallbackWithoutPortrait() throws {
    let input = CIImage.pipelineFallbackTestFrame(size: CGSize(width: 160, height: 160))
    let effects = PresenterVideoEffects(
        emojiFaceReplacementEnabled: true,
        emojiFaceReplacementSymbol: "🤖",
        emojiFaceReplacementStrength: 1,
        emojiFaceReplacementScale: 1.25
    )

    let output = PresenterEnhancementPipeline().apply(
        to: input,
        effects: effects,
        targetRect: input.extent,
        fallbackPortrait: false,
        allowSubjectAwareBeautyDetection: false
    )

    let beforeImage = try cgImage(from: input)
    let afterImage = try cgImage(from: output)
    let centerBefore = try #require(pixel(in: beforeImage, x: 80, y: 80))
    let centerAfter = try #require(pixel(in: afterImage, x: 80, y: 80))

    #expect(colorDistance(centerBefore, centerAfter) == 0)
}

@Test func presenterEnhancementPipelineRespectsEmojiDisabledEvenWithPortrait() throws {
    let input = CIImage.pipelineFallbackTestFrame(size: CGSize(width: 160, height: 160))
    let portrait = MediaPipePortraitFrame(
        timestampMilliseconds: 1,
        faces: [
            MediaPipeFacePrediction(
                confidence: 0.94,
                boundingBox: MediaPipePortraitBoundingBox(x: 0.34, y: 0.25, width: 0.32, height: 0.42),
                landmarks: []
            )
        ]
    )
    let effects = PresenterVideoEffects(
        emojiFaceReplacementEnabled: false,
        emojiFaceReplacementSymbol: "🤖",
        emojiFaceReplacementStrength: 0,
        emojiFaceReplacementScale: 1.45
    )

    let output = PresenterEnhancementPipeline().apply(
        to: input,
        effects: effects,
        targetRect: input.extent,
        portrait: portrait,
        fallbackPortrait: false,
        allowSubjectAwareBeautyDetection: false
    )

    let beforeImage = try cgImage(from: input)
    let afterImage = try cgImage(from: output)
    let centerBefore = try #require(pixel(in: beforeImage, x: 80, y: 80))
    let centerAfter = try #require(pixel(in: afterImage, x: 80, y: 80))

    #expect(colorDistance(centerBefore, centerAfter) == 0)
}

@Test func presenterEnhancementPipelineLivePreviewSkipsSubjectAwareDetector() {
    let detector = CountingBeautyFaceDetector()
    let input = CIImage.pipelineFallbackTestFrame(size: CGSize(width: 160, height: 160))
    let effects = PresenterVideoEffects(
        isSubjectAwareBeautyEnabled: true,
        skinSmoothing: 0.9,
        skinBrightening: 0.7
    )

    _ = PresenterEnhancementPipeline(
        subjectBeautyProcessor: SubjectAwarePresenterBeautyProcessor(detector: detector)
    ).apply(
        to: input,
        effects: effects,
        targetRect: input.extent,
        fallbackPortrait: false,
        allowSubjectAwareBeautyDetection: false
    )

    #expect(!detector.didRun)
}

@Test func presenterEnhancementPipelineFallbackBackgroundKeepsCornerOutsideSubject() throws {
    let input = CIImage.pipelineFallbackTestFrame(size: CGSize(width: 160, height: 160))
    let effects = PresenterVideoEffects(
        portraitSegmentationEnabled: true,
        backgroundEffect: .replacement(colorHex: "#203040", strength: 1),
        backgroundBlur: 0.6
    )

    let output = PresenterEnhancementPipeline().apply(
        to: input,
        effects: effects,
        targetRect: input.extent,
        fallbackPortrait: true
    )

    let afterImage = try cgImage(from: output)
    let topCorner = try #require(pixel(in: afterImage, x: 12, y: 146))
    let subjectCenter = try #require(pixel(in: afterImage, x: 80, y: 72))

    #expect(abs(Int(topCorner.red) - 32) < 8)
    #expect(abs(Int(topCorner.green) - 48) < 8)
    #expect(abs(Int(topCorner.blue) - 64) < 8)
    #expect(subjectCenter.red > 120)
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

private final class CountingBeautyFaceDetector: BeautyFaceDetecting {
    var didRun = false

    func faceObservations(in image: CIImage, targetRect: CGRect) -> [BeautyFaceObservation] {
        didRun = true
        return []
    }
}

private extension CIImage {
    static func pipelineFallbackTestFrame(size: CGSize) -> CIImage {
        let extent = CGRect(origin: .zero, size: size)
        let background = CIImage(color: CIColor(red: 0.05, green: 0.08, blue: 0.11, alpha: 1))
            .cropped(to: extent)
        let torso = CIImage(color: CIColor(red: 0.72, green: 0.28, blue: 0.20, alpha: 1))
            .cropped(to: CGRect(x: 50, y: 0, width: 60, height: 82))
        let face = CIImage(color: CIColor(red: 0.56, green: 0.36, blue: 0.27, alpha: 1))
            .cropped(to: CGRect(x: 54, y: 58, width: 52, height: 66))
        return face
            .composited(over: torso)
            .composited(over: background)
            .cropped(to: extent)
    }
}
