import AppKit
import AVFoundation
import Combine
import AVKit
import PresenterDirector
import SwiftUI

private enum PiPShape: String, CaseIterable, Hashable {
    case roundedRectangle
    case square
    case circle
}

private enum ScreenSourcePickerViewMode: String, CaseIterable, Hashable {
    case thumbnails
    case list
}

private enum RecordingControlState: Hashable {
    case idle
    case starting
    case recording
    case paused
}

private struct ExportProgressPresentation: Identifiable, Equatable {
    let id = "export-progress"
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
    @State private var pipOffset = CGSize(width: 18, height: -18)
    @State private var pipScale: CGFloat = 1
    @State private var pipShape: PiPShape = .roundedRectangle
    @State private var monitorCanvasSize = CGSize(width: 1280, height: 720)
    @State private var recordingStartedAt: Date?
    @State private var recordingPiPKeyframes: [RecordingPiPKeyframe] = []
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
            ExportProgressSheet(copy: copy, progress: progress)
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
                apply: {
                    applySelectedScreenWindows()
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
            commandController.refreshAccessibilityStatus()
            updateGestureHandler()
            screenArchiveRecorder.onPreviewImage = { image in
                latestScreenPreviewImage = image
            }
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
        .onChange(of: layout) {
            restartScreenPreviewIfNeeded()
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
                            sourcePreference: screenSourcePreference
                        )
                    }
                    startMicrophoneArchiveRecording(to: session.microphoneAudioURL)
                }
            } else {
                if shouldRenderStoppedRecording {
                    finalizeRecordingTimelineForLastRecording()
                }
                stopRecordingAndRenderProgram(
                    shouldRender: shouldRenderStoppedRecording,
                    discardSession: discardStoppedRecording
                )
                resetRecordingStateAfterStop()
            }
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
        .onReceive(recordingClock) { _ in
            guard commandController.isRecording, recordingControlState == .recording else {
                return
            }
            elapsedSeconds = Int(currentActiveRecordingDuration().rounded(.down))
        }
        .onDisappear {
            removeRecordingHotKeyMonitor()
            recordingCountdownTask?.cancel()
            screenSourceThumbnailTask?.cancel()
            recordingCountdownPresenter.hide()
            screenArchiveRecorder.onPreviewImage = nil
            screenPreview.stop()
            stopRecordingAndRenderProgram(shouldRender: false)
            camera.stop()
        }
    }

    /// 将当前手势和缩放回调绑定到选中的演示目标，避免目标切换时投递错位。
    private func updateGestureHandler() {
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

    private func requestRecordingToggle() {
        switch recordingControlState {
        case .idle:
            startRecordingCountdown()
        case .starting:
            cancelRecordingCountdown()
        case .recording:
            requestFinishRecording()
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
                pictureInPictureGeometry: currentPictureInPictureGeometry
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
        recordingStartedAt = now
        recordingPiPKeyframes = initialPiPKeyframes()
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
            pictureInPictureGeometry: currentPictureInPictureGeometry
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

    private func resetRecordingStateAfterStop() {
        recordingControlState = .idle
        recordingCountdownTask = nil
        recordingCountdownPresenter.hide()
        elapsedSeconds = 0
        accumulatedRecordingDuration = 0
        recordingActiveStartedAt = nil
        recordingStartedAt = nil
        lastPiPKeyframeDate = nil
        shouldRenderStoppedRecording = true
        discardStoppedRecording = false
    }

    private func installRecordingHotKeyMonitor() {
        guard localRecordingHotKeyMonitor == nil, globalRecordingHotKeyMonitor == nil else {
            return
        }

        localRecordingHotKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if isRecordingHotKey(event) {
                requestRecordingToggle()
                return nil
            }
            return event
        }
        globalRecordingHotKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if isRecordingHotKey(event) {
                requestRecordingToggle()
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

    private func isRecordingHotKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return event.charactersIgnoringModifiers?.lowercased() == "r"
            && flags.contains(.command)
            && flags.contains(.option)
    }

    private func startScreenArchiveRecording(
        to outputURL: URL,
        target: PresentationTarget,
        sourcePreference: ScreenCaptureSourcePreference
    ) {
        Task {
            do {
                try await screenArchiveRecorder.startRecording(
                    to: outputURL,
                    target: target,
                    sourcePreference: sourcePreference
                )
            } catch {
                await MainActor.run {
                    commandController.reportRecordingIssue("PPT/屏幕原始轨写入失败：\(error.localizedDescription)。请在系统设置中允许灵演进行屏幕录制。")
                }
            }
        }
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
                let outputURL = try await ProgramVideoRenderer().render(session: renderSession)
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

                Text(copy.productName)
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
                    Text(copy.brandLine2)
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
                ConsoleStatusPill(
                    icon: "hand.raised",
                    title: copy.gesture,
                    value: camera.gestureControlEnabled ? copy.recognizing : copy.standby,
                    isActive: camera.gestureControlEnabled,
                    isRecording: false
                )
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

                Button(commandController.isRehearsing ? copy.stopRehearse : copy.rehearsalButton) {
                    commandController.toggleRehearsal(target: target)
                }
                .buttonStyle(ConsoleGradientButtonStyle(variant: .gold, expands: false))

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

            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    quickStartPanel
                    presentationPanel
                    projectPanel
                    gesturePanel
                    devicePanel
                }
                .padding(.bottom, 12)
            }
            .frame(width: 300)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var previewWorkspace: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ConsolePalette.previewBase)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(ConsolePalette.border, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.75), radius: 24, x: 0, y: 12)

            ZStack {
                ProgramMonitorView(
                    copy: copy,
                    layout: layout,
                    screenImage: monitorScreenImage,
                    cameraSession: camera.session,
                    cameraStatus: camera.status,
                    cameraStatusDetail: cameraStatusDetail,
                    screenSourceLabel: monitorScreenStatusLabel,
                    isRecording: commandController.isRecording,
                    pipOffset: $pipOffset,
                    pipScale: $pipScale,
                    pipShape: pipShape,
                    canvasSizeChanged: { size in
                        monitorCanvasSize = size
                    },
                    pipInteractionEnded: {
                        recordCurrentPiPKeyframeIfNeeded(force: true)
                    },
                    pipCornerChanged: { corner in
                        updatePiPCorner(corner)
                    },
                    reconnect: { camera.start() }
                )

            }

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
                    TimelineTrackRow(row: row)
                }
            }
        }
        .padding(12)
        .background(ConsolePalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(ConsolePalette.border, lineWidth: 1)
        )
    }

    private var quickStartPanel: some View {
        VStack(spacing: 0) {
            CardHeader(title: copy.quickStart, hint: copy.realtime, isCollapsed: quickStartCollapsed) {
                quickStartCollapsed.toggle()
            }

            if !quickStartCollapsed {
                VStack(alignment: .leading, spacing: 10) {
                    ConsoleDetailLine(label: copy.rehearseState, value: commandController.isRehearsing ? copy.recording : copy.ready)
                    ConsoleDetailLine(label: copy.rehearse, value: copy.rehearsalPurpose)
                    ConsoleDetailLine(label: copy.recState, value: commandController.isRecording ? copy.recording : copy.standby)
                    ConsoleDetailLine(label: copy.activeDevice, value: localizedActiveDeviceName)
                    ConsoleDetailLine(label: copy.currentGesture, value: localizedDetectedHandShapes)

                    ConsoleDivider()

                    HStack(spacing: 7) {
                        Button(copy.refreshDevices) {
                            camera.refreshDevicesAndRestart()
                        }
                        .buttonStyle(ConsoleGradientButtonStyle(variant: .gold, expands: true))

                        Button(copy.testSlide) {
                            commandController.testNextSlide(target: target)
                        }
                        .buttonStyle(ConsoleGradientButtonStyle(variant: .gold, expands: true))
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
                            commandController.previewLastProgramExport()
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
                            exportDraftSettings = .presentationDefault
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
                                    layout = option.layout
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

                    ConsoleDivider()

                    Button(copy.openTestDeck) {
                        target = .html(engine: .custom)
                        commandController.reportDemoDeckOpenResult(DemoDeckLauncher.openDemoDeck())
                    }
                    .buttonStyle(ConsoleGradientButtonStyle(variant: .gold, expands: true))
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

                    MenuControlRow(label: copy.runtimeText("音频输入")) {
                        HStack(spacing: 7) {
                            Menu {
                                ForEach(audioInputDevices) { device in
                                    Button(device.name) {
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

                    ConsoleDivider()

                    ConsoleDetailLine(label: copy.statusLabel, value: cameraStatusValue)
                    ConsoleDetailLine(label: copy.deviceDetail, value: localizedSelectedDeviceDetail, monospaced: true)
                    ConsoleDetailLine(label: copy.runtimeText("音频详情"), value: selectedAudioInputDeviceDetail, monospaced: true)
                    ConsoleDetailLine(label: copy.inputsFound, value: discoveredDeviceSummary)
                    ConsoleDetailLine(label: copy.transport, value: localizedCommandSummary, monospaced: true)
                }
                .padding(14)
            }
        }
        .consoleCardSurface()
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
                    AboutPopoverCard(copy: copy)
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

            ExportPickerRow(label: copy.resolution) {
                ExportOptionGrid(
                    items: RecordingExportResolution.allCases,
                    selection: $exportDraftSettings.resolution
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
                DiagnosticsLine(label: copy.chromeAuto, value: localizedRuntime(commandController.automationStatus.rawValue))
                DiagnosticsLine(label: copy.scanSummary, value: localizedDeviceScanSummary)
                DiagnosticsLine(label: copy.examples, value: supportedDeviceSummary)
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
        if mode == .cameraOnly {
            latestScreenPreviewImage = nil
            screenPreview.resetImage()
        }
        restartScreenPreviewIfNeeded()
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
            screenSourceDiagnostic = snapshot.summary
            screenSourceThumbnails = [:]
            startScreenSourceThumbnailLoading(for: snapshot.options)
            if let issue = snapshot.issue {
                commandController.reportRecordingIssue("录制源读取失败：\(issue)")
            }
        }
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
        commandController.exportProgramVideo(
            settings: settings,
            onProgress: { progress in
                exportProgress = ExportProgressPresentation(
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
                    exportProgress = nil
                    exportOutcome = ExportOutcomePresentation(
                        title: copy.runtimeText("导出完成"),
                        message: [
                            "\(exportResult.width)x\(exportResult.height)",
                            formattedFileSize(exportResult.fileSize),
                            compactPath(exportResult.url)
                        ].joined(separator: "\n"),
                        url: exportResult.url
                    )
                case .failure(let error):
                    exportProgress = nil
                    if case PresentationCommandControllerError.exportCancelled = error {
                        return
                    }
                    exportOutcome = ExportOutcomePresentation(
                        title: copy.runtimeText("导出失败"),
                        message: error.localizedDescription,
                        url: nil
                    )
                }
            }
        )
    }

    private func applySelectedScreenWindows() {
        let selectedOptions = screenWindowOptions.filter { selectedScreenSourceIDs.contains($0.id) }
        guard !selectedOptions.isEmpty else {
            screenSourcePreference = .automaticPresentationWindow
            showsScreenSourcePicker = false
            handleScreenCaptureSourceChange()
            return
        }

        if let displayID = selectedOptions.compactMap(\.id.displayID).first {
            selectedScreenSourceIDs = [.display(displayID)]
            screenSourcePreference = .selectedDisplay(displayID)
        } else {
            let windowIDs = selectedOptions.compactMap(\.id.windowID)
            screenSourcePreference = .selectedWindows(windowIDs)
        }
        showsScreenSourcePicker = false
        handleScreenCaptureSourceChange()
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
        let durationMilliseconds = currentRecordingDurationMilliseconds()
        commandController.finalizeLastRecordingTimeline(
            durationMilliseconds: durationMilliseconds,
            pictureInPictureKeyframes: normalizedRecordingPiPKeyframes()
        )
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

    private func handleScreenCaptureSourceChange() {
        guard commandController.isRecording, currentProgramUsesScreen else {
            restartScreenPreviewIfNeeded()
            return
        }

        let selectedTarget = target
        let selectedSourcePreference = screenSourcePreference
        let selectedSourceLabel = screenSourcePreference.localizedLabel(copy)
        latestScreenPreviewImage = nil
        screenPreview.resetImage()
        restartScreenPreviewIfNeeded()
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

    private func restartScreenPreviewIfNeeded() {
        if !commandController.isRecording {
            latestScreenPreviewImage = nil
        }
        guard currentProgramUsesScreen else {
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
        let rawCount = expectedURLs.filter { FileManager.default.fileExists(atPath: $0.path) }.count
        return "\(rawCount) / \(expectedURLs.count) \(copy.trackUnit)"
    }

    private var programExportSummary: String {
        guard let session = commandController.lastRecordingSession else {
            return copy.previewUnavailable
        }
        return FileManager.default.fileExists(atPath: session.programOutputURL.path)
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

    private var timelineRows: [RecordingTimelineRow] {
        guard let session = commandController.lastRecordingSession else {
            return plannedTimelineRows
        }

        let roles = Set(session.manifest.project.rawTracks.map(\.role))
        var rows: [RecordingTimelineRow] = []
        if roles.contains(.slidesScreen) {
            rows.append(
                RecordingTimelineRow(
                    title: copy.text("trackSlides"),
                    detail: screenSourcePreference.localizedLabel(copy),
                    status: fileStatus(for: session.slidesScreenURL),
                    color: ConsolePalette.teal
                )
            )
        }
        if roles.contains(.presenterCamera) {
            rows.append(
                RecordingTimelineRow(
                    title: copy.text("trackSpeaker"),
                    detail: localizedActiveDeviceName,
                    status: fileStatus(for: session.presenterCameraURL),
                    color: ConsolePalette.gold
                )
            )
        }
        rows.append(
            RecordingTimelineRow(
                title: copy.text("trackMic"),
                detail: selectedAudioInputDeviceTitle,
                status: fileStatus(for: session.microphoneAudioURL),
                color: ConsolePalette.textSecondary
            )
        )
        rows.append(
            RecordingTimelineRow(
                title: copy.text("trackProgram"),
                detail: layout.localizedLabel(copy),
                status: fileStatus(for: session.programOutputURL),
                color: ConsolePalette.record
            )
        )
        return rows
    }

    private var plannedTimelineRows: [RecordingTimelineRow] {
        var rows: [RecordingTimelineRow] = []
        if currentProgramUsesScreen {
            rows.append(
                RecordingTimelineRow(
                    title: copy.text("trackSlides"),
                    detail: screenSourcePreference.localizedLabel(copy),
                    status: copy.standby,
                    color: ConsolePalette.teal
                )
            )
        }
        if currentProgramUsesCamera {
            rows.append(
                RecordingTimelineRow(
                    title: copy.text("trackSpeaker"),
                    detail: localizedActiveDeviceName,
                    status: copy.standby,
                    color: ConsolePalette.gold
                )
            )
        }
        rows.append(
            RecordingTimelineRow(
                title: copy.text("trackMic"),
                detail: selectedAudioInputDeviceTitle,
                status: copy.standby,
                color: ConsolePalette.textSecondary
            )
        )
        rows.append(
            RecordingTimelineRow(
                title: copy.text("trackProgram"),
                detail: layout.localizedLabel(copy),
                status: copy.previewUnavailable,
                color: ConsolePalette.record
            )
        )
        return rows
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
        copy.runtimeText(selectedAudioInputDevice.name)
    }

    private var selectedAudioInputDeviceDetail: String {
        copy.runtimeText(selectedAudioInputDevice.detail)
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

private enum ConsolePalette {
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
    let id = UUID()
    let title: String
    let detail: String
    let status: String
    let color: Color
}

private struct RecordingLayoutOption: Identifiable {
    let id = UUID()
    let label: String
    let layout: RecordingLayout
}

private struct TimelineTrackRow: View {
    let row: RecordingTimelineRow

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(row.color)
                .frame(width: 7, height: 7)
                .shadow(color: row.color.opacity(0.35), radius: 5, x: 0, y: 0)

            Text(row.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ConsolePalette.textPrimary)
                .frame(width: 68, alignment: .leading)

            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(row.color.opacity(0.18))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(row.color.opacity(0.42))
                            .frame(width: max(24, proxy.size.width * 0.72))
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(ConsolePalette.innerBorder, lineWidth: 1)
                    )
            }
            .frame(height: 14)

            Text(row.detail)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ConsolePalette.textTertiary)
                .lineLimit(1)
                .frame(width: 150, alignment: .trailing)

            Text(row.status)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ConsolePalette.textSecondary)
                .lineLimit(1)
                .frame(width: 64, alignment: .trailing)
        }
        .frame(height: 18)
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
    }
}

private struct MenuControlRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 10) {
            ConsoleFieldLabel(label)
                .frame(width: 58, alignment: .leading)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(copy.aboutTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ConsolePalette.textPrimary)
                Spacer()
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(ConsolePalette.textTertiary)
            }

            ConsoleDivider()

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
        .frame(width: 220)
        .background(ConsolePalette.overlay)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(ConsolePalette.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.6), radius: 16, x: 0, y: 8)
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
    let apply: () -> Void
    let refresh: () -> Void
    let requestPermission: () -> Void
    let openSettings: () -> Void
    @Environment(\.dismiss) private var dismiss

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
                    apply()
                }
                .buttonStyle(ConsoleGradientButtonStyle(variant: .gold, expands: true))
                .disabled(selectedIDs.isEmpty)
            }
        }
        .padding(18)
        .frame(minWidth: 760, idealWidth: 920, maxWidth: .infinity, minHeight: 620, idealHeight: 740, maxHeight: .infinity)
        .background(ConsolePalette.background)
        .background(ResizableSheetWindowAccessor(minSize: NSSize(width: 760, height: 620)))
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
                        isSelected: selectedIDs.contains(option.id)
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
                        isSelected: selectedIDs.contains(option.id)
                    ) {
                        toggle(option.id)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func toggle(_ id: ScreenCaptureSourceID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else if case .display = id {
            selectedIDs = [id]
        } else {
            selectedIDs = selectedIDs.filter {
                if case .display = $0 {
                    return false
                }
                return true
            }
            selectedIDs.insert(id)
        }
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
    let toggle: () -> Void

    var body: some View {
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
            .padding(8)
            .frame(minHeight: 182)
            .background(isSelected ? ConsolePalette.overlay : ConsolePalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isSelected ? ConsolePalette.gold.opacity(0.76) : ConsolePalette.border, lineWidth: 1)
            )
        }
        .buttonStyle(PressablePlainButtonStyle())
    }

    @ViewBuilder
    private var thumbnailLayer: some View {
        if let thumbnail {
            Image(decorative: thumbnail, scale: 1)
                .resizable()
                .scaledToFill()
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
    let toggle: () -> Void

    var body: some View {
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
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 46)
            .background(isSelected ? ConsolePalette.overlay : ConsolePalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? ConsolePalette.gold.opacity(0.72) : ConsolePalette.border, lineWidth: 1)
            )
        }
        .buttonStyle(PressablePlainButtonStyle())
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
    let screenImage: CGImage?
    let cameraSession: AVCaptureSession
    let cameraStatus: CameraStatus
    let cameraStatusDetail: String
    let screenSourceLabel: String
    let isRecording: Bool
    @Binding var pipOffset: CGSize
    @Binding var pipScale: CGFloat
    let pipShape: PiPShape
    let canvasSizeChanged: (CGSize) -> Void
    let pipInteractionEnded: () -> Void
    let pipCornerChanged: (PiPCorner) -> Void
    let reconnect: () -> Void
    @State private var pipDragBaseOffset: CGSize?
    @State private var pipResizeBaseScale: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                switch layout {
                case .screenOnly:
                    screenLayer
                case .speakerCloseUp, .speakerFullBody:
                    cameraLayer
                case .screenWithCameraPictureInPicture:
                    screenLayer
                    pipCameraLayer
                        .position(pipPosition(in: proxy.size))
                        .gesture(pipDrag(in: proxy.size))
                case .cameraWithScreenPictureInPicture:
                    cameraLayer
                    pipScreenLayer
                        .position(pipPosition(in: proxy.size))
                        .gesture(pipDrag(in: proxy.size))
                case .sideBySide:
                    HStack(spacing: 0) {
                        screenLayer
                        cameraLayer
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Color.black)
            .onAppear {
                canvasSizeChanged(proxy.size)
            }
            .onChange(of: proxy.size) {
                canvasSizeChanged(proxy.size)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var screenLayer: some View {
        GeometryReader { proxy in
            ZStack {
                if let screenImage {
                    Image(decorative: screenImage, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)
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

    private var cameraLayer: some View {
        ZStack {
            if cameraStatus == .running {
                CameraPreviewView(session: cameraSession)
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
                CameraPreviewView(session: cameraSession)
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
                    .scaledToFit()
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
                Button(copy.reconnect) {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .tint(ConsolePalette.goldBright)
                Text(copy.runtimeText("正在导出视频"))
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
        }
        .padding(20)
        .frame(width: 430)
        .background(ConsolePalette.background)
    }

    private var resolutionLabel: String {
        guard progress.width > 0, progress.height > 0 else {
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
