@preconcurrency import AVFoundation
import CoreImage
import Foundation

enum CameraArchiveFrameGeometry {
    static func aspectFillCropRect(sourceSize: CGSize, targetSize: CGSize) -> CGRect {
        let sourceWidth = max(1, sourceSize.width)
        let sourceHeight = max(1, sourceSize.height)
        let targetWidth = max(1, targetSize.width)
        let targetHeight = max(1, targetSize.height)
        let sourceAspect = sourceWidth / sourceHeight
        let targetAspect = targetWidth / targetHeight

        if sourceAspect > targetAspect {
            let cropWidth = sourceHeight * targetAspect
            return CGRect(
                x: (sourceWidth - cropWidth) / 2,
                y: 0,
                width: cropWidth,
                height: sourceHeight
            ).integral
        }

        let cropHeight = sourceWidth / targetAspect
        return CGRect(
            x: 0,
            y: (sourceHeight - cropHeight) / 2,
            width: sourceWidth,
            height: cropHeight
        ).integral
    }
}

final class CameraArchiveRecorder: @unchecked Sendable {
    private final class SampleBufferBox: @unchecked Sendable {
        let value: CMSampleBuffer

        init(_ value: CMSampleBuffer) {
            self.value = value
        }
    }

    private struct ActiveRecording: @unchecked Sendable {
        let url: URL
        let writer: AVAssetWriter
        let input: AVAssetWriterInput
        let adaptor: AVAssetWriterInputPixelBufferAdaptor
        let pixelSize: CGSize
    }

    private enum State {
        case idle
        case waitingForFirstFrame(URL)
        case writing(ActiveRecording)
        case finishing
    }

    private let queue = DispatchQueue(label: "com.wondershow.camera-archive-recorder")
    private let fileManager: FileManager
    private let renderContext = CIContext()
    private var state: State = .idle
    private var isPaused = false
    private var latestPixelBuffer: CVPixelBuffer?
    private var framePump: DispatchSourceTimer?
    private var frameIndex: CMTimeValue = 0

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func startRecording(to outputURL: URL) throws {
        try fileManager.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }

        queue.sync {
            isPaused = false
            framePump?.cancel()
            framePump = nil
            latestPixelBuffer = nil
            frameIndex = 0
            state = .waitingForFirstFrame(outputURL)
        }
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        let sampleBufferBox = SampleBufferBox(sampleBuffer)
        queue.async { [weak self, sampleBufferBox] in
            self?.appendOnQueue(sampleBufferBox.value)
        }
    }

    func pauseRecording() {
        queue.async { [weak self] in
            self?.isPaused = true
        }
    }

    func resumeRecording() {
        queue.async { [weak self] in
            self?.isPaused = false
        }
    }

    func stopRecording(completion: (@Sendable (URL?) -> Void)? = nil) {
        queue.async { [weak self, completion] in
            guard let self else {
                completion?(nil)
                return
            }

            switch state {
            case .idle:
                completion?(nil)
            case .waitingForFirstFrame(let url):
                isPaused = false
                latestPixelBuffer = nil
                framePump?.cancel()
                framePump = nil
                state = .idle
                completion?(url)
            case .writing(let recording):
                isPaused = false
                latestPixelBuffer = nil
                framePump?.cancel()
                framePump = nil
                state = .finishing
                let finishedURL = recording.url
                recording.input.markAsFinished()
                recording.writer.finishWriting { [weak self, completion, finishedURL] in
                    guard let recorder = self else {
                        completion?(finishedURL)
                        return
                    }
                    recorder.queue.async { [weak recorder, completion, finishedURL] in
                        recorder?.state = .idle
                        completion?(finishedURL)
                    }
                }
            case .finishing:
                completion?(nil)
            }
        }
    }

    private func appendOnQueue(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        switch state {
        case .idle, .finishing:
            return
        case .waitingForFirstFrame(let url):
            do {
                let recording = try makeRecording(url: url, pixelBuffer: pixelBuffer)
                state = .writing(recording)
                latestPixelBuffer = normalizedPixelBuffer(pixelBuffer, for: recording)
                startFramePumpOnQueue()
                appendLatestFrameOnQueue()
            } catch {
                latestPixelBuffer = nil
                state = .idle
            }
        case .writing(let recording):
            if let normalized = normalizedPixelBuffer(pixelBuffer, for: recording) {
                latestPixelBuffer = normalized
            }
        }
    }

    private func makeRecording(url: URL, pixelBuffer: CVPixelBuffer) throws -> ActiveRecording {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let width = max(1, CVPixelBufferGetWidth(pixelBuffer))
        let height = max(1, CVPixelBufferGetHeight(pixelBuffer))
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: videoOutputSettings(width: width, height: height)
        )
        input.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )

        guard writer.canAdd(input) else {
            throw NSError(domain: "CameraArchiveRecorder", code: 1)
        }
        writer.add(input)

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        return ActiveRecording(
            url: url,
            writer: writer,
            input: input,
            adaptor: adaptor,
            pixelSize: CGSize(width: width, height: height)
        )
    }

    private func startFramePumpOnQueue() {
        framePump?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(33), leeway: .milliseconds(4))
        timer.setEventHandler { [weak self] in
            self?.appendLatestFrameOnQueue()
        }
        framePump = timer
        timer.resume()
    }

    private func appendLatestFrameOnQueue() {
        guard !isPaused,
              case .writing(let recording) = state,
              let latestPixelBuffer else {
            return
        }
        guard recording.writer.status == .writing else {
            return
        }

        let presentationTime = CMTime(value: frameIndex, timescale: 30)
        frameIndex += 1
        guard recording.input.isReadyForMoreMediaData else {
            return
        }
        _ = recording.adaptor.append(latestPixelBuffer, withPresentationTime: presentationTime)
    }

    private func videoOutputSettings(width: Int, height: Int) -> [String: Any] {
        return [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
    }

    private func normalizedPixelBuffer(_ pixelBuffer: CVPixelBuffer, for recording: ActiveRecording) -> CVPixelBuffer? {
        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
        let targetWidth = max(1, Int(recording.pixelSize.width))
        let targetHeight = max(1, Int(recording.pixelSize.height))
        guard sourceWidth != targetWidth || sourceHeight != targetHeight else {
            return pixelBuffer
        }
        guard let pool = recording.adaptor.pixelBufferPool else {
            return nil
        }
        var outputBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer) == kCVReturnSuccess,
              let outputBuffer else {
            return nil
        }

        let targetRect = CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer)
        let cropRect = CameraArchiveFrameGeometry.aspectFillCropRect(
            sourceSize: sourceImage.extent.size,
            targetSize: targetRect.size
        )
        let croppedImage = sourceImage
            .cropped(to: cropRect)
            .transformed(by: CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY))
        let scaleX = targetRect.width / max(1, cropRect.width)
        let scaleY = targetRect.height / max(1, cropRect.height)
        let outputImage = croppedImage.transformed(
            by: CGAffineTransform(scaleX: scaleX, y: scaleY)
        )
        renderContext.render(outputImage, to: outputBuffer, bounds: targetRect, colorSpace: CGColorSpaceCreateDeviceRGB())
        return outputBuffer
    }
}
