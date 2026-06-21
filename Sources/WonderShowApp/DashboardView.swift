import AppKit
import AVFoundation
import Combine
import AVKit
import WonderShow
import SwiftUI

private let presenterEmojiChoices = ["😀", "😎", "🤩", "🙂", "😄", "🤖", "🫥", "🥸"]

private enum PiPShape: String, CaseIterable, Hashable {
    case roundedRectangle
    case square
    case circle
}

private enum ScreenSourcePickerViewMode: String, CaseIterable, Hashable {
    case thumbnails
    case list
}

private enum ProgramCanvasAspect: String, CaseIterable, Hashable {
    case widescreen
    case classic
    case classicVertical
    case photo
    case photoVertical
    case vertical
    case square
    case ultrawide

    var label: String {
        switch self {
        case .widescreen:
            return "16:9"
        case .classic:
            return "4:3"
        case .classicVertical:
            return "3:4"
        case .photo:
            return "3:2"
        case .photoVertical:
            return "2:3"
        case .vertical:
            return "9:16"
        case .square:
            return "1:1"
        case .ultrawide:
            return "32:9"
        }
    }

    var aspectRatio: CGFloat {
        switch self {
        case .widescreen:
            return 16 / 9
        case .classic:
            return 4 / 3
        case .classicVertical:
            return 3 / 4
        case .photo:
            return 3 / 2
        case .photoVertical:
            return 2 / 3
        case .vertical:
            return 9 / 16
        case .square:
            return 1
        case .ultrawide:
            return 32 / 9
        }
    }

    func pixelSize(for resolution: ProgramCanvasResolution) -> RecordingExportPixelSize {
        switch (self, resolution) {
        case (.widescreen, .hd):
            return RecordingExportPixelSize(width: 1920, height: 1080)
        case (.widescreen, .uhd):
            return RecordingExportPixelSize(width: 3840, height: 2160)
        case (.classic, .hd):
            return RecordingExportPixelSize(width: 1440, height: 1080)
        case (.classic, .uhd):
            return RecordingExportPixelSize(width: 2880, height: 2160)
        case (.classicVertical, .hd):
            return RecordingExportPixelSize(width: 1080, height: 1440)
        case (.classicVertical, .uhd):
            return RecordingExportPixelSize(width: 2160, height: 2880)
        case (.photo, .hd):
            return RecordingExportPixelSize(width: 1620, height: 1080)
        case (.photo, .uhd):
            return RecordingExportPixelSize(width: 3240, height: 2160)
        case (.photoVertical, .hd):
            return RecordingExportPixelSize(width: 1080, height: 1620)
        case (.photoVertical, .uhd):
            return RecordingExportPixelSize(width: 2160, height: 3240)
        case (.vertical, .hd):
            return RecordingExportPixelSize(width: 1080, height: 1920)
        case (.vertical, .uhd):
            return RecordingExportPixelSize(width: 2160, height: 3840)
        case (.square, .hd):
            return RecordingExportPixelSize(width: 1080, height: 1080)
        case (.square, .uhd):
            return RecordingExportPixelSize(width: 2160, height: 2160)
        case (.ultrawide, .hd):
            return RecordingExportPixelSize(width: 3840, height: 1080)
        case (.ultrawide, .uhd):
            return RecordingExportPixelSize(width: 7680, height: 2160)
        }
    }
}

private enum ProgramCanvasResolution: String, CaseIterable, Hashable {
    case hd
    case uhd

    var label: String {
        switch self {
        case .hd:
            return "1080p"
        case .uhd:
            return "4K"
        }
    }

    var baseResolution: RecordingExportResolution {
        switch self {
        case .hd:
            return .hd1080
        case .uhd:
            return .uhd4k
        }
    }
}

private struct ExportProgressPresentation: Identifiable, Equatable {
    let id = "export-progress"
    var title: String
    var fraction: Double
    var width: Int
    var height: Int
    var fileSize: Int64
    var outputURL: URL?
    var settings: RecordingExportSettings
}

private struct ExportOutcomePresentation: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let url: URL?
}

