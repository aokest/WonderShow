import CoreImage
import Foundation
import PresenterDirector

struct PortraitBackgroundProcessor {
    func apply(
        to image: CIImage,
        segmentation: MediaPipePortraitSegmentationMask?,
        effects: PresenterVideoEffects
    ) -> CIImage {
        guard effects.portraitSegmentationEnabled else {
            return image
        }
        guard let segmentation, let mask = maskImage(from: segmentation, targetExtent: image.extent) else {
            return image
        }

        switch effects.backgroundEffect {
        case .none:
            guard effects.backgroundBlur > 0 else {
                return image
            }
            return composite(
                foreground: image,
                background: blurredBackground(from: image, strength: effects.backgroundBlur),
                mask: mask,
                extent: image.extent
            )
        case .blur(let strength):
            return composite(
                foreground: image,
                background: blurredBackground(from: image, strength: max(strength, effects.backgroundBlur)),
                mask: mask,
                extent: image.extent
            )
        case .replacement(let colorHex, let strength):
            let replacement = CIImage(color: color(from: colorHex))
                .cropped(to: image.extent)
            let background: CIImage
            if strength < 1 {
                background = replacement.applyingFilter("CIBlendWithAlphaMask", parameters: [
                    kCIInputBackgroundImageKey: image,
                    kCIInputMaskImageKey: CIImage(
                        color: CIColor(
                            red: strength,
                            green: strength,
                            blue: strength,
                            alpha: strength
                        )
                    ).cropped(to: image.extent)
                ])
            } else {
                background = replacement
            }
            return composite(foreground: image, background: background, mask: mask, extent: image.extent)
        }
    }

    private func composite(foreground: CIImage, background: CIImage, mask: CIImage, extent: CGRect) -> CIImage {
        foreground
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: background,
                kCIInputMaskImageKey: mask
            ])
            .cropped(to: extent)
    }

    private func blurredBackground(from image: CIImage, strength: Double) -> CIImage {
        image
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: 4 + strength * 26
            ])
            .cropped(to: image.extent)
    }

    private func maskImage(
        from segmentation: MediaPipePortraitSegmentationMask,
        targetExtent: CGRect
    ) -> CIImage? {
        guard segmentation.width > 0,
              segmentation.height > 0,
              segmentation.maskData.count == segmentation.width * segmentation.height else {
            return nil
        }

        let provider = CGDataProvider(data: segmentation.maskData as CFData)
        guard let provider,
              let cgMask = CGImage(
                width: segmentation.width,
                height: segmentation.height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: segmentation.width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            return nil
        }

        var mask = CIImage(cgImage: cgMask)
            .transformed(by: CGAffineTransform(
                scaleX: targetExtent.width / CGFloat(segmentation.width),
                y: targetExtent.height / CGFloat(segmentation.height)
            ))
            .transformed(by: CGAffineTransform(translationX: targetExtent.minX, y: targetExtent.minY))
            .cropped(to: targetExtent)
        let featherRadius = min(targetExtent.width, targetExtent.height) >= 24 ? 1.2 : 0
        if featherRadius > 0 {
            mask = mask
                .applyingFilter("CIGaussianBlur", parameters: [
                    kCIInputRadiusKey: featherRadius
                ])
                .cropped(to: targetExtent)
        }
        return mask
    }

    private func color(from hex: String) -> CIColor {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard trimmed.count == 6, let value = Int(trimmed, radix: 16) else {
            return CIColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1)
        }
        return CIColor(
            red: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1
        )
    }
}
