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
        let beautified = beautifiedFaceImage(image.cropped(to: maskRect), effects: effects)
        return beautified
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

    private func radialMask(in rect: CGRect) -> CIImage {
        let side = max(1, min(rect.width, rect.height))
        let gradient = CIFilter(
            name: "CIRadialGradient",
            parameters: [
                "inputCenter": CIVector(x: rect.midX, y: rect.midY),
                "inputRadius0": side * 0.18,
                "inputRadius1": side * 0.72,
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