struct DashboardView: View {
    fileprivate static var appVersion: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.7-dev"
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        guard let buildVersion, !buildVersion.isEmpty, buildVersion != shortVersion else {
            return "v\(shortVersion)"
        }
        return "v\(shortVersion) (\(buildVersion))"
    }

    @ObservedObject private var recordingControlCenter: RecordingControlCenter
    @StateObject private var camera = CameraPreviewService()
    @StateObject private var commandController = PresentationCommandController()
    @StateObject private var screenPreview = ScreenPreviewService()
    @State private var target: PresentationTarget = .keynote
    @State private var mode: RecordingMode = .cameraAndScreen
    @State private var layout: RecordingLayout = .screenWithCameraPictureInPicture(corner: .bottomRight)
    @State private var screenSourcePreference: ScreenCaptureSourcePreference = .automaticPresentationWindow
    @State private var screenWindowOptions: [ScreenCaptureWindowOption] = []
    @State private var selectedScreenSourceIDs: Set<ScreenCaptureSourceID> = []
    @State private var screenSourceDiagnostic = ""
    @State private var screenSourceThumbnails: [ScreenCaptureSourceID: CGImage] = [:]
    @State private var screenSourcePickerMode: ScreenSourcePickerViewMode = .thumbnails
    @State private var screenSourceThumbnailTask: Task<Void, Never>?
    @State private var showsScreenSourcePicker = false
    @State private var recordingSourceSlots = RecordingSourceSlots.load()
    @State private var recordingFeatureTier = RecordingFeatureTier.load()
    @State private var calibrationFlow: CalibrationFlow?
    @State private var showsDiagnostics = false
    @State private var showsAboutCard = false
    @State private var showsGestureCheatsheet = false
    @State private var displayLanguage: AppLanguage = .zhHans
    @State private var quickStartCollapsed = false
    @State private var presentationCollapsed = false
    @State private var projectCollapsed = false
    @State private var gestureCollapsed = false
    @State private var devicesCollapsed = false
    @State private var elapsedSeconds = 0
    @State private var exportDraftSettings = RecordingExportSettings.presentationDefault
    @State private var showsExportSettings = false
    @State private var exportProgress: ExportProgressPresentation?
    @State private var activeProgramRenderTask: Task<Void, Never>?
    @State private var exportOutcome: ExportOutcomePresentation?
    @State private var recordingCountdownTask: Task<Void, Never>?
    @State private var localRecordingHotKeyMonitor: Any?
    @State private var globalRecordingHotKeyMonitor: Any?
    @State private var recordingControlState: RecordingControlState = .idle
    @State private var showsFinishRecordingAlert = false
    @State private var shouldRenderStoppedRecording = true
    @State private var discardStoppedRecording = false
    @State private var recordingActiveStartedAt: Date?
    @State private var accumulatedRecordingDuration: TimeInterval = 0
    @State private var audioInputDevices: [AudioInputDeviceOption] = MicrophoneArchiveRecorder.availableInputDevices()
    @State private var selectedAudioInputDeviceID = AudioInputDeviceOption.systemDefault.id
    @State private var latestScreenPreviewImage: CGImage?
    @State private var latestScreenPreviewSourceID: ScreenCaptureSourceID?
    @State private var screenPreviewGeneration = 0
    @State private var pipOffset = CGSize(width: 18, height: -18)
    @State private var pipScale: CGFloat = 1
    @State private var pipShape: PiPShape = .roundedRectangle
    @State private var presenterMirrorEnabled = false
    @State private var presenterBrightness: CGFloat = 0
    @State private var presenterContrast: CGFloat = 1
    @State private var presenterBeauty: CGFloat = 0
    @State private var presenterSmartBeautyEnabled = false
    @State private var presenterBeautyStyle: PresenterBeautyStyle = .natural
    @State private var presenterSkinSmoothing: CGFloat = 0
    @State private var presenterSkinBrightening: CGFloat = 0
    @State private var presenterSkinWhitening: CGFloat = 0
    @State private var presenterBlemishReduction: CGFloat = 0
    @State private var presenterComplexion: CGFloat = 0
    @State private var presenterAdvancedBeautyEnabled = false
    @State private var presenterPortraitSegmentationEnabled = false
    @State private var presenterBackgroundBlur: CGFloat = 0
    @State private var presenterBackgroundReplacementEnabled = false
    @State private var presenterBackgroundReplacementStrength: CGFloat = 0
    @State private var presenterFaceLandmarkBeautyEnabled = false
    @State private var presenterFaceSlimming: CGFloat = 0
    @State private var presenterEyeEnlargement: CGFloat = 0
    @State private var presenterEmojiFaceReplacementEnabled = false
    @State private var presenterEmojiFaceReplacementSymbol = "😀"
    @State private var presenterEmojiFaceReplacementScale: CGFloat = 1
    @State private var presenterBeautyControlsExpanded = false
    @State private var monitorCanvasSize = CGSize(width: 1280, height: 720)
    @State private var programCanvasAspect: ProgramCanvasAspect = .widescreen
    @State private var programCanvasResolution: ProgramCanvasResolution = .uhd
    @State private var recordingStartedAt: Date?
    @State private var recordingPiPKeyframes: [RecordingPiPKeyframe] = []
    @State private var recordingLayoutKeyframes: [RecordingLayoutKeyframe] = []
    @State private var collapsedTimelineTrackIDs: Set<String> = []
    @State private var selectedTimelineRange: TimelineExportRange?
    @State private var timelinePlayheadMilliseconds = 0
    @State private var lastPiPKeyframeDate: Date?
    @StateObject private var recordingCountdownPresenter = RecordingCountdownPresenter()

    private var copy: AppCopy {
        AppLocalization().copy(for: displayLanguage)
    }

    private var cameraStatusValue: String {
        camera.status == .running ? copy.connected : copy.runtimeText(camera.status.label)
    }

    private var cameraStatusDetail: String {
        copy.runtimeText(camera.status.detail)
    }

    private var cameraRecoveryHint: String {
        camera.status.recoveryHint(copy: copy)
    }

    private var cameraPrimaryActionTitle: String {
        camera.status.primaryActionTitle(copy: copy)
    }

    private var cameraPermissionStatusValue: String {
        CameraPermissionPresentation.statusText(for: camera.cameraAuthorizationStatus, copy: copy)
    }

    private var isGestureZoneActive: Bool {
        camera.gestureZoneLabel == "热区已进入"
    }

    private var localizedGestureZoneLabel: String {
        copy.runtimeText(camera.gestureZoneLabel)
    }

    private var localizedDetectedHandShapes: String {
        copy.runtimeText(camera.detectedHandShapes)
    }

    private var localizedLastActionDescription: String {
        copy.runtimeText(commandController.lastActionDescription)
    }

    private var localizedActiveDeviceName: String {
        copy.runtimeText(camera.activeDeviceName)
    }

    private var localizedSelectedDeviceTitle: String {
        copy.runtimeText(selectedDeviceTitle)
    }

    private var localizedSelectedDeviceDetail: String {
        copy.runtimeText(selectedDeviceDetail)
    }

    private var localizedCommandSummary: String {
        copy.runtimeText(commandSummary)
    }

    private var permitsPresenterColorEffects: Bool {
        WonderShowDistribution.permitsPresenterColorEffects(for: recordingFeatureTier)
    }

    private var permitsSubjectAwareBeauty: Bool {
        WonderShowDistribution.permitsSubjectAwareBeauty(for: recordingFeatureTier)
            && PresenterExperimentalEffectsGate.isEnabled
    }

    private var programCanvasExportSettings: RecordingExportSettings {
        RecordingExportSettings(
            resolution: programCanvasResolution.baseResolution,
            frameRate: .fps30,
            quality: .high,
            codec: .h264,
            customPixelSize: programCanvasAspect.pixelSize(for: programCanvasResolution)
        )
    }

    private var effectivePresenterVideoEffects: PresenterVideoEffects {
        PresenterExperimentalEffectsGate.mask(currentPresenterVideoEffects(permittedBy: recordingFeatureTier))
    }

    private var exportResolutionBinding: Binding<RecordingExportResolution> {
        Binding(
            get: {
                exportDraftSettings.resolution
            },
            set: { resolution in
                exportDraftSettings.resolution = resolution
                exportDraftSettings.customPixelSize = nil
            }
        )
    }

    private var localizedCalibrationStatus: String {
        copy.runtimeText(camera.calibrationStatus)
    }

    private var localizedDeviceScanSummary: String {
        copy.runtimeText(camera.deviceScanSummary)
    }

    private func localizedRuntime(_ text: String) -> String {
        copy.runtimeText(text)
    }

    private let director = PresentationDirector()
    private let screenArchiveRecorder = ScreenArchiveRecorder()
    private let microphoneArchiveRecorder = MicrophoneArchiveRecorder()
    private let recordingClock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(controlCenter: RecordingControlCenter = RecordingControlCenter()) {
        _recordingControlCenter = ObservedObject(wrappedValue: controlCenter)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ConsolePalette.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if commandController.isRecording {
                    Rectangle()
                        .fill(ConsolePalette.record)
                        .frame(height: 2)
                }

                topBar

                Divider()
                    .overlay(ConsolePalette.border)

                mainWorkspace

                footerArea
            }

            HelpBubble()
                .padding(.trailing, 10)
                .padding(.bottom, 10)
        }
        .sheet(item: $calibrationFlow) { flow in
            calibrationSheet(flow)
        }
        .sheet(item: $commandController.programPreviewRequest) { request in
            ProgramPreviewSheet(copy: copy, url: request.url)
        }
        .sheet(isPresented: $showsExportSettings) {
            exportSettingsSheet
        }
        .sheet(item: $exportProgress) { progress in
            ExportProgressSheet(
                copy: copy,
                progress: progress,
                cancel: cancelActiveProgramRender
            )
        }
        .alert(item: $exportOutcome) { outcome in
            if let url = outcome.url {
                Alert(
                    title: Text(outcome.title),
                    message: Text(outcome.message),
                    primaryButton: .default(Text(copy.revealProject)) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    },
                    secondaryButton: .cancel(Text(copy.runtimeText("关闭")))
                )
            } else {
                Alert(
                    title: Text(outcome.title),
                    message: Text(outcome.message),
                    dismissButton: .default(Text(copy.runtimeText("确定")))
                )
            }
        }
        .sheet(isPresented: $showsScreenSourcePicker) {
            ScreenSourcePickerSheet(
                copy: copy,
                options: screenWindowOptions,
                diagnostic: screenSourceDiagnostic,
                thumbnails: screenSourceThumbnails,
                viewMode: $screenSourcePickerMode,
                selectedIDs: $selectedScreenSourceIDs,
                sourceSlots: $recordingSourceSlots,
                featureTier: $recordingFeatureTier,
                persistSourceSlots: {
                    persistRecordingSourceSlots()
                },
                persistFeatureTier: {
                    persistRecordingFeatureTier()
                },
                apply: { selectedIDs in
                    applyScreenSourceSelection(selectedIDs)
                },
                refresh: {
                    refreshScreenWindowOptions()
                },
                requestPermission: {
                    requestScreenCapturePermissionFromPicker()
                },
                openSettings: {
                    commandController.openScreenRecordingSettings()
                }
            )
        }
        .alert(copy.runtimeText("是否保存本次录制？"), isPresented: $showsFinishRecordingAlert) {
            Button(copy.runtimeText("保存录制")) {
                finishRecording(save: true)
            }
            Button(copy.runtimeText("丢弃录制"), role: .destructive) {
                finishRecording(save: false)
            }
            Button(copy.cancel, role: .cancel) {}
        } message: {
            Text(copy.runtimeText("保存后会生成原始轨并尝试合成视频；丢弃会删除本次录制项目。"))
        }
        .onAppear {
            applyDistributionPolicy()
            configureRecordingControlCenter()
            syncRecordingControlCenter()
            commandController.refreshAccessibilityStatus()
            updateGestureHandler()
            installScreenArchivePreviewHandler()
            camera.updatePreviewEffects(effectivePresenterVideoEffects)
            camera.start()
            refreshAudioInputDevices()
            restartScreenPreviewIfNeeded()
            installRecordingHotKeyMonitor()
        }
        .onChange(of: target) {
            updateGestureHandler()
            handleScreenCaptureSourceChange()
        }
        .onChange(of: screenSourcePreference) {
            handleScreenCaptureSourceChange()
        }
        .onChange(of: recordingFeatureTier) {
            persistRecordingFeatureTier()
            applyDistributionPolicy()
            syncRecordingControlCenter()
        }
        .onChange(of: layout) {
            restartScreenPreviewIfNeeded()
            recordCurrentLayoutKeyframeIfNeeded(force: true)
        }
        .onChange(of: commandController.isRecording) {
            if commandController.isRecording {
                beginRecordingCaptureSession()
                if let session = commandController.lastRecordingSession {
                    if session.requiresPresenterCameraTrack {
                        do {
                            try camera.startCameraArchiveRecording(to: session.presenterCameraURL)
                        } catch {
                            commandController.reportRecordingIssue("讲者摄像头原始轨写入失败：\(error.localizedDescription)")
                        }
                    }
                    if session.requiresSlidesScreenTrack {
                        startScreenArchiveRecording(
                            to: session.slidesScreenURL,
                            target: target,
                            sourcePreference: screenSourcePreference,
                            recordingPixelSize: screenArchiveRecordingPixelSize
                        )
                    }
                    startMicrophoneArchiveRecording(to: session.microphoneAudioURL)
                }
            } else {
                if shouldRenderStoppedRecording {
                    updatePresenterVideoEffectsForLastRecording()
                    finalizeRecordingTimelineForLastRecording()
                }
                stopRecordingAndRenderProgram(
                    shouldRender: shouldRenderStoppedRecording,
                    discardSession: discardStoppedRecording
                )
                resetRecordingStateAfterStop(preserveTimeline: shouldRenderStoppedRecording)
            }
            syncRecordingControlCenter()
        }
        .onChange(of: recordingControlState) {
            syncRecordingControlCenter()
        }
        .onChange(of: elapsedSeconds) {
            syncRecordingControlCenter()
        }
        .onChange(of: pipOffset) {
            recordCurrentPiPKeyframeIfNeeded()
        }
        .onChange(of: pipScale) {
            recordCurrentPiPKeyframeIfNeeded()
        }
        .onChange(of: pipShape) {
            recordCurrentPiPKeyframeIfNeeded(force: true)
        }
        .onChange(of: presenterSmartBeautyEnabled) {
            handleSmartBeautyToggleChange()
        }
        .onChange(of: presenterAdvancedBeautyEnabled) {
            handleAdvancedBeautyToggleChange()
        }
        .onChange(of: presenterBackgroundReplacementEnabled) {
            handleBackgroundReplacementToggleChange()
        }
        .onChange(of: presenterEmojiFaceReplacementEnabled) {
            handleEmojiFaceReplacementToggleChange()
        }
        .onChange(of: effectivePresenterVideoEffects) {
            handlePresenterVideoEffectsChange()
        }
        .onReceive(recordingClock) { _ in
            guard commandController.isRecording, recordingControlState == .recording else {
                return
            }
            elapsedSeconds = Int(currentActiveRecordingDuration().rounded(.down))
        }
        .onDisappear(perform: handleDashboardDisappear)
    }

    private func handleDashboardDisappear() {
        cancelActiveProgramRender()
        removeRecordingHotKeyMonitor()
        recordingCountdownTask?.cancel()
        screenSourceThumbnailTask?.cancel()
        recordingCountdownPresenter.hide()
        screenArchiveRecorder.onPreviewImage = nil
        screenPreview.stop()
        stopRecordingAndRenderProgram(shouldRender: false)
        camera.stop()
    }

    private func applyDistributionPolicy() {
        if WonderShowDistribution.isCommunityEdition {
            recordingFeatureTier = WonderShowDistribution.defaultRecordingFeatureTier
        }
        if !WonderShowDistribution.includesGestureControl {
            camera.gestureControlEnabled = false
            camera.onGestureRecognized = nil
            camera.onGestureRecognizedWithMotion = nil
            camera.onZoomChanged = nil
            camera.onPanChanged = nil
            calibrationFlow = nil
            showsGestureCheatsheet = false
            if commandController.isRehearsing {
                commandController.toggleRehearsal(target: target)
            }
        }
        if !permitsSubjectAwareBeauty {
            presenterSmartBeautyEnabled = false
            presenterAdvancedBeautyEnabled = false
            presenterPortraitSegmentationEnabled = false
            presenterBackgroundBlur = 0
            presenterBackgroundReplacementEnabled = false
            presenterBackgroundReplacementStrength = 0
            presenterFaceLandmarkBeautyEnabled = false
            presenterFaceSlimming = 0
            presenterEyeEnlargement = 0
            presenterEmojiFaceReplacementEnabled = false
            presenterEmojiFaceReplacementScale = 1
            presenterBeautyControlsExpanded = false
        }
    }

    private func handleSmartBeautyToggleChange() {
        guard permitsSubjectAwareBeauty else {
            presenterSmartBeautyEnabled = false
            return
        }
        if presenterSmartBeautyEnabled {
            seedSubjectAwareBeautyDefaultsIfNeeded()
        }
    }

    private func handleAdvancedBeautyToggleChange() {
        guard permitsSubjectAwareBeauty else {
            presenterAdvancedBeautyEnabled = false
            presenterFaceLandmarkBeautyEnabled = false
            return
        }
        if presenterAdvancedBeautyEnabled {
            presenterSmartBeautyEnabled = true
            presenterFaceLandmarkBeautyEnabled = true
        }
    }

    private func handleBackgroundReplacementToggleChange() {
        guard permitsSubjectAwareBeauty else {
            presenterBackgroundReplacementEnabled = false
            presenterBackgroundReplacementStrength = 0
            return
        }
        if presenterBackgroundReplacementEnabled {
            presenterPortraitSegmentationEnabled = true
            if presenterBackgroundReplacementStrength == 0 {
                presenterBackgroundReplacementStrength = 0.72
            }
        }
    }

    private func handleEmojiFaceReplacementToggleChange() {
        guard permitsSubjectAwareBeauty else {
            presenterEmojiFaceReplacementEnabled = false
            presenterEmojiFaceReplacementScale = 1
            return
        }
        guard presenterEmojiFaceReplacementEnabled else {
            return
        }
        presenterEmojiFaceReplacementScale = max(0.68, presenterEmojiFaceReplacementScale)
    }

    private func handlePresenterVideoEffectsChange() {
        camera.updatePreviewEffects(effectivePresenterVideoEffects)
        updatePresenterVideoEffectsForLastRecording()
    }

    /// 将当前手势和缩放回调绑定到选中的演示目标，避免目标切换时投递错位。
    private func updateGestureHandler() {
        guard WonderShowDistribution.includesGestureControl else {
            camera.gestureControlEnabled = false
            camera.onGestureRecognized = nil
            camera.onGestureRecognizedWithMotion = nil
            camera.onZoomChanged = nil
            camera.onPanChanged = nil
            return
        }
        let currentTarget = target
        camera.onGestureRecognized = { gesture in
            commandController.handle(gesture, target: currentTarget)
        }
        camera.onGestureRecognizedWithMotion = { gesture, velocity in
            commandController.handle(gesture, target: currentTarget, swipeVelocity: velocity)
        }
        camera.onZoomChanged = { scale in
            commandController.setZoom(scale, target: currentTarget)
        }
        camera.onPanChanged = { x, y in
            commandController.setPan(x: x, y: y, target: currentTarget)
        }
    }

    private func configureRecordingControlCenter() {
        recordingControlCenter.featureTier = recordingFeatureTier
        recordingControlCenter.primaryAction = {
            requestRecordingToggle()
        }
        recordingControlCenter.stopAction = {
            requestFinishRecording()
        }
        recordingControlCenter.revealMainWindowAction = {
            revealMainWindow()
        }
        recordingControlCenter.showSourcePickerAction = {
            revealMainWindow()
            refreshScreenWindowOptions()
            showsScreenSourcePicker = true
        }
        recordingControlCenter.switchSourceSlotAction = { slot in
            _ = requestRecordingSourceSlotSwitch(slot)
        }
    }

    private func syncRecordingControlCenter() {
        recordingControlCenter.featureTier = recordingFeatureTier
        recordingControlCenter.state = RecordingControlSurfaceState(
            controlState: recordingControlState,
            elapsedSeconds: elapsedSeconds
        )
    }

    private func revealMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows
            .filter { $0.canBecomeMain || $0.canBecomeKey }
            .forEach { window in
                window.makeKeyAndOrderFront(nil)
            }
    }

    private func requestRecordingToggle() {
        switch recordingControlState {
        case .idle:
            startRecordingCountdown()
        case .starting:
            cancelRecordingCountdown()
        case .recording:
            pauseRecording()
        case .paused:
            resumeRecording()
        }
    }

    private func startRecordingCountdown() {
        guard recordingControlState == .idle else {
            return
        }

        recordingControlState = .starting
        recordingCountdownTask?.cancel()
        recordingCountdownTask = Task { @MainActor in
            for value in stride(from: 3, through: 1, by: -1) {
                recordingCountdownPresenter.show(count: value)
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else {
                    recordingCountdownPresenter.hide()
                    return
                }
            }
            recordingCountdownPresenter.showRecordingStarted()
            shouldRenderStoppedRecording = true
            discardStoppedRecording = false
            commandController.toggleRecording(
                scenario: recordingScenario,
                cameraName: camera.activeDeviceName,
                mode: mode,
                layout: layout,
                pictureInPictureGeometry: currentPictureInPictureGeometry,
                presenterVideoEffects: effectivePresenterVideoEffects
            )
            if !commandController.isRecording {
                recordingControlState = .idle
                elapsedSeconds = 0
            }
            try? await Task.sleep(for: .milliseconds(700))
            recordingCountdownPresenter.hide()
        }
    }

    private func cancelRecordingCountdown() {
        recordingCountdownTask?.cancel()
        recordingCountdownTask = nil
        recordingCountdownPresenter.hide()
        if !commandController.isRecording {
            recordingControlState = .idle
            elapsedSeconds = 0
        }
    }

    private func beginRecordingCaptureSession() {
        let now = Date()
        elapsedSeconds = 0
        accumulatedRecordingDuration = 0
        recordingActiveStartedAt = now
        latestScreenPreviewImage = nil
        latestScreenPreviewSourceID = nil
        recordingStartedAt = now
        recordingPiPKeyframes = initialPiPKeyframes()
        recordingLayoutKeyframes = initialLayoutKeyframes()
        lastPiPKeyframeDate = now
        recordingControlState = .recording
    }

    private func pauseRecording() {
        guard commandController.isRecording, recordingControlState == .recording else {
            return
        }
        recordCurrentPiPKeyframeIfNeeded(force: true)
        commitActiveRecordingDuration()
        camera.pauseCameraArchiveRecording()
        screenArchiveRecorder.pauseRecording()
        microphoneArchiveRecorder.pauseRecording()
        recordingControlState = .paused
        recordingActiveStartedAt = nil
        elapsedSeconds = Int(accumulatedRecordingDuration.rounded(.down))
        commandController.reportRecordingProgress("录制已暂停")
    }

    private func resumeRecording() {
        guard commandController.isRecording, recordingControlState == .paused else {
            return
        }
        recordingActiveStartedAt = Date()
        camera.resumeCameraArchiveRecording()
        screenArchiveRecorder.resumeRecording()
        microphoneArchiveRecorder.resumeRecording()
        recordingControlState = .recording
        recordCurrentPiPKeyframeIfNeeded(force: true)
        commandController.reportRecordingProgress("录制已继续")
    }

    private func requestFinishRecording() {
        guard commandController.isRecording || recordingControlState == .starting else {
            return
        }
        if recordingControlState == .starting {
            cancelRecordingCountdown()
            return
        }
        commitActiveRecordingDuration()
        showsFinishRecordingAlert = true
    }

    private func finishRecording(save: Bool) {
        guard commandController.isRecording else {
            resetRecordingStateAfterStop()
            return
        }
        recordingCountdownTask?.cancel()
        recordingCountdownPresenter.hide()
        commitActiveRecordingDuration()
        shouldRenderStoppedRecording = save
        discardStoppedRecording = !save
        commandController.toggleRecording(
            scenario: recordingScenario,
            cameraName: camera.activeDeviceName,
            mode: mode,
            layout: layout,
            pictureInPictureGeometry: currentPictureInPictureGeometry,
            presenterVideoEffects: effectivePresenterVideoEffects
        )
    }

    private func commitActiveRecordingDuration() {
        guard let recordingActiveStartedAt else {
            return
        }
        accumulatedRecordingDuration += max(0, Date().timeIntervalSince(recordingActiveStartedAt))
        self.recordingActiveStartedAt = nil
    }

    private func currentActiveRecordingDuration() -> TimeInterval {
        if let recordingActiveStartedAt, recordingControlState == .recording {
            return accumulatedRecordingDuration + max(0, Date().timeIntervalSince(recordingActiveStartedAt))
        }
        return accumulatedRecordingDuration
    }

    private func resetRecordingStateAfterStop(preserveTimeline: Bool = false) {
        recordingControlState = .idle
        recordingCountdownTask = nil
        recordingCountdownPresenter.hide()
        if !preserveTimeline {
            elapsedSeconds = 0
        }
        accumulatedRecordingDuration = 0
        recordingActiveStartedAt = nil
        recordingStartedAt = nil
        if !preserveTimeline {
            recordingPiPKeyframes = []
            recordingLayoutKeyframes = []
            timelinePlayheadMilliseconds = 0
            selectedTimelineRange = nil
        }
        lastPiPKeyframeDate = nil
        shouldRenderStoppedRecording = true
        discardStoppedRecording = false
    }

    private func installRecordingHotKeyMonitor() {
        guard localRecordingHotKeyMonitor == nil, globalRecordingHotKeyMonitor == nil else {
            return
        }

        localRecordingHotKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if let slot = RecordingSourceSlotHotKey.slot(for: event),
               requestRecordingSourceSlotSwitch(slot) {
                return nil
            }
            if let action = RecordingControlHotKey.action(for: event) {
                handleRecordingHotKey(action)
                return nil
            }
            return event
        }
        globalRecordingHotKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if let slot = RecordingSourceSlotHotKey.slot(for: event) {
                _ = requestRecordingSourceSlotSwitch(slot)
            }
            if let action = RecordingControlHotKey.action(for: event) {
                handleRecordingHotKey(action)
            }
        }
    }

    private func removeRecordingHotKeyMonitor() {
        if let monitor = localRecordingHotKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localRecordingHotKeyMonitor = nil
        }
        if let monitor = globalRecordingHotKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalRecordingHotKeyMonitor = nil
        }
    }

    private func handleRecordingHotKey(_ action: RecordingControlHotKeyAction) {
        switch action {
        case .toggleStartPauseResume:
            requestRecordingToggle()
        case .pauseResume:
            switch recordingControlState {
            case .recording:
                pauseRecording()
            case .paused:
                resumeRecording()
            case .idle, .starting:
                break
            }
        case .finish:
            switch recordingControlState {
            case .starting, .recording, .paused:
                requestFinishRecording()
            case .idle:
                break
            }
        }
    }

    @discardableResult
    private func requestRecordingSourceSlotSwitch(_ slot: Int) -> Bool {
        guard currentProgramUsesScreen else {
            return false
        }
        guard recordingFeatureTier.permitsSourceSlot(slot) else {
            commandController.reportRecordingIssue(
                "\(recordingFeatureTier.localizedLabel(copy)) \(copy.text("sourceSlotLocked")) \(slot)"
            )
            return true
        }
        switchToRecordingSourceSlot(slot)
        return true
    }

    private func startScreenArchiveRecording(
        to outputURL: URL,
        target: PresentationTarget,
        sourcePreference: ScreenCaptureSourcePreference,
        recordingPixelSize: ScreenArchiveRecorder.CapturePixelSize
    ) {
        Task {
            do {
                try await screenArchiveRecorder.startRecording(
                    to: outputURL,
                    target: target,
                    sourcePreference: sourcePreference,
                    recordingPixelSize: recordingPixelSize
                )
            } catch {
                await MainActor.run {
                    commandController.reportRecordingIssue("PPT/屏幕原始轨写入失败：\(error.localizedDescription)。请在系统设置中允许灵演进行屏幕录制。")
                }
            }
        }
    }

    private var screenArchiveRecordingPixelSize: ScreenArchiveRecorder.CapturePixelSize {
        let pixelSize = programCanvasAspect.pixelSize(for: programCanvasResolution)
        return ScreenArchiveRecorder.CapturePixelSize(
            width: pixelSize.width,
            height: pixelSize.height
        )
    }

    private func stopScreenArchiveRecording() {
        Task {
            await screenArchiveRecorder.stopRecording()
        }
    }

    private func startMicrophoneArchiveRecording(to outputURL: URL) {
        Task {
            do {
                try await microphoneArchiveRecorder.startRecording(
                    to: outputURL,
                    deviceID: selectedAudioInputDeviceID
                )
            } catch {
                await MainActor.run {
                    commandController.reportRecordingIssue("麦克风原始轨写入失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func stopMicrophoneArchiveRecording() {
        Task {
            await microphoneArchiveRecorder.stopRecording()
        }
    }

    private func stopRecordingAndRenderProgram(shouldRender: Bool, discardSession: Bool = false) {
        guard let session = commandController.lastRecordingSession else {
            stopScreenArchiveRecording()
            stopMicrophoneArchiveRecording()
            return
        }
        let renderSettings = programCanvasExportSettings

        Task {
            await camera.stopCameraArchiveRecording()
            let screenSummary = await screenArchiveRecorder.stopRecording()
            await microphoneArchiveRecorder.stopRecording()
            if discardSession {
                await MainActor.run {
                    commandController.discardLastRecordingSession(deleteFiles: true)
                }
                return
            }
            guard shouldRender else {
                return
            }
            if session.requiresSlidesScreenTrack, let issue = screenSummary.issueDescription {
                await MainActor.run {
                    commandController.reportRecordingIssue("PPT/屏幕原始轨写入失败：\(issue)")
                }
                return
            }
            do {
                let renderSession = await MainActor.run {
                    commandController.lastRecordingSession ?? session
                }
                let outputURL = try await ProgramVideoRenderer().render(
                    session: renderSession,
                    settings: renderSettings
                )
                await MainActor.run {
                    commandController.reportRecordingProgress("program 视频已导出：\(outputURL.path)")
                }
            } catch {
                await MainActor.run {
                    commandController.reportRecordingIssue("program 视频暂未导出：\(error.localizedDescription)")
                }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 18) {
            HStack(spacing: 10) {
                Group {
                    if let nsImage = NSImage(named: "AppIcon") {
                        Image(nsImage: nsImage)
                            .resizable()
                    } else if let nsImage = NSApplication.shared.applicationIconImage {
                        Image(nsImage: nsImage)
                            .resizable()
                    } else {
                        Image(systemName: "video.fill")
                            .resizable()
                    }
                }
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(ConsolePalette.border, lineWidth: 1)
                    )
                    .shadow(color: ConsolePalette.gold.opacity(0.22), radius: 10, x: 0, y: 2)
                    .accessibilityHidden(true)

                Text(WonderShowDistribution.presentation.productName(for: copy))
                    .font(.system(size: 17, weight: .bold, design: .serif))
                    .foregroundStyle(ConsolePalette.textPrimary)
                    .tracking(1.2)

                Rectangle()
                    .fill(ConsolePalette.border)
                    .frame(width: 1, height: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(copy.brandLine1)
                        .font(.system(size: 13, weight: .bold, design: .serif))
                        .foregroundStyle(ConsolePalette.textPrimary)
                        .tracking(2.2)
                    Text(WonderShowDistribution.presentation.brandLine2(for: copy))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(ConsolePalette.textTertiary)
                        .tracking(2.4)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                ConsoleStatusPill(
                    icon: "camera",
                    title: copy.camera,
                    value: cameraStatusValue,
                    isActive: camera.status == .running,
                    isRecording: false
                )
                if WonderShowDistribution.includesGestureControl {
                    ConsoleStatusPill(
                        icon: "hand.raised",
                        title: copy.gesture,
                        value: camera.gestureControlEnabled ? copy.recognizing : copy.standby,
                        isActive: camera.gestureControlEnabled,
                        isRecording: false
                    )
                }
                ConsoleStatusPill(
                    icon: "rectangle.on.rectangle",
                    title: copy.target,
                    value: target.localizedLabel(copy),
                    isActive: true,
                    isRecording: false
                )
                ConsoleStatusPill(
                    icon: "record.circle",
                    title: copy.rec,
                    value: "\(recordingStatusLabel) · \(elapsedTime)",
                    isActive: commandController.isRecording || recordingControlState == .starting,
                    isRecording: true
                )
            }

            Spacer(minLength: 12)

            HStack(spacing: 12) {
                HStack(spacing: 0) {
                    ForEach(AppLanguage.allCases, id: \.self) { tab in
                        Button(tab.label) {
                            displayLanguage = tab
                        }
                        .buttonStyle(LanguageTabButtonStyle(isSelected: displayLanguage == tab))
                    }
                }
                .background(ConsolePalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(ConsolePalette.border, lineWidth: 1)
                )

                if WonderShowDistribution.includesGestureControl {
                    Button(commandController.isRehearsing ? copy.stopRehearse : copy.rehearsalButton) {
                        commandController.toggleRehearsal(target: target)
                    }
                    .buttonStyle(ConsoleGradientButtonStyle(variant: .gold, expands: false))
                }

                recordingControls
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .background(ConsolePalette.background)
    }

    @ViewBuilder
    private var recordingControls: some View {
        switch recordingControlState {
        case .idle:
            Button(copy.recordButton) {
                requestRecordingToggle()
            }
            .buttonStyle(ConsoleGradientButtonStyle(variant: .danger, expands: false))
        case .starting:
            Button(copy.runtimeText("倒计时中")) {
                cancelRecordingCountdown()
            }
            .buttonStyle(ConsoleGradientButtonStyle(variant: .outline, expands: false))
        case .recording:
            HStack(spacing: 8) {
                Button(copy.runtimeText("暂停录制")) {
                    pauseRecording()
                }
                .buttonStyle(ConsoleGradientButtonStyle(variant: .gold, expands: false))

                Button(copy.runtimeText("终止录制")) {
                    requestFinishRecording()
                }
                .buttonStyle(ConsoleGradientButtonStyle(variant: .danger, expands: false))
            }
        case .paused:
            HStack(spacing: 8) {
                Button(copy.runtimeText("继续录制")) {
                    resumeRecording()
                }
                .buttonStyle(ConsoleGradientButtonStyle(variant: .gold, expands: false))

                Button(copy.runtimeText("终止录制")) {
                    requestFinishRecording()
                }
                .buttonStyle(ConsoleGradientButtonStyle(variant: .danger, expands: false))
            }
        }
    }

    private var mainWorkspace: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 10) {
                previewWorkspace
                recordingTimelineStrip
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .zIndex(3)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    quickStartPanel
                    presentationPanel
                    projectPanel
                    if WonderShowDistribution.includesGestureControl {
                        gesturePanel
                    }
                    devicePanel
                }
                .padding(.bottom, 12)
            }
            .frame(width: 300)
            .zIndex(0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var previewWorkspace: some View {
        monitorSurface
        .zIndex(12)
    }

    private var monitorSurface: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ConsolePalette.previewBase)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(ConsolePalette.border, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.75), radius: 24, x: 0, y: 12)

            ProgramMonitorView(
                copy: copy,
                layout: layout,
                canvasAspectRatio: programCanvasAspect.aspectRatio,
                screenImage: monitorScreenImage,
                screenSourceID: monitorScreenSourceID,
                cameraPreviewImage: camera.latestPreviewImage,
                cameraSession: camera.session,
                cameraStatus: camera.status,
                cameraStatusDetail: cameraRecoveryHint,
                cameraActionTitle: cameraPrimaryActionTitle,
                screenSourceLabel: monitorScreenStatusLabel,
                isRecording: commandController.isRecording,
                pipOffset: $pipOffset,
                pipScale: $pipScale,
                pipShape: pipShape,
                presenterVideoEffects: effectivePresenterVideoEffects,
                canvasSizeChanged: { size in
                    monitorCanvasSize = size
                },
                pipInteractionEnded: {
                    recordCurrentPiPKeyframeIfNeeded(force: true)
                },
                pipCornerChanged: { corner in
                    updatePiPCorner(corner)
                },
                reconnect: { handleCameraPrimaryAction() }
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(commandController.isRecording ? ConsolePalette.record : ConsolePalette.teal)
                        .frame(width: 6, height: 6)
                    Text(copy.live)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ConsolePalette.textPrimary)
                        .tracking(1.2)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding([.top, .leading], 12)
                .frame(maxHeight: .infinity, alignment: .topLeading)
            }

            ProgramCanvasControls(
                copy: copy,
                aspect: $programCanvasAspect,
                resolution: $programCanvasResolution,
                showsAdvancedPresenterEffectsUI: WonderShowDistribution.showsAdvancedPresenterEffectsUI,
                presenterBeautyControlsExpanded: $presenterBeautyControlsExpanded,
                presenterSmartBeautyEnabled: $presenterSmartBeautyEnabled,
                presenterBeauty: $presenterBeauty,
                presenterBeautyStyle: $presenterBeautyStyle,
                presenterSkinSmoothing: $presenterSkinSmoothing,
                presenterSkinBrightening: $presenterSkinBrightening,
                presenterSkinWhitening: $presenterSkinWhitening,
                presenterBlemishReduction: $presenterBlemishReduction,
                presenterComplexion: $presenterComplexion,
                presenterAdvancedBeautyEnabled: $presenterAdvancedBeautyEnabled,
                presenterPortraitSegmentationEnabled: $presenterPortraitSegmentationEnabled,
                presenterBackgroundBlur: $presenterBackgroundBlur,
                presenterBackgroundReplacementEnabled: $presenterBackgroundReplacementEnabled,
                presenterBackgroundReplacementStrength: $presenterBackgroundReplacementStrength,
                presenterFaceLandmarkBeautyEnabled: $presenterFaceLandmarkBeautyEnabled,
                presenterFaceSlimming: $presenterFaceSlimming,
                presenterEyeEnlargement: $presenterEyeEnlargement,
                presenterEmojiFaceReplacementEnabled: $presenterEmojiFaceReplacementEnabled,
                presenterEmojiFaceReplacementSymbol: $presenterEmojiFaceReplacementSymbol,
                presenterEmojiFaceReplacementScale: $presenterEmojiFaceReplacementScale,
                onBeautyEditingEnded: handlePresenterVideoEffectsChange,
                onBeautyEnabled: seedSubjectAwareBeautyDefaultsIfNeeded,
                isSubjectAwareBeautyPermitted: permitsSubjectAwareBeauty
            )
            .frame(width: 48, height: WonderShowDistribution.showsAdvancedPresenterEffectsUI ? 258 : 106)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .padding(.trailing, 12)
            .zIndex(20)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
    }

    private var recordingTimelineStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "timeline.selection")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ConsolePalette.textTertiary)
                Text(copy.text("timelineTitle"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ConsolePalette.textPrimary)
                Spacer()
                Text(timelineHint)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ConsolePalette.textTertiary)
                    .lineLimit(1)
            }

            VStack(spacing: 5) {
                ForEach(timelineRows) { row in
                    TimelineTrackRow(
                        row: row,
                        selectedRange: selectedTimelineRange,
                        playheadFraction: timelinePlayheadFraction,
                        toggleCollapsed: {
                            toggleTimelineTrack(row.id)
                        },
                        selectSegment: { segment in
                            selectTimelineSegment(segment)
                        }
                    )
                }
            }

            timelineSelectionControls
        }
        .padding(12)
        .background(ConsolePalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(ConsolePalette.border, lineWidth: 1)
        )
    }

    private var timelineSelectionControls: some View {
        HStack(spacing: 8) {
            Text(timelineSelectionSummary)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(ConsolePalette.textTertiary)
                .lineLimit(1)

            Spacer()

            Button(copy.text("timelineFullProgram")) {
                selectedTimelineRange = nil
                commandController.reportRecordingProgress(copy.text("timelineFullProgramSelected"))
            }
            .buttonStyle(TimelineMiniButtonStyle())
            .disabled(selectedTimelineRange == nil)

            Button(copy.text("timelineClearSelection")) {
                selectedTimelineRange = nil
            }
            .buttonStyle(TimelineMiniButtonStyle())
            .disabled(selectedTimelineRange == nil)

            Button(copy.text("timelineExportRange")) {
                saveCurrentPiPTimelineForLastRecording()
                exportDraftSettings = programCanvasExportSettings
                showsExportSettings = true
            }
            .buttonStyle(TimelineMiniButtonStyle())
            .disabled(commandController.lastRecordingSession == nil || selectedTimelineRange == nil)
        }
    }

    private var quickStartPanel: some View {
        VStack(spacing: 0) {
            CardHeader(title: copy.quickStart, hint: copy.realtime, isCollapsed: quickStartCollapsed) {
                quickStartCollapsed.toggle()
            }

            if !quickStartCollapsed {
                VStack(alignment: .leading, spacing: 10) {
                    ConsoleDetailLine(label: copy.recState, value: commandController.isRecording ? copy.recording : copy.standby)
                    ConsoleDetailLine(label: copy.activeDevice, value: localizedActiveDeviceName)
                    if WonderShowDistribution.includesGestureControl {
                        ConsoleDetailLine(label: copy.rehearseState, value: commandController.isRehearsing ? copy.recording : copy.ready)
                        ConsoleDetailLine(label: copy.rehearse, value: copy.rehearsalPurpose)
                        ConsoleDetailLine(label: copy.currentGesture, value: localizedDetectedHandShapes)
                    }

                    ConsoleDivider()

                    HStack(spacing: 7) {
                        Button(copy.refreshDevices) {
                            camera.refreshDevicesAndRestart()
                        }
                        .buttonStyle(ConsoleGradientButtonStyle(variant: .gold, expands: true))

                        if WonderShowDistribution.includesGestureControl {
                            Button(copy.testSlide) {
                                commandController.testNextSlide(target: target)
                            }
                            .buttonStyle(ConsoleGradientButtonStyle(variant: .gold, expands: true))
                        }
                    }
                }
                .padding(14)
            }
        }
        .consoleCardSurface()
    }

    private var projectPanel: some View {
        VStack(spacing: 0) {
            CardHeader(title: copy.projectTitle, hint: projectPanelHint, isCollapsed: projectCollapsed) {
                projectCollapsed.toggle()
            }

            if !projectCollapsed {
                VStack(alignment: .leading, spacing: 10) {
                    ConsoleDetailLine(label: copy.projectLocation, value: projectLocationSummary, monospaced: true)
                    ConsoleDetailLine(label: copy.rawTracks, value: rawTrackSummary)
                    ConsoleDetailLine(label: copy.programExport, value: programExportSummary, monospaced: true)

                    ConsoleDivider()

                    HStack(spacing: 7) {
                        Button(copy.text("importProject")) {
                            commandController.importRecordingProject()
                        }
                        .buttonStyle(ConsoleGradientButtonStyle(variant: .outline, expands: true))

                        Button(copy.openProject) {
                            commandController.openLastRecordingProject()
                        }
                        .buttonStyle(ConsoleGradientButtonStyle(variant: .gold, expands: true))
                        .disabled(commandController.lastRecordingSession == nil)

                        Button(copy.previewProgram) {
                            saveCurrentPiPTimelineForLastRecording()
                            previewProgramExport()
                        }
                        .buttonStyle(ConsoleGradientButtonStyle(variant: .outline, expands: true))
                        .disabled(commandController.lastRecordingSession == nil)
                    }

                    HStack(spacing: 7) {
                        Button(copy.text("exportProject")) {
                            commandController.exportRecordingProject()
                        }
                        .buttonStyle(ConsoleGradientButtonStyle(variant: .outline, expands: true))
                        .disabled(commandController.lastRecordingSession == nil)

                        Button(copy.text("exportVideo")) {
                            saveCurrentPiPTimelineForLastRecording()
                            exportDraftSettings = programCanvasExportSettings
                            showsExportSettings = true
                        }
                        .buttonStyle(ConsoleGradientButtonStyle(variant: .outline, expands: true))
                        .disabled(commandController.lastRecordingSession == nil)
                    }

                    Button(copy.revealProject) {
                        commandController.revealLastRecordingProject()
                    }
                    .buttonStyle(ConsoleGradientButtonStyle(variant: .outline, expands: true))
                    .disabled(commandController.lastRecordingSession == nil)
                }
                .padding(14)
            }
        }
        .consoleCardSurface()
    }

    private var presentationPanel: some View {
        VStack(spacing: 0) {
            CardHeader(title: copy.presentSettings, hint: copy.auto, isCollapsed: presentationCollapsed) {
                presentationCollapsed.toggle()
            }

            if !presentationCollapsed {
                VStack(alignment: .leading, spacing: 8) {
                    MenuControlRow(label: copy.targetApp) {
                        Menu {
                            Button(copy.appPPT) { target = .powerPoint }
                            Button(copy.appWPS) { target = .wps }
                            Button(copy.appKeynote) { target = .keynote }
                            Button(copy.appWord) { target = .word }
                            Button(copy.appExcel) { target = .excel }
                            Button(copy.appPDF) { target = .pdfViewer }
                            Button(copy.appHTML) { target = .html(engine: .revealJS) }
                        } label: {
                            MenuFieldLabel(text: target.localizedLabel(copy))
                        }
                        .menuStyle(.borderlessButton)
                        .buttonStyle(.plain)
                    }

                    MenuControlRow(label: copy.text("screenCaptureSource")) {
                        Menu {
                            Button(copy.text("chooseWindows")) {
                                refreshScreenWindowOptions()
                                showsScreenSourcePicker = true
                            }
                            Button(copy.text("sourcePresentationWindow")) {
                                selectedScreenSourceIDs = []
                                screenSourcePreference = .automaticPresentationWindow
                            }
                            Button(copy.text("sourceEntireDisplay")) {
                                selectedScreenSourceIDs = []
                                screenSourcePreference = .entireDisplay
                            }
                        } label: {
                            MenuFieldLabel(text: screenSourcePreference.localizedLabel(copy))
                        }
                        .menuStyle(.borderlessButton)
                        .buttonStyle(.plain)
                    }

                    MenuControlRow(label: copy.recMode) {
                        Menu {
                            Button(copy.text("modeScreenOnly")) {
                                applyRecordingPreset(mode: .screenOnly, layout: .screenOnly)
                            }
                            Button(copy.text("modeSpeakerOnly")) {
                                applyRecordingPreset(mode: .cameraOnly, layout: .speakerCloseUp)
                            }
                            Button(copy.modeCamScreen) {
                                applyRecordingPreset(
                                    mode: .cameraAndScreen,
                                    layout: .screenWithCameraPictureInPicture(corner: .bottomRight)
                                )
                            }
                        } label: {
                            MenuFieldLabel(text: mode.localizedLabel(copy))
                        }
                        .menuStyle(.borderlessButton)
                        .buttonStyle(.plain)
                    }

                    MenuControlRow(label: copy.layout) {
                        Menu {
                            ForEach(availableLayoutOptions) { option in
                                Button(option.label) {
                                    applyLayoutSelection(option.layout)
                                }
                            }
                        } label: {
                            MenuFieldLabel(text: layout.localizedLabel(copy))
                        }
                        .menuStyle(.borderlessButton)
                        .buttonStyle(.plain)
                    }

                    if currentProgramUsesPiP {
                        VStack(alignment: .leading, spacing: 8) {
                            ConsoleFieldLabel(copy.text("pipControls"))
                            HStack(spacing: 10) {
                                Text(copy.text("pipSize"))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(ConsolePalette.textSecondary)
                                    .frame(width: 34, alignment: .leading)
                                ConsoleValueSlider(
                                    value: $pipScale,
                                    range: 0.65...1.6,
                                    onEditingEnded: {
                                        recordCurrentPiPKeyframeIfNeeded(force: true)
                                    }
                                )
                                Text("\(Int(pipScale * 100))%")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(ConsolePalette.textSecondary)
                                    .frame(width: 42, alignment: .trailing)
                            }
                            ExportOptionGrid(
                                items: PiPShape.allCases,
                                selection: $pipShape
                            ) { $0.localizedLabel(copy) }
                        }
                    }

                    if WonderShowDistribution.includesDemoDeck {
                        ConsoleDivider()

                        Button(copy.openTestDeck) {
                            target = .html(engine: .custom)
                            commandController.reportDemoDeckOpenResult(DemoDeckLauncher.openDemoDeck())
                        }
                        .buttonStyle(ConsoleGradientButtonStyle(variant: .gold, expands: true))
                    }
                }
                .padding(14)
            }
        }
        .consoleCardSurface()
    }

    private var gesturePanel: some View {
        VStack(spacing: 0) {
            CardHeader(title: copy.gestureWorkspace, hint: copy.last5min, isCollapsed: gestureCollapsed) {
                gestureCollapsed.toggle()
            }

            if !gestureCollapsed {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(copy.enableGesture)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ConsolePalette.textSecondary)
                        Spacer()
                        Toggle("", isOn: $camera.gestureControlEnabled)
                            .labelsHidden()
                            .toggleStyle(ConsoleSwitchToggleStyle())
                            .onChange(of: camera.gestureControlEnabled) {
                                commandController.refreshAccessibilityStatus()
                            }
                    }

                    ConsoleDivider()

                    ConsoleDetailLine(label: copy.recogState, value: localizedRuntime(camera.gestureStatus.rawValue))
                    ConsoleDetailLine(label: copy.session, value: localizedRuntime(camera.gestureSessionLabel))
                    ConsoleDetailLine(label: copy.engine, value: localizedRuntime(camera.gestureEngineLabel), monospaced: true)
                    ConsoleDetailLine(label: copy.zone, value: localizedGestureZoneLabel)

                    ConsoleDivider()

                    HStack {
                        Button(copy.calibrate) {
                            calibrationFlow = CalibrationFlow()
                            camera.gestureControlEnabled = true
                            camera.gestureCalibrationProfile = .easyTesting
                        }
                        .buttonStyle(ConsoleGradientButtonStyle(variant: .gold, expands: false))

                        Spacer()

                        Button {
                            showsGestureCheatsheet.toggle()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                                    .rotationEffect(.degrees(showsGestureCheatsheet ? 180 : 0))
                                Text(copy.cheatsheet)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(ConsolePalette.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }

                    if showsGestureCheatsheet {
                        VStack(spacing: 0) {
                            GestureCheatsheetRow(icon: "hand.point.right", gesture: copy.g1name, action: copy.g1result)
                            GestureCheatsheetRow(icon: "hand.point.left", gesture: copy.g2name, action: copy.g2result)
                            GestureCheatsheetRow(icon: "hand.raised", gesture: copy.g3name, action: copy.g3result)
                            GestureCheatsheetRow(icon: "arrow.up.left.and.arrow.down.right", gesture: copy.g4name, action: copy.g4result)
                        }
                    }
                }
                .padding(14)
            }
        }
        .consoleCardSurface()
    }

    private var devicePanel: some View {
        VStack(spacing: 0) {
            CardHeader(title: copy.devicesTitle, hint: copy.autoScan, isCollapsed: devicesCollapsed) {
                devicesCollapsed.toggle()
            }

            if !devicesCollapsed {
                VStack(alignment: .leading, spacing: 10) {
                    MenuControlRow(label: copy.inputDevice) {
                        HStack(spacing: 7) {
                            Menu {
                                ForEach(camera.availableDevices) { device in
                                    Button(device.name) {
                                        camera.selectDevice(id: device.id)
                                    }
                                }
                            } label: {
                                MenuFieldLabel(text: localizedSelectedDeviceTitle)
                            }
                            .menuStyle(.borderlessButton)
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)

                            Button(copy.rescan) {
                                camera.refreshDevicesAndRestart()
                            }
                            .buttonStyle(ConsoleGradientButtonStyle(variant: .gold, expands: false, compact: true))
                        }
                    }

                    MenuControlRow(label: copy.text("audioInput")) {
                        HStack(spacing: 7) {
                            Menu {
                                ForEach(audioInputDevices) { device in
                                    Button(localizedAudioInputName(device)) {
                                        selectedAudioInputDeviceID = device.id
                                    }
                                }
                            } label: {
                                MenuFieldLabel(text: selectedAudioInputDeviceTitle)
                            }
                            .menuStyle(.borderlessButton)
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)

                            Button(copy.rescan) {
                                refreshAudioInputDevices()
                            }
                            .buttonStyle(ConsoleGradientButtonStyle(variant: .gold, expands: false, compact: true))
                        }
                    }

                    presenterVideoEffectsControls

                    ConsoleDivider()

                    ConsoleDetailLine(label: copy.statusLabel, value: cameraStatusValue)
                    ConsoleDetailLine(label: copy.deviceDetail, value: localizedSelectedDeviceDetail, monospaced: true)
                    ConsoleDetailLine(label: copy.text("audioDetails"), value: selectedAudioInputDeviceDetail, monospaced: true)
                    ConsoleDetailLine(label: copy.inputsFound, value: discoveredDeviceSummary)
                    ConsoleDetailLine(label: copy.transport, value: localizedCommandSummary, monospaced: true)
                }
                .padding(14)
            }
        }
        .consoleCardSurface()
    }

    private var presenterVideoEffectsControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ConsoleFieldLabel(copy.text("presenterVideoEffects"))
                if WonderShowDistribution.showsFeatureTierUI {
                    FeatureTierBadge(text: copy.text("sourceTierVIP"))
                    FeatureTierBadge(text: copy.text("sourceTierSVIP"), isProminent: true)
                }
                Spacer()
                Toggle("", isOn: $presenterMirrorEnabled)
                    .labelsHidden()
                    .toggleStyle(ConsoleSwitchToggleStyle())
                Text(copy.text("mirrorPresenter"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ConsolePalette.textSecondary)
            }

            presenterEffectSlider(
                label: copy.text("presenterBrightness"),
                value: $presenterBrightness,
                range: -0.3...0.45,
                format: { value in
                    let percent = Int((value * 100).rounded())
                    return percent > 0 ? "+\(percent)%" : "\(percent)%"
                }
            )
            .disabled(!permitsPresenterColorEffects)
            .opacity(permitsPresenterColorEffects ? 1 : 0.42)
            presenterEffectSlider(
                label: copy.text("presenterContrast"),
                value: $presenterContrast,
                range: 0.75...1.35,
                format: { value in "\(Int((value * 100).rounded()))%" }
            )
            .disabled(!permitsPresenterColorEffects)
            .opacity(permitsPresenterColorEffects ? 1 : 0.42)

            if WonderShowDistribution.showsAdvancedPresenterEffectsUI {
                presenterEffectSlider(
                    label: copy.text("presenterNaturalBeauty"),
                    value: $presenterBeauty,
                    range: 0...0.8,
                    format: { value in "\(Int((value * 100).rounded()))%" }
                )
                .disabled(!permitsPresenterColorEffects || !PresenterExperimentalEffectsGate.isEnabled)
                .opacity(permitsPresenterColorEffects && PresenterExperimentalEffectsGate.isEnabled ? 1 : 0.42)
                HStack(spacing: 8) {
                    Text(copy.text("presenterSmartBeauty"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ConsolePalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    if WonderShowDistribution.showsFeatureTierUI {
                        FeatureTierBadge(text: copy.text("sourceTierSVIP"), isProminent: true)
                    }
                    Spacer()
                    Toggle("", isOn: $presenterSmartBeautyEnabled)
                        .labelsHidden()
                        .toggleStyle(ConsoleSwitchToggleStyle())
                        .onChange(of: presenterSmartBeautyEnabled) { _, enabled in
                            if enabled {
                                seedSubjectAwareBeautyDefaultsIfNeeded()
                            }
                            updatePresenterVideoEffectsForLastRecording()
                        }
                }
                .disabled(!permitsSubjectAwareBeauty)
                .opacity(permitsSubjectAwareBeauty ? 1 : 0.42)
                .help(copy.text("presenterBeautyHelp"))

                if presenterSmartBeautyEnabled && permitsSubjectAwareBeauty {
                    advancedPresenterVideoEffectsControls
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ConsolePalette.overlay.opacity(0.34))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ConsolePalette.innerBorder, lineWidth: 1)
        )
    }

    private func presenterEffectSlider(
        label: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        format: @escaping (CGFloat) -> String
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ConsolePalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: 62, alignment: .leading)
            ConsoleValueSlider(value: value, range: range) {
                updatePresenterVideoEffectsForLastRecording()
            }
            Text(format(value.wrappedValue))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(ConsolePalette.textTertiary)
                .frame(width: 42, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var advancedPresenterVideoEffectsControls: some View {
        HStack(spacing: 8) {
            Text(copy.runtimeText("高级美颜"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ConsolePalette.textSecondary)
            Spacer()
            Toggle("", isOn: $presenterAdvancedBeautyEnabled)
                .labelsHidden()
                .toggleStyle(ConsoleSwitchToggleStyle())
        }
        HStack(spacing: 8) {
            Text(copy.runtimeText("背景分割"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ConsolePalette.textSecondary)
            Spacer()
            Toggle("", isOn: $presenterPortraitSegmentationEnabled)
                .labelsHidden()
                .toggleStyle(ConsoleSwitchToggleStyle())
        }
        MenuControlRow(label: copy.text("presenterBeautyStyle")) {
            Menu {
                ForEach(PresenterBeautyStyle.allCases, id: \.self) { style in
                    Button(style.localizedLabel(copy)) {
                        presenterBeautyStyle = style
                        updatePresenterVideoEffectsForLastRecording()
                    }
                }
            } label: {
                MenuFieldLabel(text: presenterBeautyStyle.localizedLabel(copy))
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
        }

        presenterEffectSlider(
            label: copy.text("presenterSkinSmoothing"),
            value: $presenterSkinSmoothing,
            range: 0...1,
            format: { value in "\(Int((value * 100).rounded()))%" }
        )
        presenterEffectSlider(
            label: copy.text("presenterSkinBrightening"),
            value: $presenterSkinBrightening,
            range: 0...1,
            format: { value in "\(Int((value * 100).rounded()))%" }
        )
        presenterEffectSlider(
            label: copy.text("presenterSkinWhitening"),
            value: $presenterSkinWhitening,
            range: 0...1,
            format: { value in "\(Int((value * 100).rounded()))%" }
        )
        presenterEffectSlider(
            label: copy.text("presenterComplexion"),
            value: $presenterComplexion,
            range: 0...1,
            format: { value in "\(Int((value * 100).rounded()))%" }
        )
        presenterEffectSlider(
            label: copy.runtimeText("背景虚化"),
            value: $presenterBackgroundBlur,
            range: 0...1,
            format: { value in "\(Int((value * 100).rounded()))%" }
        )
        HStack(spacing: 8) {
            Text(copy.runtimeText("换背景"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ConsolePalette.textSecondary)
            Spacer()
            Toggle("", isOn: $presenterBackgroundReplacementEnabled)
                .labelsHidden()
                .toggleStyle(ConsoleSwitchToggleStyle())
        }
        if presenterBackgroundReplacementEnabled {
            presenterEffectSlider(
                label: copy.runtimeText("替换强度"),
                value: $presenterBackgroundReplacementStrength,
                range: 0...1,
                format: { value in "\(Int((value * 100).rounded()))%" }
            )
        }
        HStack(spacing: 8) {
            Text(copy.runtimeText("Emoji脸"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ConsolePalette.textSecondary)
            Spacer()
            Toggle("", isOn: $presenterEmojiFaceReplacementEnabled)
                .labelsHidden()
                .toggleStyle(ConsoleSwitchToggleStyle())
        }
        if presenterEmojiFaceReplacementEnabled {
            MenuControlRow(label: copy.runtimeText("Emoji")) {
                Menu {
                    ForEach(presenterEmojiChoices, id: \.self) { symbol in
                        Button(symbol) {
                            presenterEmojiFaceReplacementSymbol = symbol
                            handlePresenterVideoEffectsChange()
                        }
                    }
                } label: {
                    MenuFieldLabel(text: presenterEmojiFaceReplacementSymbol)
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.plain)
            }
            presenterEffectSlider(
                label: copy.runtimeText("大小"),
                value: $presenterEmojiFaceReplacementScale,
                range: 0.68...1.65,
                format: { value in "\(Int((value * 100).rounded()))%" }
            )
        }
        presenterEffectSlider(
            label: copy.runtimeText("瘦脸"),
            value: $presenterFaceSlimming,
            range: 0...0.6,
            format: { value in "\(Int((value * 100).rounded()))%" }
        )
        presenterEffectSlider(
            label: copy.runtimeText("大眼"),
            value: $presenterEyeEnlargement,
            range: 0...0.5,
            format: { value in "\(Int((value * 100).rounded()))%" }
        )
        presenterEffectSlider(
            label: copy.text("presenterBlemishReduction"),
            value: $presenterBlemishReduction,
            range: 0...1,
            format: { value in "\(Int((value * 100).rounded()))%" }
        )
    }

    private var footerArea: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(ConsolePalette.border)

            ZStack(alignment: .bottomLeading) {
                HStack {
                    HStack(spacing: 10) {
                        Text("\(Self.appVersion) · \(copy.directorMode)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(ConsolePalette.textTertiary)

                        Button(copy.about) {
                            showsAboutCard.toggle()
                            if showsAboutCard {
                                showsDiagnostics = false
                            }
                        }
                        .buttonStyle(PressablePlainButtonStyle())
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(showsAboutCard ? ConsolePalette.gold : ConsolePalette.textSecondary)
                    }

                    Spacer()

                    Button {
                        showsDiagnostics.toggle()
                        if showsDiagnostics {
                            showsAboutCard = false
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .rotationEffect(.degrees(showsDiagnostics ? 90 : 0))
                            Text(copy.advDiag)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(showsDiagnostics ? ConsolePalette.textSecondary : ConsolePalette.textTertiary)
                    }
                    .buttonStyle(PressablePlainButtonStyle())

                    Spacer()

                    HStack(spacing: 6) {
                        Circle()
                            .fill(ConsolePalette.teal)
                            .frame(width: 6, height: 6)
                        Text(camera.status == .running ? copy.connected : copy.waitingConnection)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(ConsolePalette.textSecondary)
                    }
                }
                .padding(.horizontal, 20)
                .frame(height: 40)

                if showsAboutCard {
                    AboutPopoverCard(copy: copy, presentation: WonderShowDistribution.presentation)
                        .padding(.leading, 12)
                        .padding(.bottom, 48)
                }
            }
            .background(ConsolePalette.background)

            if showsDiagnostics {
                diagnosticsPanel
            }
        }
    }

    private var exportSettingsSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(copy.exportSettings)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ConsolePalette.textPrimary)

            Text(timelineSelectionSummary)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(ConsolePalette.textTertiary)

            ExportPickerRow(label: copy.resolution) {
                ExportOptionGrid(
                    items: RecordingExportResolution.allCases,
                    selection: exportResolutionBinding
                ) { $0.localizedLabel(copy) }
            }

            ExportPickerRow(label: copy.frameRate) {
                ExportOptionGrid(
                    items: RecordingExportFrameRate.allCases,
                    selection: $exportDraftSettings.frameRate
                ) { "\($0.rawValue) fps" }
            }

            ExportPickerRow(label: copy.quality) {
                ExportOptionGrid(
                    items: RecordingExportQuality.allCases,
                    selection: $exportDraftSettings.quality
                ) { $0.localizedLabel(copy) }
            }

            ExportPickerRow(label: copy.codec) {
                ExportOptionGrid(
                    items: RecordingExportCodec.allCases,
                    selection: $exportDraftSettings.codec
                ) { $0.localizedLabel }
            }

            ConsoleDivider()

            HStack(spacing: 8) {
                Button(copy.cancel) {
                    showsExportSettings = false
                }
                .buttonStyle(ConsoleGradientButtonStyle(variant: .outline, expands: true))

                Button(copy.export) {
                    let settings = exportDraftSettings
                    showsExportSettings = false
                    saveCurrentPiPTimelineForLastRecording()
                    exportProgramVideo(settings: settings)
                }
                .buttonStyle(ConsoleGradientButtonStyle(variant: .gold, expands: true))
            }
        }
        .padding(18)
        .frame(width: 420)
        .background(ConsolePalette.background)
    }

    private var diagnosticsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 32) {
                DiagnosticsLine(label: copy.accessPerm, value: localizedRuntime(commandController.accessibilityStatus.rawValue))
                DiagnosticsLine(label: copy.text("cameraPerm"), value: cameraPermissionStatusValue)
                DiagnosticsLine(label: copy.chromeAuto, value: localizedRuntime(commandController.automationStatus.rawValue))
                DiagnosticsLine(label: copy.scanSummary, value: localizedDeviceScanSummary)
            }

            HStack(spacing: 7) {
                Button(copy.permBtn) {
                    commandController.openAccessibilitySettings()
                }
                .buttonStyle(FooterGhostButtonStyle())

                Button(copy.requestBtn) {
                    commandController.requestAccessibilityPermission()
                }
                .buttonStyle(FooterGhostButtonStyle())

                Button(copy.text("cameraPermBtn")) {
                    camera.requestCameraAccessOrOpenSettings()
                }
                .buttonStyle(FooterGhostButtonStyle())

                Button(copy.chromeBtn) {
                    commandController.requestChromeAutomationPermission()
                }
                .buttonStyle(FooterGhostButtonStyle())

                Button(copy.text("screenPermBtn")) {
                    commandController.openScreenRecordingSettings()
                }
                .buttonStyle(FooterGhostButtonStyle())

                Button(copy.refreshBtn) {
                    commandController.refreshAccessibilityStatus()
                }
                .buttonStyle(FooterGhostButtonStyle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(ConsolePalette.background)
        .overlay(alignment: .top) {
            Divider()
                .overlay(ConsolePalette.innerBorder)
        }
    }

    private func handleCameraPrimaryAction() {
        if camera.status == .permissionDenied {
            camera.requestCameraAccessOrOpenSettings()
        } else {
            camera.start()
        }
    }

    private var elapsedTime: String {
        let hours = elapsedSeconds / 3600
        let minutes = (elapsedSeconds % 3600) / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private var recordingStatusLabel: String {
        switch recordingControlState {
        case .idle:
            return copy.standby
        case .starting:
            return copy.runtimeText("倒计时")
        case .recording:
            return copy.recording
        case .paused:
            return copy.runtimeText("已暂停")
        }
    }

    private var monitorScreenImage: CGImage? {
        commandController.isRecording
            ? (latestScreenPreviewImage ?? screenPreview.latestImage)
            : screenPreview.latestImage
    }

    private var monitorScreenSourceID: ScreenCaptureSourceID? {
        commandController.isRecording
            ? (latestScreenPreviewSourceID ?? screenPreview.latestSourceID)
            : screenPreview.latestSourceID
    }

    private var monitorScreenStatusLabel: String {
        guard monitorScreenImage == nil else {
            return screenSourcePreference.localizedLabel(copy)
        }
        let status = copy.runtimeText(screenPreview.statusText)
        return status.isEmpty || status == copy.standby
            ? screenSourcePreference.localizedLabel(copy)
            : status
    }

    private func applyRecordingPreset(mode: RecordingMode, layout: RecordingLayout) {
        self.mode = mode
        self.layout = normalizedLayout(layout, for: mode)
        recordCurrentLayoutKeyframeIfNeeded(force: true)
        if mode == .cameraOnly {
            latestScreenPreviewImage = nil
            latestScreenPreviewSourceID = nil
            screenPreview.resetImage()
        }
        restartScreenPreviewIfNeeded()
    }

    private func applyLayoutSelection(_ selectedLayout: RecordingLayout) {
        layout = normalizedLayout(selectedLayout, for: mode)
        recordCurrentLayoutKeyframeIfNeeded(force: true)
    }

    private var availableLayoutOptions: [RecordingLayoutOption] {
        switch mode {
        case .screenOnly:
            return [
                RecordingLayoutOption(label: copy.text("screenOnlyLayout"), layout: .screenOnly)
            ]
        case .cameraOnly:
            return [
                RecordingLayoutOption(label: copy.layoutCloseup, layout: .speakerCloseUp),
                RecordingLayoutOption(label: copy.text("layoutSpeakerFullBody"), layout: .speakerFullBody)
            ]
        case .cameraAndScreen:
            return [
                RecordingLayoutOption(
                    label: copy.text("screenMainPipLayout"),
                    layout: .screenWithCameraPictureInPicture(corner: .bottomRight)
                ),
                RecordingLayoutOption(
                    label: copy.text("speakerMainPipLayout"),
                    layout: .cameraWithScreenPictureInPicture(corner: .topRight)
                )
            ]
        }
    }

    private func normalizedLayout(_ layout: RecordingLayout, for mode: RecordingMode) -> RecordingLayout {
        switch mode {
        case .screenOnly:
            return .screenOnly
        case .cameraOnly:
            switch layout {
            case .speakerFullBody:
                return .speakerFullBody
            default:
                return .speakerCloseUp
            }
        case .cameraAndScreen:
            switch layout {
            case .screenWithCameraPictureInPicture, .cameraWithScreenPictureInPicture:
                return layout
            default:
                return .screenWithCameraPictureInPicture(corner: .bottomRight)
            }
        }
    }

    private func updatePiPCorner(_ corner: PiPCorner) {
        switch layout {
        case .screenWithCameraPictureInPicture:
            layout = .screenWithCameraPictureInPicture(corner: corner)
        case .cameraWithScreenPictureInPicture:
            layout = .cameraWithScreenPictureInPicture(corner: corner)
        default:
            break
        }
    }

    private func refreshScreenWindowOptions() {
        Task { @MainActor in
            let snapshot = await ScreenArchiveRecorder.availableSourceSnapshot()
            screenWindowOptions = snapshot.options
            autoAssignSourceSlots(for: snapshot.options)
            screenSourceDiagnostic = snapshot.summary
            screenSourceThumbnails = [:]
            startScreenSourceThumbnailLoading(for: snapshot.options)
            if let issue = snapshot.issue {
                commandController.reportRecordingIssue("录制源读取失败：\(issue)")
            }
        }
    }

    private func persistRecordingSourceSlots() {
        recordingSourceSlots.save()
    }

    private func autoAssignSourceSlots(for options: [ScreenCaptureWindowOption]) {
        if recordingSourceSlots.assignDefaultSlots(
            for: options,
            featureTier: recordingFeatureTier
        ) {
            persistRecordingSourceSlots()
        }
    }

    private func persistRecordingFeatureTier() {
        recordingFeatureTier.save()
    }

    private func startScreenSourceThumbnailLoading(for options: [ScreenCaptureWindowOption]) {
        screenSourceThumbnailTask?.cancel()
        let sourceIDs = options.prefix(80).map(\.id)
        screenSourceThumbnailTask = Task { @MainActor in
            for sourceID in sourceIDs {
                guard !Task.isCancelled else {
                    return
                }
                do {
                    let thumbnail = try await ScreenArchiveRecorder.thumbnail(for: sourceID)
                    guard !Task.isCancelled else {
                        return
                    }
                    screenSourceThumbnails[sourceID] = thumbnail
                } catch {
                    continue
                }
            }
        }
    }

    private func requestScreenCapturePermissionFromPicker() {
        let status = ScreenArchiveRecorder.requestScreenCapturePermission()
        switch status {
        case .granted:
            commandController.reportRecordingIssue("屏幕录制权限已允许，正在重新扫描录制源")
        case .denied:
            commandController.reportRecordingIssue("屏幕录制权限仍未生效，请在系统设置中重新允许灵演")
        }
        refreshScreenWindowOptions()
    }

    private func exportProgramVideo(settings: RecordingExportSettings) {
        updatePresenterVideoEffectsForLastRecording()
        activeProgramRenderTask?.cancel()
        activeProgramRenderTask = commandController.exportProgramVideo(
            settings: settings,
            selectedRange: selectedTimelineRange,
            onProgress: { progress in
                exportProgress = ExportProgressPresentation(
                    title: copy.runtimeText("正在导出视频"),
                    fraction: progress.fraction,
                    width: progress.width,
                    height: progress.height,
                    fileSize: progress.writtenBytes,
                    outputURL: progress.outputURL,
                    settings: settings
                )
            },
            completion: { result in
                switch result {
                case .success(let exportResult):
                    activeProgramRenderTask = nil
                    presentExportOutcomeAfterProgressDismissal(ExportOutcomePresentation(
                        title: copy.runtimeText("导出完成"),
                        message: [
                            "\(exportResult.width)x\(exportResult.height)",
                            formattedFileSize(exportResult.fileSize),
                            compactPath(exportResult.url)
                        ].joined(separator: "\n"),
                        url: exportResult.url
                    ))
                case .failure(let error):
                    activeProgramRenderTask = nil
                    if case PresentationCommandControllerError.exportCancelled = error {
                        exportProgress = nil
                        return
                    }
                    if case ProgramVideoRendererError.cancelled = error {
                        exportProgress = nil
                        return
                    }
                    presentExportOutcomeAfterProgressDismissal(ExportOutcomePresentation(
                        title: copy.runtimeText("导出失败"),
                        message: error.localizedDescription,
                        url: nil
                    ))
                }
            }
        )
    }

    private func previewProgramExport() {
        updatePresenterVideoEffectsForLastRecording()
        activeProgramRenderTask?.cancel()
        let previewSettings = RecordingExportSettings(
            resolution: .hd1080,
            frameRate: .fps30,
            quality: .standard,
            codec: .h264,
            customPixelSize: nil
        )
        activeProgramRenderTask = commandController.previewLastProgramExport(
            settings: previewSettings,
            onProgress: { progress in
                exportProgress = ExportProgressPresentation(
                    title: copy.runtimeText("正在生成预览"),
                    fraction: progress.fraction,
                    width: progress.width,
                    height: progress.height,
                    fileSize: progress.writtenBytes,
                    outputURL: progress.outputURL,
                    settings: previewSettings
                )
            },
            completion: { result in
                activeProgramRenderTask = nil
                switch result {
                case .success(let previewResult):
                    presentProgramPreviewAfterProgressDismissal(previewResult.url)
                case .failure(let error):
                    if case ProgramVideoRendererError.cancelled = error {
                        exportProgress = nil
                        return
                    }
                    presentExportOutcomeAfterProgressDismissal(ExportOutcomePresentation(
                        title: copy.runtimeText("预览合成失败"),
                        message: error.localizedDescription,
                        url: nil
                    ))
                    return
                }
            }
        )
    }

    private func presentProgramPreviewAfterProgressDismissal(_ url: URL) {
        exportProgress = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            commandController.presentProgramPreview(url)
        }
    }

    private func presentExportOutcomeAfterProgressDismissal(_ outcome: ExportOutcomePresentation) {
        exportProgress = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            exportOutcome = outcome
        }
    }

    private func cancelActiveProgramRender() {
        activeProgramRenderTask?.cancel()
        activeProgramRenderTask = nil
        exportProgress = nil
    }

    private func applySelectedScreenWindows() {
        applyScreenSourceSelection(selectedScreenSourceIDs)
    }

    private func applyScreenSourceSelection(_ selectedIDs: Set<ScreenCaptureSourceID>) {
        guard let result = ScreenSourceSelectionResolver.resolve(
            options: screenWindowOptions,
            selectedIDs: selectedIDs
        ) else {
            screenSourcePreference = .automaticPresentationWindow
            selectedScreenSourceIDs = []
            showsScreenSourcePicker = false
            handleScreenCaptureSourceChange()
            return
        }

        selectedScreenSourceIDs = result.selectedIDs
        screenSourcePreference = result.sourcePreference
        showsScreenSourcePicker = false
        handleScreenCaptureSourceChange()
    }

    private func switchToRecordingSourceSlot(_ slot: Int) {
        Task { @MainActor in
            let snapshot = await ScreenArchiveRecorder.availableSourceSnapshot()
            screenWindowOptions = snapshot.options
            autoAssignSourceSlots(for: snapshot.options)
            screenSourceDiagnostic = snapshot.summary
            screenSourceThumbnails = [:]
            startScreenSourceThumbnailLoading(for: snapshot.options)

            guard let assignment = recordingSourceSlots.assignment(for: slot) else {
                commandController.reportRecordingIssue("源位 \(slot) 尚未绑定录制源")
                return
            }
            guard let preference = recordingSourceSlots.resolvedPreference(
                for: slot,
                availableOptions: snapshot.options
            ) else {
                commandController.reportRecordingIssue("源位 \(slot) 的录制源不可用：\(assignment.displayName)")
                return
            }

            selectedScreenSourceIDs = [assignment.sourceID]
            let previousPreference = screenSourcePreference
            screenSourcePreference = preference
            if previousPreference == preference {
                handleScreenCaptureSourceChange()
            }
            commandController.reportRecordingProgress("源位 \(slot) 已切换：\(assignment.displayName)")
        }
    }

    private func updatePresenterVideoEffectsForLastRecording() {
        guard commandController.lastRecordingSession != nil else {
            return
        }
        commandController.updateLastRecordingPresenterVideoEffects(effectivePresenterVideoEffects)
    }

    private func saveCurrentPiPTimelineForLastRecording() {
        recordCurrentPiPKeyframeIfNeeded(force: true)
        let keyframes = normalizedRecordingPiPKeyframes()
        if keyframes.isEmpty {
            commandController.updateLastRecordingPictureInPictureGeometry(currentPictureInPictureGeometry)
        } else {
            commandController.updateLastRecordingPictureInPictureKeyframes(keyframes)
        }
    }

    private func finalizeRecordingTimelineForLastRecording() {
        recordCurrentPiPKeyframeIfNeeded(force: true)
        recordCurrentLayoutKeyframeIfNeeded(force: true)
        let durationMilliseconds = currentRecordingDurationMilliseconds()
        commandController.finalizeLastRecordingTimeline(
            durationMilliseconds: durationMilliseconds,
            pictureInPictureKeyframes: normalizedRecordingPiPKeyframes(),
            layoutKeyframes: normalizedRecordingLayoutKeyframes()
        )
    }

    private func initialLayoutKeyframes() -> [RecordingLayoutKeyframe] {
        [
            RecordingLayoutKeyframe(
                milliseconds: 0,
                mode: mode,
                layout: normalizedLayout(layout, for: mode),
                pictureInPictureGeometry: currentPictureInPictureGeometry
            )
        ]
    }

    private func initialPiPKeyframes() -> [RecordingPiPKeyframe] {
        guard let geometry = currentPictureInPictureGeometry else {
            return []
        }
        return [RecordingPiPKeyframe(milliseconds: 0, geometry: geometry)]
    }

    private func recordCurrentPiPKeyframeIfNeeded(force: Bool = false) {
        guard commandController.isRecording,
              recordingControlState == .recording,
              let geometry = currentPictureInPictureGeometry,
              recordingStartedAt != nil else {
            return
        }

        let now = Date()
        if !force,
           let lastPiPKeyframeDate,
           now.timeIntervalSince(lastPiPKeyframeDate) < 0.28 {
            return
        }

        if recordingPiPKeyframes.last?.geometry == geometry {
            return
        }

        let milliseconds = max(0, Int(currentActiveRecordingDuration() * 1_000))
        recordingPiPKeyframes.append(
            RecordingPiPKeyframe(milliseconds: milliseconds, geometry: geometry)
        )
        lastPiPKeyframeDate = now
    }

    private func currentRecordingDurationMilliseconds() -> Int {
        if commandController.isRecording || accumulatedRecordingDuration > 0 {
            return max(1, Int(currentActiveRecordingDuration() * 1_000))
        }
        guard let recordingStartedAt else {
            return max(1, elapsedSeconds * 1_000)
        }
        return max(1, Int(Date().timeIntervalSince(recordingStartedAt) * 1_000))
    }

    private func normalizedRecordingPiPKeyframes() -> [RecordingPiPKeyframe] {
        var normalized: [RecordingPiPKeyframe] = []
        for keyframe in recordingPiPKeyframes.sorted(by: { $0.milliseconds < $1.milliseconds }) {
            if let last = normalized.last, last.milliseconds == keyframe.milliseconds {
                normalized[normalized.count - 1] = keyframe
                continue
            }
            if normalized.last?.geometry == keyframe.geometry {
                continue
            }
            normalized.append(keyframe)
        }
        return normalized
    }

    private func recordCurrentLayoutKeyframeIfNeeded(force: Bool = false) {
        guard commandController.isRecording,
              recordingControlState == .recording,
              recordingStartedAt != nil else {
            return
        }

        let keyframe = RecordingLayoutKeyframe(
            milliseconds: max(0, Int(currentActiveRecordingDuration() * 1_000)),
            mode: mode,
            layout: normalizedLayout(layout, for: mode),
            pictureInPictureGeometry: currentPictureInPictureGeometry
        )
        if !force, recordingLayoutKeyframes.last == keyframe {
            return
        }
        if recordingLayoutKeyframes.last?.mode == keyframe.mode,
           recordingLayoutKeyframes.last?.layout == keyframe.layout,
           recordingLayoutKeyframes.last?.pictureInPictureGeometry == keyframe.pictureInPictureGeometry {
            return
        }
        recordingLayoutKeyframes.append(keyframe)
    }

    private func normalizedRecordingLayoutKeyframes() -> [RecordingLayoutKeyframe] {
        var normalized: [RecordingLayoutKeyframe] = []
        for keyframe in recordingLayoutKeyframes.sorted(by: { $0.milliseconds < $1.milliseconds }) {
            if let last = normalized.last, last.milliseconds == keyframe.milliseconds {
                normalized[normalized.count - 1] = keyframe
                continue
            }
            if let last = normalized.last,
               last.mode == keyframe.mode,
               last.layout == keyframe.layout,
               last.pictureInPictureGeometry == keyframe.pictureInPictureGeometry {
                continue
            }
            normalized.append(keyframe)
        }
        return normalized
    }

    private func handleScreenCaptureSourceChange() {
        screenPreviewGeneration += 1
        installScreenArchivePreviewHandler()

        guard commandController.isRecording, currentProgramUsesScreen else {
            restartScreenPreviewIfNeeded()
            return
        }

        let selectedTarget = target
        let selectedSourcePreference = screenSourcePreference
        let selectedSourceLabel = screenSourcePreference.localizedLabel(copy)
        latestScreenPreviewImage = nil
        latestScreenPreviewSourceID = nil
        screenPreview.stop()
        screenPreview.resetImage()
        Task {
            do {
                try await screenArchiveRecorder.updateSource(
                    target: selectedTarget,
                    sourcePreference: selectedSourcePreference
                )
                await MainActor.run {
                    commandController.reportRecordingProgress("录制源已切换：\(selectedSourceLabel)")
                }
            } catch {
                await MainActor.run {
                    commandController.reportRecordingIssue("录制源切换失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func installScreenArchivePreviewHandler() {
        let generation = screenPreviewGeneration
        screenArchiveRecorder.onPreviewImage = { image, sourceID in
            guard generation == screenPreviewGeneration else { return }
            latestScreenPreviewImage = image
            latestScreenPreviewSourceID = sourceID
        }
    }

    private func restartScreenPreviewIfNeeded() {
        if !commandController.isRecording {
            latestScreenPreviewImage = nil
            latestScreenPreviewSourceID = nil
        }
        guard currentProgramUsesScreen else {
            latestScreenPreviewSourceID = nil
            screenPreview.stop()
            screenPreview.resetImage()
            return
        }

        screenPreview.start(
            target: target,
            sourcePreference: screenSourcePreference
        )
    }

    private var commandSummary: String {
        director.command(for: .swipeLeft, target: target).transport.localizedLabel(copy)
    }

    private var projectPanelHint: String {
        commandController.lastRecordingSession == nil ? copy.standby : copy.ready
    }

    private var projectLocationSummary: String {
        guard let session = commandController.lastRecordingSession else {
            return copy.projectPending
        }
        return compactPath(session.url)
    }

    private var rawTrackSummary: String {
        guard let session = commandController.lastRecordingSession else {
            return "0 \(copy.trackUnit)"
        }
        let expectedURLs = rawTrackURLs(for: session)
        let rawCount = expectedURLs.filter { isNonEmptyFile(at: $0) }.count
        return "\(rawCount) / \(expectedURLs.count) \(copy.trackUnit)"
    }

    private var programExportSummary: String {
        guard let session = commandController.lastRecordingSession else {
            return copy.previewUnavailable
        }
        return isNonEmptyFile(at: session.programOutputURL)
            ? compactPath(session.programOutputURL)
            : copy.previewUnavailable
    }

    private var autoDirectorSummary: String {
        compositionSummary
    }

    private var compositionSummary: String {
        switch layout {
        case .screenOnly:
            return copy.text("compositionScreenOnly")
        case .speakerCloseUp, .speakerFullBody:
            return copy.text("compositionSpeakerOnly")
        case .screenWithCameraPictureInPicture:
            return copy.text("compositionScreenMain")
        case .cameraWithScreenPictureInPicture:
            return copy.text("compositionSpeakerMain")
        case .sideBySide:
            return copy.text("compositionScreenMain")
        }
    }

    private var autoDirectorPreviewLabel: String {
        switch layout {
        case .screenOnly:
            return copy.text("screenOnlyLayout")
        case .speakerCloseUp, .speakerFullBody:
            return copy.text("speakerOnlyLayout")
        case .screenWithCameraPictureInPicture:
            return copy.text("screenMainPipLayout")
        case .cameraWithScreenPictureInPicture:
            return copy.text("speakerMainPipLayout")
        case .sideBySide:
            return copy.text("screenMainPipLayout")
        }
    }

    private var recordingScenario: RecordingScenario {
        switch mode {
        case .cameraAndScreen:
            return .stagePresentation
        case .screenOnly:
            return .trainingCourse
        case .cameraOnly:
            return .trainingCourse
        }
    }

    private var currentProgramUsesScreen: Bool {
        switch mode {
        case .screenOnly:
            return true
        case .cameraOnly:
            return false
        case .cameraAndScreen:
            switch layout {
            case .speakerCloseUp, .speakerFullBody:
                return false
            case .screenOnly, .screenWithCameraPictureInPicture, .cameraWithScreenPictureInPicture, .sideBySide:
                return true
            }
        }
    }

    private var currentProgramUsesCamera: Bool {
        switch mode {
        case .screenOnly:
            return false
        case .cameraOnly:
            return true
        case .cameraAndScreen:
            switch layout {
            case .screenOnly:
                return false
            case .speakerCloseUp, .speakerFullBody, .screenWithCameraPictureInPicture, .cameraWithScreenPictureInPicture, .sideBySide:
                return true
            }
        }
    }

    private func currentPresenterVideoEffects(permittedBy tier: RecordingFeatureTier) -> PresenterVideoEffects {
        let permitsPresenterColorEffects = WonderShowDistribution.permitsPresenterColorEffects(for: tier)
        let permitsSubjectAwareBeauty = WonderShowDistribution.permitsSubjectAwareBeauty(for: tier)
        let backgroundEffect: PresenterBackgroundEffect
        if permitsSubjectAwareBeauty, presenterBackgroundReplacementEnabled {
            backgroundEffect = .replacement(
                colorHex: "#203040",
                strength: Double(presenterBackgroundReplacementStrength)
            )
        } else if permitsSubjectAwareBeauty, presenterBackgroundBlur > 0 {
            backgroundEffect = .blur(strength: Double(presenterBackgroundBlur))
        } else {
            backgroundEffect = .none
        }

        return PresenterVideoEffects(
            isMirrored: presenterMirrorEnabled,
            brightness: permitsPresenterColorEffects ? Double(presenterBrightness) : 0,
            contrast: permitsPresenterColorEffects ? Double(presenterContrast) : 1,
            beauty: permitsPresenterColorEffects && WonderShowDistribution.showsAdvancedPresenterEffectsUI ? Double(presenterBeauty) : 0,
            isSubjectAwareBeautyEnabled: permitsSubjectAwareBeauty && presenterSmartBeautyEnabled,
            skinSmoothing: permitsSubjectAwareBeauty ? Double(presenterSkinSmoothing) : 0,
            skinBrightening: permitsSubjectAwareBeauty ? Double(presenterSkinBrightening) : 0,
            skinWhitening: permitsSubjectAwareBeauty ? Double(presenterSkinWhitening) : 0,
            blemishReduction: permitsSubjectAwareBeauty ? Double(presenterBlemishReduction) : 0,
            complexion: permitsSubjectAwareBeauty ? Double(presenterComplexion) : 0,
            beautyStyle: presenterBeautyStyle,
            advancedBeautyEnabled: permitsSubjectAwareBeauty && presenterAdvancedBeautyEnabled,
            portraitSegmentationEnabled: permitsSubjectAwareBeauty && presenterPortraitSegmentationEnabled,
            backgroundEffect: backgroundEffect,
            backgroundBlur: permitsSubjectAwareBeauty ? Double(presenterBackgroundBlur) : 0,
            faceLandmarkBeautyEnabled: permitsSubjectAwareBeauty && presenterFaceLandmarkBeautyEnabled,
            faceSlimming: permitsSubjectAwareBeauty ? Double(presenterFaceSlimming) : 0,
            eyeEnlargement: permitsSubjectAwareBeauty ? Double(presenterEyeEnlargement) : 0,
            emojiFaceReplacementEnabled: permitsSubjectAwareBeauty && presenterEmojiFaceReplacementEnabled,
            emojiFaceReplacementSymbol: presenterEmojiFaceReplacementSymbol,
            emojiFaceReplacementStrength: permitsSubjectAwareBeauty && presenterEmojiFaceReplacementEnabled ? 1 : 0,
            emojiFaceReplacementScale: permitsSubjectAwareBeauty ? Double(presenterEmojiFaceReplacementScale) : 1
        )
    }

    private func seedSubjectAwareBeautyDefaultsIfNeeded() {
        guard permitsSubjectAwareBeauty else {
            return
        }
        guard presenterBeauty == 0,
              presenterSkinSmoothing == 0,
              presenterSkinBrightening == 0,
              presenterSkinWhitening == 0,
              presenterBlemishReduction == 0,
              presenterComplexion == 0 else {
            return
        }
        presenterBeauty = 0.18
        presenterSkinSmoothing = 0.20
        presenterSkinBrightening = 0.12
        presenterSkinWhitening = 0.08
        presenterBlemishReduction = 0.10
        presenterComplexion = 0.08
    }

    private var currentProgramShowsCameraOverlay: Bool {
        if case .screenWithCameraPictureInPicture = layout {
            return currentProgramUsesCamera
        }
        return false
    }

    private var currentProgramUsesPiP: Bool {
        switch layout {
        case .screenWithCameraPictureInPicture, .cameraWithScreenPictureInPicture:
            return mode == .cameraAndScreen
        default:
            return false
        }
    }

    private var currentPictureInPictureGeometry: ProgramPictureInPictureGeometry? {
        guard currentProgramUsesPiP else {
            return nil
        }
        let canvas = CGSize(
            width: max(1, monitorCanvasSize.width),
            height: max(1, monitorCanvasSize.height)
        )
        let size = pictureInPictureSize(layout: layout, scale: pipScale, shape: pipShape)
        let position = pictureInPicturePosition(in: canvas, pipSize: size, offset: pipOffset)
        return ProgramPictureInPictureGeometry(
            centerX: Double(position.x / canvas.width),
            centerY: Double(position.y / canvas.height),
            width: Double(size.width / canvas.width),
            height: Double(size.height / canvas.height),
            shape: pipShape.programShape
        )
    }

    private func pictureInPictureSize(
        layout: RecordingLayout,
        scale: CGFloat,
        shape: PiPShape
    ) -> CGSize {
        let boundedScale = min(max(scale, 0.65), 1.6)
        let base: CGSize
        switch layout {
        case .cameraWithScreenPictureInPicture:
            base = CGSize(width: 270, height: 152)
        default:
            base = CGSize(width: 250, height: 141)
        }
        switch shape {
        case .roundedRectangle:
            return CGSize(width: base.width * boundedScale, height: base.height * boundedScale)
        case .square, .circle:
            let side = min(max(base.height * boundedScale, 92), 245)
            return CGSize(width: side, height: side)
        }
    }

    private func pictureInPicturePosition(
        in canvasSize: CGSize,
        pipSize: CGSize,
        offset: CGSize
    ) -> CGPoint {
        let margin: CGFloat = 18
        let halfWidth = pipSize.width / 2
        let halfHeight = pipSize.height / 2
        let x = canvasSize.width - halfWidth - margin + offset.width
        let y = canvasSize.height - halfHeight - margin + offset.height
        return CGPoint(
            x: min(max(halfWidth + margin, x), max(halfWidth + margin, canvasSize.width - halfWidth - margin)),
            y: min(max(halfHeight + margin, y), max(halfHeight + margin, canvasSize.height - halfHeight - margin))
        )
    }

    private var cameraOverlaySize: CGSize {
        switch layout {
        case .speakerCloseUp, .speakerFullBody:
            return CGSize(width: 360, height: 203)
        case .sideBySide:
            return CGSize(width: 250, height: 141)
        case .screenOnly, .screenWithCameraPictureInPicture, .cameraWithScreenPictureInPicture:
            return CGSize(width: 250, height: 141)
        }
    }

    private var timelineHint: String {
        guard let session = commandController.lastRecordingSession else {
            return copy.text("timelinePending")
        }
        return commandController.isRecording
            ? copy.text("timelineRecording")
            : compactPath(session.url)
    }

    private var timelineDurationMilliseconds: Int {
        if let session = commandController.lastRecordingSession {
            return max(
                1,
                session.manifest.project.timeline.durationMilliseconds,
                Int(currentActiveRecordingDuration() * 1000)
            )
        }
        return max(1, Int(currentActiveRecordingDuration() * 1000))
    }

    private var timelinePlayheadFraction: Double {
        min(1, max(0, Double(timelinePlayheadMilliseconds) / Double(timelineDurationMilliseconds)))
    }

    private var timelineSelectionSummary: String {
        guard let selectedTimelineRange else {
            return "\(copy.text("timelineRange")): \(copy.text("timelineFullProgram"))"
        }
        return "\(copy.text("timelineRange")): \(formattedTimelineTime(selectedTimelineRange.startMilliseconds))-\(formattedTimelineTime(selectedTimelineRange.endMilliseconds))"
    }

    private func toggleTimelineTrack(_ id: String) {
        if collapsedTimelineTrackIDs.contains(id) {
            collapsedTimelineTrackIDs.remove(id)
        } else {
            collapsedTimelineTrackIDs.insert(id)
        }
    }

    private func selectTimelineSegment(_ segment: RecordingTimelineSegmentPresentation) {
        guard let range = segment.exportRange else {
            return
        }
        selectedTimelineRange = range
        timelinePlayheadMilliseconds = range.startMilliseconds
    }

    private func formattedTimelineTime(_ milliseconds: Int) -> String {
        let totalSeconds = max(0, milliseconds) / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var timelineRows: [RecordingTimelineRow] {
        guard let session = commandController.lastRecordingSession else {
            return plannedTimelineRows
        }
        return RecordingTimelineTrackModel.rows(
            manifest: session.manifest,
            fileStates: timelineFileStates(for: session),
            fallbackDurationMilliseconds: max(1, Int(currentActiveRecordingDuration() * 1000))
        ).map(recordingTimelineRow)
    }

    private var plannedTimelineRows: [RecordingTimelineRow] {
        var rows: [RecordingTimelineRow] = []
        if currentProgramUsesScreen {
            rows.append(
                RecordingTimelineRow(
                    id: "planned-slides",
                    title: copy.text("trackSlides"),
                    detail: screenSourcePreference.localizedLabel(copy),
                    status: copy.standby,
                    color: ConsolePalette.teal,
                    isCollapsed: collapsedTimelineTrackIDs.contains("planned-slides"),
                    segments: [.placeholder]
                )
            )
        }
        if currentProgramUsesCamera {
            rows.append(
                RecordingTimelineRow(
                    id: "planned-speaker",
                    title: copy.text("trackSpeaker"),
                    detail: localizedActiveDeviceName,
                    status: copy.standby,
                    color: ConsolePalette.gold,
                    isCollapsed: collapsedTimelineTrackIDs.contains("planned-speaker"),
                    segments: [.placeholder]
                )
            )
        }
        rows.append(
            RecordingTimelineRow(
                id: "planned-mic",
                title: copy.text("trackMic"),
                detail: selectedAudioInputDeviceTitle,
                status: copy.standby,
                color: ConsolePalette.textSecondary,
                isCollapsed: collapsedTimelineTrackIDs.contains("planned-mic"),
                segments: [.placeholder]
            )
        )
        rows.append(
            RecordingTimelineRow(
                id: "planned-program",
                title: copy.text("trackProgram"),
                detail: layout.localizedLabel(copy),
                status: copy.previewUnavailable,
                color: ConsolePalette.record,
                isCollapsed: collapsedTimelineTrackIDs.contains("planned-program"),
                segments: [.placeholder]
            )
        )
        return rows
    }

    private func recordingTimelineRow(_ model: RecordingTimelineTrackRowModel) -> RecordingTimelineRow {
        RecordingTimelineRow(
            id: model.id,
            title: localizedTimelineTitle(model),
            detail: model.detail,
            status: localizedTimelineState(model.state),
            color: timelineColor(for: model.role),
            isCollapsed: collapsedTimelineTrackIDs.contains(model.id),
            segments: model.segments.map {
                RecordingTimelineSegmentPresentation(
                    startMilliseconds: $0.startMilliseconds,
                    endMilliseconds: $0.endMilliseconds,
                    fraction: $0.fraction,
                    label: copy.runtimeText($0.label)
                )
            }
        )
    }

    private func localizedTimelineTitle(_ row: RecordingTimelineTrackRowModel) -> String {
        switch row.role {
        case .slidesScreen:
            return copy.text("trackSlides")
        case .presenterCamera:
            return copy.text("trackSpeaker")
        case .microphoneAudio:
            return copy.text("trackMic")
        case nil:
            return copy.text("trackProgram")
        }
    }

    private func localizedTimelineState(_ state: RecordingTimelineFileState) -> String {
        switch state {
        case .missing:
            return copy.previewUnavailable
        case .writing:
            return copy.text("trackWriting")
        case .ready:
            return copy.ready
        }
    }

    private func timelineColor(for role: RecordingTrackRole?) -> Color {
        switch role {
        case .slidesScreen:
            return ConsolePalette.teal
        case .presenterCamera:
            return ConsolePalette.gold
        case .microphoneAudio:
            return ConsolePalette.textSecondary
        case nil:
            return ConsolePalette.record
        }
    }

    private func timelineFileStates(for session: RecordingSessionRecord) -> [String: RecordingTimelineFileState] {
        var states: [String: RecordingTimelineFileState] = [:]
        for asset in session.manifest.mediaAssets {
            let url = session.url.appendingPathComponent(asset.relativePath)
            if commandController.isRecording,
               asset.output != .programRecording,
               FileManager.default.fileExists(atPath: url.path) {
                states[asset.relativePath] = .writing
            } else {
                states[asset.relativePath] = isNonEmptyFile(at: url) ? .ready : .missing
            }
        }
        return states
    }

    private func isNonEmptyFile(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?
            .int64Value ?? 0
        return size > 0
    }

    private func fileStatus(for url: URL) -> String {
        if commandController.isRecording {
            return FileManager.default.fileExists(atPath: url.path)
                ? copy.text("trackWriting")
                : copy.text("trackStarting")
        }
        return FileManager.default.fileExists(atPath: url.path)
            ? copy.ready
            : copy.previewUnavailable
    }

    private func rawTrackURLs(for session: RecordingSessionRecord) -> [URL] {
        var urls: [URL] = []
        let roles = Set(session.manifest.project.rawTracks.map(\.role))
        if roles.contains(.presenterCamera) {
            urls.append(session.presenterCameraURL)
        }
        if roles.contains(.slidesScreen) {
            urls.append(session.slidesScreenURL)
        }
        urls.append(session.microphoneAudioURL)
        return urls
    }

    private func compactPath(_ url: URL) -> String {
        let parent = url.deletingLastPathComponent().lastPathComponent
        let name = url.lastPathComponent
        guard !parent.isEmpty else {
            return name
        }
        return "\(parent)/\(name)"
    }

    private func formattedFileSize(_ bytes: Int64) -> String {
        guard bytes > 0 else {
            return "0 KB"
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = bytes >= 1_000_000_000 ? [.useGB] : [.useMB, .useKB]
        return formatter.string(fromByteCount: bytes)
    }

    private var supportedDeviceSummary: String {
        copy.supportedDevices
    }

    private var discoveredDeviceSummary: String {
        let count = max(0, camera.availableDevices.count - 1)
        return count == 0 ? copy.noInputsFound : "\(count) \(copy.inputCountSuffix)"
    }

    private var selectedDeviceTitle: String {
        camera.availableDevices.first(where: { $0.id == camera.selectedDeviceID })?.name ?? copy.selectInputDevice
    }

    private var selectedDeviceDetail: String {
        camera.availableDevices.first(where: { $0.id == camera.selectedDeviceID })?.detail ?? copy.deviceListPending
    }

    private var selectedAudioInputDevice: AudioInputDeviceOption {
        audioInputDevices.first(where: { $0.id == selectedAudioInputDeviceID }) ?? .systemDefault
    }

    private var selectedAudioInputDeviceTitle: String {
        localizedAudioInputName(selectedAudioInputDevice)
    }

    private var selectedAudioInputDeviceDetail: String {
        localizedAudioInputDetail(selectedAudioInputDevice)
    }

    private func localizedAudioInputName(_ device: AudioInputDeviceOption) -> String {
        device.isSystemDefault ? copy.text("systemDefaultMicrophone") : copy.runtimeText(device.name)
    }

    private func localizedAudioInputDetail(_ device: AudioInputDeviceOption) -> String {
        device.isSystemDefault ? copy.text("systemDefaultMicrophoneDetail") : copy.runtimeText(device.detail)
    }

    private func refreshAudioInputDevices() {
        let devices = MicrophoneArchiveRecorder.availableInputDevices()
        audioInputDevices = devices
        if !devices.contains(where: { $0.id == selectedAudioInputDeviceID }) {
            selectedAudioInputDeviceID = AudioInputDeviceOption.systemDefault.id
        }
    }

    private var calibrationThemeBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(ConsolePalette.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(ConsolePalette.border, lineWidth: 1)
            )
    }

    /// 构建个人手势校准浮层，保留原功能但切换为 Figma 版暖黑金样式。
    private func calibrationSheet(_ flow: CalibrationFlow) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(copy.calibrationTitle)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(ConsolePalette.textPrimary)

            Text(flow.currentGesture.instruction(copy))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(ConsolePalette.textPrimary)

            Text(copy.calibrationSampleProgress(current: flow.currentSample, total: 3))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ConsolePalette.textSecondary)

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ConsolePalette.previewBase)
                CameraPreviewView(session: camera.session)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                HandPointOverlay(
                    points: camera.latestHandPoints,
                    landmarkPoints: camera.latestHandLandmarkPoints,
                    isCalibrating: true,
                    isZoneActive: true
                )
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(ConsolePalette.border, lineWidth: 1)
            )

            ProgressView(value: camera.calibrationProgress)
                .tint(ConsolePalette.gold)

            Text(localizedCalibrationStatus)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ConsolePalette.textPrimary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ConsolePalette.overlay)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(ConsolePalette.innerBorder, lineWidth: 1)
                )

            HStack(spacing: 12) {
                Button(copy.startAutoSample) {
                    runAutomaticCalibrationSample(flow)
                }
                .buttonStyle(ConsoleGradientButtonStyle(variant: .gold, expands: true))

                Button(copy.finish) {
                    calibrationFlow = nil
                }
                .buttonStyle(ConsoleGradientButtonStyle(variant: .outline, expands: true))
            }

            ConsoleDetailLine(label: copy.currentHandShape, value: localizedDetectedHandShapes)
        }
        .padding(24)
        .frame(width: 560)
        .background(calibrationThemeBackground)
        .padding(8)
        .background(ConsolePalette.background)
    }

    /// 执行一次自动采样并推进校准流程，失败时保留在当前步骤。
    private func runAutomaticCalibrationSample(_ flow: CalibrationFlow) {
        Task { @MainActor in
            let success = await camera.autoCaptureCalibration(
                intent: flow.currentGesture.intent,
                sampleIndex: flow.currentSample
            )
            guard success else {
                commandController.reportCalibrationMode(
                    localizedRuntime("采样不足，请保持手在画面中并重做这次动作")
                )
                return
            }

            if calibrationFlow?.isLastSample == true {
                commandController.reportCalibrationMode(
                    localizedRuntime("个人手势校准完成，后续识别会优先使用你的动作模板")
                )
                calibrationFlow = nil
            } else {
                calibrationFlow?.advance()
            }
        }
    }
}


