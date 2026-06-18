import AppKit
@preconcurrency import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import PresenterDirector
@preconcurrency import ScreenCaptureKit

private final class QueuedSampleBuffer: @unchecked Sendable {
    let value: CMSampleBuffer

    init(_ value: CMSampleBuffer) {
        self.value = value
    }
}

private final class QueuedWriter: @unchecked Sendable {
    let value: AVAssetWriter

    init(_ value: AVAssetWriter) {
        self.value = value
    }
}

let shouldRequestAccess = CommandLine.arguments.contains("--request")
let shouldRecordSmoke = CommandLine.arguments.contains("--record-smoke")

print("bundleIdentifier=\(Bundle.main.bundleIdentifier ?? "<none>")")
print("executable=\(CommandLine.arguments.first ?? "<unknown>")")
print("preflightBefore=\(CGPreflightScreenCaptureAccess())")

if shouldRequestAccess {
    print("requestResult=\(CGRequestScreenCaptureAccess())")
    print("preflightAfterRequest=\(CGPreflightScreenCaptureAccess())")
}

do {
    let content = try await SCShareableContent.excludingDesktopWindows(
        false,
        onScreenWindowsOnly: true
    )
    print("displays=\(content.displays.count)")
    for (index, display) in content.displays.enumerated() {
        print("display[\(index)]=id:\(display.displayID) size:\(display.width)x\(display.height)")
    }

    let rawWindows = content.windows
    let shareableWindows = rawWindows.filter { window in
        let frame = window.frame
        let candidate = CaptureWindowCandidate(
            id: window.windowID,
            displayID: 0,
            title: window.title ?? "",
            applicationName: window.owningApplication?.applicationName ?? "",
            bundleIdentifier: window.owningApplication?.bundleIdentifier ?? "",
            frameWidth: Int(frame.width),
            frameHeight: Int(frame.height)
        )
        return ScreenSharingWindowFilter().isShareable(candidate)
    }

    print("rawWindows=\(rawWindows.count)")
    print("shareableWindows=\(shareableWindows.count)")
    for window in shareableWindows.prefix(40) {
        let title = window.title ?? ""
        let app = window.owningApplication?.applicationName ?? "Unknown"
        let bundle = window.owningApplication?.bundleIdentifier ?? ""
        let frame = window.frame
        print("window=id:\(window.windowID) app:\(app) bundle:\(bundle) title:\(title) size:\(Int(frame.width))x\(Int(frame.height))")
    }

    if shouldRecordSmoke {
        guard let display = content.displays.first else {
            print("recordSmokeError=no display")
            exit(2)
        }
        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lingyan-screen-smoke-\(UUID().uuidString).mov")
        let recorder = SmokeRecorder(outputURL: outputURL)
        try await recorder.start(display: display)
        try await Task.sleep(for: .seconds(2))
        let summary = await recorder.stop()
        print("recordSmokeURL=\(outputURL.path)")
        print("recordSmokeFrames=\(summary.frames)")
        print("recordSmokeBytes=\(summary.bytes)")
        print("recordSmokeSize=\(summary.width)x\(summary.height)")
        if summary.frames <= 0 || summary.bytes <= 0 {
            print("recordSmokeError=\(summary.error ?? "no frames or empty file")")
            exit(3)
        }
    }
} catch {
    print("shareableContentError=\(error.localizedDescription)")
    exit(1)
}

private final class SmokeRecorder: NSObject, SCStreamOutput, @unchecked Sendable {
    struct Summary {
        let frames: Int
        let bytes: Int64
        let width: Int
        let height: Int
        let error: String?
    }

    private let outputURL: URL
    private let queue = DispatchQueue(label: "lingyan.screen-smoke")
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var latestPixelBuffer: CVPixelBuffer?
    private var framePump: DispatchSourceTimer?
    private var frameIndex: CMTimeValue = 0
    private var frames = 0
    private var samples = 0
    private var width = 0
    private var height = 0
    private var error: String?

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func start(display: SCDisplay) async throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        let configuration = SCStreamConfiguration()
        configuration.width = max(2, display.width * 2)
        configuration.height = max(2, display.height * 2)
        configuration.width += configuration.width.isMultiple(of: 2) ? 0 : 1
        configuration.height += configuration.height.isMultiple(of: 2) ? 0 : 1
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 5
        configuration.showsCursor = true
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.scalesToFit = true
        if #available(macOS 14.0, *) {
            configuration.preservesAspectRatio = true
            configuration.captureResolution = .best
            configuration.shouldBeOpaque = true
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        self.stream = stream
        try queue.sync {
            try self.makeWriter(width: configuration.width, height: configuration.height)
            self.startFramePump()
        }
        try await stream.startCapture()
    }

    func stop() async -> Summary {
        try? await stream?.stopCapture()
        return await withCheckedContinuation { continuation in
            queue.async {
                self.framePump?.cancel()
                self.framePump = nil
                guard let writer = self.writer, let input = self.input else {
                    continuation.resume(returning: self.summary())
                    return
            }
            input.markAsFinished()
            let queuedWriter = QueuedWriter(writer)
            writer.finishWriting {
                let finishedWriterError = queuedWriter.value.error?.localizedDescription
                self.queue.async {
                    if let finishedWriterError {
                        self.error = finishedWriterError
                        }
                        continuation.resume(returning: self.summary())
                    }
                }
            }
        }
    }

    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen else {
            return
        }
        let queuedSampleBuffer = QueuedSampleBuffer(sampleBuffer)
        queue.async { [queuedSampleBuffer] in
            self.handle(queuedSampleBuffer.value)
        }
    }

    private func handle(_ sampleBuffer: CMSampleBuffer) {
        guard sampleBuffer.isValid,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let description = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return
        }
        let dimensions = CMVideoFormatDescriptionGetDimensions(description)
        width = Int(dimensions.width)
        height = Int(dimensions.height)
        samples += 1
        latestPixelBuffer = imageBuffer
    }

    private func makeWriter(width: Int, height: Int) throws {
        writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: max(8_000_000, width * height * 2)
                ]
            ]
        )
        input?.expectsMediaDataInRealTime = true
        guard let input, let writer, writer.canAdd(input) else {
            throw NSError(domain: "SmokeRecorder", code: 1)
        }
        writer.add(input)
        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
    }

    private func startFramePump() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(33), leeway: .milliseconds(4))
        timer.setEventHandler { [weak self] in
            self?.appendLatestFrame()
        }
        framePump = timer
        timer.resume()
    }

    private func appendLatestFrame() {
        guard let latestPixelBuffer,
              let writer,
              let input,
              let adaptor,
              writer.status == .writing,
              input.isReadyForMoreMediaData else {
            return
        }
        let time = CMTime(value: frameIndex, timescale: 30)
        frameIndex += 1
        if adaptor.append(latestPixelBuffer, withPresentationTime: time) {
            frames += 1
        } else {
            error = writer.error?.localizedDescription
        }
    }

    private func summary() -> Summary {
        let bytes = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?
            .int64Value ?? 0
        return Summary(frames: frames, bytes: bytes, width: width, height: height, error: error)
    }
}
