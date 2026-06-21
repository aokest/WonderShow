@preconcurrency import AVFoundation
import CoreImage
import Foundation

enum CameraArchiveFrameGeometry {
    static func centeredAspectFitRect(
        sourceSize: CGSize,
        targetSize: CGSize,
        allowsUpscaling: Bool = true
    ) -> CGRect {
        let sourceWidth = max(1, sourceSize.width)
        let sourceHeight = max(1, sourceSize.height)
        let targetWidth = max(1, targetSize.width)
        let targetHeight = max(1, targetSize.height)
        let scale = min(
            allowsUpscaling ? .greatestFiniteMagnitude : 1,
            targetWidth / sourceWidth,
            targetHeight / sourceHeight
        )
        let width = sourceWidth * scale
        let height = sourceHeight * scale
        return CGRect(
            x: (targetWidth - width) / 2,
            y: (targetHeight - height) / 2,
            width: width,
            height: height
        ).integral
    }
}

enum CameraFrameMatteDetector {
    static func contentRect(in pixelBuffer: CVPixelBuffer) -> CGRect? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width >= 320, height >= 240 else {
            return nil
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)
        let sampleStep = max(2, min(width, height) / 180)
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        var contentSamples = 0

        for y in stride(from: 0, to: height, by: sampleStep) {
            for x in stride(from: 0, to: width, by: sampleStep) {
                let offset = y * bytesPerRow + x * 4
                let blue = Int(pointer[offset])
                let green = Int(pointer[offset + 1])
                let red = Int(pointer[offset + 2])
                if red + green + blue > 48 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                    contentSamples += 1
                }
            }
        }

        guard contentSamples > 20, maxX > minX, maxY > minY else {
            return nil
        }
        let expansion = sampleStep * 2
        let rect = CGRect(
            x: max(0, minX - expansion),
            y: max(0, minY - expansion),
            width: min(width - 1, maxX + expansion) - max(0, minX - expansion) + 1,
            height: min(height - 1, maxY + expansion) - max(0, minY - expansion) + 1
        ).integral
        let frameArea = CGFloat(width * height)
        let rectArea = rect.width * rect.height
        guard rectArea / frameArea >= 0.04, rectArea / frameArea <= 0.92 else {
            return nil
        }
        guard rect.minX > 8 || rect.minY > 8 || rect.maxX < CGFloat(width - 8) || rect.maxY < CGFloat(height - 8) else {
            return nil
        }
        return rect
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
    private var recordingStartedAt: DispatchTime?

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
            recordingStartedAt = nil
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
                recordingStartedAt = nil
                state = .idle
                completion?(url)
            case .writing(let recording):
                appendLatestFrameOnQueue()
                isPaused = false
                latestPixelBuffer = nil
                framePump?.cancel()
                framePump = nil
                recordingStartedAt = nil
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
        recordingStartedAt = .now()
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

        let elapsedFrameIndex = elapsedFrameIndexOnQueue()
        let presentationFrameIndex = max(frameIndex, elapsedFrameIndex)
        let elapsedPresentationTime = CMTime(value: presentationFrameIndex, timescale: 30)
        guard recording.input.isReadyForMoreMediaData else {
            return
        }
        if recording.adaptor.append(latestPixelBuffer, withPresentationTime: elapsedPresentationTime) {
            frameIndex = presentationFrameIndex + 1
        }
    }

    private func elapsedFrameIndexOnQueue() -> CMTimeValue {
        guard let recordingStartedAt else {
            return frameIndex
        }
        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - recordingStartedAt.uptimeNanoseconds
        let elapsedSeconds = Double(elapsedNanoseconds) / 1_000_000_000
        return max(0, CMTimeValue((elapsedSeconds * 30).rounded(.down)))
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
        let sourceExtent = CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight)
        let detectedContentRect = CameraFrameMatteDetector.contentRect(in: pixelBuffer)
        guard sourceWidth != targetWidth || sourceHeight != targetHeight || detectedContentRect != nil else {
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
        let contentRect = detectedContentRect ?? sourceExtent
        let contentImage = sourceImage
            .cropped(to: contentRect)
            .transformed(by: CGAffineTransform(translationX: -contentRect.minX, y: -contentRect.minY))
        let fittedRect = CameraArchiveFrameGeometry.centeredAspectFitRect(
            sourceSize: contentImage.extent.size,
            targetSize: targetRect.size
        )
        let scale = min(
            fittedRect.width / max(1, contentImage.extent.width),
            fittedRect.height / max(1, contentImage.extent.height)
        )
        let fittedImage = contentImage
            .applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: scale,
                kCIInputAspectRatioKey: 1
            ])
            .transformed(by: CGAffineTransform(translationX: fittedRect.minX, y: fittedRect.minY))
        let outputImage = fittedImage
            .composited(over: CIImage(color: .black).cropped(to: targetRect))
            .cropped(to: targetRect)
        renderContext.render(outputImage, to: outputBuffer, bounds: targetRect, colorSpace: CGColorSpaceCreateDeviceRGB())
        return outputBuffer
    }
}
