import CoreGraphics
import CoreImage
import PresenterDirector

struct AdvancedPortraitBeautyProcessor {
    func apply(
        to image: CIImage,
        portrait: MediaPipePortraitFrame,
        effects: PresenterVideoEffects
    ) -> CIImage {
        guard effects.advancedBeautyEnabled || effects.faceLandmarkBeautyEnabled else {
            return image
        }
        guard let face = portrait.faces.max(by: { lhs, rhs in
            lhs.boundingBox.width * lhs.boundingBox.height < rhs.boundingBox.width * rhs.boundingBox.height
        }) else {
            return image
        }

        let faceRect = rect(from: face.boundingBox, in: image.extent)
        guard faceRect.width > 0, faceRect.height > 0 else {
            return image
        }

        let maskRect = faceRect
            .insetBy(dx: -faceRect.width * 0.12, dy: -faceRect.height * 0.16)
            .intersection(image.extent)
        let mask = radialMask(in: maskRect)
        let warped = landmarkWarpedImage(image, face: face, faceRect: faceRect, effects: effects)
        let beautified = beautifiedFaceImage(warped.cropped(to: maskRect), effects: effects)
        return beautified
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: image,
                kCIInputMaskImageKey: mask
            ])
            .cropped(to: image.extent)
    }

    private func landmarkWarpedImage(
        _ image: CIImage,
        face: MediaPipeFacePrediction,
        faceRect: CGRect,
        effects: PresenterVideoEffects
    ) -> CIImage {
        guard effects.faceLandmarkBeautyEnabled else {
            return image
        }

        var output = image
        if effects.faceSlimming > 0 {
            let leftCheek = landmarkPoint(at: 234, fallback: CGPoint(x: faceRect.minX + faceRect.width * 0.16, y: faceRect.midY), face: face, in: image.extent)
            let rightCheek = landmarkPoint(at: 454, fallback: CGPoint(x: faceRect.maxX - faceRect.width * 0.16, y: faceRect.midY), face: face, in: image.extent)
            let radius = max(faceRect.width, faceRect.height) * (0.30 + CGFloat(effects.faceSlimming) * 0.10)
            let scale = CGFloat(-0.12 - effects.faceSlimming * 0.22)
            output = pinch(output, center: leftCheek, radius: radius, scale: scale)
            output = pinch(output, center: rightCheek, radius: radius, scale: scale)
        }

        if effects.eyeEnlargement > 0 {
            let leftEye = averageLandmarkPoint(
                indices: [33, 133, 159, 145],
                fallback: CGPoint(x: faceRect.minX + faceRect.width * 0.33, y: faceRect.minY + faceRect.height * 0.62),
                face: face,
                in: image.extent
            )
            let rightEye = averageLandmarkPoint(
                indices: [263, 362, 386, 374],
                fallback: CGPoint(x: faceRect.maxX - faceRect.width * 0.33, y: faceRect.minY + faceRect.height * 0.62),
                face: face,
                in: image.extent
            )
            let radius = max(4, faceRect.width * (0.10 + CGFloat(effects.eyeEnlargement) * 0.10))
            let scale = CGFloat(0.18 + effects.eyeEnlargement * 0.34)
            output = bump(output, center: leftEye, radius: radius, scale: scale)
            output = bump(output, center: rightEye, radius: radius, scale: scale)
            output = enlargeEye(output, center: leftEye, radius: radius, strength: CGFloat(effects.eyeEnlargement))
            output = enlargeEye(output, center: rightEye, radius: radius, strength: CGFloat(effects.eyeEnlargement))
            output = enhanceEyeDetail(output, center: leftEye, radius: radius, strength: CGFloat(effects.eyeEnlargement))
            output = enhanceEyeDetail(output, center: rightEye, radius: radius, strength: CGFloat(effects.eyeEnlargement))
        }

        return output.cropped(to: image.extent)
    }

    private func pinch(_ image: CIImage, center: CGPoint, radius: CGFloat, scale: CGFloat) -> CIImage {
        image
            .clampedToExtent()
            .applyingFilter("CIPinchDistortion", parameters: [
                kCIInputCenterKey: CIVector(cgPoint: center),
                kCIInputRadiusKey: radius,
                kCIInputScaleKey: scale
            ])
            .cropped(to: image.extent)
    }

    private func bump(_ image: CIImage, center: CGPoint, radius: CGFloat, scale: CGFloat) -> CIImage {
        image
            .clampedToExtent()
            .applyingFilter("CIBumpDistortion", parameters: [
                kCIInputCenterKey: CIVector(cgPoint: center),
                kCIInputRadiusKey: radius,
                kCIInputScaleKey: scale
            ])
            .cropped(to: image.extent)
    }

    private func enlargeEye(_ image: CIImage, center: CGPoint, radius: CGFloat, strength: CGFloat) -> CIImage {
        let sourceRect = CGRect(
            x: center.x - radius * 0.92,
            y: center.y - radius * 0.52,
            width: radius * 1.84,
            height: radius * 1.04
        ).intersection(image.extent)
        guard sourceRect.width > 2, sourceRect.height > 2 else {
            return image
        }

        let scale = 1 + strength * 0.48
        let scaled = image
            .cropped(to: sourceRect)
            .transformed(
                by: CGAffineTransform(translationX: center.x, y: center.y)
                    .scaledBy(x: scale, y: scale)
                    .translatedBy(x: -center.x, y: -center.y)
            )
        let maskRect = sourceRect.insetBy(dx: -radius * 0.34, dy: -radius * 0.22).intersection(image.extent)
        let mask = radialMask(in: maskRect, innerRadius: 0.12, outerRadius: 0.70)
        return scaled
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: image,
                kCIInputMaskImageKey: mask
            ])
            .cropped(to: image.extent)
    }

    private func enhanceEyeDetail(_ image: CIImage, center: CGPoint, radius: CGFloat, strength: CGFloat) -> CIImage {
        let maskRect = CGRect(
            x: center.x - radius * 1.55,
            y: center.y - radius * 0.95,
            width: radius * 3.10,
            height: radius * 1.90
        ).intersection(image.extent)
        guard maskRect.width > 2, maskRect.height > 2 else {
            return image
        }
        let crop = image.cropped(to: maskRect)
        let sharpened = crop
            .applyingFilter("CISharpenLuminance", parameters: [
                kCIInputSharpnessKey: 0.28 + strength * 1.10
            ])
            .applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 1 + strength * 0.86,
                kCIInputSaturationKey: 1 + strength * 0.14,
                kCIInputBrightnessKey: -strength * 0.085
            ])
        let mask = radialMask(in: maskRect, innerRadius: 0.10, outerRadius: 0.72)
        return sharpened
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: image,
                kCIInputMaskImageKey: mask
            ])
            .cropped(to: image.extent)
    }

    private func beautifiedFaceImage(_ image: CIImage, effects: PresenterVideoEffects) -> CIImage {
        var output = image
        let brightening = max(effects.skinBrightening, effects.beauty * 0.5)
        let whitening = max(effects.skinWhitening, effects.beauty * 0.35)
        let complexion = effects.complexion
        let smoothing = max(effects.skinSmoothing, effects.beauty * 0.5)

        if smoothing > 0 {
            output = output.applyingFilter("CINoiseReduction", parameters: [
                "inputNoiseLevel": 0.015 + smoothing * 0.028,
                "inputSharpness": max(0.62, 0.90 - smoothing * 0.18)
            ])
        }
        if brightening > 0 || whitening > 0 || complexion > 0 {
            output = output.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: brightening * 0.12 + whitening * 0.04,
                kCIInputContrastKey: 1 + brightening * 0.02,
                kCIInputSaturationKey: 1 - whitening * 0.03 + complexion * 0.05
            ])
            output = output.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(
                    x: whitening * 0.022 + complexion * 0.025,
                    y: whitening * 0.024 + complexion * 0.012,
                    z: whitening * 0.026,
                    w: 0
                )
            ])
        }
        return output.cropped(to: image.extent)
    }

    private func rect(from box: MediaPipePortraitBoundingBox, in extent: CGRect) -> CGRect {
        CGRect(
            x: extent.minX + CGFloat(box.x) * extent.width,
            y: extent.minY + CGFloat(1 - box.y - box.height) * extent.height,
            width: CGFloat(box.width) * extent.width,
            height: CGFloat(box.height) * extent.height
        ).intersection(extent)
    }

    private func landmarkPoint(
        at index: Int,
        fallback: CGPoint,
        face: MediaPipeFacePrediction,
        in extent: CGRect
    ) -> CGPoint {
        guard face.landmarks.indices.contains(index) else {
            return fallback
        }
        return point(from: face.landmarks[index], in: extent)
    }

    private func averageLandmarkPoint(
        indices: [Int],
        fallback: CGPoint,
        face: MediaPipeFacePrediction,
        in extent: CGRect
    ) -> CGPoint {
        let points = indices.compactMap { index -> CGPoint? in
            guard face.landmarks.indices.contains(index) else {
                return nil
            }
            return point(from: face.landmarks[index], in: extent)
        }
        guard !points.isEmpty else {
            return fallback
        }
        let sum = points.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    private func point(from landmark: MediaPipeNormalizedLandmark, in extent: CGRect) -> CGPoint {
        CGPoint(
            x: extent.minX + CGFloat(landmark.x) * extent.width,
            y: extent.minY + CGFloat(1 - landmark.y) * extent.height
        )
    }

    private func radialMask(
        in rect: CGRect,
        innerRadius: CGFloat = 0.18,
        outerRadius: CGFloat = 0.72
    ) -> CIImage {
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
        let transform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: rect.width / side, y: rect.height / side)
            .translatedBy(x: -rect.midX, y: -rect.midY)
        return gradient.transformed(by: transform).cropped(to: rect)
    }
}
