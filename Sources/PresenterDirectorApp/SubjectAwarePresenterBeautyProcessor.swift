import CoreGraphics
import CoreImage
import Foundation
import PresenterDirector
@preconcurrency import Vision

struct BeautyFaceObservation: Hashable, Sendable {
    let faceRect: CGRect
    let contourPoints: [CGPoint]
    let confidence: Float

    init(faceRect: CGRect, contourPoints: [CGPoint] = [], confidence: Float = 1) {
        self.faceRect = faceRect
        self.contourPoints = contourPoints
        self.confidence = confidence
    }
}

protocol BeautyFaceDetecting {
    func faceObservations(in image: CIImage, targetRect: CGRect) -> [BeautyFaceObservation]
}

struct VisionBeautyFaceDetector: BeautyFaceDetecting {
    func faceObservations(in image: CIImage, targetRect: CGRect) -> [BeautyFaceObservation] {
        guard targetRect.width >= 32, targetRect.height >= 32 else {
            return []
        }

        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(ciImage: image.cropped(to: targetRect), options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        return (request.results ?? [])
            .map { observation in
                let box = observation.boundingBox
                let rect = CGRect(
                    x: targetRect.minX + box.minX * targetRect.width,
                    y: targetRect.minY + box.minY * targetRect.height,
                    width: box.width * targetRect.width,
                    height: box.height * targetRect.height
                )
                let contourPoints = observation.landmarks?.faceContour?.normalizedPoints.map { point in
                    CGPoint(
                        x: rect.minX + CGFloat(point.x) * rect.width,
                        y: rect.minY + CGFloat(point.y) * rect.height
                    )
                } ?? []
                return BeautyFaceObservation(
                    faceRect: rect,
                    contourPoints: contourPoints,
                    confidence: observation.confidence
                )
            }
            .filter { $0.confidence >= 0.35 && $0.faceRect.width >= 24 && $0.faceRect.height >= 24 }
            .sorted { lhs, rhs in
                lhs.faceRect.width * lhs.faceRect.height > rhs.faceRect.width * rhs.faceRect.height
            }
    }
}

struct SubjectAwarePresenterBeautyProcessor {
    private let detector: any BeautyFaceDetecting

    init(detector: any BeautyFaceDetecting = VisionBeautyFaceDetector()) {
        self.detector = detector
    }

    func applyPresenterEffects(
        to image: CIImage,
        effects: PresenterVideoEffects,
        targetRect: CGRect
    ) -> CIImage {
        guard !effects.isDefault else {
            return image
        }

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

        if effects.hasSubjectAwareBeautyAdjustments {
            return applySubjectAwareBeauty(to: output, effects: effects, targetRect: targetRect)
        }

        if effects.beauty > 0 {
            return applyLegacySoftening(to: output, strength: effects.beauty)
        }

        return output
    }

