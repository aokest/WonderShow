@testable import WonderShowApp
import CoreGraphics
import Testing

@MainActor
@Test func screenPreviewRestartKeepsPreviousFrameUntilReplacementArrives() throws {
    let service = ScreenPreviewService()
    let image = try makePreviewTestImage(width: 16, height: 9)

    service.replaceLatestFrameForTesting(image, sourceID: .display(1), statusText: "画面已接入")
    service.start(target: .genericKeyboard, sourcePreference: .automaticPresentationWindow)

    #expect(service.latestImage === image)
    #expect(service.latestSourceID == .display(1))
}

private func makePreviewTestImage(width: Int, height: Int) throws -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw PreviewTestImageError.contextCreationFailed
    }
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let image = context.makeImage() else {
        throw PreviewTestImageError.imageCreationFailed
    }
    return image
}

private enum PreviewTestImageError: Error {
    case contextCreationFailed
    case imageCreationFailed
}
