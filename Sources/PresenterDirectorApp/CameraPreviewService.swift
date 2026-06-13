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
    @Published private(set) var detectedHandShapes = "未检测"
    @Published var gestureControlEnabled = false
    @Published var gestureCalibrationProfile = GestureProfile.default

    var onGestureRecognized: ((GestureIntent) -> Void)?

    private let sessionBox = CaptureSessionBox()
    private let sessionQueue = DispatchQueue(label: "com.lingyan.camera-session")
    private let handPoseRequest = VNDetectHumanHandPoseRequest()
    private var gestureSamples: [TimedHandFrame] = []
    private var lastAcceptedGestureTime = Date.distantPast
    private var connectionAttemptID = UUID()

    var session: AVCaptureSession {
        sessionBox.session
    }

    override init() {
        handPoseRequest.maximumHandCount = 2
        super.init()
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
            let observations = Array((handPoseRequest.results ?? []).prefix(2))
            guard !observations.isEmpty else {
                gestureStatus = .searching
                return
            }

            let points = try observations
                .map { try handAnchorPoint(from: $0) }
                .sorted { $0.x < $1.x }
            detectedHandShapes = points.map(\.shape.label).joined(separator: "、")
            appendGestureFrame(points)
            gestureStatus = .tracking
        } catch {
            gestureStatus = .failed
        }
    }

    private func handAnchorPoint(from observation: VNHumanHandPoseObservation) throws -> HandPoint {
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
        return HandPoint(x: Double(x), y: Double(y), shape: classifyHandShape(points))
    }

    private func classifyHandShape(_ points: [VNHumanHandPoseObservation.JointName: VNRecognizedPoint]) -> HandShape {
        let thumb = isExtended(.thumbTip, base: .thumbCMC, points: points, ratio: 1.15)
        let index = isExtended(.indexTip, base: .indexMCP, points: points)
        let middle = isExtended(.middleTip, base: .middleMCP, points: points)
        let ring = isExtended(.ringTip, base: .ringMCP, points: points)
        let little = isExtended(.littleTip, base: .littleMCP, points: points)

        if thumb, index, !middle, !ring, !little {
            return .lShape
        }

        if index, !ring, !little {
            return .fingerGun
        }

        return .natural
    }

    private func isExtended(
        _ tip: VNHumanHandPoseObservation.JointName,
        base: VNHumanHandPoseObservation.JointName,
        points: [VNHumanHandPoseObservation.JointName: VNRecognizedPoint],
        ratio: Double = 1.28
    ) -> Bool {
        guard
            let wrist = points[.wrist],
            let tipPoint = points[tip],
            let basePoint = points[base],
            wrist.confidence > 0.35,
            tipPoint.confidence > 0.35,
            basePoint.confidence > 0.35
        else {
            return false
        }

        let tipDistance = distance(wrist.location, tipPoint.location)
        let baseDistance = distance(wrist.location, basePoint.location)
        return tipDistance > baseDistance * ratio
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(a.x - b.x)
        let dy = Double(a.y - b.y)
        return (dx * dx + dy * dy).squareRoot()
    }

    private func appendGestureFrame(_ points: [HandPoint]) {
        let now = Date()
        gestureSamples.append(TimedHandFrame(points: points, timestamp: now))
        gestureSamples = gestureSamples.filter { now.timeIntervalSince($0.timestamp) <= 0.75 }

        guard
            let first = gestureSamples.first,
            let last = gestureSamples.last,
            now.timeIntervalSince(lastAcceptedGestureTime) >= 0.85
        else {
            return
        }

        let duration = Int(last.timestamp.timeIntervalSince(first.timestamp) * 1_000)
        let recognizer = FrameGestureRecognizer(profile: gestureCalibrationProfile)
        guard let gesture = recognizer.recognize(
            start: first.points,
            end: last.points,
            durationMilliseconds: duration
        ) else {
            return
        }

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

private struct TimedHandFrame {
    let points: [HandPoint]
    let timestamp: Date
}

private enum GestureFrameError: Error {
    case missingHandPoint
}

private extension HandShape {
    var label: String {
        switch self {
        case .unknown:
            return "未知"
        case .natural:
            return "自然手"
        case .fingerGun:
            return "指枪"
        case .lShape:
            return "八字"
        }
    }
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