    private func applySubjectAwareBeauty(
        to image: CIImage,
        effects: PresenterVideoEffects,
        targetRect: CGRect
    ) -> CIImage {
        let settings = BeautyRenderSettings(effects: effects)
        guard !settings.isEmpty else {
            return image
        }

        let faces = detector.faceObservations(in: image, targetRect: targetRect)
        guard let face = faces.first else {
            return image
        }
        let mask = faceAndNeckMask(
            face: face,
            targetRect: targetRect,
            feather: 18 + settings.smoothing * 18
        )
        let effectRect = mask.extent.intersection(image.extent)
        guard effectRect.width > 0, effectRect.height > 0 else {
            return image
        }

        let sourceCrop = image.cropped(to: effectRect)
        let beautified = beautifiedSkinImage(from: sourceCrop, settings: settings)
        let opacityMask = mask.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: settings.maskOpacity, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: settings.maskOpacity, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: settings.maskOpacity, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: settings.maskOpacity)
        ])

        return beautified
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: image,
                kCIInputMaskImageKey: opacityMask.cropped(to: effectRect)
            ])
            .cropped(to: image.extent)
    }

    private func beautifiedSkinImage(from image: CIImage, settings: BeautyRenderSettings) -> CIImage {
        var output = image

        if settings.smoothing > 0 || settings.blemishReduction > 0 {
            output = output.applyingFilter("CINoiseReduction", parameters: [
                "inputNoiseLevel": 0.012 + settings.smoothing * 0.034 + settings.blemishReduction * 0.016,
                "inputSharpness": max(0.55, 0.88 - settings.smoothing * 0.18)
            ])
        }

        if settings.blemishReduction > 0 {
            let softened = output
                .clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [
                    kCIInputRadiusKey: 0.35 + settings.blemishReduction * 0.85
                ])
                .cropped(to: output.extent)
            output = softened.applyingFilter("CIBlendWithAlphaMask", parameters: [
                kCIInputBackgroundImageKey: output,
                kCIInputMaskImageKey: CIImage(
                    color: CIColor(
                        red: settings.blemishReduction * 0.16,
                        green: settings.blemishReduction * 0.16,
                        blue: settings.blemishReduction * 0.16,
                        alpha: settings.blemishReduction * 0.16
                    )
                ).cropped(to: output.extent)
            ])
        }

        if settings.brightening > 0 || settings.whitening > 0 {
            output = output.applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputShadowAmount": 0.08 + settings.brightening * 0.24,
                "inputHighlightAmount": 0.97
            ])
            output = output.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: settings.brightening * 0.11 + settings.whitening * 0.035,
                kCIInputContrastKey: 1 + settings.brightening * 0.025,
                kCIInputSaturationKey: 1 - settings.whitening * 0.035 + settings.complexion * 0.025
            ])
        }

        if settings.whitening > 0 || settings.complexion > 0 {
            output = output.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(
                    x: settings.whitening * 0.020 + settings.complexion * 0.028,
                    y: settings.whitening * 0.024 + settings.complexion * 0.014,
                    z: settings.whitening * 0.026,
                    w: 0
                )
            ])
        }

        return output.cropped(to: image.extent)
    }

    private func faceAndNeckMask(face: BeautyFaceObservation, targetRect: CGRect, feather: CGFloat) -> CIImage {
        let faceRect = face.faceRect.intersection(targetRect)
        guard !faceRect.isNull, faceRect.width > 0, faceRect.height > 0 else {
            return CIImage(color: .black).cropped(to: targetRect)
        }

        let faceMaskRect = resolvedFaceMaskRect(face: face, faceRect: faceRect, targetRect: targetRect)
        let neckRect = CGRect(
            x: faceRect.minX + faceRect.width * 0.27,
            y: faceRect.minY - faceRect.height * 0.54,
            width: faceRect.width * 0.46,
            height: faceRect.height * 0.62
        ).intersection(targetRect)

        let faceMask = radialMask(in: faceMaskRect, innerRadius: 0.24, outerRadius: 0.76)
        let neckMask = taperedNeckMask(in: neckRect, faceRect: faceRect)
        return faceMask
            .applyingFilter("CIMaximumCompositing", parameters: [
                kCIInputBackgroundImageKey: neckMask
            ])
            .applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: max(1, feather * 0.08)
            ])
            .cropped(to: faceMaskRect.union(neckRect).intersection(targetRect))
    }

    private func resolvedFaceMaskRect(
        face: BeautyFaceObservation,
        faceRect: CGRect,
        targetRect: CGRect
    ) -> CGRect {
        let baseRect: CGRect
        if face.contourPoints.count >= 4 {
            let points = face.contourPoints.filter { targetRect.contains($0) }
            if let first = points.first {
                var minX = first.x
                var maxX = first.x
                var minY = first.y
                var maxY = first.y
                for point in points.dropFirst() {
                    minX = min(minX, point.x)
                    maxX = max(maxX, point.x)
                    minY = min(minY, point.y)
                    maxY = max(maxY, point.y)
                }
                baseRect = CGRect(
                    x: minX,
                    y: minY,
                    width: max(1, maxX - minX),
                    height: max(1, maxY - minY)
                ).union(CGRect(
                    x: faceRect.minX + faceRect.width * 0.18,
                    y: faceRect.maxY - faceRect.height * 0.10,
                    width: faceRect.width * 0.64,
                    height: faceRect.height * 0.18
                ))
            } else {
                baseRect = faceRect
            }
        } else {
            baseRect = faceRect
        }

        return baseRect
            .insetBy(dx: -faceRect.width * 0.20, dy: -faceRect.height * 0.24)
            .intersection(targetRect)
    }

    private func radialMask(
        in rect: CGRect,
        innerRadius: CGFloat = 0.30,
        outerRadius: CGFloat = 0.74
    ) -> CIImage {
        guard rect.width > 0, rect.height > 0 else {
            return CIImage(color: .black).cropped(to: rect)
        }

        let side = max(1, min(rect.width, rect.height))
        let gradient = CIFilter(
            name: "CIRadialGradient",
            parameters: [
                "inputCenter": CIVector(x: rect.midX, y: rect.midY),
                "inputRadius0": side * innerRadius,
                "inputRadius1": side * outerRadius,
                "inputColor0": CIColor.white,
                "inputColor1": CIColor.black
            ]
        )?.outputImage ?? CIImage(color: .black)

        let ellipseTransform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: rect.width / side, y: rect.height / side)
            .translatedBy(x: -rect.midX, y: -rect.midY)

        return gradient
            .transformed(by: ellipseTransform)
            .cropped(to: rect)
    }

    private func taperedNeckMask(in rect: CGRect, faceRect: CGRect) -> CIImage {
        guard rect.width > 0, rect.height > 0 else {
            return CIImage(color: .black).cropped(to: rect)
        }

        let upperRect = CGRect(
            x: rect.midX - faceRect.width * 0.18,
            y: rect.minY + rect.height * 0.58,
            width: faceRect.width * 0.36,
            height: rect.height * 0.42
        ).intersection(rect)
        let middleRect = CGRect(
            x: rect.midX - faceRect.width * 0.15,
            y: rect.minY + rect.height * 0.30,
            width: faceRect.width * 0.30,
            height: rect.height * 0.55
        ).intersection(rect)
        let lowerRect = CGRect(
            x: rect.midX - faceRect.width * 0.10,
            y: rect.minY + rect.height * 0.04,
            width: faceRect.width * 0.20,
            height: rect.height * 0.44
        ).intersection(rect)

        return radialMask(in: upperRect, innerRadius: 0.18, outerRadius: 0.54)
            .applyingFilter("CIMaximumCompositing", parameters: [
                kCIInputBackgroundImageKey: radialMask(in: middleRect, innerRadius: 0.14, outerRadius: 0.48)
            ])
            .applyingFilter("CIMaximumCompositing", parameters: [
                kCIInputBackgroundImageKey: radialMask(in: lowerRect, innerRadius: 0.10, outerRadius: 0.44)
            ])
            .cropped(to: rect)
    }

    private func applyLegacySoftening(to image: CIImage, strength: Double) -> CIImage {
        let softened = image
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: 1.2 + strength * 2.8
            ])
            .cropped(to: image.extent)
        return softened.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: image,
            kCIInputMaskImageKey: CIImage(color: CIColor(
                red: strength * 0.35,
                green: strength * 0.35,
                blue: strength * 0.35,
                alpha: strength * 0.35
            )).cropped(to: image.extent)
        ])
    }
}

