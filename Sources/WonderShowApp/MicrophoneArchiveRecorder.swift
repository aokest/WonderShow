@preconcurrency import AVFoundation
import Foundation

enum MicrophoneArchiveRecorderError: Error, LocalizedError {
    case permissionDenied
    case cannotStart
    case deviceUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "未获得麦克风权限"
        case .cannotStart:
            return "麦克风录制启动失败"
        case .deviceUnavailable:
            return "所选麦克风不可用"
        }
    }
}

struct AudioInputDeviceOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let detail: String
    let isSystemDefault: Bool

    static let systemDefault = AudioInputDeviceOption(
        id: "system-default",
        name: "系统默认麦克风",
        detail: "跟随 macOS 当前声音输入设置",
        isSystemDefault: true
    )
}

private final class MicrophoneSampleBuffer: @unchecked Sendable {
    let value: CMSampleBuffer

    init(_ value: CMSampleBuffer) {
        self.value = value
    }
}

enum MicrophoneArchiveAudioSettings {
    static func capturePCM() -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
    }

    static func writerAAC() -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 48_000,
            AVEncoderBitRateKey: 128_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVSampleRateConverterAudioQualityKey: AVAudioQuality.high.rawValue
        ]
    }
}

final class MicrophoneArchiveRecorder: NSObject, @unchecked Sendable {
    private struct ActiveRecording: @unchecked Sendable {
        let writer: AVAssetWriter
        let input: AVAssetWriterInput
        let outputURL: URL
        var sessionStarted = false
        var firstSampleTime: CMTime?
        var totalPausedDuration = CMTime.zero
        var pauseStartedAt: CMTime?
        var latestSampleTime: CMTime?
        var samplesWritten = 0
    }

