import AppKit
@preconcurrency import AVFoundation
@preconcurrency import Vision
import Foundation
import WonderShow
import SwiftUI

final class CaptureSessionBox: @unchecked Sendable {
    static let previewFrameInterval: TimeInterval = 1 / 18

    let session = AVCaptureSession()
    let videoOutput = AVCaptureVideoDataOutput()
    let videoQueue = DispatchQueue(label: "com.wondershow.camera-frames")
    let previewContext = CIContext()
    let previewPipeline = PresenterEnhancementPipeline()
    var lastPreviewFramePublishedAt = Date.distantPast
    var previewEffects = PresenterVideoEffects.default
    var latestPortraitFrame: MediaPipePortraitFrame?
    var latestPortraitSegmentation: MediaPipePortraitSegmentationMask?
}

private struct CameraGestureRuntimeSnapshot: Sendable {
    let gestureControlEnabled: Bool
    let isMediaPipeAvailable: Bool
    let mediaPipeInferenceInFlight: Bool
    let lastMediaPipeFrameTimestampMilliseconds: Int
}

enum CameraPreviewMediaPipePolicy {
    static func requiresPortraitInference(for effects: PresenterVideoEffects) -> Bool {
        effects.advancedBeautyEnabled
            || effects.portraitSegmentationEnabled
            || effects.faceLandmarkBeautyEnabled
            || effects.emojiFaceReplacementEnabled
            || effects.backgroundBlur > 0
            || effects.backgroundEffect != .none
    }

    static func shouldRunMediaPipe(
        gestureControlEnabled: Bool,
        effects: PresenterVideoEffects
    ) -> Bool {
        gestureControlEnabled || requiresPortraitInference(for: effects)
    }

    static func shouldUseSyntheticPortraitFallbackForLiveMonitor(_ effects: PresenterVideoEffects) -> Bool {
        false
    }

    static func shouldRunSubjectAwareBeautyDetectionForLiveMonitor(_ effects: PresenterVideoEffects) -> Bool {
        false
    }
}

private final class CameraGestureRuntimeState: @unchecked Sendable {
    private let lock = NSLock()
    private var gestureControlEnabled = false
    private var isMediaPipeAvailable = false
    private var mediaPipeInferenceInFlight = false
    private var lastMediaPipeFrameTimestampMilliseconds = 0

    func update(
        gestureControlEnabled: Bool? = nil,
        isMediaPipeAvailable: Bool? = nil,
        mediaPipeInferenceInFlight: Bool? = nil,
        lastMediaPipeFrameTimestampMilliseconds: Int? = nil
    ) {
        lock.withLock {
            if let gestureControlEnabled {
                self.gestureControlEnabled = gestureControlEnabled
            }
            if let isMediaPipeAvailable {
                self.isMediaPipeAvailable = isMediaPipeAvailable
            }
            if let mediaPipeInferenceInFlight {
                self.mediaPipeInferenceInFlight = mediaPipeInferenceInFlight
            }
            if let lastMediaPipeFrameTimestampMilliseconds {
                self.lastMediaPipeFrameTimestampMilliseconds = lastMediaPipeFrameTimestampMilliseconds
            }
        }
    }

    func snapshot() -> CameraGestureRuntimeSnapshot {
        lock.withLock {
            CameraGestureRuntimeSnapshot(
                gestureControlEnabled: gestureControlEnabled,
                isMediaPipeAvailable: isMediaPipeAvailable,
                mediaPipeInferenceInFlight: mediaPipeInferenceInFlight,
                lastMediaPipeFrameTimestampMilliseconds: lastMediaPipeFrameTimestampMilliseconds
            )
        }
    }
}

struct CameraInputDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String

    static let automatic = CameraInputDevice(
        id: "automatic",
        name: "自动选择最佳输入",
        detail: "优先外接跟踪相机，其次内置摄像头"
    )

    init(id: String, name: String, detail: String) {
        self.id = id
        self.name = name
        self.detail = detail
    }

    init(device: AVCaptureDevice) {
        id = device.uniqueID
        name = device.localizedName
        detail = Self.detail(for: device)
    }

    private static func detail(for device: AVCaptureDevice) -> String {
        switch device.deviceType {
        case .external:
            return "外接/UVC 输入"
        case .builtInWideAngleCamera:
            return "Mac 内置摄像头"
        case .continuityCamera:
            return "连续互通摄像头"
        case .deskViewCamera:
            return "桌面视角摄像头"
        default:
            return "系统视频输入"
        }
    }
}

@MainActor
final class CameraPreviewService: NSObject, ObservableObject {
    @Published private(set) var status: CameraStatus = .idle
    @Published private(set) var activeDeviceName: String = "未连接"
    @Published private(set) var availableDevices: [CameraInputDevice] = []
    @Published private(set) var deviceScanSummary = "尚未扫描"
    @Published var selectedDeviceID: String = CameraInputDevice.automatic.id
    @Published private(set) var gestureStatus: GestureStatus = .idle
    @Published private(set) var lastGesture: GestureIntent?
    @Published private(set) var detectedHandShapes = "未检测"
    @Published private(set) var latestHandPoints: [HandPoint] = []
    @Published private(set) var latestHandLandmarkPoints: [HandPoint] = []
    @Published private(set) var calibrationStatus = "未校准"
    @Published private(set) var calibrationProgress: Double = 0
    @Published private(set) var zoomScale: Double = 1
    @Published private(set) var panX: Double = 0
    @Published private(set) var panY: Double = 0
    @Published private(set) var gestureGuidance = "先把手放到中央热区"
    @Published private(set) var gestureSessionLabel = "待命中"
    @Published private(set) var gestureEngineLabel = "Vision 增强版"
    @Published private(set) var gestureZoneLabel = "热区待进入"
    @Published private(set) var gestureModeLabel = "空闲"
    @Published private(set) var latestPreviewImage: CGImage?
    @Published var gestureControlEnabled = false {
        didSet {
            gestureRuntimeState.update(gestureControlEnabled: gestureControlEnabled)
        }
    }
    @Published var gestureCalibrationProfile = GestureProfile.default

    var onGestureRecognized: ((GestureIntent) -> Void)?
    var onGestureRecognizedWithMotion: ((GestureIntent, Double?) -> Void)?
    var onZoomChanged: ((Double) -> Void)?
    var onPanChanged: ((Double, Double) -> Void)?

    private let cameraArchiveRecorder = CameraArchiveRecorder()
    private let sessionBox = CaptureSessionBox()
    private let sessionQueue = DispatchQueue(label: "com.wondershow.camera-session")
    private let activationZone = GestureActivationZone.presentationDefault
    private let unlockRecognizer = GestureHoldRecognizer(requiredShape: .openPalm)
    private let mediaPipeSidecar = MediaPipeSidecarClient()
    private let gestureRuntimeState = CameraGestureRuntimeState()
    private var gestureSamples: [GestureFrameSnapshot] = []
    private var connectionAttemptID = UUID()
    private var personalizedLibrary = PersonalizedGestureLibrary()
    private var calibrationCapture: CalibrationCapture?
    private var continuousZoomTracker = ContinuousZoomTracker()
    private var gestureModeCoordinator = GestureModeCoordinator()
    private let discreteGestureSuppressionEvaluator = DiscreteGestureSuppressionEvaluator()
    private let swipeReadyDetector = SwipeReadyDetector()
    private let twoHandZoomPoseDetector = TwoHandZoomPoseDetector()
    private var gestureSessionCoordinator = GestureSessionCoordinator()
    private var smoothedPoints: [HandPoint] = []
    private var latestHandGeometries: [MediaPipeHandGeometry] = []
    private var isMediaPipeAvailable = false
    private var mediaPipeInferenceInFlight = false
    private var lastMediaPipeFrameTimestampMilliseconds = 0
    private var mediaPipeEmptyFrameStreak = 0
    private var mediaPipeLaunchAttempted = false
    private var mediaPipeSidecarProcess: Process?
    private let mediaPipeMinimumFrameIntervalMilliseconds = 60

    private var isPanning = false
    private var panBaselinePoint: HandPoint?
    private var panBaselineX: Double = 0
    private var panBaselineY: Double = 0
    private var lastPanSentAtMilliseconds = 0
    private var singleHandZoomPulseRecognizer = SingleHandZoomPulseRecognizer()
    private var zoomPoseStreak = 0
    private var lastReportedGestureMode: GestureMode = .idle
    private var swipeReturnLockGesture: GestureIntent?
    private var swipeReturnLockUntilMilliseconds = 0
    private var isCameraArchiveRecording = false

    var session: AVCaptureSession {
        sessionBox.session
    }

