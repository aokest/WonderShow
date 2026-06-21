import AppKit
import CoreGraphics
import Foundation
import WonderShow
@preconcurrency import ScreenCaptureKit

@MainActor
final class ScreenPreviewService: ObservableObject {
    @Published private(set) var latestImage: CGImage?
    @Published private(set) var statusText = "待命"
    @Published private(set) var latestSourceID: ScreenCaptureSourceID?

    private var previewTask: Task<Void, Never>?
    private var previewGeneration = 0

    func start(
        target: PresentationTarget,
        sourcePreference: ScreenCaptureSourcePreference
    ) {
        previewGeneration += 1
        let generation = previewGeneration

        guard CGPreflightScreenCaptureAccess() else {
            latestImage = nil
            latestSourceID = nil
            statusText = "需要屏幕录制权限"
            stop()
            return
        }

        previewTask?.cancel()
        previewTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.captureOnce(
                    target: target,
                    sourcePreference: sourcePreference,
                    generation: generation
                )
                try? await Task.sleep(for: .milliseconds(650))
            }
        }
    }

    func stop() {
        previewGeneration += 1
        previewTask?.cancel()
        previewTask = nil
    }

    func resetImage() {
        latestImage = nil
        latestSourceID = nil
    }

#if DEBUG
    func replaceLatestFrameForTesting(
        _ image: CGImage,
        sourceID: ScreenCaptureSourceID,
        statusText: String = "画面已接入"
    ) {
        latestImage = image
        latestSourceID = sourceID
        self.statusText = statusText
    }
#endif

    private func captureOnce(
        target: PresentationTarget,
        sourcePreference: ScreenCaptureSourcePreference,
        generation: Int
    ) async {
        do {
            let content = try await ScreenCaptureSourceResolver.shareableContent()
            guard generation == previewGeneration else {
                return
            }
            guard let selection = ScreenCaptureSourceResolver.preferredSelection(
                from: content,
                target: target,
                sourcePreference: sourcePreference
            ) else {
                statusText = "未找到可预览窗口"
                return
            }

            let configuration = ScreenArchiveRecorder.streamConfiguration(for: selection)

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: selection.filter,
                configuration: configuration
            )
            guard generation == previewGeneration else {
                return
            }
            latestImage = image
            latestSourceID = selection.sourceID
            statusText = "画面已接入"
        } catch {
            guard generation == previewGeneration else {
                return
            }
            statusText = error.localizedDescription
            if error.localizedDescription.contains("屏幕录制权限")
                || error.localizedDescription.localizedCaseInsensitiveContains("screen recording") {
                stop()
            }
        }
    }
}
