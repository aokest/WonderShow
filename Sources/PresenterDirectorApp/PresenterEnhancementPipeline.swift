@preconcurrency import Vision
import CoreImage
import Foundation
import PresenterDirector

struct PresenterEnhancementPipeline {
    private let subjectBeautyProcessor: SubjectAwarePresenterBeautyProcessor
    private let backgroundProcessor = PortraitBackgroundProcessor()
    private let advancedBeautyProcessor = AdvancedPortraitBeautyProcessor()
    private let emojiProcessor = EmojiFaceOverlayProcessor()

    init(subjectBeautyProcessor: SubjectAwarePresenterBeautyProcessor = SubjectAwarePresenterBeautyProcessor()) {
        self.subjectBeautyProcessor = subjectBeautyProcessor
    }

    func apply(
        to image: CIImage,
        effects: PresenterVideoEffects,
        targetRect: CGRect,
        portrait: MediaPipePortraitFrame? = nil,
        segmentation: MediaPipePortraitSegmentationMask? = nil,
        fallbackPortrait: Bool = false,
        allowSubjectAwareBeautyDetection: Bool = true
    ) -> CIImage {
        guard !effects.isDefault else {
            return image
        }
        let shouldResolvePortrait = Self.needsPortraitFallback(for: effects)
        let resolvedPortrait = portrait
            ?? (fallbackPortrait && shouldResolvePortrait ? Self.visionPortraitFrame(in: image, targetRect: targetRect) : nil)
            ?? (fallbackPortrait && shouldResolvePortrait ? Self.estimatedPortraitFrame(in: image.extent, targetRect: targetRect, effects: effects) : nil)
        let resolvedSegmentation = segmentation
            ?? resolvedPortrait?.segmentation
            ?? (fallbackPortrait && shouldResolvePortrait ? Self.estimatedSegmentation(for: resolvedPortrait, extent: image.extent) : nil)
        let portraitFrame = resolvedPortrait ?? MediaPipePortraitFrame(timestampMilliseconds: 0)

        let backgroundImage = backgroundProcessor.apply(
            to: image,
            segmentation: resolvedSegmentation,
            effects: effects
        )
        let advancedImage = advancedBeautyProcessor.apply(
            to: backgroundImage,
            portrait: portraitFrame,
            effects: effects
        )
        let emojiImage = effects.emojiFaceReplacementEnabled
            ? emojiProcessor.apply(
                to: advancedImage,
                portrait: portraitFrame,
                emoji: effects.emojiFaceReplacementSymbol,
                opacity: 1,
                scale: effects.emojiFaceReplacementScale
            )
            : advancedImage
        guard allowSubjectAwareBeautyDetection else {
            return Self.applyBaseFrameAdjustments(
                to: emojiImage,
                effects: effects,
                targetRect: targetRect
            )
        }
        return subjectBeautyProcessor.applyPresenterEffects(
            to: emojiImage,
            effects: effects,
            targetRect: targetRect
        )
    }