private enum ConsoleButtonVariant {
    case gold
    case danger
    case outline
}

enum ConsolePalette {
    static let background = Color(red: 13 / 255, green: 10 / 255, blue: 7 / 255)
    static let surface = Color(red: 24 / 255, green: 19 / 255, blue: 9 / 255)
    static let overlay = Color(red: 30 / 255, green: 24 / 255, blue: 16 / 255)
    static let previewBase = Color(red: 5 / 255, green: 3 / 255, blue: 2 / 255)
    static let border = Color(red: 58 / 255, green: 46 / 255, blue: 30 / 255)
    static let innerBorder = Color(red: 44 / 255, green: 36 / 255, blue: 24 / 255)
    static let gold = Color(red: 200 / 255, green: 146 / 255, blue: 58 / 255)
    static let goldBright = Color(red: 232 / 255, green: 200 / 255, blue: 112 / 255)
    static let textPrimary = Color(red: 237 / 255, green: 232 / 255, blue: 220 / 255)
    static let textSecondary = Color(red: 184 / 255, green: 168 / 255, blue: 130 / 255)
    static let textTertiary = Color(red: 138 / 255, green: 122 / 255, blue: 98 / 255)
    static let teal = Color(red: 62 / 255, green: 181 / 255, blue: 176 / 255)
    static let record = Color(red: 200 / 255, green: 64 / 255, blue: 56 / 255)

