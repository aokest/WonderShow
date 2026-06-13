@preconcurrency import AVFoundation
@preconcurrency import Vision
import PresenterDirector
import SwiftUI

final class CaptureSessionBox: @unchecked Sendable {
    let session = AVCaptureSession()
    let videoOutput = AVCaptureVideoDataOutput()
    let videoQueue = DispatchQueue(label: "com.lingyan.camera-frames")
}

@MainActor
final class CameraPreviewService: NSObject, ObservableObject {
    @Published private(set) var status: CameraStatus = .idle
    @Published private(set) var activeDeviceName: String = "未连接"
    @Published private(set) var gestureStatus: GestureStatus = .idle
    @Published private(set) var lastGesture: GestureIntent?
    @Published var gestureControlEnabled = false
    @Published var gestureCalibrationProfile = GestureProfile.default

    var onGestureRecognized: ((GestureIntent) -> Void)?

    private let sessionBox = CaptureSessionBox()
    private let sessionQueue = DispatchQueue(label: "com.lingyan.camera-session")
    private let handPoseRequest = VNDetectHumanHandPoseRequest()
    private var gestureSamples: [TimedHandPoint] = []
    private var lastAcceptedGestureTime = Date.distantPast
    private var connectionAttemptID = UUID()

    var session: AVCaptureSession {
        sessionBox.session
    }

    func start() {
        connectionAttemptID = UUID()
        let attemptID = connectionAttemptID
        status = .connecting
        scheduleConnectionTimeout(for: attemptID)

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    granted ? self?.configureAndStart() : self?.setPermissionDenied()
                }
            }
        case .denied, .restricted:
            setPermissionDenied()
        @unknown default:
            setPermissionDenied()
        }
    }

    func stop() {
        let sessionBox = sessionBox
        sessionQueue.async {
            if sessionBox.session.isRunning {
                sessionBox.session.stopRunning()
            }
        }
    }

    private func configureAndStart() {
        status = .connecting
        let attemptID = connectionAttemptID

        let sessionBox = sessionBox
        sessionQueue.async { [weak self] in
            let selectedDevice = Self.preferredCamera()
            guard let selectedDevice else {
                Task { @MainActor in
                    self?.status = .missingDevice
                    self?.activeDeviceName = "未找到摄像头"
                }
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: selectedDevice)
                let session = sessionBox.session

                session.beginConfiguration()
                session.sessionPreset = .high
                session.inputs.forEach { session.removeInput($0) }
                session.outputs.forEach { session.removeOutput($0) }
                if session.canAddInput(input) {
                    session.addInput(input)
                }
                self?.configureVideoOutput(on: session, sessionBox: sessionBox)
                session.commitConfiguration()
                session.startRunning()

                Task { @MainActor in
                    guard self?.connectionAttemptID == attemptID else { return }
                    self?.activeDeviceName = selectedDevice.localizedName
                    self?.status = .running
                }
            } catch {
                Task { @MainActor in
                    guard self?.connectionAttemptID == attemptID else { return }
                    self?.status = .failed(error.localizedDescription)
                    self?.activeDeviceName = selectedDevice.localizedName
                }
            }
        }
    }

    private func scheduleConnectionTimeout(for attemptID: UUID) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            guard connectionAttemptID == attemptID, status == .connecting else { return }
            status = .failed("连接超时，请确认 Pocket 3 已进入摄像头模式，或重新插拔后再试。")
        }
    }

    private func setPermissionDenied() {
        status = .permissionDenied
        activeDeviceName = "需要摄像头权限"
    }

    private nonisolated static func preferredCamera() -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )

        return discovery.devices.first { device in
            let name = device.localizedName.lowercased()
            return name.contains("osmo") || name.contains("pocket")
        } ?? discovery.devices.first
    }

    private nonisolated func configureVideoOutput(on session: AVCaptureSession, sessionBox: CaptureSessionBox) {
        sessionBox.videoOutput.alwaysDiscardsLateVideoFrames = true
        sessionBox.videoOutput.setSampleBufferDelegate(self, queue: sessionBox.videoQueue)
        if session.canAddOutput(sessionBox.videoOutput) {
            session.addOutput(sessionBox.videoOutput)
        }
    }
}

extension CameraPreviewService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        Task { @MainActor in
            guard gestureControlEnabled else { return }
            processGestureFrame(sampleBuffer)
        }
    }

    private func processGestureFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        do {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            try handler.perform([handPoseRequest])
            guard let observation = handPoseRequest.results?.first else {
                gestureStatus = .searching
                return
            }

            let point = try handAnchorPoint(from: observation)
            appendGesturePoint(point)
            gestureStatus = .tracking
        } catch {
            gestureStatus = .failed
        }
    }

    private func handAnchorPoint(from observation: VNHumanHandPoseObservation) throws -> CGPoint {
        let points = try observation.recognizedPoints(.all)
        let candidates = [
            points[.wrist],
            points[.middleMCP],
            points[.indexMCP],
            points[.ringMCP]
        ].compactMap { $0 }.filter { $0.confidence > 0.35 }

        guard !candidates.isEmpty else {
            throw GestureFrameError.missingHandPoint
        }

        let x = candidates.map(\.location.x).reduce(0, +) / CGFloat(candidates.count)
        let y = candidates.map(\.location.y).reduce(0, +) / CGFloat(candidates.count)
        return CGPoint(x: x, y: y)
    }

    private func appendGesturePoint(_ point: CGPoint) {
        let now = Date()
        gestureSamples.append(TimedHandPoint(point: point, timestamp: now))
        gestureSamples = gestureSamples.filter { now.timeIntervalSince($0.timestamp) <= 0.75 }

        guard
            let first = gestureSamples.first,
            let last = gestureSamples.last,
            now.timeIntervalSince(lastAcceptedGestureTime) >= 0.85
        else {
            return
        }

        let duration = Int(last.timestamp.timeIntervalSince(first.timestamp) * 1_000)
        let motion = GestureMotion(
            horizontalTravel: Double(last.point.x - first.point.x),
            verticalTravel: Double(last.point.y - first.point.y),
            durationMilliseconds: duration
        )

        let recognizer = MotionGestureRecognizer(profile: gestureCalibrationProfile)
        guard let gesture = recognizer.recognize(motion) else { return }

        lastAcceptedGestureTime = now
        lastGesture = gesture
        gestureSamples.removeAll()
        onGestureRecognized?(gesture)
    }
}

enum GestureStatus: String {
    case idle = "未开启"
    case searching = "寻找手势"
    case tracking = "正在跟踪"
    case failed = "识别异常"
}

private struct TimedHandPoint {
    let point: CGPoint
    let timestamp: Date
}

private enum GestureFrameError: Error {
    case missingHandPoint
}

enum CameraStatus: Equatable {
    case idle
    case connecting
    case running
    case permissionDenied
    case missingDevice
    case failed(String)

    var label: String {
        switch self {
        case .idle:
            return "未启动"
        case .connecting:
            return "正在连接"
        case .running:
            return "画面已接入"
        case .permissionDenied:
            return "缺少摄像头权限"
        case .missingDevice:
            return "未发现摄像头"
        case .failed:
            return "连接失败"
        }
    }

    var detail: String {
        switch self {
        case .failed(let message):
            return message
        default:
            return label
        }
    }
}

struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewHostView {
        let view = PreviewHostView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateNSView(_ nsView: PreviewHostView, context: Context) {
        nsView.previewLayer.session = session
    }
}

final class PreviewHostView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = AVCaptureVideoPreviewLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer = AVCaptureVideoPreviewLayer()
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
