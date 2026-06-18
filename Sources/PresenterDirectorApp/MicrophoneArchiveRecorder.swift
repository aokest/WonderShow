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

final class MicrophoneArchiveRecorder: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.lingyan.microphone-archive-recorder")
    private let fileManager: FileManager
    private var session: AVCaptureSession?
    private var audioOutput: AVCaptureAudioFileOutput?
    private var recordingDelegate: MicrophoneArchiveRecordingDelegate?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
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
            guard self?.audioOutput?.isRecording == true,
                  self?.audioOutput?.isRecordingPaused == false else {
                return
            }
            self?.audioOutput?.pauseRecording()
        }
    }

    func resumeRecording() {
        queue.async { [weak self] in
            guard self?.audioOutput?.isRecording == true,
                  self?.audioOutput?.isRecordingPaused == true else {
                return
            }
            self?.audioOutput?.resumeRecording()
        }
    }

    private func startOnQueue(outputURL: URL, deviceID: String?) throws {
        guard audioOutput?.isRecording != true else {
            throw MicrophoneArchiveRecorderError.cannotStart
        }
        stopOnQueue()

        let session = AVCaptureSession()
        session.beginConfiguration()
        let device = try audioDevice(for: deviceID)
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw MicrophoneArchiveRecorderError.cannotStart
        }
        session.addInput(input)

        let output = AVCaptureAudioFileOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw MicrophoneArchiveRecorderError.cannotStart
        }
        session.addOutput(output)
        session.commitConfiguration()

        let delegate = MicrophoneArchiveRecordingDelegate()
        self.session = session
        self.audioOutput = output
        self.recordingDelegate = delegate

        session.startRunning()
        output.startRecording(to: outputURL, outputFileType: .m4a, recordingDelegate: delegate)
        guard output.isRecording else {
            session.stopRunning()
            self.session = nil
            self.audioOutput = nil
            self.recordingDelegate = nil
            throw MicrophoneArchiveRecorderError.cannotStart
        }
    }

    private func stopOnQueue(completion: (@Sendable () -> Void)? = nil) {
        if audioOutput?.isRecording == true, let delegate = recordingDelegate {
            delegate.onFinish = { [weak self, completion] in
                guard let recorder = self else {
                    completion?()
                    return
                }
                recorder.queue.async { [weak recorder, completion] in
                    recorder?.session?.stopRunning()
                    recorder?.audioOutput = nil
                    recorder?.recordingDelegate = nil
                    recorder?.session = nil
                    completion?()
                }
            }
            audioOutput?.stopRecording()
            return
        }
        session?.stopRunning()
        audioOutput = nil
        recordingDelegate = nil
        session = nil
        completion?()
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
}

private final class MicrophoneArchiveRecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    var onFinish: (@Sendable () -> Void)?

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: (any Error)?
    ) {
        onFinish?()
        onFinish = nil
    }
}
