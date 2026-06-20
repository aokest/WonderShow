@preconcurrency import AVFoundation
import Foundation

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
        var frameIndex: CMTimeValue
    }

    private enum State {
        case idle
        case waitingForFirstFrame(URL)
        case writing(ActiveRecording)
        case finishing
    }

    private let queue = DispatchQueue(label: "com.wondershow.camera-archive-recorder")
    private let fileManager: FileManager
    private var state: State = .idle
    private var isPaused = false

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
                state = .idle
                completion?(url)
            case .writing(let recording):
                isPaused = false
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
        guard !isPaused else {
            return
        }

        switch state {
        case .idle, .finishing:
            return
        case .waitingForFirstFrame(let url):
            do {
                let recording = try makeRecording(url: url, sampleBuffer: sampleBuffer)
                state = .writing(recording)
                append(sampleBuffer, to: recording)
            } catch {
                state = .idle
            }
        case .writing(let recording):
            append(sampleBuffer, to: recording)
        }
    }

    private func makeRecording(url: URL, sampleBuffer: CMSampleBuffer) throws -> ActiveRecording {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: videoOutputSettings(from: sampleBuffer)
        )
        input.expectsMediaDataInRealTime = true

        if writer.canAdd(input) {
            writer.add(input)
        }

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        return ActiveRecording(url: url, writer: writer, input: input, frameIndex: 0)
    }

    private func append(_ sampleBuffer: CMSampleBuffer, to recording: ActiveRecording) {
        guard recording.writer.status == .writing else {
            return
        }
        guard recording.input.isReadyForMoreMediaData else {
            return
        }

        var recording = recording
        let presentationTime = CMTime(value: recording.frameIndex, timescale: 30)
        recording.frameIndex += 1
        state = .writing(recording)
        recording.input.append(retimed(sampleBuffer, presentationTime: presentationTime) ?? sampleBuffer)
    }

    private func videoOutputSettings(from sampleBuffer: CMSampleBuffer) -> [String: Any] {
        let dimensions = CMSampleBufferGetFormatDescription(sampleBuffer)
            .map(CMVideoFormatDescriptionGetDimensions)
        let width = max(1, Int(dimensions?.width ?? 1920))
        let height = max(1, Int(dimensions?.height ?? 1080))

        return [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
    }

    private func retimed(_ sampleBuffer: CMSampleBuffer, presentationTime: CMTime) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var output: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &output
        )
        guard status == noErr else {
            return nil
        }
        return output
    }
}