    static var previewGlow: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.08),
                    Color.black.opacity(0.24)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(0.3),
                    Color.black.opacity(0.8)
                ],
                center: .center,
                startRadius: 50,
                endRadius: 400
            )

            VStack(spacing: 0) {
                Spacer()
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 200 / 255, green: 146 / 255, blue: 58 / 255).opacity(0.14),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 120
                        )
                    )
                    .frame(width: 320, height: 74)
                    .blur(radius: 10)
                    .padding(.bottom, 24)
            }
        }
    }
}

private struct ConsoleStatusPill: View {
    let icon: String
    let title: String
    let value: String
    let isActive: Bool
    let isRecording: Bool

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(isActive ? (isRecording ? ConsolePalette.record : ConsolePalette.teal) : .clear)
                .frame(width: 6, height: 6)
                .overlay(
                    Circle()
                        .stroke(isActive ? .clear : ConsolePalette.textTertiary, lineWidth: 1.2)
                )

            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ConsolePalette.textTertiary)

            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ConsolePalette.textSecondary)
                .tracking(0.9)

            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ConsolePalette.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .frame(height: 30)
        .background(ConsolePalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ConsolePalette.border, lineWidth: 1)
        )
    }
}

private struct PreviewChip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ConsolePalette.textTertiary)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ConsolePalette.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(Color.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(ConsolePalette.gold.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct SummaryCell: View {
    let label: String
    let value: String
    let monospaced: Bool
    let showsTrailingDivider: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ConsolePalette.textTertiary)
                .tracking(0.8)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: monospaced ? .monospaced : .default))
                .foregroundStyle(ConsolePalette.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(ConsolePalette.border)
                .frame(width: 1)
                .opacity(showsTrailingDivider ? 0.65 : 0)
        }
    }
}