    private let queue = DispatchQueue(label: "com.wondershow.microphone-archive-recorder")
    private let fileManager: FileManager
    private var session: AVCaptureSession?
    private var audioOutput: AVCaptureAudioDataOutput?
    private var activeRecording: ActiveRecording?
    private var isFinishing = false
    private var pendingStopCompletions: [@Sendable () -> Void] = []

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        super.init()
    }

    static func availableInputDevices() -> [AudioInputDeviceOption] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        let devices = discovery.devices
            .sorted { lhs, rhs in
                lhs.localizedName.localizedCaseInsensitiveCompare(rhs.localizedName) == .orderedAscending
            }
            .map { device in
                AudioInputDeviceOption(
                    id: device.uniqueID,
                    name: device.localizedName,
                    detail: device.modelID.isEmpty ? device.uniqueID : device.modelID,
                    isSystemDefault: false
                )
            }
        return [AudioInputDeviceOption.systemDefault] + devices
    }

    func startRecording(to outputURL: URL, deviceID: String? = nil) async throws {
        let granted = await requestPermissionIfNeeded()
        guard granted else {
            throw MicrophoneArchiveRecorderError.permissionDenied
        }

        try fileManager.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }

        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                do {
                    try self?.startOnQueue(outputURL: outputURL, deviceID: deviceID)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stopRecording() async {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                self?.stopOnQueue {
                    continuation.resume()
                } ?? continuation.resume()
            }
        }
    }

    func pauseRecording() {
        queue.async { [weak self] in
            guard var recording = self?.activeRecording,
                  recording.pauseStartedAt == nil else {
                return
            }
            recording.pauseStartedAt = recording.latestSampleTime ?? recording.firstSampleTime
            self?.activeRecording = recording
        }
    }

    func resumeRecording() {
        queue.async { [weak self] in
            guard var recording = self?.activeRecording,
                  let pauseStartedAt = recording.pauseStartedAt else {
                return
            }
            let latestSampleTime = recording.latestSampleTime ?? pauseStartedAt
            if latestSampleTime > pauseStartedAt {
                recording.totalPausedDuration = recording.totalPausedDuration + (latestSampleTime - pauseStartedAt)
            }
            recording.pauseStartedAt = nil
            self?.activeRecording = recording
        }
    }

    private func startOnQueue(outputURL: URL, deviceID: String?) throws {
        guard activeRecording == nil, !isFinishing else {
            throw MicrophoneArchiveRecorderError.cannotStart
        }
        stopOnQueue()

        let captureSession = AVCaptureSession()
        captureSession.beginConfiguration()
        let device = try audioDevice(for: deviceID)
        let input = try AVCaptureDeviceInput(device: device)
        guard captureSession.canAddInput(input) else {
            captureSession.commitConfiguration()
            throw MicrophoneArchiveRecorderError.cannotStart
        }
        captureSession.addInput(input)

        let output = AVCaptureAudioDataOutput()
        output.audioSettings = MicrophoneArchiveAudioSettings.capturePCM()
        output.setSampleBufferDelegate(self, queue: queue)
        guard captureSession.canAddOutput(output) else {
            captureSession.commitConfiguration()
            throw MicrophoneArchiveRecorderError.cannotStart
        }
        captureSession.addOutput(output)
        captureSession.commitConfiguration()

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        let writerInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: MicrophoneArchiveAudioSettings.writerAAC()
        )
        writerInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(writerInput) else {
            throw MicrophoneArchiveRecorderError.cannotStart
        }
        writer.add(writerInput)
        guard writer.startWriting() else {
            throw writer.error ?? MicrophoneArchiveRecorderError.cannotStart
        }

        session = captureSession
        audioOutput = output
        activeRecording = ActiveRecording(
            writer: writer,
            input: writerInput,
            outputURL: outputURL
        )
        captureSession.startRunning()
    }

    private func stopOnQueue(completion: (@Sendable () -> Void)? = nil) {
        if let completion {
            pendingStopCompletions.append(completion)
        }

        session?.stopRunning()
        session = nil
        audioOutput?.setSampleBufferDelegate(nil, queue: nil)
        audioOutput = nil

        guard let recording = activeRecording, !isFinishing else {
            finishPendingStopCompletions()
            return
        }

        isFinishing = true
        activeRecording = nil
        recording.input.markAsFinished()
        recording.writer.finishWriting { [weak self] in
            guard let recorder = self else {
                return
            }
            recorder.queue.async { [weak recorder] in
                recorder?.isFinishing = false
                recorder?.finishPendingStopCompletions()
            }
        }
    }

    private func finishPendingStopCompletions() {
        let completions = pendingStopCompletions
        pendingStopCompletions = []
        completions.forEach { $0() }
    }

    private func appendOnQueue(_ sampleBuffer: CMSampleBuffer) {
        guard var recording = activeRecording,
              recording.writer.status == .writing else {
            return
        }

        let sampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard sampleTime.isValid else {
            return
        }
        recording.latestSampleTime = sampleTime

        if recording.pauseStartedAt != nil {
            activeRecording = recording
            return
        }

        guard recording.input.isReadyForMoreMediaData else {
            activeRecording = recording
            return
        }

        if recording.firstSampleTime == nil {
            recording.firstSampleTime = sampleTime
            recording.writer.startSession(atSourceTime: sampleTime + Self.startupTransientSkip)
            recording.sessionStarted = true
            activeRecording = recording
            return
        }

        guard recording.sessionStarted,
              let firstSampleTime = recording.firstSampleTime,
              sampleTime - firstSampleTime >= Self.startupTransientSkip else {
            activeRecording = recording
            return
        }

        let sampleToAppend = retimed(sampleBuffer, subtracting: recording.totalPausedDuration) ?? sampleBuffer
        if recording.input.append(sampleToAppend) {
            recording.samplesWritten += 1
        }
        activeRecording = recording
    }

    private func retimed(_ sampleBuffer: CMSampleBuffer, subtracting offset: CMTime) -> CMSampleBuffer? {
        guard offset.isValid, offset > .zero else {
            return sampleBuffer
        }

        var timingCount: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &timingCount
        )
        guard timingCount > 0 else {
            return nil
        }

        var timing = Array(
            repeating: CMSampleTimingInfo(
                duration: .invalid,
                presentationTimeStamp: .invalid,
                decodeTimeStamp: .invalid
            ),
            count: timingCount
        )
        let status = CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: timingCount,
            arrayToFill: &timing,
            entriesNeededOut: nil
        )
        guard status == noErr else {
            return nil
        }

        for index in timing.indices {
            if timing[index].presentationTimeStamp.isValid {
                timing[index].presentationTimeStamp = timing[index].presentationTimeStamp - offset
            }
            if timing[index].decodeTimeStamp.isValid {
                timing[index].decodeTimeStamp = timing[index].decodeTimeStamp - offset
            }
        }

        var retimedBuffer: CMSampleBuffer?
        let copyStatus = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: timingCount,
            sampleTimingArray: &timing,
            sampleBufferOut: &retimedBuffer
        )
        guard copyStatus == noErr else {
            return nil
        }
        return retimedBuffer
    }

    private func audioDevice(for deviceID: String?) throws -> AVCaptureDevice {
        let selectedID = deviceID == AudioInputDeviceOption.systemDefault.id ? nil : deviceID
        if let selectedID, !selectedID.isEmpty {
            guard let device = AVCaptureDevice(uniqueID: selectedID) else {
                throw MicrophoneArchiveRecorderError.deviceUnavailable
            }
            return device
        }

        if let defaultDevice = AVCaptureDevice.default(for: .audio) {
            return defaultDevice
        }

        guard let firstDevice = Self.availableInputDevices().first(where: { !$0.isSystemDefault }),
              let device = AVCaptureDevice(uniqueID: firstDevice.id) else {
            throw MicrophoneArchiveRecorderError.deviceUnavailable
        }
        return device
    }

    private func requestPermissionIfNeeded() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private static let startupTransientSkip = CMTime(seconds: 0.12, preferredTimescale: 48_000)
}

extension MicrophoneArchiveRecorder: AVCaptureAudioDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let sampleBufferBox = MicrophoneSampleBuffer(sampleBuffer)
        queue.async { [weak self, sampleBufferBox] in
            self?.appendOnQueue(sampleBufferBox.value)
        }
    }
}