    private static func applyBaseFrameAdjustments(
        to image: CIImage,
        effects: PresenterVideoEffects,
        targetRect: CGRect
    ) -> CIImage {
        var output = image
        if effects.isMirrored {
            output = output.transformed(
                by: CGAffineTransform(translationX: targetRect.midX, y: 0)
                    .scaledBy(x: -1, y: 1)
                    .translatedBy(x: -targetRect.midX, y: 0)
            )
        }

        if effects.brightness != 0 || effects.contrast != 1 {
            output = output.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: effects.brightness,
                kCIInputContrastKey: effects.contrast
            ])
        }

        return output
    }

    private static func visionPortraitFrame(in image: CIImage, targetRect: CGRect) -> MediaPipePortraitFrame? {
        let detector = VisionBeautyFaceDetector()
        guard let observation = detector.faceObservations(in: image, targetRect: targetRect).first else {
            return nil
        }
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else {
            return nil
        }
        let faceRect = observation.faceRect.intersection(extent)
        guard faceRect.width > 1, faceRect.height > 1 else {
            return nil
        }
        let landmarks = observation.contourPoints.map { point in
            MediaPipeNormalizedLandmark(
                x: Double((point.x - extent.minX) / extent.width),
                y: Double(1 - ((point.y - extent.minY) / extent.height)),
                z: 0
            )
        }
        return MediaPipePortraitFrame(
            timestampMilliseconds: 0,
            faces: [
                MediaPipeFacePrediction(
                    confidence: Double(observation.confidence),
                    boundingBox: MediaPipePortraitBoundingBox(
                        x: Double((faceRect.minX - extent.minX) / extent.width),
                        y: Double(1 - ((faceRect.maxY - extent.minY) / extent.height)),
                        width: Double(faceRect.width / extent.width),
                        height: Double(faceRect.height / extent.height)
                    ),
                    landmarks: landmarks
                )
            ]
        )
    }

    private static func estimatedPortraitFrame(
        in extent: CGRect,
        targetRect: CGRect,
        effects: PresenterVideoEffects
    ) -> MediaPipePortraitFrame? {
        guard needsPortraitFallback(for: effects), extent.width > 0, extent.height > 0 else {
            return nil
        }
        let safeTarget = targetRect.intersection(extent)
        guard safeTarget.width > 1, safeTarget.height > 1 else {
            return nil
        }
        let faceWidth = safeTarget.width * 0.30
        let faceHeight = safeTarget.height * 0.42
        let faceRect = CGRect(
            x: safeTarget.midX - faceWidth / 2,
            y: safeTarget.midY - faceHeight * 0.30,
            width: faceWidth,
            height: faceHeight
        ).intersection(extent)
        guard faceRect.width > 1, faceRect.height > 1 else {
            return nil
        }
        let leftEye = CGPoint(x: faceRect.minX + faceRect.width * 0.34, y: faceRect.minY + faceRect.height * 0.62)
        let rightEye = CGPoint(x: faceRect.minX + faceRect.width * 0.66, y: faceRect.minY + faceRect.height * 0.62)
        let leftCheek = CGPoint(x: faceRect.minX + faceRect.width * 0.17, y: faceRect.minY + faceRect.height * 0.44)
        let rightCheek = CGPoint(x: faceRect.minX + faceRect.width * 0.83, y: faceRect.minY + faceRect.height * 0.44)
        var landmarks = Array(repeating: normalizedLandmark(from: CGPoint(x: faceRect.midX, y: faceRect.midY), in: extent), count: 455)
        for index in [33, 133, 159, 145] {
            landmarks[index] = normalizedLandmark(from: leftEye, in: extent)
        }
        for index in [263, 362, 386, 374] {
            landmarks[index] = normalizedLandmark(from: rightEye, in: extent)
        }
        landmarks[234] = normalizedLandmark(from: leftCheek, in: extent)
        landmarks[454] = normalizedLandmark(from: rightCheek, in: extent)
        return MediaPipePortraitFrame(
            timestampMilliseconds: 0,
            faces: [
                MediaPipeFacePrediction(
                    confidence: 0.40,
                    boundingBox: MediaPipePortraitBoundingBox(
                        x: Double((faceRect.minX - extent.minX) / extent.width),
                        y: Double(1 - ((faceRect.maxY - extent.minY) / extent.height)),
                        width: Double(faceRect.width / extent.width),
                        height: Double(faceRect.height / extent.height)
                    ),
                    landmarks: landmarks
                )
            ]
        )
    }

    private static func needsPortraitFallback(for effects: PresenterVideoEffects) -> Bool {
        effects.advancedBeautyEnabled
            || effects.faceLandmarkBeautyEnabled
            || effects.portraitSegmentationEnabled
            || effects.emojiFaceReplacementEnabled
            || effects.backgroundBlur > 0
            || effects.backgroundEffect != .none
    }

    private static func normalizedLandmark(from point: CGPoint, in extent: CGRect) -> MediaPipeNormalizedLandmark {
        MediaPipeNormalizedLandmark(
            x: Double((point.x - extent.minX) / extent.width),
            y: Double(1 - ((point.y - extent.minY) / extent.height)),
            z: 0
        )
    }

    private static func estimatedSegmentation(
        for portrait: MediaPipePortraitFrame?,
        extent: CGRect
    ) -> MediaPipePortraitSegmentationMask? {
        guard let face = portrait?.faces.max(by: { lhs, rhs in
            lhs.boundingBox.width * lhs.boundingBox.height < rhs.boundingBox.width * rhs.boundingBox.height
        }) else {
            return nil
        }
        let width = 96
        let height = max(1, Int(Double(width) * Double(extent.height / max(1, extent.width))))
        let faceCenterX = face.boundingBox.x + face.boundingBox.width / 2
        let faceCenterY = face.boundingBox.y + face.boundingBox.height / 2
        let faceHeight = max(0.06, face.boundingBox.height)
        let faceWidth = max(0.05, face.boundingBox.width)
        let headCenterY = max(0.04, faceCenterY - faceHeight * 0.44)
        let upperBodyCenterY = min(0.94, faceCenterY + faceHeight * 0.78)
        let shoulderCenterY = min(0.92, faceCenterY + faceHeight * 0.56)
        let headWidth = min(0.62, max(0.20, faceWidth * 1.32))
        let headHeight = min(0.52, max(0.22, faceHeight * 1.30))
        let torsoWidth = min(0.92, max(0.32, faceWidth * 2.40))
        let torsoHeight = min(0.98, max(0.44, faceHeight * 2.55))
        let shoulderWidth = min(0.98, max(0.42, faceWidth * 2.85))
        let shoulderHeight = min(0.66, max(0.16, faceHeight * 0.95))
        var data = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let nx = (Double(x) + 0.5) / Double(width)
                let nyTop = (Double(y) + 0.5) / Double(height)
                let head = softEllipseAlpha(
                    x: nx,
                    y: nyTop,
                    centerX: faceCenterX,
                    centerY: headCenterY,
                    width: headWidth,
                    height: headHeight
                )
                let torso = softEllipseAlpha(
                    x: nx,
                    y: nyTop,
                    centerX: faceCenterX,
                    centerY: upperBodyCenterY,
                    width: torsoWidth,
                    height: torsoHeight
                )
                let shoulders = softEllipseAlpha(
                    x: nx,
                    y: nyTop,
                    centerX: faceCenterX,
                    centerY: shoulderCenterY,
                    width: shoulderWidth,
                    height: shoulderHeight
                )
                let alpha = max(head, max(torso * 0.92, shoulders * 0.98))
                data[y * width + x] = UInt8((alpha * 255).rounded())
            }
        }
        return MediaPipePortraitSegmentationMask(width: width, height: height, maskData: Data(data))
    }

    private static func softEllipseAlpha(
        x: Double,
        y: Double,
        centerX: Double,
        centerY: Double,
        width: Double,
        height: Double
    ) -> Double {
        guard width > 0, height > 0 else {
            return 0
        }
        let dx = (x - centerX) / max(0.001, width / 2)
        let dy = (y - centerY) / max(0.001, height / 2)
        let distance = dx * dx + dy * dy
        return max(0, min(1, (1.10 - distance) / 0.28))
    }
}