private struct ConsoleDetailLine: View {
    let label: String
    let value: String
    var monospaced: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ConsolePalette.textTertiary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: monospaced ? .monospaced : .default))
                .foregroundStyle(ConsolePalette.textPrimary.opacity(0.92))
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }
}

private struct RecordingTimelineRow: Identifiable {
    let id: String
    let title: String
    let detail: String
    let status: String
    let color: Color
    let isCollapsed: Bool
    let segments: [RecordingTimelineSegmentPresentation]
}

private struct RecordingTimelineSegmentPresentation: Hashable {
    let startMilliseconds: Int?
    let endMilliseconds: Int?
    let fraction: Double
    let label: String

    var exportRange: TimelineExportRange? {
        guard let startMilliseconds, let endMilliseconds, startMilliseconds < endMilliseconds else {
            return nil
        }
        return TimelineExportRange(startMilliseconds: startMilliseconds, endMilliseconds: endMilliseconds)
    }

    static let placeholder = RecordingTimelineSegmentPresentation(
        startMilliseconds: nil,
        endMilliseconds: nil,
        fraction: 1,
        label: ""
    )
}

private struct RecordingLayoutOption: Identifiable {
    let id = UUID()
    let label: String
    let layout: RecordingLayout
}

private struct TimelineTrackRow: View {
    let row: RecordingTimelineRow
    let selectedRange: TimelineExportRange?
    let playheadFraction: Double
    let toggleCollapsed: () -> Void
    let selectSegment: (RecordingTimelineSegmentPresentation) -> Void

    var body: some View {
        HStack(spacing: 9) {
            Button {
                toggleCollapsed()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(row.isCollapsed ? 0 : 90))
                    .foregroundStyle(ConsolePalette.textTertiary)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)

            Circle()
                .fill(row.color)
                .frame(width: 7, height: 7)
                .shadow(color: row.color.opacity(0.35), radius: 5, x: 0, y: 0)

            Text(row.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ConsolePalette.textPrimary)
                .frame(width: 68, alignment: .leading)

            if row.isCollapsed {
                Spacer(minLength: 0)
            } else {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        HStack(spacing: 2) {
                            ForEach(Array(row.segments.enumerated()), id: \.offset) { _, segment in
                                Button {
                                    selectSegment(segment)
                                } label: {
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(isSelected(segment) ? row.color.opacity(0.72) : row.color.opacity(0.34))
                                        .overlay {
                                            if !segment.label.isEmpty && proxy.size.width * segment.fraction > 52 {
                                                Text(segment.label)
                                                    .font(.system(size: 8, weight: .semibold))
                                                    .foregroundStyle(ConsolePalette.textPrimary.opacity(0.72))
                                                    .lineLimit(1)
                                                    .minimumScaleFactor(0.7)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .frame(width: max(8, proxy.size.width * segment.fraction))
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(2)

                        Rectangle()
                            .fill(ConsolePalette.goldBright.opacity(0.86))
                            .frame(width: 1.5)
                            .offset(x: max(0, min(proxy.size.width - 1.5, proxy.size.width * playheadFraction)))
                    }
                    .background(row.color.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(ConsolePalette.innerBorder, lineWidth: 1)
                    )
                }
                .frame(height: 14)
            }

            if !row.isCollapsed {
                Text(row.detail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ConsolePalette.textTertiary)
                    .lineLimit(1)
                    .frame(width: 150, alignment: .trailing)
            }

            Text(row.status)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ConsolePalette.textSecondary)
                .lineLimit(1)
                .frame(width: 64, alignment: .trailing)
        }
        .frame(height: 18)
    }

    private func isSelected(_ segment: RecordingTimelineSegmentPresentation) -> Bool {
        guard let selectedRange, let exportRange = segment.exportRange else {
            return false
        }
        return selectedRange == exportRange
    }
}

private struct ConsoleFieldLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(ConsolePalette.textSecondary)
            .tracking(0.8)
            .lineLimit(1)
            .minimumScaleFactor(0.68)
    }
}