    func updatePreviewEffects(_ effects: PresenterVideoEffects) {
        let sessionBox = sessionBox
        sessionBox.videoQueue.async {
            sessionBox.previewEffects = effects
        }
    }

    override init() {
        super.init()
        loadPersonalizedLibrary()
        refreshAvailableDevices()
        refreshGestureEngineAvailability()
    }

    private func setMediaPipeAvailable(_ isAvailable: Bool) {
        isMediaPipeAvailable = isAvailable
        gestureRuntimeState.update(isMediaPipeAvailable: isAvailable)
    }

    private func setMediaPipeInferenceInFlight(_ isInFlight: Bool) {
        mediaPipeInferenceInFlight = isInFlight
        gestureRuntimeState.update(mediaPipeInferenceInFlight: isInFlight)
    }

    private func setLastMediaPipeFrameTimestampMilliseconds(_ timestampMilliseconds: Int) {
        lastMediaPipeFrameTimestampMilliseconds = timestampMilliseconds
        gestureRuntimeState.update(lastMediaPipeFrameTimestampMilliseconds: timestampMilliseconds)
    }

    var cameraAuthorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    func start() {
        refreshAvailableDevices()
        refreshGestureEngineAvailability()
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

    func requestCameraAccessOrOpenSettings() {
        refreshAvailableDevices()

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            start()
        case .notDetermined:
            status = .connecting
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    granted ? self?.start() : self?.setPermissionDenied()
                }
            }
        case .denied, .restricted:
            setPermissionDenied()
            openCameraPrivacySettings()
        @unknown default:
            setPermissionDenied()
            openCameraPrivacySettings()
        }
    }

    func openCameraPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func stop() {
        resetGestureTracking()
        latestPreviewImage = nil
        if !isCameraArchiveRecording {
            stopCameraArchiveRecording()
        }
        stopCaptureSession()
    }

    private func stopCaptureSession() {
        let sessionBox = sessionBox
        sessionQueue.async {
            if sessionBox.session.isRunning {
                sessionBox.session.stopRunning()
            }
        }
    }

    func startCameraArchiveRecording(to outputURL: URL) throws {
        try cameraArchiveRecorder.startRecording(to: outputURL)
        isCameraArchiveRecording = true
    }

    func pauseCameraArchiveRecording() {
        cameraArchiveRecorder.pauseRecording()
    }

    func resumeCameraArchiveRecording() {
        cameraArchiveRecorder.resumeRecording()
    }

    func stopCameraArchiveRecording() {
        isCameraArchiveRecording = false
        cameraArchiveRecorder.stopRecording()
    }

    func stopCameraArchiveRecording() async {
        isCameraArchiveRecording = false
        await withCheckedContinuation { continuation in
            cameraArchiveRecorder.stopRecording { _ in
                continuation.resume()
            }
        }
    }

    func selectDevice(id: String) {
        selectedDeviceID = id
        start()
    }

    func refreshAvailableDevices() {
        let devices = Self.discoverCaptureDevices()
        var nextDevices = [CameraInputDevice.automatic]
        nextDevices.append(contentsOf: devices.map(CameraInputDevice.init(device:)))
        availableDevices = nextDevices
        deviceScanSummary = devices.isEmpty
            ? "系统未返回任何视频输入"
            : devices.map { "\($0.localizedName) [\($0.deviceType.rawValue)]" }.joined(separator: "；")

        if !nextDevices.contains(where: { $0.id == selectedDeviceID }) {
            selectedDeviceID = CameraInputDevice.automatic.id
        }
    }

    func refreshDevicesAndRestart() {
        resetGestureTracking()
        latestPreviewImage = nil
        if !isCameraArchiveRecording {
            stopCameraArchiveRecording()
        }
        stopCaptureSession()
        refreshAvailableDevices()
        start()
    }

    func beginCalibrationCapture(intent: GestureIntent, sampleIndex: Int) {
        calibrationCapture = CalibrationCapture(intent: intent, sampleIndex: sampleIndex, frames: [])
        calibrationProgress = 0
        calibrationStatus = "\(intent.calibrationLabel) 第 \(sampleIndex) 次：请做动作"
    }

    @discardableResult
    func finishCalibrationCapture() -> Bool {
        guard let capture = calibrationCapture else {
            calibrationStatus = "未开始采样"
            return false
        }

        let usableFrames = capture.frames.suffix(24)
        let template = GestureTemplate(
            intent: capture.intent,
            frames: Array(usableFrames),
            createdAtMilliseconds: usableFrames.last?.timestampMilliseconds ?? 0
        )
        calibrationCapture = nil

        guard template.isUsable else {
            calibrationStatus = "\(capture.intent.calibrationLabel) 第 \(capture.sampleIndex) 次采样不足"
            calibrationProgress = 0
            return false
        }

        personalizedLibrary.add(template)
        savePersonalizedLibrary()
        calibrationStatus = "\(capture.intent.calibrationLabel) 第 \(capture.sampleIndex) 次已保存"
        calibrationProgress = 1
        return true
    }

    func autoCaptureCalibration(intent: GestureIntent, sampleIndex: Int) async -> Bool {
        beginCalibrationCapture(intent: intent, sampleIndex: sampleIndex)
        let ticks = 12
        for tick in 1...ticks {
            try? await Task.sleep(for: .milliseconds(180))
            calibrationProgress = Double(tick) / Double(ticks)
        }
        return finishCalibrationCapture()
    }

    private func configureAndStart() {
        status = .connecting
        let attemptID = connectionAttemptID
        let selectedDeviceID = selectedDeviceID

        let sessionBox = sessionBox
        sessionQueue.async { [weak self] in
            let selectedDevice = Self.preferredCamera(selectedDeviceID: selectedDeviceID)
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
            status = .failed("连接超时，请确认摄像头已开启并处于可采集模式，或重新插拔后再试。")
        }
    }

    private func setPermissionDenied() {
        status = .permissionDenied
        activeDeviceName = "需要摄像头权限"
    }

    /// Checks whether the MediaPipe sidecar is reachable and updates the visible engine label.
    private func refreshGestureEngineAvailability() {
        Task { @MainActor in
            var health = await mediaPipeSidecar.health()
            if !isTrustedMediaPipeHealth(health) {
                launchMediaPipeSidecarIfPossible()
                try? await Task.sleep(for: .milliseconds(450))
                health = await mediaPipeSidecar.health()
            }
            setMediaPipeAvailable(isTrustedMediaPipeHealth(health))
            gestureEngineLabel = isMediaPipeAvailable
                ? GestureEngineBackend.mediaPipeSidecar.rawValue
                : GestureEngineBackend.visionLegacy.rawValue
        }
    }

    private func isTrustedMediaPipeHealth(_ health: MediaPipeSidecarHealth?) -> Bool {
        health?.ok == true && health?.authRequired == true
    }

    /// Attempts to launch the local MediaPipe sidecar from the project scripts when it is not already running.
    /// - Important: This only runs once per app session and only when the project-root scripts exist.
    private func launchMediaPipeSidecarIfPossible() {
        guard !mediaPipeLaunchAttempted else { return }
        mediaPipeLaunchAttempted = true

        guard let projectRootURL = mediaPipeProjectRootURL() else { return }
        let scriptURL = projectRootURL.appendingPathComponent("scripts/run-mediapipe-sidecar.sh")
        let venvURL = projectRootURL.appendingPathComponent(".venv-mediapipe")
        guard FileManager.default.fileExists(atPath: scriptURL.path),
              FileManager.default.fileExists(atPath: venvURL.path) else {
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        process.currentDirectoryURL = projectRootURL
        WonderShowLocalSecurity.applyTokenEnvironment(to: process)
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            mediaPipeSidecarProcess = process
        } catch {
            mediaPipeSidecarProcess = nil
        }
    }

    /// Resolves the project root so the app can find `scripts/run-mediapipe-sidecar.sh` after being launched from the app bundle.
    /// - Returns: The project root URL when the expected scripts directory exists, otherwise `nil`.
    private func mediaPipeProjectRootURL() -> URL? {
        let bundleRoot = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let currentRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [bundleRoot, currentRoot]

        for candidate in candidates {
            let scriptsURL = candidate.appendingPathComponent("scripts")
            if FileManager.default.fileExists(atPath: scriptsURL.path) {
                return candidate
            }
        }
        return nil
    }

    private nonisolated static func preferredCamera(selectedDeviceID: String) -> AVCaptureDevice? {
        let devices = discoverCaptureDevices()
        if selectedDeviceID != CameraInputDevice.automatic.id,
           let selected = devices.first(where: { $0.uniqueID == selectedDeviceID }) {
            return selected
        }

        return devices.first { device in
            let name = device.localizedName.lowercased()
            return name.contains("osmo") || name.contains("pocket")
        } ?? devices.first
    }

    private nonisolated static func discoverCaptureDevices() -> [AVCaptureDevice] {
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .external,
            .builtInWideAngleCamera,
            .continuityCamera,
            .deskViewCamera
        ]
        return AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        ).devices
            .sorted { lhs, rhs in
                devicePriority(lhs) < devicePriority(rhs)
            }
    }

    private nonisolated static func devicePriority(_ device: AVCaptureDevice) -> Int {
        let name = device.localizedName.lowercased()
        if name.contains("osmo") || name.contains("pocket") || name.contains("dji") {
            return 0
        }
        if device.deviceType == .external {
            return 1
        }
        if device.deviceType == .continuityCamera || device.deviceType == .deskViewCamera {
            return 2
        }
        return 3
    }

    private nonisolated func processGestureFrameFromCaptureQueue(
        _ sampleBuffer: CMSampleBuffer,
        timestampMilliseconds: Int
    ) {
        let snapshot = gestureRuntimeState.snapshot()
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let previewEffects = sessionBox.previewEffects
        guard CameraPreviewMediaPipePolicy.shouldRunMediaPipe(
            gestureControlEnabled: snapshot.gestureControlEnabled,
            effects: previewEffects
        ) else { return }

        if snapshot.isMediaPipeAvailable {
            guard !snapshot.mediaPipeInferenceInFlight else { return }
            guard timestampMilliseconds - snapshot.lastMediaPipeFrameTimestampMilliseconds >= mediaPipeMinimumFrameIntervalMilliseconds else {
                return
            }

            if let jpegData = MediaPipeSidecarClient.jpegData(from: pixelBuffer) {
                Task { @MainActor [weak self, jpegData, timestampMilliseconds] in
                    self?.processGestureFrameWithMediaPipe(
                        jpegData: jpegData,
                        timestampMilliseconds: timestampMilliseconds
                    )
                }
                return
            }
        }

        guard snapshot.gestureControlEnabled else { return }

        do {
            let rawPoints = try Self.visionHandPoints(from: pixelBuffer)
            Task { @MainActor [weak self, rawPoints, timestampMilliseconds] in
                self?.processVisionHandPoints(
                    rawPoints,
                    timestampMilliseconds: timestampMilliseconds
                )
            }
        } catch {
            Task { @MainActor [weak self] in
                self?.processVisionFailure()
            }
        }
    }

    private nonisolated func publishPreviewFrameIfNeeded(_ sampleBuffer: CMSampleBuffer) {
        autoreleasepool {
            let now = Date()
            guard now.timeIntervalSince(sessionBox.lastPreviewFramePublishedAt) >= CaptureSessionBox.previewFrameInterval else {
                return
            }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                return
            }
            let image = CIImage(cvPixelBuffer: pixelBuffer)
            let effects = sessionBox.previewEffects
            let previewImage = sessionBox.previewPipeline.apply(
                to: image,
                effects: effects,
                targetRect: image.extent,
                portrait: sessionBox.latestPortraitFrame,
                segmentation: sessionBox.latestPortraitSegmentation,
                fallbackPortrait: CameraPreviewMediaPipePolicy.shouldUseSyntheticPortraitFallbackForLiveMonitor(effects),
                allowSubjectAwareBeautyDetection: CameraPreviewMediaPipePolicy
                    .shouldRunSubjectAwareBeautyDetectionForLiveMonitor(effects)
            )
            let displayImage: CIImage
            let displayExtent: CGRect
            if let contentRect = CameraFrameMatteDetector.contentRect(in: pixelBuffer) {
                displayImage = previewImage
                    .cropped(to: contentRect)
                    .transformed(by: CGAffineTransform(translationX: -contentRect.minX, y: -contentRect.minY))
                displayExtent = displayImage.extent
            } else {
                displayImage = previewImage
                displayExtent = image.extent
            }
            guard let cgImage = sessionBox.previewContext.createCGImage(displayImage, from: displayExtent) else {
                return
            }
            sessionBox.lastPreviewFramePublishedAt = now
            Task { @MainActor [weak self, cgImage] in
                self?.latestPreviewImage = cgImage
            }
        }
    }

    private nonisolated func configureVideoOutput(on session: AVCaptureSession, sessionBox: CaptureSessionBox) {
        sessionBox.videoOutput.alwaysDiscardsLateVideoFrames = true
        sessionBox.videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
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
        cameraArchiveRecorder.append(sampleBuffer)
        publishPreviewFrameIfNeeded(sampleBuffer)

        let timestampMilliseconds = Int(Date().timeIntervalSince1970 * 1_000)
        processGestureFrameFromCaptureQueue(sampleBuffer, timestampMilliseconds: timestampMilliseconds)
    }

    /// Sends an encoded frame to the local MediaPipe sidecar and applies the returned landmarks.
    /// - Parameters:
    ///   - jpegData: Captured camera frame encoded on the capture queue.
    ///   - timestampMilliseconds: Frame timestamp used for ordering and recognition windows.
    private func processGestureFrameWithMediaPipe(
        jpegData: Data,
        timestampMilliseconds: Int
    ) {
        let shouldRunForPreview = CameraPreviewMediaPipePolicy.shouldRunMediaPipe(
            gestureControlEnabled: gestureControlEnabled,
            effects: sessionBox.previewEffects
        )
        guard shouldRunForPreview else { return }
        guard !mediaPipeInferenceInFlight else { return }
        guard timestampMilliseconds - lastMediaPipeFrameTimestampMilliseconds >= mediaPipeMinimumFrameIntervalMilliseconds else {
            return
        }

        setMediaPipeInferenceInFlight(true)
        setLastMediaPipeFrameTimestampMilliseconds(timestampMilliseconds)

        Task { [weak self, jpegData, timestampMilliseconds] in
            guard let self else { return }
            let frame = await self.mediaPipeSidecar.infer(
                jpegData: jpegData,
                timestampMilliseconds: timestampMilliseconds
            )
            await MainActor.run {
                self.setMediaPipeInferenceInFlight(false)
                guard let frame else {
                    self.setMediaPipeAvailable(false)
                    self.gestureEngineLabel = GestureEngineBackend.visionLegacy.rawValue
                    self.refreshGestureEngineAvailability()
                    return
                }

                self.setMediaPipeAvailable(true)
                self.sessionBox.videoQueue.async { [sessionBox = self.sessionBox, portrait = frame.portrait] in
                    sessionBox.latestPortraitFrame = portrait
                    let segmentation = portrait.segmentation
                    sessionBox.latestPortraitSegmentation = segmentation
                }
                guard self.gestureControlEnabled else { return }
                let gestureFrame = MediaPipeGestureAdapter.gestureCoordinateFrame(from: frame)
                if gestureFrame.hands.isEmpty {
                    self.mediaPipeEmptyFrameStreak += 1
                    self.handleNoHandsDetected(
                        timestampMilliseconds: gestureFrame.timestampMilliseconds,
                        engine: .mediaPipeSidecar
                    )
                    return
                }
                self.mediaPipeEmptyFrameStreak = 0
                self.latestHandGeometries = MediaPipeGestureAdapter.handGeometries(from: gestureFrame.hands)
                self.latestHandLandmarkPoints = self.latestHandGeometries.flatMap { geometry in
                    geometry.landmarkHandPoints()
                }
                self.processDetectedPoints(
                    MediaPipeGestureAdapter.palmHandPoints(from: gestureFrame.hands),
                    timestampMilliseconds: gestureFrame.timestampMilliseconds,
                    engine: .mediaPipeSidecar
                )
            }
        }
    }

    /// Applies Vision fallback hand points already extracted on the capture queue.
    /// - Parameters:
    ///   - rawPoints: Vision-derived hand anchor points.
    ///   - timestampMilliseconds: Frame timestamp used for downstream recognition windows.
    private func processVisionHandPoints(
        _ rawPoints: [HandPoint],
        timestampMilliseconds: Int
    ) {
        guard gestureControlEnabled else { return }
        guard !rawPoints.isEmpty else {
            handleNoHandsDetected(
                timestampMilliseconds: timestampMilliseconds,
                engine: .visionLegacy
            )
            return
        }

        latestHandGeometries = []
        latestHandLandmarkPoints = []
        processDetectedPoints(
            rawPoints,
            timestampMilliseconds: timestampMilliseconds,
            engine: .visionLegacy
        )
    }

    private func processVisionFailure() {
        latestHandPoints = []
        detectedHandShapes = "未检测"
        latestHandLandmarkPoints = []
        gestureEngineLabel = GestureEngineBackend.visionLegacy.rawValue
        gestureZoneLabel = "识别异常"
        gestureGuidance = "识别失败，请检查光线和手部是否完整入镜"
        continuousZoomTracker.reset(currentScale: zoomScale)
        gestureSessionCoordinator.reset()
        gestureStatus = .failed
    }

    /// Applies recognized hand points to the existing gesture pipeline regardless of the detection backend.
    /// - Parameters:
    ///   - rawPoints: Detected hand anchor points for the current frame.
    ///   - timestampMilliseconds: Frame timestamp used for recognition windows.
    ///   - engine: Detection backend that produced the points.
    private func processDetectedPoints(
        _ rawPoints: [HandPoint],
        timestampMilliseconds: Int,
        engine: GestureEngineBackend
    ) {
        guard !rawPoints.isEmpty else {
            handleNoHandsDetected(timestampMilliseconds: timestampMilliseconds, engine: engine)
            return
        }

        let allPoints = smooth(points: rawPoints.sorted { $0.x < $1.x })
        latestHandPoints = allPoints
        detectedHandShapes = allPoints.map(\.shape.label).joined(separator: "、")
        gestureEngineLabel = engine.rawValue
        let activePoints = GestureHandSelector(zone: activationZone).selectPrimaryHands(from: allPoints)
        guard !activePoints.isEmpty else {
            gestureZoneLabel = "热区外"
            gestureGuidance = "请把手移动到画面中央的激活框内"
            gestureSessionLabel = "待命中"
            gestureStatus = .searching
            return
        }
        let snapshot = makeGestureSnapshot(activePoints, timestampMilliseconds: timestampMilliseconds)
        let activeGeometries = currentActiveGeometries(for: activePoints)
        // #region debug-point A:frame-processed
        debugReport(
            hypothesisId: "A",
            location: "CameraPreviewService.processDetectedPoints",
            message: "[DEBUG] frame processed",
            data: [
                "engine": engine.rawValue,
                "pointsCount": activePoints.count,
                "shapes": activePoints.map(\.shape.rawValue).joined(separator: ","),
                "zoneLabel": gestureZoneLabel,
                "gestureEnabled": gestureControlEnabled
            ]
        )
        // #endregion
        calibrationCapture?.frames.append(snapshot)
        if let capture = calibrationCapture, capture.frames.count % 4 == 0 {
            calibrationStatus = "\(capture.intent.calibrationLabel) 第 \(capture.sampleIndex) 次：采集中 \(capture.frames.count) 帧"
        }
        if calibrationCapture != nil {
            gestureGuidance = "校准中，请按提示稳定完成动作"
            gestureSessionLabel = "校准采集中"
            gestureStatus = .tracking
            return
        }

        gestureZoneLabel = "热区已进入"
        gestureGuidance = "先张开手掌停留，再执行动作"
        let gestureMode = updateGestureMode(
            activePoints: activePoints,
            activeGeometries: activeGeometries,
            timestampMilliseconds: snapshot.timestampMilliseconds
        )
        publishGestureMode(
            gestureMode,
            activePoints: activePoints,
            timestampMilliseconds: snapshot.timestampMilliseconds
        )
        if handleZoomMode(
            gestureMode: gestureMode,
            activePoints: activePoints,
            activeGeometries: activeGeometries,
            timestampMilliseconds: snapshot.timestampMilliseconds
        ) {
            gestureStatus = .tracking
            return
        }

        recordGestureSample(snapshot)

        let sessionUpdate = gestureSessionCoordinator.refresh(at: snapshot.timestampMilliseconds)
        gestureSessionLabel = sessionUpdate.message
        // #region debug-point A:session-refresh
        debugReport(
            hypothesisId: "A",
            location: "CameraPreviewService.processDetectedPoints",
            message: "[DEBUG] gesture session refreshed",
            data: [
                "engine": engine.rawValue,
                "state": sessionUpdate.state.rawValue,
                "message": sessionUpdate.message,
                "samples": gestureSamples.count
            ]
        )
        // #endregion

        if handleUnlockGesture() {
            gestureStatus = .tracking
            return
        }

        if activePoints.count == 1 {
            if handleSingleHandZoomStep(point: activePoints[0], at: snapshot.timestampMilliseconds) {
                gestureStatus = .tracking
                return
            }

            if handlePanGesture(point: activePoints[0], at: snapshot.timestampMilliseconds) {
                gestureStatus = .tracking
                return
            }
        }

        if sessionUpdate.state == .armed {
            if activePoints.count == 1 {
                let shape = activePoints[0].shape
                if shape == .pinch || shape == .fist || shape == .openPalm {
                    gestureGuidance = "单手揪取缩小，伸展开来放大；抓握移动可拖拽"
                    gestureStatus = .tracking
                    return
                }
            }

            if activePoints.count >= 2, isLikelyTwoHandZoomCandidate(points: activePoints) {
                let handledZoom = handleContinuousZoom(points: activePoints, at: snapshot.timestampMilliseconds)
                // #region debug-point E:zoom-candidate
                debugReport(
                    hypothesisId: "E",
                    location: "CameraPreviewService.processDetectedPoints",
                    message: "[DEBUG] two-hand zoom candidate evaluated",
                    data: [
                        "engine": engine.rawValue,
                        "handledZoom": handledZoom,
                        "shapes": activePoints.prefix(2).map(\.shape.rawValue).joined(separator: ","),
                        "samples": gestureSamples.count
                    ]
                )
                // #endregion
                if handledZoom {
                    gestureGuidance = "检测到双手缩放，已优先处理缩放"
                    gestureStatus = .tracking
                    return
                }
            }
        } else {
            if activePoints.count == 1 {
                let shape = activePoints[0].shape
                if shape == .pinch || shape == .fist || shape == .openPalm {
                    gestureGuidance = "检测到单手动作：先张开手掌停留解锁后再用单手缩放/拖拽"
                    gestureStatus = .tracking
                    return
                }
            }
        }

        if activePoints.count >= 2, isLikelyTwoHandZoomCandidate(points: activePoints) {
            let handledZoom = handleContinuousZoom(points: activePoints, at: snapshot.timestampMilliseconds)
            if handledZoom {
                gestureGuidance = "检测到双手缩放，已优先处理缩放"
                gestureStatus = .tracking
                return
            }
        }

        if shouldAllowSwipe(activePoints: activePoints, activeGeometries: activeGeometries) {
            appendGestureFrame(snapshot)
        } else {
            if activePoints.allSatisfy({ !$0.shape.allowsSwipe(profile: gestureCalibrationProfile) }) {
                swipeReturnLockGesture = nil
                swipeReturnLockUntilMilliseconds = 0
                gestureSamples.removeAll()
            }
            gestureGuidance = "单手翻页只在明确剑指时生效"
        }
        gestureStatus = .tracking
    }

    /// Selects the active MediaPipe geometries that correspond to the already-selected active hand points.
    /// - Parameter activePoints: Current active hand anchors after zone filtering.
    /// - Returns: MediaPipe hand geometries sorted from left to right for the same active hands.
    private func currentActiveGeometries(for activePoints: [HandPoint]) -> [MediaPipeHandGeometry] {
        guard !latestHandGeometries.isEmpty else {
            return []
        }

        let geometriesInZone = latestHandGeometries.filter { geometry in
            activationZone.contains(geometry.asHandPoint())
        }
        .sorted { $0.palmCenter.x < $1.palmCenter.x }

        return Array(geometriesInZone.prefix(activePoints.count))
    }

    /// Updates the mutually exclusive swipe/zoom mode coordinator for the current frame.
    /// - Parameters:
    ///   - activePoints: Current active hand anchors after zone filtering.
    ///   - activeGeometries: Current MediaPipe geometries for the same active hands.
    ///   - timestampMilliseconds: Current frame timestamp.
    /// - Returns: The dominant interaction mode after arbitration.
    private func updateGestureMode(
        activePoints: [HandPoint],
        activeGeometries: [MediaPipeHandGeometry],
        timestampMilliseconds: Int
    ) -> GestureMode {
        let swipeReady = activeGeometries.isEmpty
            ? swipeReadyDetector.isSwipeReady(points: activePoints)
            : swipeReadyDetector.isSwipeReady(geometries: activeGeometries)
        let zoomReady = activeGeometries.isEmpty
            ? twoHandZoomPoseDetector.isZoomReady(points: activePoints)
            : twoHandZoomPoseDetector.isZoomReady(geometries: activeGeometries)

        return gestureModeCoordinator.update(
            swipeReady: swipeReady,
            zoomReady: zoomReady,
            timestampMilliseconds: timestampMilliseconds
        )
    }

    /// Publishes the current interaction mode to the UI and reports mode transitions for real-camera debugging.
    /// - Parameters:
    ///   - gestureMode: Newly resolved dominant mode.
    ///   - activePoints: Current active hand anchors used to summarize shapes.
    ///   - timestampMilliseconds: Current frame timestamp.
    private func publishGestureMode(
        _ gestureMode: GestureMode,
        activePoints: [HandPoint],
        timestampMilliseconds: Int
    ) {
        gestureModeLabel = switch gestureMode {
        case .idle:
            "空闲"
        case .swipe:
            "翻页模式"
        case .zoom:
            "缩放模式"
        }

        guard gestureMode != lastReportedGestureMode else {
            return
        }

        debugReport(
            hypothesisId: "M",
            location: "CameraPreviewService.publishGestureMode",
            message: "[DEBUG] gesture interaction mode changed",
            data: [
                "gestureMode": gestureMode.rawValue,
                "timestampMilliseconds": timestampMilliseconds,
                "shapes": activePoints.map(\.shape.rawValue).joined(separator: ","),
                "pointCount": activePoints.count
            ]
        )
        lastReportedGestureMode = gestureMode
    }

    /// Handles the mutually exclusive two-hand zoom mode before the discrete swipe pipeline runs.
    /// - Parameters:
    ///   - gestureMode: Current dominant mode chosen by the coordinator.
    ///   - activePoints: Current active hand anchors after zone filtering.
    ///   - activeGeometries: Current MediaPipe geometries for the same active hands.
    ///   - timestampMilliseconds: Current frame timestamp.
    /// - Returns: `true` when zoom mode owns this frame and swipe recognition must stop.
    private func handleZoomMode(
        gestureMode: GestureMode,
        activePoints: [HandPoint],
        activeGeometries: [MediaPipeHandGeometry],
        timestampMilliseconds: Int
    ) -> Bool {
        guard gestureMode == .zoom else {
            return false
        }

        gestureSamples.removeAll()
        let handledZoom = activeGeometries.isEmpty
            ? handleContinuousZoom(points: activePoints, at: timestampMilliseconds)
            : handleContinuousZoom(geometries: activeGeometries, at: timestampMilliseconds)

        gestureGuidance = handledZoom
            ? "双手枪指或八字缩放中，翻页识别已锁定"
            : "已进入双手缩放模式，保持枪指或八字再继续放缩"
        gestureSessionLabel = "缩放模式"
        return true
    }

    /// Returns whether the current frame is allowed to enter discrete swipe recognition.
    /// - Parameters:
    ///   - activePoints: Current active hand anchors after zone filtering.
    ///   - activeGeometries: Current MediaPipe geometries for the same active hands.
    /// - Returns: `true` when the current frame explicitly matches sword or finger-gun swipe mode.
    private func shouldAllowSwipe(
        activePoints: [HandPoint],
        activeGeometries: [MediaPipeHandGeometry]
    ) -> Bool {
        if activeGeometries.isEmpty {
            return swipeReadyDetector.isSwipeReady(points: activePoints)
        }
        return swipeReadyDetector.isSwipeReady(geometries: activeGeometries)
    }

    private nonisolated static func visionHandPoints(from pixelBuffer: CVPixelBuffer) throws -> [HandPoint] {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try handler.perform([request])
        let observations = Array((request.results ?? []).prefix(2))
        return try observations
            .map { try handAnchorPoint(from: $0) }
            .sorted { $0.x < $1.x }
    }

    private nonisolated static func handAnchorPoint(from observation: VNHumanHandPoseObservation) throws -> HandPoint {
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

    private nonisolated static func classifyHandShape(_ points: [VNHumanHandPoseObservation.JointName: VNRecognizedPoint]) -> HandShape {
        let thumb = isExtended(.thumbTip, base: .thumbCMC, points: points, ratio: 1.15)
        let index = isExtended(.indexTip, base: .indexMCP, points: points)
        let middle = isExtended(.middleTip, base: .middleMCP, points: points)
        let ring = isExtended(.ringTip, base: .ringMCP, points: points)
        let little = isExtended(.littleTip, base: .littleMCP, points: points)
        let extendedCount = [thumb, index, middle, ring, little].filter { $0 }.count

        if extendedCount == 5 {
            return .openPalm
        }

        if extendedCount == 0 {
            return .fist
        }

        if thumb, index, !middle, !ring, !little {
            return .lShape
        }

        if index, middle, !ring, !little {
            return .sword
        }

        if index, !ring, !little {
            return .fingerGun
        }

        return .natural
    }

    private nonisolated static func isExtended(
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

    private nonisolated static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(a.x - b.x)
        let dy = Double(a.y - b.y)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Builds a normalized gesture snapshot using the supplied frame timestamp.
    /// - Parameters:
    ///   - points: Hand anchor points for the current frame.
    ///   - timestampMilliseconds: Frame timestamp to preserve temporal ordering.
    /// - Returns: Snapshot consumed by gesture recognizers and calibration storage.
    private func makeGestureSnapshot(
        _ points: [HandPoint],
        timestampMilliseconds: Int
    ) -> GestureFrameSnapshot {
        return GestureFrameSnapshot(
            points: points,
            timestampMilliseconds: timestampMilliseconds
        )
    }

    private func appendGestureFrame(_ snapshot: GestureFrameSnapshot) {
        if shouldBlockSwipeReturnLock(for: snapshot) {
            gestureGuidance = "请先收回翻页手势，再执行下一次翻页"
            return
        }

        if shouldSuppressDiscreteGestureDuringZoom(for: snapshot) {
            // #region debug-point B:discrete-suppressed-for-zoom
            debugReport(
                hypothesisId: "B",
                location: "CameraPreviewService.appendGestureFrame",
                message: "[DEBUG] discrete gesture suppressed because zoom pose is active",
                data: [
                    "sampleCount": gestureSamples.count,
                    "latestShapes": snapshot.points.map(\.shape.rawValue).joined(separator: ","),
                    "zoomPoseStreak": zoomPoseStreak
                ]
            )
            // #endregion
            return
        }
        guard let gesture = recognizeDiscreteGesture() else {
            // #region debug-point A:no-discrete-gesture
            debugReport(
                hypothesisId: "A",
                location: "CameraPreviewService.appendGestureFrame",
                message: "[DEBUG] no discrete gesture recognized for current sample window",
                data: [
                    "sampleCount": gestureSamples.count,
                    "pointsCount": snapshot.points.count,
                    "engine": gestureEngineLabel
                ]
            )
            // #endregion
            return
        }
        // #region debug-point B:discrete-gesture
        debugReport(
            hypothesisId: "B",
            location: "CameraPreviewService.appendGestureFrame",
            message: "[DEBUG] discrete gesture recognized",
            data: [
                "gesture": gesture.rawValue,
                "sampleCount": gestureSamples.count
            ]
        )
        // #endregion

        let sessionUpdate = gestureSessionCoordinator.consume(gesture, at: snapshot.timestampMilliseconds)
        gestureSessionLabel = sessionUpdate.message
        // #region debug-point B:session-consume
        debugReport(
            hypothesisId: "B",
            location: "CameraPreviewService.appendGestureFrame",
            message: "[DEBUG] gesture session consumed gesture",
            data: [
                "gesture": gesture.rawValue,
                "state": sessionUpdate.state.rawValue,
                "emittedGesture": sessionUpdate.emittedGesture?.rawValue ?? "nil",
                "message": sessionUpdate.message
            ]
        )
        // #endregion
        guard let emittedGesture = sessionUpdate.emittedGesture else {
            return
        }

        lastGesture = emittedGesture
        gestureModeCoordinator.markSwipeTriggered(at: snapshot.timestampMilliseconds)
        if emittedGesture == .swipeLeft || emittedGesture == .swipeRight {
            swipeReturnLockGesture = emittedGesture
            swipeReturnLockUntilMilliseconds = snapshot.timestampMilliseconds + 1_100
        }
        gestureGuidance = "动作已触发，请等待冷却结束"
        let swipeVelocity = horizontalSwipeVelocity(for: emittedGesture, frames: gestureSamples)
        gestureSamples.removeAll()
        if let onGestureRecognizedWithMotion {
            onGestureRecognizedWithMotion(emittedGesture, swipeVelocity)
        } else {
            onGestureRecognized?(emittedGesture)
        }
    }

    private func shouldBlockSwipeReturnLock(for snapshot: GestureFrameSnapshot) -> Bool {
        guard let swipeReturnLockGesture else {
            return false
        }
        guard snapshot.points.count == 1 else {
            return false
        }
        let shape = snapshot.points[0].shape
        if !shape.allowsSwipe(profile: gestureCalibrationProfile) {
            self.swipeReturnLockGesture = nil
            swipeReturnLockUntilMilliseconds = 0
            gestureSamples.removeAll()
            return false
        }

        swipeReturnLockUntilMilliseconds = max(
            swipeReturnLockUntilMilliseconds,
            snapshot.timestampMilliseconds + 250
        )
        return swipeReturnLockGesture == .swipeLeft || swipeReturnLockGesture == .swipeRight
    }

    /// Computes normalized horizontal swipe velocity for targets that can animate page transitions.
    /// - Parameters:
    ///   - gesture: Recognized gesture intent.
    ///   - frames: Recent samples used by the recognizer.
    /// - Returns: Absolute normalized screen-widths per second for swipe gestures.
    private func horizontalSwipeVelocity(
        for gesture: GestureIntent,
        frames: [GestureFrameSnapshot]
    ) -> Double? {
        guard gesture == .swipeLeft || gesture == .swipeRight else {
            return nil
        }
        guard
            let firstFrame = frames.first(where: { $0.points.first?.shape.allowsSwipe(profile: gestureCalibrationProfile) == true }),
            let lastFrame = frames.last(where: { $0.points.first?.shape.allowsSwipe(profile: gestureCalibrationProfile) == true }),
            let first = firstFrame.points.first,
            let last = lastFrame.points.first
        else {
            return nil
        }

        let durationSeconds = max(0.001, Double(lastFrame.timestampMilliseconds - firstFrame.timestampMilliseconds) / 1_000)
        return abs(last.x - first.x) / durationSeconds
    }

    private func shouldSuppressDiscreteGestureDuringZoom(for snapshot: GestureFrameSnapshot) -> Bool {
        discreteGestureSuppressionEvaluator.shouldSuppressDiscreteGesture(
            existingFrames: gestureSamples,
            incomingFrame: snapshot,
            zoomPoseStreak: zoomPoseStreak
        )
    }

    /// Appends the latest frame and trims the recognition window to the active sample duration.
    /// - Parameter snapshot: The latest normalized gesture frame snapshot.
    private func recordGestureSample(_ snapshot: GestureFrameSnapshot) {
        gestureSamples.append(snapshot)
        let sampleWindow = Double(gestureCalibrationProfile.maximumGestureDurationMilliseconds) / 1_000
        let cutoff = snapshot.timestampMilliseconds - Int(sampleWindow * 1_000)
        gestureSamples = gestureSamples.filter { $0.timestampMilliseconds >= cutoff }
    }

    /// Applies continuous zoom updates from lightweight hand anchors.
    /// - Parameters:
    ///   - points: Active hand anchors sorted from left to right.
    ///   - timestampMilliseconds: Current frame timestamp.
    /// - Returns: `true` when the frame belongs to the continuous zoom interaction.
    private func handleContinuousZoom(points: [HandPoint], at timestampMilliseconds: Int) -> Bool {
        guard points.count >= 2 else {
            continuousZoomTracker.reset(currentScale: zoomScale)
            // #region debug-point E:zoom-reset-few-points
            debugReport(
                hypothesisId: "E",
                location: "CameraPreviewService.handleContinuousZoom",
                message: "[DEBUG] zoom tracker reset due to insufficient points",
                data: [
                    "pointsCount": points.count,
                    "currentScale": zoomScale
                ]
            )
            // #endregion
            return false
        }

        let usesZoomPose = points.prefix(2).allSatisfy { $0.shape.allowsTwoHandZoom }
        guard usesZoomPose else {
            continuousZoomTracker.reset(currentScale: zoomScale)
            zoomPoseStreak = 0
            // #region debug-point E:zoom-reset-pose
            debugReport(
                hypothesisId: "E",
                location: "CameraPreviewService.handleContinuousZoom",
                message: "[DEBUG] zoom tracker reset due to unsupported hand pose",
                data: [
                    "shapes": points.prefix(2).map(\.shape.rawValue).joined(separator: ","),
                    "currentScale": zoomScale
                ]
            )
            // #endregion
            return false
        }

        if let update = continuousZoomTracker.update(
            points: points,
            currentScale: zoomScale,
            timestampMilliseconds: timestampMilliseconds
        ) {
            zoomScale = update.scale
            lastGesture = update.relativeDistanceChange >= 0 ? .zoomIn : .zoomOut
            gestureSessionLabel = "缩放中"
            onZoomChanged?(update.scale)
            // #region debug-point E:zoom-update
            debugReport(
                hypothesisId: "E",
                location: "CameraPreviewService.handleContinuousZoom",
                message: "[DEBUG] zoom update emitted",
                data: [
                    "scale": update.scale,
                    "relativeDistanceChange": update.relativeDistanceChange,
                    "confidence": update.confidence
                ]
            )
            // #endregion
            zoomPoseStreak = min(12, zoomPoseStreak + 1)
        } else {
            // #region debug-point E:zoom-no-update
            debugReport(
                hypothesisId: "E",
                location: "CameraPreviewService.handleContinuousZoom",
                message: "[DEBUG] zoom candidate produced no scale update",
                data: [
                    "currentScale": zoomScale,
                    "shapes": points.prefix(2).map(\.shape.rawValue).joined(separator: ",")
                ]
            )
            // #endregion
            zoomPoseStreak = min(12, zoomPoseStreak + 1)
        }

        return true
    }

    /// Applies continuous zoom updates from full MediaPipe geometry.
    /// - Parameters:
    ///   - geometries: Active MediaPipe hand geometries sorted from left to right.
    ///   - timestampMilliseconds: Current frame timestamp.
    /// - Returns: `true` when the frame belongs to the continuous zoom interaction.
    private func handleContinuousZoom(
        geometries: [MediaPipeHandGeometry],
        at timestampMilliseconds: Int
    ) -> Bool {
        guard geometries.count >= 2 else {
            continuousZoomTracker.reset(currentScale: zoomScale)
            zoomPoseStreak = 0
            return false
        }

        guard twoHandZoomPoseDetector.isZoomReady(geometries: geometries) else {
            continuousZoomTracker.reset(currentScale: zoomScale)
            zoomPoseStreak = 0
            return false
        }

        let hands = Array(geometries.prefix(2))
        // #region debug-point C:zoom-geometry-frame
        debugReport(
            hypothesisId: "C",
            location: "CameraPreviewService.handleContinuousZoom(geometries:)",
            message: "[DEBUG] zoom geometry frame accepted",
            data: [
                "timestampMilliseconds": timestampMilliseconds,
                "leftHandedness": hands[0].handedness,
                "rightHandedness": hands[1].handedness,
                "leftPalmCenterX": hands[0].palmCenter.x,
                "leftPalmCenterY": hands[0].palmCenter.y,
                "rightPalmCenterX": hands[1].palmCenter.x,
                "rightPalmCenterY": hands[1].palmCenter.y,
                "leftPalmSize": hands[0].palmSize,
                "rightPalmSize": hands[1].palmSize,
                "normalizedDistance": hands[0].normalizedDistance(to: hands[1]),
                "screenDistance": hands[0].palmCenter.distance(to: hands[1].palmCenter),
                "leftShape": hands[0].primaryShape.rawValue,
                "rightShape": hands[1].primaryShape.rawValue
            ]
        )
        // #endregion

        if let update = continuousZoomTracker.update(
            geometries: geometries,
            currentScale: zoomScale,
            timestampMilliseconds: timestampMilliseconds
        ) {
            zoomScale = update.scale
            lastGesture = update.relativeDistanceChange >= 0 ? .zoomIn : .zoomOut
            gestureSessionLabel = "缩放中"
            onZoomChanged?(update.scale)
            // #region debug-point C:zoom-geometry-update
            debugReport(
                hypothesisId: "C",
                location: "CameraPreviewService.handleContinuousZoom(geometries:)",
                message: "[DEBUG] zoom update emitted from geometry path",
                data: [
                    "timestampMilliseconds": timestampMilliseconds,
                    "scale": update.scale,
                    "relativeDistanceChange": update.relativeDistanceChange,
                    "confidence": update.confidence,
                    "leftHandedness": hands[0].handedness,
                    "rightHandedness": hands[1].handedness
                ]
            )
            // #endregion
            zoomPoseStreak = min(12, zoomPoseStreak + 1)
        } else {
            // #region debug-point C:zoom-geometry-no-update
            debugReport(
                hypothesisId: "C",
                location: "CameraPreviewService.handleContinuousZoom(geometries:)",
                message: "[DEBUG] geometry path produced no zoom update",
                data: [
                    "timestampMilliseconds": timestampMilliseconds,
                    "currentScale": zoomScale,
                    "normalizedDistance": hands[0].normalizedDistance(to: hands[1]),
                    "screenDistance": hands[0].palmCenter.distance(to: hands[1].palmCenter)
                ]
            )
            // #endregion
            zoomPoseStreak = min(12, zoomPoseStreak + 1)
        }

        return true
    }

    private func handleSingleHandZoomStep(point: HandPoint, at timestampMilliseconds: Int) -> Bool {
        guard let update = singleHandZoomPulseRecognizer.observe(
            shape: point.shape,
            currentScale: zoomScale,
            timestampMilliseconds: timestampMilliseconds
        ) else {
            return false
        }

        zoomScale = update.scale
        lastGesture = update.intent
        gestureSessionLabel = "缩放中"
        gestureGuidance = "单手揪取缩小，伸展开来放大"
        gestureSamples.removeAll()
        onZoomChanged?(update.scale)
        return true
    }

    private func handlePanGesture(point: HandPoint, at timestampMilliseconds: Int) -> Bool {
        let isGrabbing = point.shape == .fist
        guard isGrabbing else {
            if isPanning {
                isPanning = false
                panBaselinePoint = nil
                gestureGuidance = "已固定缩放位置"
            }
            return false
        }

        if !isPanning {
            singleHandZoomPulseRecognizer.reset()
            isPanning = true
            panBaselinePoint = point
            panBaselineX = panX
            panBaselineY = panY
            lastPanSentAtMilliseconds = 0
            gestureGuidance = "握拳抓取移动：移动手来调整缩放中心"
            return true
        }

        guard let baseline = panBaselinePoint else {
            panBaselinePoint = point
            panBaselineX = panX
            panBaselineY = panY
            return true
        }

        let sensitivity = max(1.45, 2.25 / max(zoomScale, 1.0))
        let nextX = min(1, max(-1, panBaselineX + (point.x - baseline.x) * sensitivity))
        let nextY = min(1, max(-1, panBaselineY + (point.y - baseline.y) * sensitivity))

        let minimumDelta = 0.01
        let changed = abs(nextX - panX) >= minimumDelta || abs(nextY - panY) >= minimumDelta
        let sendInterval = 80
        guard changed, timestampMilliseconds - lastPanSentAtMilliseconds >= sendInterval else {
            return true
        }

        panX = nextX
        panY = nextY
        lastPanSentAtMilliseconds = timestampMilliseconds
        onPanChanged?(nextX, nextY)
        return true
    }

    /// Detects whether recent samples look like a deliberate two-hand zoom attempt.
    /// - Parameter points: Current frame hand points.
    /// - Returns: `true` when the recent motion is more likely a zoom than a page swipe.
    private func isLikelyTwoHandZoomCandidate(points: [HandPoint]) -> Bool {
        guard points.count >= 2 else { return false }
        let window = Array(gestureSamples.suffix(12))
        guard window.count >= 4 else { return false }
        let candidates = window.filter { $0.points.count >= 2 }
        guard candidates.count >= 3 else { return false }

        let poseCoverage = discreteGestureSuppressionEvaluator.twoHandZoomPoseCoverage(frames: candidates)
        guard poseCoverage.frameCount >= 4 else { return false }
        if poseCoverage.zoomPoseFrameCount < 2 || poseCoverage.zoomPoseCoverage < 0.25 {
            // #region debug-point B:zoom-coverage-reject
            debugReport(
                hypothesisId: "B",
                location: "CameraPreviewService.isLikelyTwoHandZoomCandidate",
                message: "[DEBUG] zoom candidate rejected by pose coverage",
                data: [
                    "frameCount": poseCoverage.frameCount,
                    "zoomPoseFrameCount": poseCoverage.zoomPoseFrameCount,
                    "zoomPoseCoverage": poseCoverage.zoomPoseCoverage
                ]
            )
            // #endregion
            return false
        }

        guard let start = candidates.dropLast().last, let end = candidates.last else {
            return false
        }

        let stableZoomPoseShortcut =
            start.points.prefix(2).allSatisfy { $0.shape.allowsTwoHandZoom }
            && end.points.prefix(2).allSatisfy { $0.shape.allowsTwoHandZoom }
            && poseCoverage.zoomPoseFrameCount >= 2
        if stableZoomPoseShortcut {
            // #region debug-point A:zoom-candidate-shortcut
            debugReport(
                hypothesisId: "A",
                location: "CameraPreviewService.isLikelyTwoHandZoomCandidate",
                message: "[DEBUG] zoom candidate accepted by stable zoom-pose shortcut",
                data: [
                    "startShapes": start.points.prefix(2).map(\.shape.rawValue).joined(separator: ","),
                    "endShapes": end.points.prefix(2).map(\.shape.rawValue).joined(separator: ","),
                    "zoomPoseFrameCount": poseCoverage.zoomPoseFrameCount,
                    "zoomPoseCoverage": poseCoverage.zoomPoseCoverage
                ]
            )
            // #endregion
            return true
        }

        let prioritized = ContinuousZoomCandidateEvaluator(profile: gestureCalibrationProfile)
            .shouldPrioritizeZoom(start: start.points, end: end.points)
        // #region debug-point A:zoom-candidate-decision
        debugReport(
            hypothesisId: "A",
            location: "CameraPreviewService.isLikelyTwoHandZoomCandidate",
            message: "[DEBUG] zoom candidate evaluated",
            data: [
                "prioritized": prioritized,
                "startShapes": start.points.prefix(2).map(\.shape.rawValue).joined(separator: ","),
                "endShapes": end.points.prefix(2).map(\.shape.rawValue).joined(separator: ","),
                "zoomPoseFrameCount": poseCoverage.zoomPoseFrameCount,
                "zoomPoseCoverage": poseCoverage.zoomPoseCoverage
            ]
        )
        // #endregion
        return prioritized
    }

    /// Detects the unlock gesture from recent frames and updates the session state.
    /// - Returns: `true` when the unlock gesture was recognized and consumed.
    private func handleUnlockGesture() -> Bool {
        guard let holdGesture = unlockRecognizer.recognize(frames: gestureSamples) else {
            return false
        }
        // #region debug-point A:unlock-recognized
        debugReport(
            hypothesisId: "A",
            location: "CameraPreviewService.handleUnlockGesture",
            message: "[DEBUG] unlock gesture recognized",
            data: [
                "gesture": holdGesture.rawValue,
                "samples": gestureSamples.count
            ]
        )
        // #endregion
        let update = gestureSessionCoordinator.consume(holdGesture, at: currentTimestampMilliseconds())
        gestureSessionLabel = update.message
        gestureGuidance = update.state == .armed
            ? "已解锁，请快速完成翻页或缩放动作"
            : gestureGuidance
        if update.state == .armed {
            singleHandZoomPulseRecognizer.prime(with: .openPalm)
            gestureSamples.removeAll()
        }
        return update.state == .armed
    }

    private func recognizeDiscreteGesture() -> GestureIntent? {
        let personalized = PersonalizedGestureRecognizer(
            library: personalizedLibrary,
            minimumConfidence: 0.34,
            minimumWinningMargin: 0.03,
            minimumDirectionalTravel: 0.07
        )
            .recognizeMatch(frames: gestureSamples)

        if let personalized {
            // #region debug-point C:discrete-personalized
            debugReport(
                hypothesisId: "C",
                location: "CameraPreviewService.recognizeDiscreteGesture",
                message: "[DEBUG] discrete gesture recognized from personalized template",
                data: [
                    "gesture": personalized.intent.rawValue,
                    "confidence": personalized.confidence,
                    "distance": personalized.distance
                ]
            )
            // #endregion
            return personalized.intent
        }

        let recognized = StreamingGestureRecognizer(
            profile: gestureCalibrationProfile,
            minimumDecisionDurationMilliseconds: 70,
            minimumDirectionConsistency: 0.54,
            minimumHorizontalVelocity: 0.36
        )
            .recognize(frames: gestureSamples)
        // #region debug-point C:discrete-streaming
        debugReport(
            hypothesisId: "C",
            location: "CameraPreviewService.recognizeDiscreteGesture",
            message: recognized == nil
                ? "[DEBUG] discrete gesture not recognized by streaming recognizer"
                : "[DEBUG] discrete gesture recognized by streaming recognizer",
            data: [
                "gesture": recognized?.rawValue ?? "nil",
                "sampleCount": gestureSamples.count,
                "latestShapes": gestureSamples.last?.points.map(\.shape.rawValue).joined(separator: ",") ?? "none"
            ]
        )
        // #endregion
        return recognized
    }

    /// Smooths landmark anchors with exponential moving average to reduce jitter.
    /// - Parameter points: The raw points from the current frame.
    /// - Returns: Smoothed points preserving order and detected hand shape.
    private func smooth(points: [HandPoint]) -> [HandPoint] {
        guard !smoothedPoints.isEmpty, smoothedPoints.count == points.count else {
            smoothedPoints = points
            return points
        }

        let alpha: Double
        if points.count >= 2, points.prefix(2).allSatisfy({ $0.shape.allowsTwoHandZoom || $0.shape == .unknown }) {
            alpha = 0.5
        } else if points.count == 1, let shape = points.first?.shape, shape.allowsSwipe(profile: gestureCalibrationProfile) || shape.allowsTwoHandZoom {
            alpha = 0.48
        } else {
            alpha = 0.35
        }
        let next = zip(smoothedPoints, points).map { previous, current in
            HandPoint(
                x: previous.x + (current.x - previous.x) * alpha,
                y: previous.y + (current.y - previous.y) * alpha,
                shape: current.shape
            )
        }
        smoothedPoints = next
        return next
    }

    /// Updates UI state when no hands are detected in the current frame.
    /// - Parameters:
    ///   - timestampMilliseconds: Current frame timestamp.
    ///   - engine: Detection backend currently active.
    private func handleNoHandsDetected(
        timestampMilliseconds: Int,
        engine: GestureEngineBackend
    ) {
        latestHandPoints = []
        latestHandGeometries = []
        latestHandLandmarkPoints = []
        gestureModeLabel = "空闲"
        lastReportedGestureMode = .idle
        detectedHandShapes = "未检测"
        gestureEngineLabel = engine.rawValue
        gestureZoneLabel = "热区待进入"
        gestureGuidance = "未检测到手，请将手抬到镜头前"
        gestureSessionLabel = gestureSessionCoordinator.refresh(at: timestampMilliseconds).message
        gestureStatus = .searching
        // #region debug-point A:no-hands
        debugReport(
            hypothesisId: "A",
            location: "CameraPreviewService.handleNoHandsDetected",
            message: "[DEBUG] no hands detected",
            data: [
                "engine": engine.rawValue,
                "timestampMilliseconds": timestampMilliseconds
            ]
        )
        // #endregion
    }

    /// Resets in-memory tracking state when capture is interrupted or restarted.
    private func resetGestureTracking() {
        gestureSamples.removeAll()
        smoothedPoints.removeAll()
        latestHandGeometries.removeAll()
        latestHandLandmarkPoints.removeAll()
        setMediaPipeInferenceInFlight(false)
        mediaPipeEmptyFrameStreak = 0
        setLastMediaPipeFrameTimestampMilliseconds(0)
        continuousZoomTracker.reset(currentScale: 1)
        gestureModeCoordinator.reset()
        gestureSessionCoordinator.reset()
        panX = 0
        panY = 0
        isPanning = false
        panBaselinePoint = nil
        panBaselineX = 0
        panBaselineY = 0
        lastPanSentAtMilliseconds = 0
        singleHandZoomPulseRecognizer.reset()
        lastReportedGestureMode = .idle
        gestureModeLabel = "空闲"
        gestureGuidance = "先把手放到中央热区"
        gestureSessionLabel = "待命中"
        gestureZoneLabel = "热区待进入"
    }

    /// Switches to Vision temporarily after repeated empty MediaPipe frames and retries the sidecar later.
    private func activateVisionFallbackAfterMediaPipeMisses() {
        setMediaPipeAvailable(false)
        mediaPipeEmptyFrameStreak = 0
        gestureEngineLabel = GestureEngineBackend.visionLegacy.rawValue
        gestureGuidance = "MediaPipe 当前未稳定检出手，已临时切换到 Vision 兜底"
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.refreshGestureEngineAvailability()
        }
    }

    /// Returns the current wall-clock timestamp in milliseconds.
    /// - Returns: Current time since 1970 in milliseconds.
    private func currentTimestampMilliseconds() -> Int {
        Int(Date().timeIntervalSince1970 * 1_000)
    }

    // #region debug-point Z:report-helper
    private func debugReport(
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: Any]
    ) {
        #if DEBUG
        guard let url = URL(string: "http://127.0.0.1:7777/event") else { return }
        guard JSONSerialization.isValidJSONObject(data) else { return }
        let payload: [String: Any] = [
            "sessionId": "zoom-instability-v07",
            "runId": "pre-fix",
            "hypothesisId": hypothesisId,
            "location": location,
            "msg": message,
            "data": data,
            "ts": currentTimestampMilliseconds()
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        URLSession.shared.dataTask(with: request).resume()
        #else
        _ = hypothesisId
        _ = location
        _ = message
        _ = data
        #endif
    }
    // #endregion

    private func savePersonalizedLibrary() {
        do {
            let data = try JSONEncoder().encode(personalizedLibrary)
            let url = Self.personalizedLibraryURL()
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            UserDefaults.standard.set(false, forKey: Self.personalizedLibraryDisabledKey)
        } catch {
            calibrationStatus = "保存个人手势失败：\(error.localizedDescription)"
        }
    }

    private func loadPersonalizedLibrary() {
        if UserDefaults.standard.bool(forKey: Self.personalizedLibraryDisabledKey) {
            personalizedLibrary = PersonalizedGestureLibrary()
            calibrationStatus = "个人手势样本已停用，当前只使用实时识别"
            return
        }
        let url = Self.personalizedLibraryURL()
        guard let data = try? Data(contentsOf: url),
              let library = try? JSONDecoder().decode(PersonalizedGestureLibrary.self, from: data)
        else {
            return
        }
        personalizedLibrary = library
        calibrationStatus = "已加载 \(library.templates.count) 个个人手势样本"
    }

    /// Clears persisted personalized gesture templates and returns to live recognition only.
    func clearPersonalizedCalibration() {
        personalizedLibrary = PersonalizedGestureLibrary()
        UserDefaults.standard.set(true, forKey: Self.personalizedLibraryDisabledKey)
        calibrationStatus = "已停用旧个人手势样本，当前只使用实时识别"
    }

    private static let personalizedLibraryDisabledKey = "WonderShow.personalizedLibraryDisabled"

    private static func personalizedLibraryURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WonderShow", isDirectory: true)
            .appendingPathComponent("personalized-gestures.json")
    }
}

