import AppKit
import CoreGraphics
import CoreImage
import WonderShow

struct EmojiFaceOverlayProcessor {
    func apply(
        to image: CIImage,
        portrait: MediaPipePortraitFrame,
        emoji: String,
        opacity: Double,
        scale: Double
    ) -> CIImage {
        guard opacity > 0, !emoji.isEmpty else {
            return image
        }
        guard let face = portrait.faces.max(by: { lhs, rhs in
            lhs.boundingBox.width * lhs.boundingBox.height < rhs.boundingBox.width * rhs.boundingBox.height
        }) else {
            return image
        }

        let faceRect = rect(from: face.boundingBox, in: image.extent)
            .insetBy(dx: -image.extent.width * 0.012, dy: -image.extent.height * 0.012)
        let scaledFaceRect = scaled(faceRect, by: CGFloat(scale), in: image.extent)
        let emojiRect = scaledFaceRect.intersection(image.extent)
        guard emojiRect.width > 1, emojiRect.height > 1 else {
            return image
        }
        guard let emojiImage = emojiCIImage(emoji: emoji, rect: emojiRect, opacity: opacity) else {
            return image
        }
        return emojiImage.composited(over: image).cropped(to: image.extent)
    }

    private func emojiCIImage(emoji: String, rect: CGRect, opacity: Double) -> CIImage? {
        autoreleasepool {
            let scale: CGFloat = 2
            let pixelSize = CGSize(width: max(2, rect.width * scale), height: max(2, rect.height * scale))
            let image = NSImage(size: pixelSize)
            image.lockFocus()
            NSColor.clear.setFill()
            NSRect(origin: .zero, size: pixelSize).fill()

            let fontSize = min(pixelSize.width, pixelSize.height) * 0.82
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor.white.withAlphaComponent(max(0, min(1, opacity)))
            ]
            let attributed = NSAttributedString(string: emoji, attributes: attributes)
            let textSize = attributed.size()
            let textRect = NSRect(
                x: (pixelSize.width - textSize.width) / 2,
                y: (pixelSize.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            attributed.draw(in: textRect)
            image.unlockFocus()

            guard let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let cgImage = bitmap.cgImage else {
                return nil
            }

            return CIImage(cgImage: cgImage)
                .transformed(by: CGAffineTransform(scaleX: rect.width / CGFloat(cgImage.width), y: rect.height / CGFloat(cgImage.height)))
                .transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
                .cropped(to: rect)
        }
    }

    private func rect(from box: MediaPipePortraitBoundingBox, in extent: CGRect) -> CGRect {
        CGRect(
            x: extent.minX + CGFloat(box.x) * extent.width,
            y: extent.minY + CGFloat(1 - box.y - box.height) * extent.height,
            width: CGFloat(box.width) * extent.width,
            height: CGFloat(box.height) * extent.height
        )
    }

    private func scaled(_ rect: CGRect, by scale: CGFloat, in extent: CGRect) -> CGRect {
        guard rect.width > 0, rect.height > 0 else {
            return rect
        }
        let safeScale = max(0.55, min(scale, 1.8))
        let scaledWidth = rect.width * safeScale
        let scaledHeight = rect.height * safeScale
        let scaledRect = CGRect(
            x: rect.midX - scaledWidth / 2,
            y: rect.midY - scaledHeight / 2,
            width: scaledWidth,
            height: scaledHeight
        )
        return scaledRect.intersection(extent)
    }
}