private struct MenuControlRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 10) {
            ConsoleFieldLabel(label)
                .frame(width: 70, alignment: .leading)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 32)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ConsolePalette.overlay.opacity(0.34))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ConsolePalette.innerBorder, lineWidth: 1)
        )
    }
}

private struct MenuFieldLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "chevron.down.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(ConsolePalette.previewBase, ConsolePalette.goldBright)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ConsolePalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Spacer(minLength: 8)
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(ConsolePalette.goldBright)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 86 / 255, green: 58 / 255, blue: 19 / 255),
                    Color(red: 43 / 255, green: 31 / 255, blue: 11 / 255)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ConsolePalette.gold.opacity(0.7), lineWidth: 1)
        )
        .shadow(color: ConsolePalette.gold.opacity(0.12), radius: 6, x: 0, y: 2)
    }
}

private struct ConsoleValueSlider: View {
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let onEditingEnded: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let fraction = normalizedFraction
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(ConsolePalette.previewBase.opacity(0.96))
                    .overlay(
                        Capsule()
                            .stroke(ConsolePalette.innerBorder.opacity(0.9), lineWidth: 1)
                    )
                    .frame(height: 8)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                ConsolePalette.goldBright,
                                ConsolePalette.gold
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(8, proxy.size.width * fraction), height: 8)

                Circle()
                    .fill(ConsolePalette.textPrimary)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .stroke(ConsolePalette.goldBright, lineWidth: 1.4)
                    )
                    .shadow(color: .black.opacity(0.42), radius: 4, x: 0, y: 2)
                    .offset(x: min(max(0, proxy.size.width * fraction - 10), max(0, proxy.size.width - 20)))
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        updateValue(at: gesture.location.x, width: proxy.size.width)
                    }
                    .onEnded { _ in
                        onEditingEnded()
                    }
            )
        }
        .frame(height: 24)
        .accessibilityLabel("PiP size")
        .accessibilityValue("\(Int(value * 100))%")
    }

    private var normalizedFraction: CGFloat {
        guard range.upperBound > range.lowerBound else {
            return 0
        }
        return min(max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }

    private func updateValue(at x: CGFloat, width: CGFloat) {
        guard width > 0 else {
            return
        }
        let fraction = min(max(x / width, 0), 1)
        value = range.lowerBound + (range.upperBound - range.lowerBound) * fraction
    }
}

private struct CardHeader: View {
    let title: String
    let hint: String
    let isCollapsed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(ConsolePalette.textTertiary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ConsolePalette.textPrimary)
                Spacer()
                Text(hint)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ConsolePalette.textTertiary)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
        }
                        .buttonStyle(PressablePlainButtonStyle())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isCollapsed ? .clear : ConsolePalette.innerBorder)
                .frame(height: 1)
        }
    }
}

private struct GestureCheatsheetRow: View {
    let icon: String
    let gesture: String
    let action: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 18)
                .foregroundStyle(ConsolePalette.textSecondary)
            Text(gesture)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ConsolePalette.textSecondary)
            Spacer()
            Text(action)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ConsolePalette.textTertiary)
        }
        .frame(height: 26)
    }
}

private struct DiagnosticsLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ConsolePalette.textTertiary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(ConsolePalette.textSecondary)
                .lineLimit(1)
        }
    }
}

private struct AboutPopoverCard: View {
    let copy: AppCopy
    let presentation: WonderShowEditionPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(presentation.aboutTitle(for: copy))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ConsolePalette.textPrimary)
                Spacer()
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(ConsolePalette.textTertiary)
            }

            ConsoleDivider()

            if let editionNote = presentation.aboutEditionNote(for: copy) {
                Text(editionNote)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ConsolePalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                ConsoleDivider()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(copy.authorLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ConsolePalette.textTertiary)
                Text(copy.authorVal)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ConsolePalette.textPrimary)
                Text("GitHub")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ConsolePalette.textTertiary)
                Link("github.com/aokest", destination: URL(string: "https://github.com/aokest")!)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(ConsolePalette.gold)
            }

            ConsoleDivider()

            VStack(alignment: .leading, spacing: 8) {
                Text(presentation.supportTitle(for: copy))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ConsolePalette.textPrimary)
                Text("Buy me a coffee")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(ConsolePalette.gold)
                Text(presentation.supportBody(for: copy))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ConsolePalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    ForEach(AboutSupportQRCodeResource.allCases, id: \.rawValue) { code in
                        AboutSupportQRCodeTile(resource: code)
                    }
                }
            }

            ConsoleDivider()

            HStack {
                Text(DashboardView.appVersion)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(ConsolePalette.textTertiary)
                Spacer()
                Text("WonderShow")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ConsolePalette.textTertiary)
            }
        }
        .padding(16)
        .frame(width: 292)
        .background(ConsolePalette.overlay)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(ConsolePalette.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.6), radius: 16, x: 0, y: 8)
    }
}

private struct AboutSupportQRCodeTile: View {
    let resource: AboutSupportQRCodeResource

    var body: some View {
        VStack(spacing: 5) {
            Group {
                if let image = resource.image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(ConsolePalette.surface.opacity(0.65))
                        .overlay(
                            Image(systemName: "qrcode")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(ConsolePalette.textTertiary)
                        )
                }
            }
            .frame(width: 94, height: 94)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(ConsolePalette.border.opacity(0.9), lineWidth: 1)
            )

            Text(resource.label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(ConsolePalette.textTertiary)
        }
        .frame(width: 104)
    }
}

private struct HelpBubble: View {
    var body: some View {
        Circle()
            .fill(Color.white.opacity(0.96))
            .frame(width: 28, height: 28)
            .overlay(
                Text("?")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.72))
            )
            .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 4)
    }
}

private struct TimelineMiniButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(ConsolePalette.textSecondary)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(ConsolePalette.overlay.opacity(configuration.isPressed ? 0.72 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(ConsolePalette.innerBorder, lineWidth: 1)
            )
    }
}

private struct ConsoleDivider: View {
    var body: some View {
        Rectangle()
            .fill(ConsolePalette.innerBorder)
            .frame(height: 1)
    }
}

private struct HandPointOverlay: View {
    let points: [HandPoint]
    let landmarkPoints: [HandPoint]
    let isCalibrating: Bool
    let isZoneActive: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isCalibrating ? ConsolePalette.gold.opacity(0.95) : zoneColor,
                        style: StrokeStyle(lineWidth: 2, dash: [10, 6])
                    )
                    .frame(width: proxy.size.width * 0.40, height: proxy.size.height * 0.54)

                handSkeleton(in: proxy.size)
                    .stroke(
                        Color.black.opacity(0.45),
                        style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round)
                    )

                handSkeleton(in: proxy.size)
                    .stroke(
                        ConsolePalette.goldBright.opacity(0.92),
                        style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round)
                    )

                ForEach(Array(landmarkPoints.enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(ConsolePalette.textPrimary.opacity(0.62))
                        .frame(width: 5, height: 5)
                        .overlay(
                            Circle()
                                .stroke(Color.black.opacity(0.35), lineWidth: 0.5)
                        )
                        .position(
                            x: proxy.size.width * point.x,
                            y: proxy.size.height * (1 - point.y)
                        )
                }

                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(ConsolePalette.goldBright.opacity(0.9))
                        .frame(width: 11, height: 11)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.9), lineWidth: 1)
                        )
                        .position(
                            x: proxy.size.width * point.x,
                            y: proxy.size.height * (1 - point.y)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
    }

    private var zoneColor: Color {
        isZoneActive ? ConsolePalette.gold.opacity(0.72) : ConsolePalette.gold.opacity(0.46)
    }

    private func handSkeleton(in size: CGSize) -> Path {
        var path = Path()
        guard landmarkPoints.count >= 21 else {
            return path
        }

        for handStart in stride(from: 0, to: landmarkPoints.count, by: 21) {
            let handEnd = handStart + 21
            guard handEnd <= landmarkPoints.count else {
                break
            }

            for connection in MediaPipeHandGeometry.landmarkConnections {
                let start = landmarkPoints[handStart + connection.0]
                let end = landmarkPoints[handStart + connection.1]
                path.move(to: CGPoint(x: size.width * start.x, y: size.height * (1 - start.y)))
                path.addLine(to: CGPoint(x: size.width * end.x, y: size.height * (1 - end.y)))
            }
        }

        return path
    }
}

private struct CalibrationFlow: Identifiable {
    enum GestureStep: Int, CaseIterable {
        case swipeLeft
        case swipeRight
        case zoomIn
        case zoomOut

        var intent: GestureIntent {
            switch self {
            case .swipeLeft:
                return .swipeLeft
            case .swipeRight:
                return .swipeRight
            case .zoomIn:
                return .zoomIn
            case .zoomOut:
                return .zoomOut
            }
        }

        func instruction(_ copy: AppCopy) -> String {
            switch self {
            case .swipeLeft:
                return copy.runtimeText("做你的‘下一页’左挥手势")
            case .swipeRight:
                return copy.runtimeText("做你的‘上一页’右挥手势")
            case .zoomIn:
                return copy.runtimeText("双手八字分开，作为放大")
            case .zoomOut:
                return copy.runtimeText("双手八字合拢，作为缩小")
            }
        }
    }

    let id = UUID()
    private(set) var stepIndex = 0
    private(set) var currentSample = 1

    var currentGesture: GestureStep {
        GestureStep.allCases[min(stepIndex, GestureStep.allCases.count - 1)]
    }

    var isLastSample: Bool {
        stepIndex == GestureStep.allCases.count - 1 && currentSample == 3
    }

    /// 在当前手势采样完成后推进到下一个样本或下一个手势步骤。
    mutating func advance() {
        if currentSample < 3 {
            currentSample += 1
            return
        }
        currentSample = 1
        stepIndex = min(stepIndex + 1, GestureStep.allCases.count - 1)
    }
}

private struct ConsoleGradientButtonStyle: ButtonStyle {
    let variant: ConsoleButtonVariant
    var expands: Bool = true
    var compact: Bool = false