private struct BeautyRenderSettings {
    let smoothing: Double
    let brightening: Double
    let whitening: Double
    let blemishReduction: Double
    let complexion: Double
    let maskOpacity: Double

    init(effects: PresenterVideoEffects) {
        let style = BeautyStyleMultipliers(style: effects.beautyStyle)
        smoothing = Self.clamp01(max(effects.skinSmoothing, effects.beauty * 0.72) * style.smoothing)
        brightening = Self.clamp01(max(effects.skinBrightening, effects.beauty * 0.52) * style.brightening)
        whitening = Self.clamp01(max(effects.skinWhitening, effects.beauty * 0.44) * style.whitening)
        blemishReduction = Self.clamp01(max(effects.blemishReduction, effects.beauty * 0.38) * style.blemishReduction)
        complexion = Self.clamp01(max(effects.complexion, effects.beauty * 0.22) * style.complexion)
        maskOpacity = Self.clamp01(0.58 + max(effects.beauty, max(smoothing, brightening)) * 0.28)
    }

    var isEmpty: Bool {
        smoothing == 0
            && brightening == 0
            && whitening == 0
            && blemishReduction == 0
            && complexion == 0
    }

    private static func clamp01(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

private struct BeautyStyleMultipliers {
    let smoothing: Double
    let brightening: Double
    let whitening: Double
    let blemishReduction: Double
    let complexion: Double

    init(style: PresenterBeautyStyle) {
        switch style {
        case .natural:
            smoothing = 0.92
            brightening = 0.90
            whitening = 0.80
            blemishReduction = 0.82
            complexion = 0.88
        case .clean:
            smoothing = 1.00
            brightening = 0.94
            whitening = 1.08
            blemishReduction = 1.05
            complexion = 0.76
        case .bright:
            smoothing = 0.94
            brightening = 1.16
            whitening = 1.12
            blemishReduction = 0.92
            complexion = 0.84
        case .cameraReady:
            smoothing = 1.08
            brightening = 1.04
            whitening = 0.96
            blemishReduction = 1.00
            complexion = 1.10
        }
    }
}