enum GestureStatus: String {
    case idle = "未开启"
    case searching = "寻找手势"
    case tracking = "正在跟踪"
    case failed = "识别异常"
}

private enum GestureFrameError: Error {
    case missingHandPoint
}

private struct CalibrationCapture {
    let intent: GestureIntent
    let sampleIndex: Int
    var frames: [GestureFrameSnapshot]
}

private extension HandShape {
    var label: String {
        switch self {
        case .unknown:
            return "未知"
        case .natural:
            return "自然手"
        case .openPalm:
            return "开掌"
        case .pinch:
            return "揪取"
        case .fist:
            return "握拳"
        case .fingerGun:
            return "指枪"
        case .sword:
            return "剑指"
        case .lShape:
            return "八字"
        }
    }
}

private extension GestureIntent {
    var calibrationLabel: String {
        switch self {
        case .swipeLeft:
            return "左挥下一页"
        case .swipeRight:
            return "右挥上一页"
        case .zoomIn:
            return "双手分开放大"
        case .zoomOut:
            return "双手合拢缩小"
        case .startPresentation:
            return "开始播放"
        case .exitPresentation:
            return "退出播放"
        case .toggleRecording:
            return "开始/停止录制"
        case .pinchToggle:
            return "开关标注"
        case .pinchDrag:
            return "绘制标注"
        case .openPalmHold:
            return "清除标注"
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

    func primaryActionTitle(copy: AppCopy) -> String {
        switch self {
        case .permissionDenied:
            return copy.text("cameraPermBtn")
        default:
            return copy.reconnect
        }
    }

    func recoveryHint(copy: AppCopy) -> String {
        switch self {
        case .permissionDenied:
            return copy.text("cameraPermissionDeniedHint")
        default:
            return copy.runtimeText(detail)
        }
    }
}

enum CameraPermissionPresentation {
    static func statusText(for status: AVAuthorizationStatus, copy: AppCopy) -> String {
        switch status {
        case .authorized:
            return copy.text("permissionGranted")
        case .notDetermined:
            return copy.text("permissionNeeded")
        case .denied:
            return copy.text("permissionDenied")
        case .restricted:
            return copy.text("permissionRestricted")
        @unknown default:
            return copy.text("permissionUnknown")
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