    /// 生成导演台按钮外观，统一处理金色主按钮、红色录制按钮与描边按钮。
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 11 : 12, weight: .semibold))
            .foregroundStyle(textColor)
            .frame(maxWidth: expands ? .infinity : nil)
            .padding(.horizontal, compact ? 10 : 13)
            .frame(height: compact ? 26 : 30)
            .background(buttonBackground(configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: compact ? 7 : 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 7 : 8, style: .continuous)
                    .stroke(borderColor(configuration.isPressed), lineWidth: 1)
            )
            .shadow(color: shadowColor.opacity(configuration.isPressed ? 0.18 : 0.34), radius: 6, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .offset(y: configuration.isPressed ? 1 : 0)
            .brightness(configuration.isPressed ? -0.025 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }

    private var textColor: Color {
        switch variant {
        case .danger:
            return .white
        case .gold:
            return ConsolePalette.goldBright
        case .outline:
            return ConsolePalette.textSecondary
        }
    }

    private var shadowColor: Color {
        switch variant {
        case .danger:
            return ConsolePalette.record
        case .gold, .outline:
            return .black
        }
    }

    private func borderColor(_ isPressed: Bool) -> Color {
        switch variant {
        case .danger:
            return isPressed ? Color(red: 106 / 255, green: 30 / 255, blue: 26 / 255) : Color(red: 224 / 255, green: 80 / 255, blue: 64 / 255)
        case .gold:
            return isPressed ? Color(red: 208 / 255, green: 152 / 255, blue: 64 / 255) : Color(red: 138 / 255, green: 100 / 255, blue: 40 / 255)
        case .outline:
            return Color(red: 90 / 255, green: 68 / 255, blue: 40 / 255)
        }
    }

    /// 根据按钮变体与按压态返回对应的渐变或纯色背景。
    private func buttonBackground(_ isPressed: Bool) -> AnyView {
        switch variant {
        case .danger:
            return AnyView(
                LinearGradient(
                    colors: [
                        Color(red: 216 / 255, green: 72 / 255, blue: 64 / 255).opacity(isPressed ? 0.88 : 1),
                        Color(red: 184 / 255, green: 52 / 255, blue: 40 / 255).opacity(isPressed ? 0.86 : 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        case .gold:
            return AnyView(
                LinearGradient(
                    colors: [
                        Color(red: 74 / 255, green: 50 / 255, blue: 20 / 255).opacity(isPressed ? 0.92 : 1),
                        Color(red: 56 / 255, green: 38 / 255, blue: 14 / 255).opacity(isPressed ? 0.9 : 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        case .outline:
            return AnyView(ConsolePalette.overlay.opacity(isPressed ? 0.9 : 1))
        }
    }
}

private struct LanguageTabButtonStyle: ButtonStyle {
    let isSelected: Bool

    /// 绘制顶栏语言切换胶囊，保持和 Figma 原稿一致的三段式按钮结构。
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: isSelected ? .bold : .medium))
            .foregroundStyle(isSelected ? ConsolePalette.goldBright : ConsolePalette.textTertiary)
            .frame(width: 36, height: 28)
            .background(
                Group {
                    if isSelected {
                        LinearGradient(
                            colors: [
                                Color(red: 74 / 255, green: 50 / 255, blue: 20 / 255),
                                Color(red: 56 / 255, green: 38 / 255, blue: 14 / 255)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    } else {
                        ConsolePalette.surface.opacity(configuration.isPressed ? 0.86 : 1)
                    }
                }
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct FooterGhostButtonStyle: ButtonStyle {
    /// 渲染底部诊断区的轻量描边按钮，避免与主操作按钮抢视觉层级。
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(configuration.isPressed ? ConsolePalette.textSecondary : ConsolePalette.textTertiary)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(configuration.isPressed ? ConsolePalette.border : ConsolePalette.innerBorder, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct PressablePlainButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.975

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .offset(y: configuration.isPressed ? 1 : 0)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct ConsoleSwitchToggleStyle: ToggleStyle {
    /// 将 macOS 原生开关重绘为暖金色小开关，贴近 Figma 原稿的手势开关外观。
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: configuration.isOn ? [
                                Color(red: 208 / 255, green: 152 / 255, blue: 56 / 255),
                                Color(red: 160 / 255, green: 112 / 255, blue: 32 / 255)
                            ] : [
                                Color(red: 42 / 255, green: 32 / 255, blue: 22 / 255),
                                Color(red: 30 / 255, green: 24 / 255, blue: 12 / 255)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 36, height: 20)
                    .overlay(
                        Capsule()
                            .stroke(configuration.isOn ? Color(red: 176 / 255, green: 120 / 255, blue: 48 / 255) : ConsolePalette.border, lineWidth: 1)
                    )
                Circle()
                    .fill(configuration.isOn ? Color(red: 1, green: 240 / 255, blue: 200 / 255) : Color(red: 90 / 255, green: 78 / 255, blue: 60 / 255))
                    .frame(width: 14, height: 14)
                    .padding(2)
            }
        }
        .buttonStyle(PressablePlainButtonStyle())
    }
}

private struct ProgramPreviewSheet: View {
    let copy: AppCopy
    let url: URL
    @StateObject private var model: ProgramPreviewModel

    init(copy: AppCopy, url: URL) {
        self.copy = copy
        self.url = url
        _model = StateObject(wrappedValue: ProgramPreviewModel(url: url))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(copy.previewProgram)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ConsolePalette.textPrimary)
                Text(url.lastPathComponent)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(ConsolePalette.textTertiary)
                    .lineLimit(1)
                Spacer()
                Button(copy.openFile) {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(ConsoleGradientButtonStyle(variant: .outline, expands: false, compact: true))
                Button(copy.revealProject) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .buttonStyle(ConsoleGradientButtonStyle(variant: .outline, expands: false, compact: true))
            }
            .padding(14)
            .background(ConsolePalette.surface)

            ProgramPlayerView(player: model.player)
                .frame(minWidth: 920, minHeight: 518)
                .background(Color.black)
        }
        .background(ConsolePalette.background)
        .onAppear {
            model.play()
        }
        .onDisappear {
            model.pause()
        }
    }
}

private struct ScreenSourcePickerSheet: View {
    let copy: AppCopy
    let options: [ScreenCaptureWindowOption]
    let diagnostic: String
    let thumbnails: [ScreenCaptureSourceID: CGImage]
    @Binding var viewMode: ScreenSourcePickerViewMode
    @Binding var selectedIDs: Set<ScreenCaptureSourceID>
    @Binding var sourceSlots: RecordingSourceSlots
    @Binding var featureTier: RecordingFeatureTier
    let persistSourceSlots: () -> Void
    let persistFeatureTier: () -> Void
    let apply: (Set<ScreenCaptureSourceID>) -> Void
    let refresh: () -> Void
    let requestPermission: () -> Void
    let openSettings: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draftSelectedIDs: Set<ScreenCaptureSourceID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(copy.text("chooseWindows"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ConsolePalette.textPrimary)
                Text(copy.text("chooseWindowsHint"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ConsolePalette.textTertiary)
                Spacer()
                if WonderShowDistribution.showsFeatureTierUI {
                    SourceTierPicker(copy: copy, selection: $featureTier) {
                        persistFeatureTier()
                    }
                }
                ScreenSourceViewModePicker(copy: copy, selection: $viewMode)
                Button(copy.rescan) {
                    refresh()
                }
                .buttonStyle(ConsoleGradientButtonStyle(variant: .outline, expands: false, compact: true))
            }

            Text(diagnostic.isEmpty ? copy.text("screenSourcePending") : copy.runtimeText(diagnostic))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ConsolePalette.textTertiary)
                .lineLimit(2)

            Group {
                if options.isEmpty {
                    emptySourceState
                } else if viewMode == .thumbnails {
                    thumbnailGrid
                } else {
                    listView
                }
            }
            .frame(minHeight: 380)

            ConsoleDivider()

            HStack(spacing: 8) {
                Button(copy.cancel) {
                    dismiss()
                }
                .buttonStyle(ConsoleGradientButtonStyle(variant: .outline, expands: true))

                Button(copy.text("useSelectedSource")) {
                    let selection = draftSelectedIDs
                    selectedIDs = selection
                    apply(selection)
                    dismiss()
                }
                .buttonStyle(ConsoleGradientButtonStyle(variant: .gold, expands: true))
                .disabled(draftSelectedIDs.isEmpty)
            }
        }
        .padding(18)
        .frame(minWidth: 760, idealWidth: 920, maxWidth: .infinity, minHeight: 620, idealHeight: 740, maxHeight: .infinity)
        .background(ConsolePalette.background)
        .background(ResizableSheetWindowAccessor(minSize: NSSize(width: 760, height: 620)))
        .onAppear {
            draftSelectedIDs = selectedIDs
        }
    }

    private var emptySourceState: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.dashed")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(ConsolePalette.textTertiary)
            Text(copy.text("noScreenSources"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ConsolePalette.textSecondary)
            Text(copy.text("noScreenSourcesHint"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ConsolePalette.textTertiary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            HStack(spacing: 8) {
                Button(copy.text("requestScreenCaptureAccess")) {
                    requestPermission()
                }
                .buttonStyle(ConsoleGradientButtonStyle(variant: .gold, expands: false, compact: true))

                Button(copy.text("openScreenCaptureSettings")) {
                    openSettings()
                }
                .buttonStyle(ConsoleGradientButtonStyle(variant: .outline, expands: false, compact: true))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var thumbnailGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 210), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(options) { option in
                    ScreenSourceThumbnailCard(
                        copy: copy,
                        option: option,
                        thumbnail: thumbnails[option.id],
                        isSelected: draftSelectedIDs.contains(option.id),
                        assignedSlot: sourceSlots.slot(for: option.id),
                        featureTier: featureTier,
                        assignSlot: { slot in
                            assign(option, to: slot)
                        }
                    ) {
                        toggle(option.id)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var listView: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(options) { option in
                    ScreenSourceListRow(
                        copy: copy,
                        option: option,
                        isSelected: draftSelectedIDs.contains(option.id),
                        assignedSlot: sourceSlots.slot(for: option.id),
                        featureTier: featureTier,
                        assignSlot: { slot in
                            assign(option, to: slot)
                        }
                    ) {
                        toggle(option.id)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func toggle(_ id: ScreenCaptureSourceID) {
        if draftSelectedIDs.contains(id) {
            draftSelectedIDs.remove(id)
        } else if case .display = id {
            draftSelectedIDs = [id]
        } else {
            draftSelectedIDs = draftSelectedIDs.filter {
                if case .display = $0 {
                    return false
                }
                return true
            }
            draftSelectedIDs.insert(id)
        }
    }

    private func assign(_ option: ScreenCaptureWindowOption, to slot: Int) {
        guard featureTier.permitsSourceSlot(slot) else {
            return
        }
        if sourceSlots.assignment(for: slot)?.sourceID == option.id {
            sourceSlots.clear(slot: slot)
            persistSourceSlots()
            return
        }
        if sourceSlots.assign(option, to: slot) {
            persistSourceSlots()
        }
    }
}

private struct SourceTierPicker: View {
    let copy: AppCopy
    @Binding var selection: RecordingFeatureTier
    let persist: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(RecordingFeatureTier.allCases, id: \.self) { tier in
                Button {
                    selection = tier
                    persist()
                } label: {
                    Text(tier.localizedLabel(copy))
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .frame(width: tier == .free ? 44 : 38, height: 26)
                        .foregroundStyle(selection == tier ? ConsolePalette.goldBright : ConsolePalette.textTertiary)
                        .background(selection == tier ? ConsolePalette.overlay : Color.clear)
                }
                .buttonStyle(PressablePlainButtonStyle(scale: 0.94))
                .help("\(copy.text("sourceTierSlots")) \(tier.sourceSlotRange.lowerBound)-\(tier.sourceSlotRange.upperBound)")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(ConsolePalette.border, lineWidth: 1)
        )
    }
}

private struct ScreenSourceViewModePicker: View {
    let copy: AppCopy
    @Binding var selection: ScreenSourcePickerViewMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ScreenSourcePickerViewMode.allCases, id: \.self) { mode in
                Button {
                    selection = mode
                } label: {
                    Image(systemName: mode.iconName)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 32, height: 26)
                        .foregroundStyle(selection == mode ? ConsolePalette.goldBright : ConsolePalette.textTertiary)
                        .background(selection == mode ? ConsolePalette.overlay : Color.clear)
                }
                .buttonStyle(PressablePlainButtonStyle(scale: 0.94))
                .help(mode.localizedLabel(copy))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(ConsolePalette.border, lineWidth: 1)
        )
    }
}

private struct ScreenSourceThumbnailCard: View {
    let copy: AppCopy
    let option: ScreenCaptureWindowOption
    let thumbnail: CGImage?
    let isSelected: Bool
    let assignedSlot: Int?
    let featureTier: RecordingFeatureTier
    let assignSlot: (Int) -> Void
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: toggle) {
                VStack(alignment: .leading, spacing: 8) {
                    ZStack(alignment: .topLeading) {
                        thumbnailLayer
                            .frame(height: 122)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                        HStack(spacing: 6) {
                            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                .font(.system(size: 13, weight: .semibold))
                            Image(systemName: option.iconName)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(isSelected ? ConsolePalette.goldBright : ConsolePalette.textSecondary)
                        .padding(7)
                        .background(Color.black.opacity(0.42))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .padding(7)

                        if let assignedSlot {
                            Text("\(assignedSlot)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(ConsolePalette.previewBase)
                                .frame(width: 24, height: 24)
                                .background(ConsolePalette.goldBright)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .padding(7)
                                .frame(maxWidth: .infinity, alignment: .topTrailing)
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(copy.runtimeText(option.displayTitle))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ConsolePalette.textPrimary)
                            .lineLimit(1)
                        Text(copy.runtimeText(option.detail))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(ConsolePalette.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(PressablePlainButtonStyle())

            SourceSlotPicker(
                copy: copy,
                assignedSlot: assignedSlot,
                featureTier: featureTier,
                assignSlot: assignSlot
            )
        }
        .padding(8)
        .frame(minHeight: 216)
        .background(isSelected ? ConsolePalette.overlay : ConsolePalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(isSelected ? ConsolePalette.gold.opacity(0.76) : ConsolePalette.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var thumbnailLayer: some View {
        if let thumbnail {
            Image(decorative: thumbnail, scale: 1)
                .resizable()
                .scaledToFit()
                .background(Color.black)
        } else {
            ZStack {
                ConsolePalette.previewBase
                VStack(spacing: 6) {
                    Image(systemName: option.iconName)
                        .font(.system(size: 23, weight: .medium))
                    Text(copy.text("thumbnailLoading"))
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(ConsolePalette.textTertiary)
            }
        }
    }
}

private struct ScreenSourceListRow: View {
    let copy: AppCopy
    let option: ScreenCaptureWindowOption
    let isSelected: Bool
    let assignedSlot: Int?
    let featureTier: RecordingFeatureTier
    let assignSlot: (Int) -> Void
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Button(action: toggle) {
                HStack(spacing: 9) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? ConsolePalette.goldBright : ConsolePalette.textTertiary)
                    Image(systemName: option.iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ConsolePalette.textSecondary)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(copy.runtimeText(option.displayTitle))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ConsolePalette.textPrimary)
                            .lineLimit(1)
                        Text(copy.runtimeText(option.detail))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(ConsolePalette.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(PressablePlainButtonStyle())

            Spacer()
            SourceSlotPicker(
                copy: copy,
                assignedSlot: assignedSlot,
                featureTier: featureTier,
                assignSlot: assignSlot
            )
        }
        .padding(.horizontal, 10)
        .frame(height: 52)
        .background(isSelected ? ConsolePalette.overlay : ConsolePalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? ConsolePalette.gold.opacity(0.72) : ConsolePalette.border, lineWidth: 1)
        )
    }
}

private struct SourceSlotPicker: View {
    let copy: AppCopy
    let assignedSlot: Int?
    let featureTier: RecordingFeatureTier
    let assignSlot: (Int) -> Void

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(22), spacing: 4), count: 5),
            alignment: .leading,
            spacing: 4
        ) {
            ForEach(WonderShowDistribution.visibleSourceSlots(for: featureTier), id: \.self) { slot in
                let isPermitted = featureTier.permitsSourceSlot(slot)
                Button {
                    assignSlot(slot)
                } label: {
                    Text("\(slot)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(slotForeground(slot: slot, isPermitted: isPermitted))
                        .frame(width: 22, height: 20)
                        .background(slotBackground(slot: slot, isPermitted: isPermitted))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(assignedSlot == slot ? ConsolePalette.goldBright : ConsolePalette.border, lineWidth: 1)
                        )
                }
                .buttonStyle(PressablePlainButtonStyle(scale: 0.9))
                .disabled(!isPermitted)
                .help(isPermitted ? "\(copy.text("sourceSlotHelp")) \(slot) · Command+\(slot)" : WonderShowDistribution.unavailableSourceSlotMessage(slot: slot, copy: copy, tier: featureTier))
            }
        }
    }

    private func slotForeground(slot: Int, isPermitted: Bool) -> Color {
        guard isPermitted else {
            return ConsolePalette.textTertiary.opacity(0.42)
        }
        return assignedSlot == slot ? ConsolePalette.previewBase : ConsolePalette.textTertiary
    }

    private func slotBackground(slot: Int, isPermitted: Bool) -> Color {
        guard isPermitted else {
            return ConsolePalette.overlay.opacity(0.36)
        }
        return assignedSlot == slot ? ConsolePalette.goldBright : ConsolePalette.overlay
    }
}

private struct ProgramCanvasControls: View {
    let copy: AppCopy
    @Binding var aspect: ProgramCanvasAspect
    @Binding var resolution: ProgramCanvasResolution
    let showsAdvancedPresenterEffectsUI: Bool
    @Binding var presenterBeautyControlsExpanded: Bool
    @Binding var presenterSmartBeautyEnabled: Bool
    @Binding var presenterBeauty: CGFloat
    @Binding var presenterBeautyStyle: PresenterBeautyStyle
    @Binding var presenterSkinSmoothing: CGFloat
    @Binding var presenterSkinBrightening: CGFloat
    @Binding var presenterSkinWhitening: CGFloat
    @Binding var presenterBlemishReduction: CGFloat
    @Binding var presenterComplexion: CGFloat
    @Binding var presenterAdvancedBeautyEnabled: Bool
    @Binding var presenterPortraitSegmentationEnabled: Bool
    @Binding var presenterBackgroundBlur: CGFloat
    @Binding var presenterBackgroundReplacementEnabled: Bool
    @Binding var presenterBackgroundReplacementStrength: CGFloat
    @Binding var presenterFaceLandmarkBeautyEnabled: Bool
    @Binding var presenterFaceSlimming: CGFloat
    @Binding var presenterEyeEnlargement: CGFloat
    @Binding var presenterEmojiFaceReplacementEnabled: Bool
    @Binding var presenterEmojiFaceReplacementSymbol: String
    @Binding var presenterEmojiFaceReplacementScale: CGFloat
    let onBeautyEditingEnded: () -> Void
    let onBeautyEnabled: () -> Void
    let isSubjectAwareBeautyPermitted: Bool
    @State private var expandedPopover: CanvasControlPopover?

    var body: some View {
        controlRail
            .overlay(alignment: .trailing) {
                if let expandedPopover {
                    popoverContent(for: expandedPopover)
                        .offset(x: -62)
                        .zIndex(2)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .frame(width: 48, height: showsAdvancedPresenterEffectsUI ? 258 : 106)
        .zIndex(20)
    }

    private var controlRail: some View {
        VStack(spacing: 8) {
            if showsAdvancedPresenterEffectsUI {
                CanvasControlRailButton(
                    title: copy.text("presenterSmartBeauty"),
                    shortTitle: copy.runtimeText("美颜"),
                    icon: "sparkles",
                    isActive: isSubjectAwareBeautyPermitted && presenterSmartBeautyEnabled,
                    isEnabled: isSubjectAwareBeautyPermitted,
                    help: copy.text("presenterBeautyHelp")
                ) {
                    guard isSubjectAwareBeautyPermitted else { return }
                    let willExpand = expandedPopover != .beauty
                    togglePopover(.beauty)
                    if willExpand && presenterSmartBeautyEnabled {
                        onBeautyEnabled()
                    }
                }

                CanvasControlRailButton(
                    title: copy.runtimeText("背景虚化"),
                    shortTitle: copy.runtimeText("背景"),
                    icon: "person.crop.rectangle",
                    isActive: isSubjectAwareBeautyPermitted
                        && presenterPortraitSegmentationEnabled
                        && (presenterBackgroundBlur > 0 || presenterBackgroundReplacementEnabled),
                    isEnabled: isSubjectAwareBeautyPermitted,
                    help: copy.runtimeText("直接开启人像分割、背景虚化或自然换背景")
                ) {
                    guard isSubjectAwareBeautyPermitted else { return }
                    enablePortraitEffects()
                    if presenterBackgroundBlur == 0, !presenterBackgroundReplacementEnabled {
                        presenterBackgroundBlur = 0.55
                    }
                    togglePopover(.background)
                    onBeautyEditingEnded()
                }

                CanvasControlRailButton(
                    title: copy.runtimeText("Emoji替脸"),
                    shortTitle: copy.runtimeText("Emoji"),
                    icon: "face.smiling",
                    isActive: isSubjectAwareBeautyPermitted && presenterEmojiFaceReplacementEnabled,
                    isEnabled: isSubjectAwareBeautyPermitted,
                    help: copy.runtimeText("用 Emoji 直接覆盖讲者脸部，预览实时生效")
                ) {
                    guard isSubjectAwareBeautyPermitted else { return }
                    presenterEmojiFaceReplacementEnabled.toggle()
                    togglePopover(.emoji)
                    onBeautyEditingEnded()
                }
            }

            CanvasControlRailButton(
                title: copy.runtimeText("画布"),
                shortTitle: copy.runtimeText("画布"),
                icon: "aspectratio",
                isActive: expandedPopover == .aspect,
                isEnabled: true,
                help: copy.runtimeText("切换监视器和默认导出的画面比例")
            ) {
                togglePopover(.aspect)
            }

            CanvasControlRailButton(
                title: copy.runtimeText("清晰度"),
                shortTitle: copy.runtimeText("清晰"),
                icon: "rectangle.compress.vertical",
                isActive: expandedPopover == .resolution,
                isEnabled: true,
                help: copy.runtimeText("切换预览和默认导出的输出分辨率")
            ) {
                togglePopover(.resolution)
            }
        }
        .padding(6)
        .background(Color.black.opacity(0.56))
        .background(.ultraThinMaterial.opacity(0.34))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ConsolePalette.goldBright.opacity(0.96), lineWidth: 1.2)
        )
        .shadow(color: .black.opacity(0.82), radius: 16, x: 0, y: 7)
    }

    private func enablePortraitEffects() {
        guard showsAdvancedPresenterEffectsUI else {
            return
        }
        presenterSmartBeautyEnabled = true
        presenterAdvancedBeautyEnabled = true
        presenterFaceLandmarkBeautyEnabled = true
        presenterPortraitSegmentationEnabled = true
        onBeautyEnabled()
    }

    private func togglePopover(_ popover: CanvasControlPopover) {
        if expandedPopover == popover {
            expandedPopover = nil
            if popover == .beauty {
                presenterBeautyControlsExpanded = false
            }
        } else {
            expandedPopover = popover
            presenterBeautyControlsExpanded = popover == .beauty
        }
    }

    @ViewBuilder
    private func popoverContent(for popover: CanvasControlPopover) -> some View {
        switch popover {
        case .beauty:
            presenterBeautyPanel
        case .background:
            backgroundPanel
        case .emoji:
            emojiPanel
        case .aspect:
            CanvasOptionPanel(
                title: copy.runtimeText("画布"),
                options: ProgramCanvasAspect.allCases.map { CanvasOption(id: $0.rawValue, label: $0.label) },
                selectedID: aspect.rawValue
            ) { id in
                if let next = ProgramCanvasAspect(rawValue: id) {
                    aspect = next
                }
                expandedPopover = nil
            }
        case .resolution:
            CanvasOptionPanel(
                title: copy.runtimeText("清晰度"),
                options: ProgramCanvasResolution.allCases.map { CanvasOption(id: $0.rawValue, label: $0.label) },
                selectedID: resolution.rawValue
            ) { id in
                if let next = ProgramCanvasResolution(rawValue: id) {
                    resolution = next
                }
                expandedPopover = nil
            }
        }
    }

    private var presenterBeautyPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Toggle("", isOn: $presenterSmartBeautyEnabled)
                    .labelsHidden()
                    .toggleStyle(ConsoleSwitchToggleStyle())
                    .onChange(of: presenterSmartBeautyEnabled) { _, enabled in
                        if enabled {
                            onBeautyEnabled()
                        }
                        onBeautyEditingEnded()
                    }
                Text(copy.text("presenterSmartBeauty"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ConsolePalette.textPrimary)
                Spacer()
                Menu {
                    ForEach(PresenterBeautyStyle.allCases, id: \.self) { style in
                        Button(style.localizedLabel(copy)) {
                            presenterBeautyStyle = style
                            onBeautyEditingEnded()
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(presenterBeautyStyle.localizedLabel(copy))
                            .font(.system(size: 11, weight: .bold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(ConsolePalette.goldBright)
                    .padding(.horizontal, 9)
                    .frame(height: 25)
                    .background(ConsolePalette.overlay.opacity(0.58))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(ConsolePalette.innerBorder, lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.plain)
                Button {
                    closePopover()
                } label: {
                    CanvasControlIcon(name: "xmark")
                        .frame(width: 24, height: 24)
                        .background(ConsolePalette.overlay.opacity(0.58))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(ConsolePalette.innerBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help(copy.runtimeText("关闭智能美颜面板"))
            }
            beautyPanelSlider(label: copy.text("presenterNaturalBeauty"), value: $presenterBeauty, range: 0...1)
            beautyPanelSlider(label: copy.text("presenterSkinSmoothing"), value: $presenterSkinSmoothing, range: 0...1)
            beautyPanelSlider(label: copy.text("presenterSkinBrightening"), value: $presenterSkinBrightening, range: 0...1)
            beautyPanelSlider(label: copy.text("presenterSkinWhitening"), value: $presenterSkinWhitening, range: 0...1)
            beautyPanelSlider(label: copy.text("presenterBlemishReduction"), value: $presenterBlemishReduction, range: 0...1)
            beautyPanelSlider(label: copy.text("presenterComplexion"), value: $presenterComplexion, range: 0...1)
            beautyPanelSlider(label: copy.runtimeText("瘦脸"), value: $presenterFaceSlimming, range: 0...0.8)
            beautyPanelSlider(label: copy.runtimeText("大眼"), value: $presenterEyeEnlargement, range: 0...0.65)
        }
        .padding(12)
        .frame(width: 292)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.94),
                    ConsolePalette.surface.opacity(0.98)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ConsolePalette.goldBright.opacity(0.78), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.78), radius: 16, x: 0, y: 8)
    }

    private var backgroundPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            panelHeader(title: copy.runtimeText("背景效果"))
            CanvasToggleRow(
                title: copy.runtimeText("背景分割"),
                isOn: $presenterPortraitSegmentationEnabled,
                onChange: {
                    if presenterPortraitSegmentationEnabled {
                        enablePortraitEffects()
                    }
                    onBeautyEditingEnded()
                }
            )
            beautyPanelSlider(label: copy.runtimeText("虚化"), value: $presenterBackgroundBlur, range: 0...1)
            CanvasToggleRow(
                title: copy.runtimeText("自然换背景"),
                isOn: $presenterBackgroundReplacementEnabled,
                onChange: {
                    enablePortraitEffects()
                    if presenterBackgroundReplacementEnabled, presenterBackgroundReplacementStrength == 0 {
                        presenterBackgroundReplacementStrength = 0.85
                    }
                    onBeautyEditingEnded()
                }
            )
            if presenterBackgroundReplacementEnabled {
                beautyPanelSlider(label: copy.runtimeText("替换强度"), value: $presenterBackgroundReplacementStrength, range: 0...1)
            }
        }
        .padding(12)
        .frame(width: 292)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ConsolePalette.goldBright.opacity(0.78), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.78), radius: 16, x: 0, y: 8)
    }

    private var emojiPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            panelHeader(title: copy.runtimeText("Emoji替脸"))
            CanvasToggleRow(
                title: copy.runtimeText("启用 Emoji 脸"),
                isOn: $presenterEmojiFaceReplacementEnabled,
                onChange: {
                    onBeautyEditingEnded()
                }
            )
            MenuControlRow(label: copy.runtimeText("Emoji")) {
                Menu {
                    ForEach(presenterEmojiChoices, id: \.self) { symbol in
                        Button(symbol) {
                            presenterEmojiFaceReplacementSymbol = symbol
                            onBeautyEditingEnded()
                        }
                    }
                } label: {
                    MenuFieldLabel(text: presenterEmojiFaceReplacementSymbol)
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.plain)
            }
            beautyPanelSlider(label: copy.runtimeText("大小"), value: $presenterEmojiFaceReplacementScale, range: 0.68...1.65)
        }
        .padding(12)
        .frame(width: 292)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ConsolePalette.goldBright.opacity(0.78), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.78), radius: 16, x: 0, y: 8)
    }

    private func panelHeader(title: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ConsolePalette.textPrimary)
            Spacer()
            Button {
                closePopover()
            } label: {
                CanvasControlIcon(name: "xmark")
                    .frame(width: 24, height: 24)
                    .background(ConsolePalette.overlay.opacity(0.58))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(ConsolePalette.innerBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help(copy.runtimeText("关闭面板"))
        }
    }

    private func beautyPanelSlider(
        label: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ConsolePalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: 52, alignment: .leading)
            ConsoleValueSlider(value: value, range: range) {
                onBeautyEditingEnded()
            }
            Text("\(Int((value.wrappedValue * 100).rounded()))%")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(ConsolePalette.textTertiary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    private var panelBackground: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.94),
                ConsolePalette.surface.opacity(0.98)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func closePopover() {
        expandedPopover = nil
        presenterBeautyControlsExpanded = false
    }

}

private struct CanvasToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ConsolePalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(ConsoleSwitchToggleStyle())
                .onChange(of: isOn) {
                    onChange()
                }
        }
    }
}

private enum CanvasControlPopover: Hashable {
    case beauty
    case background
    case emoji
    case aspect
    case resolution
}

private struct CanvasOption: Identifiable {
    let id: String
    let label: String
}

private struct CanvasOptionPanel: View {
    let title: String
    let options: [CanvasOption]
    let selectedID: String
    let select: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ConsolePalette.textPrimary)
            ForEach(options) { option in
                optionButton(option)
            }
        }
        .padding(12)
        .frame(width: 168)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ConsolePalette.goldBright.opacity(0.78), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.78), radius: 16, x: 0, y: 8)
    }

    private func optionButton(_ option: CanvasOption) -> some View {
        let isSelected = selectedID == option.id
        return Button {
            select(option.id)
        } label: {
            HStack(spacing: 8) {
                Text(option.label)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(isSelected ? ConsolePalette.previewBase : ConsolePalette.goldBright)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    CanvasControlIcon(name: "checkmark")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(isSelected ? ConsolePalette.goldBright : ConsolePalette.overlay.opacity(0.58))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(ConsolePalette.goldBright.opacity(isSelected ? 0.9 : 0.42), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var panelBackground: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.94),
                ConsolePalette.surface.opacity(0.98)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct CanvasControlRailButton: View {
    let title: String
    let shortTitle: String
    let icon: String
    let isActive: Bool
    let isEnabled: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                CanvasControlIcon(name: icon)
                Text(shortTitle)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(ConsolePalette.goldBright)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 36, height: 42)
            .background(buttonBackground)
            .background(.ultraThinMaterial.opacity(0.42))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(ConsolePalette.goldBright.opacity(isActive ? 0.86 : 0.44), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.46)
        .help("\(title) · \(help)")
    }

    private var buttonBackground: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(isActive ? 0.82 : 0.58),
                ConsolePalette.surface.opacity(isActive ? 0.92 : 0.62)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct CanvasControlIcon: View {
    let name: String
    private let gold = Color(red: 255 / 255, green: 214 / 255, blue: 101 / 255)

    var body: some View {
        Canvas { context, size in
            let stroke = StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
            let rect = CGRect(x: 3.5, y: 4.5, width: size.width - 7, height: size.height - 9)
            var path = Path()
            switch name {
            case "sparkles":
                drawSparkles(in: &context, size: size)
            case "aspectratio":
                path.addRoundedRect(in: rect, cornerSize: CGSize(width: 1.5, height: 1.5))
                context.stroke(path, with: .color(gold), style: stroke)
                var diagonal = Path()
                diagonal.move(to: CGPoint(x: 6, y: 12.5))
                diagonal.addLine(to: CGPoint(x: 12.5, y: 6))
                diagonal.move(to: CGPoint(x: 6, y: 10))
                diagonal.addLine(to: CGPoint(x: 6, y: 12.5))
                diagonal.addLine(to: CGPoint(x: 8.5, y: 12.5))
                diagonal.move(to: CGPoint(x: 10, y: 6))
                diagonal.addLine(to: CGPoint(x: 12.5, y: 6))
                diagonal.addLine(to: CGPoint(x: 12.5, y: 8.5))
                context.stroke(diagonal, with: .color(gold), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            case "rectangle.compress.vertical":
                path.addRoundedRect(in: rect, cornerSize: CGSize(width: 1.5, height: 1.5))
                context.stroke(path, with: .color(gold), style: stroke)
                var lines = Path()
                lines.move(to: CGPoint(x: 6.2, y: 7.2))
                lines.addLine(to: CGPoint(x: 11.8, y: 7.2))
                lines.move(to: CGPoint(x: 6.2, y: 9))
                lines.addLine(to: CGPoint(x: 11.8, y: 9))
                lines.move(to: CGPoint(x: 6.2, y: 10.8))
                lines.addLine(to: CGPoint(x: 11.8, y: 10.8))
                context.stroke(lines, with: .color(gold), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            case "checkmark":
                path.move(to: CGPoint(x: 4.5, y: 9.2))
                path.addLine(to: CGPoint(x: 7.6, y: 12.2))
                path.addLine(to: CGPoint(x: 13.7, y: 5.6))
                context.stroke(path, with: .color(gold), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            case "xmark":
                path.move(to: CGPoint(x: 5.5, y: 5.5))
                path.addLine(to: CGPoint(x: 12.5, y: 12.5))
                path.move(to: CGPoint(x: 12.5, y: 5.5))
                path.addLine(to: CGPoint(x: 5.5, y: 12.5))
                context.stroke(path, with: .color(gold), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            default:
                path.addEllipse(in: CGRect(x: 5, y: 5, width: 8, height: 8))
                context.stroke(path, with: .color(gold), style: stroke)
            }
        }
        .frame(width: 18, height: 18)
    }

    private func drawSparkles(in context: inout GraphicsContext, size: CGSize) {
        let stroke = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
        var large = Path()
        large.move(to: CGPoint(x: 8.5, y: 3.5))
        large.addLine(to: CGPoint(x: 8.5, y: 12.5))
        large.move(to: CGPoint(x: 4, y: 8))
        large.addLine(to: CGPoint(x: 13, y: 8))
        large.move(to: CGPoint(x: 5.4, y: 4.9))
        large.addLine(to: CGPoint(x: 11.6, y: 11.1))
        large.move(to: CGPoint(x: 11.6, y: 4.9))
        large.addLine(to: CGPoint(x: 5.4, y: 11.1))
        context.stroke(large, with: .color(gold), style: stroke)

        var small = Path()
        small.move(to: CGPoint(x: 14.2, y: 12.2))
        small.addLine(to: CGPoint(x: 14.2, y: 15.2))
        small.move(to: CGPoint(x: 12.7, y: 13.7))
        small.addLine(to: CGPoint(x: 15.7, y: 13.7))
        context.stroke(small, with: .color(gold), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
    }
}

private struct CanvasControlChevron: View {
    private let gold = Color(red: 255 / 255, green: 214 / 255, blue: 101 / 255)

    var body: some View {
        Canvas { context, _ in
            var path = Path()
            path.move(to: CGPoint(x: 1.5, y: 2.5))
            path.addLine(to: CGPoint(x: 5, y: 6))
            path.addLine(to: CGPoint(x: 8.5, y: 2.5))
            context.stroke(path, with: .color(gold), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 10, height: 8)
    }
}

private struct FeatureTierBadge: View {
    let text: String
    var isProminent = false

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(isProminent ? ConsolePalette.previewBase : ConsolePalette.goldBright)
            .padding(.horizontal, 5)
            .frame(height: 16)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isProminent ? ConsolePalette.goldBright : Color.black.opacity(0.42))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(ConsolePalette.goldBright.opacity(0.72), lineWidth: 0.8)
            )
    }
}

private struct ResizableSheetWindowAccessor: NSViewRepresentable {
    let minSize: NSSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else {
            return
        }
        window.styleMask.insert(.resizable)
        window.minSize = minSize
    }
}

private struct ProgramCanvasPlaceholder: View {
    let copy: AppCopy
    let isRecording: Bool
    let target: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 16 / 255, green: 14 / 255, blue: 11 / 255),
                    Color(red: 30 / 255, green: 25 / 255, blue: 18 / 255)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 8) {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(ConsolePalette.gold.opacity(0.72))
                Text(isRecording ? copy.runtimeText("正在录制演示画面") : copy.runtimeText("导播监视器"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ConsolePalette.textPrimary)
                Text(target)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(ConsolePalette.textTertiary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ProgramMonitorView: View {
    let copy: AppCopy
    let layout: RecordingLayout
    let canvasAspectRatio: CGFloat
    let screenImage: CGImage?
    let screenSourceID: ScreenCaptureSourceID?
    let cameraPreviewImage: CGImage?
    let cameraSession: AVCaptureSession
    let cameraStatus: CameraStatus
    let cameraStatusDetail: String
    let cameraActionTitle: String
    let screenSourceLabel: String
    let isRecording: Bool
    @Binding var pipOffset: CGSize
    @Binding var pipScale: CGFloat
    let pipShape: PiPShape
    let presenterVideoEffects: PresenterVideoEffects
    let canvasSizeChanged: (CGSize) -> Void
    let pipInteractionEnded: () -> Void
    let pipCornerChanged: (PiPCorner) -> Void
    let reconnect: () -> Void
    @State private var pipDragBaseOffset: CGSize?
    @State private var pipResizeBaseScale: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            let canvasRect = canvasRect(in: proxy.size)

            ZStack(alignment: .topLeading) {
                Color.black
                canvasScene(in: canvasRect.size)
                    .frame(width: canvasRect.width, height: canvasRect.height)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(ConsolePalette.goldBright.opacity(0.72), lineWidth: 1.2)
                    )
                    .shadow(color: .black.opacity(0.65), radius: 18, x: 0, y: 8)
                    .position(x: canvasRect.midX, y: canvasRect.midY)
                canvasMask(outside: canvasRect, in: proxy.size)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Color.black)
            .onAppear {
                canvasSizeChanged(canvasRect.size)
            }
            .onChange(of: proxy.size) { _, newSize in
                canvasSizeChanged(self.canvasRect(in: newSize).size)
            }
            .onChange(of: canvasAspectRatio) { _, _ in
                canvasSizeChanged(self.canvasRect(in: proxy.size).size)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func canvasRect(in size: CGSize) -> CGRect {
        let safeAspectRatio = max(0.1, canvasAspectRatio)
        let containerAspectRatio = max(0.1, size.width / max(1, size.height))
        let canvasSize: CGSize

        if containerAspectRatio > safeAspectRatio {
            let height = size.height
            canvasSize = CGSize(width: height * safeAspectRatio, height: height)
        } else {
            let width = size.width
            canvasSize = CGSize(width: width, height: width / safeAspectRatio)
        }

        return CGRect(
            x: (size.width - canvasSize.width) / 2,
            y: (size.height - canvasSize.height) / 2,
            width: canvasSize.width,
            height: canvasSize.height
        )
    }

    private func canvasMask(outside rect: CGRect, in size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.black.opacity(0.44))
                .frame(width: size.width, height: max(0, rect.minY))
                .position(x: size.width / 2, y: max(0, rect.minY) / 2)

            Rectangle()
                .fill(Color.black.opacity(0.44))
                .frame(width: size.width, height: max(0, size.height - rect.maxY))
                .position(x: size.width / 2, y: rect.maxY + max(0, size.height - rect.maxY) / 2)

            Rectangle()
                .fill(Color.black.opacity(0.44))
                .frame(width: max(0, rect.minX), height: rect.height)
                .position(x: max(0, rect.minX) / 2, y: rect.midY)

            Rectangle()
                .fill(Color.black.opacity(0.44))
                .frame(width: max(0, size.width - rect.maxX), height: rect.height)
                .position(x: rect.maxX + max(0, size.width - rect.maxX) / 2, y: rect.midY)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func canvasScene(in size: CGSize) -> some View {
        ZStack {
            switch layout {
            case .screenOnly:
                screenLayer(fillMode: .fit)
            case .speakerCloseUp, .speakerFullBody:
                cameraLayer
            case .screenWithCameraPictureInPicture:
                screenLayer(fillMode: .fit)
                pipCameraLayer
                    .position(pipPosition(in: size))
                    .gesture(pipDrag(in: size))
            case .cameraWithScreenPictureInPicture:
                cameraLayer
                pipScreenLayer
                    .position(pipPosition(in: size))
                    .gesture(pipDrag(in: size))
            case .sideBySide:
                HStack(spacing: 0) {
                    screenLayer(fillMode: .fit)
                    cameraLayer
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func screenLayer(fillMode: ContentMode) -> some View {
        GeometryReader { proxy in
            ZStack {
                if let screenImage {
                    screenImageView(
                        screenImage,
                        preservesWholeSource: fillMode == .fit || screenSourceID?.isWindow == true,
                        in: proxy.size
                    )
                } else {
                    ProgramCanvasPlaceholder(
                        copy: copy,
                        isRecording: isRecording,
                        target: screenSourceLabel
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Color.black)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func screenImageView(_ image: CGImage, preservesWholeSource: Bool, in size: CGSize) -> some View {
        let sourceSize = CGSize(width: image.width, height: image.height)
        if preservesWholeSource {
            let rect = ScreenArchiveRecorder.maxIntegralAspectFitRect(
                sourceSize: sourceSize,
                targetSize: size
            )
            Image(decorative: image, scale: 1)
                .resizable()
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        } else {
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .clipped()
        }
    }

    private var cameraLayer: some View {
        ZStack {
            if cameraStatus == .running {
                presenterCameraPreview
            } else {
                cameraPlaceholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private var pipCameraLayer: some View {
        pipChrome {
            if cameraStatus == .running {
                presenterCameraPreview
            } else {
                cameraPlaceholder
            }
        }
    }

    private var pipScreenLayer: some View {
        pipChrome {
            if let screenImage {
                Image(decorative: screenImage, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .background(Color.black)
            } else {
                ProgramCanvasPlaceholder(
                    copy: copy,
                    isRecording: isRecording,
                    target: screenSourceLabel
                )
            }
        }
    }

    @ViewBuilder
    private var presenterCameraPreview: some View {
        if let cameraPreviewImage {
            Image(decorative: cameraPreviewImage, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipped()
        } else {
            CameraPreviewView(session: cameraSession)
                .modifier(PresenterVideoPreviewEffectModifier(effects: presenterVideoEffects))
        }
    }

    private func pipChrome<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let size = pipSize
        return ZStack(alignment: .bottomTrailing) {
            content()
                .frame(width: size.width, height: size.height)
                .background(Color.black)
                .modifier(PiPShapeModifier(shape: pipShape, cornerRadius: 10))
                .overlay(
                    PiPShapeOverlay(shape: pipShape, cornerRadius: 10)
                        .stroke(ConsolePalette.gold.opacity(0.7), lineWidth: 1)
                )

            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(ConsolePalette.goldBright)
                .frame(width: 22, height: 22)
                .background(ConsolePalette.surface.opacity(0.92))
                .clipShape(Circle())
                .overlay(Circle().stroke(ConsolePalette.gold.opacity(0.75), lineWidth: 1))
                .padding(6)
                .gesture(pipResizeGesture)
        }
        .frame(width: size.width, height: size.height)
        .shadow(color: .black.opacity(0.45), radius: 12, x: 0, y: 6)
    }

    private var cameraPlaceholder: some View {
        ZStack {
            ConsolePalette.previewGlow
            VStack(spacing: 10) {
                Image(systemName: "camera.slash")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(ConsolePalette.textTertiary)
                Text(copy.cameraNotConnected)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ConsolePalette.textSecondary)
                Text(cameraStatusDetail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ConsolePalette.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Button(cameraActionTitle) {
                    reconnect()
                }
                .buttonStyle(ConsoleGradientButtonStyle(variant: .outline, expands: false))
            }
            .padding(16)
        }
    }

    private var pipSize: CGSize {
        let scale = min(max(pipScale, 0.65), 1.6)
        let base: CGSize
        switch layout {
        case .cameraWithScreenPictureInPicture:
            base = CGSize(width: 270, height: 152)
        default:
            base = CGSize(width: 250, height: 141)
        }
        switch pipShape {
        case .roundedRectangle:
            return CGSize(width: base.width * scale, height: base.height * scale)
        case .square, .circle:
            let side = min(max(base.height * scale, 92), 245)
            return CGSize(width: side, height: side)
        }
    }

    private func pipPosition(in size: CGSize) -> CGPoint {
        let margin: CGFloat = 18
        let halfWidth = pipSize.width / 2
        let halfHeight = pipSize.height / 2
        let x = size.width - halfWidth - margin + pipOffset.width
        let y = size.height - halfHeight - margin + pipOffset.height
        return CGPoint(
            x: min(max(halfWidth + margin, x), max(halfWidth + margin, size.width - halfWidth - margin)),
            y: min(max(halfHeight + margin, y), max(halfHeight + margin, size.height - halfHeight - margin))
        )
    }

    private func pipDrag(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let baseOffset = pipDragBaseOffset ?? pipOffset
                pipDragBaseOffset = baseOffset
                let nextOffset = CGSize(
                    width: baseOffset.width + value.translation.width,
                    height: baseOffset.height + value.translation.height
                )
                pipOffset = clampedOffset(nextOffset, in: size)
            }
            .onEnded { value in
                pipDragBaseOffset = nil
                let corner = nearestCorner(position: pipPosition(in: size), in: size)
                pipCornerChanged(corner)
                pipInteractionEnded()
            }
    }

    private var pipResizeGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let baseScale = pipResizeBaseScale ?? pipScale
                pipResizeBaseScale = baseScale
                let delta = (value.translation.width + value.translation.height) / 260
                pipScale = min(max(baseScale + delta, 0.65), 1.6)
            }
            .onEnded { _ in
                pipResizeBaseScale = nil
                pipInteractionEnded()
            }
    }

    private func clampedOffset(_ offset: CGSize, in size: CGSize) -> CGSize {
        let margin: CGFloat = 18
        let halfWidth = pipSize.width / 2
        let halfHeight = pipSize.height / 2
        let defaultX = size.width - halfWidth - margin
        let defaultY = size.height - halfHeight - margin
        let minX = halfWidth + margin
        let maxX = size.width - halfWidth - margin
        let minY = halfHeight + margin
        let maxY = size.height - halfHeight - margin
        return CGSize(
            width: min(max(minX - defaultX, offset.width), maxX - defaultX),
            height: min(max(minY - defaultY, offset.height), maxY - defaultY)
        )
    }

    private func nearestCorner(position: CGPoint, in size: CGSize) -> PiPCorner {
        let isLeft = position.x < size.width / 2
        let isTop = position.y < size.height / 2
        switch (isLeft, isTop) {
        case (true, true):
            return .topLeft
        case (false, true):
            return .topRight
        case (true, false):
            return .bottomLeft
        case (false, false):
            return .bottomRight
        }
    }

    private func offset(for corner: PiPCorner, in size: CGSize) -> CGSize {
        let margin: CGFloat = 18
        let halfWidth = pipSize.width / 2
        let halfHeight = pipSize.height / 2
        let defaultX = size.width - halfWidth - margin
        let defaultY = size.height - halfHeight - margin
        let targetX: CGFloat
        let targetY: CGFloat
        switch corner {
        case .topLeft:
            targetX = halfWidth + margin
            targetY = halfHeight + margin
        case .topRight:
            targetX = defaultX
            targetY = halfHeight + margin
        case .bottomLeft:
            targetX = halfWidth + margin
            targetY = defaultY
        case .bottomRight:
            targetX = defaultX
            targetY = defaultY
        }
        return CGSize(width: targetX - defaultX, height: targetY - defaultY)
    }
}

private struct PresenterVideoPreviewEffectModifier: ViewModifier {
    let effects: PresenterVideoEffects

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: effects.isMirrored ? -1 : 1, y: 1, anchor: .center)
            .brightness(effects.brightness)
            .contrast(effects.contrast)
            .brightness(effects.hasSubjectAwareBeautyAdjustments ? previewBeautyBrightness : 0)
            .saturation(effects.hasSubjectAwareBeautyAdjustments ? previewBeautySaturation : 1)
            .blur(radius: effects.hasSubjectAwareBeautyAdjustments ? 0 : effects.beauty * 1.4)
    }

    private var previewBeautyBrightness: Double {
        min(0.18, effects.skinBrightening * 0.09 + effects.skinWhitening * 0.04 + effects.beauty * 0.05)
    }

    private var previewBeautySaturation: Double {
        min(1.12, 1 + effects.complexion * 0.08)
    }
}

private struct PiPShapeModifier: ViewModifier {
    let shape: PiPShape
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        switch shape {
        case .roundedRectangle:
            content.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        case .square:
            content.clipShape(Rectangle())
        case .circle:
            content.clipShape(Circle())
        }
    }
}

private struct PiPShapeOverlay: Shape {
    let shape: PiPShape
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        switch shape {
        case .roundedRectangle:
            return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect)
        case .square:
            return Rectangle().path(in: rect)
        case .circle:
            return Circle().path(in: rect)
        }
    }
}

@MainActor
private final class ProgramPreviewModel: ObservableObject {
    let player: AVPlayer

    init(url: URL) {
        player = AVPlayer(url: url)
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }
}

private struct ProgramPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

@MainActor
private final class RecordingCountdownPresenter: ObservableObject {
    private var window: NSWindow?

    func show(count: Int) {
        show(text: "\(count)")
    }

    func showRecordingStarted() {
        show(text: "REC")
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }

    private func show(text: String) {
        let hostingView = NSHostingView(rootView: RecordingCountdownOverlay(text: text))
        let window = window ?? makeWindow()
        window.contentView = hostingView
        position(window)
        window.orderFrontRegardless()
        self.window = window
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 180),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = true
        return window
    }

    private func position(_ window: NSWindow) {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = window.frame.size
        window.setFrameOrigin(
            NSPoint(
                x: screenFrame.midX - size.width / 2,
                y: screenFrame.midY - size.height / 2
            )
        )
    }
}

private struct RecordingCountdownOverlay: View {
    let text: String

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.74))
                .overlay(Circle().stroke(ConsolePalette.record.opacity(0.9), lineWidth: 2))
            Text(text)
                .font(.system(size: text == "REC" ? 40 : 72, weight: .black, design: .rounded))
                .foregroundStyle(text == "REC" ? ConsolePalette.record : ConsolePalette.goldBright)
        }
        .frame(width: 180, height: 180)
        .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 12)
    }
}

private struct ExportProgressSheet: View {
    let copy: AppCopy
    let progress: ExportProgressPresentation
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .tint(ConsolePalette.goldBright)
                Text(progress.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ConsolePalette.textPrimary)
                Spacer()
                Text("\(Int((progress.fraction * 100).rounded()))%")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(ConsolePalette.goldBright)
            }

            ProgressView(value: progress.fraction)
                .tint(ConsolePalette.goldBright)

            VStack(alignment: .leading, spacing: 8) {
                ExportProgressLine(label: copy.resolution, value: resolutionLabel)
                ExportProgressLine(label: copy.runtimeText("文件大小"), value: fileSizeLabel)
                ExportProgressLine(label: copy.codec, value: progress.settings.codec.localizedLabel)
                ExportProgressLine(label: copy.frameRate, value: "\(progress.settings.frameRate.rawValue) fps")
                if let outputURL = progress.outputURL {
                    ExportProgressLine(label: copy.runtimeText("输出文件"), value: outputURL.lastPathComponent)
                }
            }

            Text(copy.runtimeText("导出期间请不要关闭灵演。"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ConsolePalette.textTertiary)

            HStack {
                Spacer()
                Button(copy.runtimeText("取消")) {
                    cancel()
                }
                .buttonStyle(ConsoleGradientButtonStyle(variant: .outline, expands: false, compact: true))
            }
        }
        .padding(20)
        .frame(width: 430)
        .background(ConsolePalette.background)
    }

    private var resolutionLabel: String {
        guard progress.width > 0, progress.height > 0 else {
            if let customPixelSize = progress.settings.customPixelSize {
                return "\(customPixelSize.width)x\(customPixelSize.height)"
            }
            return progress.settings.resolution.localizedLabel(copy)
        }
        return "\(progress.width)x\(progress.height)"
    }

    private var fileSizeLabel: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = progress.fileSize >= 1_000_000_000 ? [.useGB] : [.useMB, .useKB]
        return formatter.string(fromByteCount: max(0, progress.fileSize))
    }
}

private struct ExportProgressLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ConsolePalette.textTertiary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(ConsolePalette.textPrimary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(ConsolePalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ConsolePalette.innerBorder, lineWidth: 1)
        )
    }
}

private struct ExportPickerRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ConsoleFieldLabel(label)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ExportOptionGrid<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let label: (Item) -> String

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 82), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(items, id: \.self) { item in
                Button {
                    selection = item
                } label: {
                    Text(label(item))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selection == item ? ConsolePalette.goldBright : ConsolePalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selection == item ? ConsolePalette.overlay : ConsolePalette.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(selection == item ? ConsolePalette.gold.opacity(0.75) : ConsolePalette.border, lineWidth: 1)
                        )
                }
                .buttonStyle(PressablePlainButtonStyle(scale: 0.96))
            }
        }
    }
}

private extension View {
    /// 给右侧卡片统一套用暖黑金导演台面板样式。
    func consoleCardSurface() -> some View {
        self
            .background(ConsolePalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(ConsolePalette.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 12, x: 0, y: 4)
    }
}

private extension PresentationTarget {
    func localizedLabel(_ copy: AppCopy) -> String {
        switch self {
        case .powerPoint:
            return copy.appPPT
        case .wps:
            return copy.appWPS
        case .keynote:
            return copy.appKeynote
        case .word:
            return copy.appWord
        case .excel:
            return copy.appExcel
        case .pdfViewer:
            return copy.appPDF
        case .genericKeyboard:
            return copy.genericKeyboard
        case .html:
            return copy.appHTML
        }
    }
}

private extension RecordingMode {
    func localizedLabel(_ copy: AppCopy) -> String {
        switch self {
        case .cameraOnly:
            return copy.text("modeSpeakerOnly")
        case .screenOnly:
            return copy.text("modeScreenOnly")
        case .cameraAndScreen:
            return copy.modeCamScreen
        }
    }
}

private extension RecordingLayout {
    func localizedLabel(_ copy: AppCopy) -> String {
        switch self {
        case .speakerCloseUp:
            return copy.layoutCloseup
        case .speakerFullBody:
            return copy.text("layoutSpeakerFullBody")
        case .screenOnly:
            return copy.text("screenOnlyLayout")
        case .screenWithCameraPictureInPicture(let corner):
            if corner == .bottomRight {
                return copy.text("screenMainPipLayout")
            }
            return "\(copy.text("screenMainPipLayout")) · \(corner.localizedLabel(copy))"
        case .cameraWithScreenPictureInPicture(let corner):
            if corner == .topRight {
                return copy.text("speakerMainPipLayout")
            }
            return "\(copy.text("speakerMainPipLayout")) · \(corner.localizedLabel(copy))"
        case .sideBySide:
            return copy.layoutSide
        }
    }
}

private extension ScreenCaptureSourcePreference {
    func localizedLabel(_ copy: AppCopy) -> String {
        switch self {
        case .automaticPresentationWindow:
            return copy.text("sourcePresentationWindow")
        case .entireDisplay:
            return copy.text("sourceEntireDisplay")
        case .selectedDisplay:
            return copy.text("selectedDisplay")
        case .selectedWindows(let ids):
            if ids.count == 1 {
                return copy.text("selectedOneWindow")
            }
            return "\(copy.text("selectedWindowsPrefix")) \(ids.count)"
        }
    }
}

private extension PiPShape {
    var programShape: ProgramPictureInPictureShape {
        switch self {
        case .roundedRectangle:
            return .roundedRectangle
        case .square:
            return .square
        case .circle:
            return .circle
        }
    }

    func localizedLabel(_ copy: AppCopy) -> String {
        switch self {
        case .roundedRectangle:
            return copy.text("pipShapeRounded")
        case .square:
            return copy.text("pipShapeSquare")
        case .circle:
            return copy.text("pipShapeCircle")
        }
    }
}

private extension PresenterBeautyStyle {
    func localizedLabel(_ copy: AppCopy) -> String {
        switch self {
        case .natural:
            return copy.text("presenterBeautyNatural")
        case .clean:
            return copy.text("presenterBeautyClean")
        case .bright:
            return copy.text("presenterBeautyBright")
        case .cameraReady:
            return copy.text("presenterBeautyCameraReady")
        }
    }
}

private extension ScreenSourcePickerViewMode {
    var iconName: String {
        switch self {
        case .thumbnails:
            return "square.grid.2x2"
        case .list:
            return "list.bullet"
        }
    }

    func localizedLabel(_ copy: AppCopy) -> String {
        switch self {
        case .thumbnails:
            return copy.text("thumbnailView")
        case .list:
            return copy.text("listView")
        }
    }
}

private extension RecordingExportResolution {
    func localizedLabel(_ copy: AppCopy) -> String {
        switch self {
        case .source:
            return copy.runtimeText("源分辨率")
        case .hd1080:
            return "1080p"
        case .qhd1440:
            return "1440p"
        case .uhd4k:
            return "4K"
        }
    }
}

private extension RecordingExportQuality {
    func localizedLabel(_ copy: AppCopy) -> String {
        switch self {
        case .standard:
            return copy.runtimeText("标准")
        case .high:
            return copy.runtimeText("高")
        case .archival:
            return copy.runtimeText("归档")
        }
    }
}

private extension RecordingExportCodec {
    var localizedLabel: String {
        switch self {
        case .h264:
            return "H.264"
        case .hevc:
            return "HEVC"
        }
    }
}

private extension PiPCorner {
    func localizedLabel(_ copy: AppCopy) -> String {
        switch self {
        case .topLeft:
            return copy.text("topLeft")
        case .topRight:
            return copy.text("topRight")
        case .bottomLeft:
            return copy.text("bottomLeft")
        case .bottomRight:
            return copy.text("bottomRight")
        }
    }
}

private extension CommandTransport {
    func localizedLabel(_ copy: AppCopy) -> String {
        switch self {
        case .keyboardShortcut:
            return copy.runtimeText("键盘事件")
        case .accessibilityAutomation:
            return copy.runtimeText("辅助控制")
        case .htmlBridge:
            return copy.runtimeText("HTML 桥接")
        case .internalOverlay:
            return copy.runtimeText("应用浮层")
        }
    }
}
