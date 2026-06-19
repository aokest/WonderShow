import AppKit
import PresenterDirector
import UniformTypeIdentifiers

struct ProgramPreviewRequest: Identifiable {
    let id = UUID()
    let url: URL
}

struct ProgramVideoExportResult: Sendable {
    let url: URL
    let width: Int
    let height: Int
    let fileSize: Int64
    let settings: RecordingExportSettings
}

enum PresentationCommandControllerError: Error, LocalizedError {
    case noRecordingSession
    case rawTrackValidationFailed
    case exportCancelled

    var errorDescription: String? {
        switch self {
        case .noRecordingSession:
            return "尚未创建录制项目"
        case .rawTrackValidationFailed:
            return "原始轨道未通过导出检查"
        case .exportCancelled:
            return "用户取消导出"
        }
    }
}

@MainActor
final class PresentationCommandController: ObservableObject {
    @Published private(set) var accessibilityStatus: AccessibilityStatus = .unknown
    @Published private(set) var automationStatus: AutomationStatus = .unknown
    @Published private(set) var lastActionDescription = "尚未触发"
    @Published private(set) var lastDeliveryBackend = "未发送"
    @Published private(set) var frontmostApplication = "未检测"
    @Published private(set) var lastDeliveryDetail = "等待命令"
    @Published private(set) var isRecording = false
    @Published private(set) var isRehearsing = false
    @Published private(set) var lastRecordingSession: RecordingSessionRecord?
    @Published var programPreviewRequest: ProgramPreviewRequest?

    private let director = PresentationDirector()
    private let recordingSessionService = RecordingSessionService()
    private let projectStore = RecordingProjectStore()
    private var activeRecordingSession: RecordingSessionRecord?

    func refreshAccessibilityStatus() {
        accessibilityStatus = AXIsProcessTrusted() ? .granted : .missing
    }

    func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(options)
        accessibilityStatus = granted ? .granted : .missing
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func openAutomationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }

    func openScreenRecordingSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    func requestChromeAutomationPermission() {
        let result = runChromeAutomationScript("""
        tell application "Google Chrome"
            if (count of windows) is 0 then return "Chrome 已授权，但没有打开窗口"
            return "Chrome 自动化已授权"
        end tell
        """)
        _ = finishDelivery(result)
    }

    func reportDemoDeckOpenResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            lastActionDescription = "测试演示页已打开"
            lastDeliveryBackend = "本地测试页桥接"
            lastDeliveryDetail = "测试页地址：\(url.absoluteString)"
        case .failure(let error):
            lastActionDescription = "测试演示页打开失败"
            lastDeliveryBackend = "本地测试页桥接"
            lastDeliveryDetail = error.localizedDescription
        }
    }

    func reportCalibrationMode(_ message: String) {
        lastActionDescription = "快速校准已启用"
        lastDeliveryBackend = "手势识别"
        lastDeliveryDetail = message
    }

    func reportRecordingIssue(_ message: String) {
        lastActionDescription = "录制准备异常"
        lastDeliveryBackend = "录制工程"
        lastDeliveryDetail = message
    }

    func reportRecordingProgress(_ message: String) {
        lastActionDescription = "录制工程更新"
        lastDeliveryBackend = "录制工程"
        lastDeliveryDetail = message
    }

    func revealLastRecordingProject() {
        guard let session = lastRecordingSession else {
            reportRecordingIssue("尚未创建录制项目")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([session.url])
        lastActionDescription = "录制项目已定位"
        lastDeliveryBackend = "录制工程"
        lastDeliveryDetail = session.url.path
    }

    func openLastRecordingProject() {
        guard let session = lastRecordingSession else {
            reportRecordingIssue("尚未创建录制项目")
            return
        }
        NSWorkspace.shared.open(session.url)
        lastActionDescription = "录制项目已打开"
        lastDeliveryBackend = "录制工程"
        lastDeliveryDetail = session.url.path
    }

    func discardLastRecordingSession(deleteFiles: Bool) {
        let url = lastRecordingSession?.url
        lastRecordingSession = nil
        activeRecordingSession = nil
        if deleteFiles, let url {
            try? FileManager.default.removeItem(at: url)
        }
        lastActionDescription = "录制已丢弃"
        lastDeliveryBackend = "录制工程"
        lastDeliveryDetail = url?.path ?? "未保留项目"
    }

    func previewLastProgramExport() {
        guard let session = lastRecordingSession else {
            reportRecordingIssue("尚未创建录制项目")
            return
        }
        lastActionDescription = "正在打开预览"
        lastDeliveryBackend = "录制工程"
        lastDeliveryDetail = "准备合成视频预览"
        guard validateRawTracksForRendering(session: session) else {
            return
        }

        lastActionDescription = "正在生成预览"
        lastDeliveryBackend = "录制工程"
        lastDeliveryDetail = "正在从原始轨合成预览视频"

        Task { @MainActor in
            do {
                let outputURL = try await ProgramVideoRenderer().render(
                    session: session,
                    settings: .presentationDefault
                )
                guard self.lastRecordingSession?.url == session.url else {
                    return
                }
                openProgramPreview(outputURL)
            } catch {
                reportRecordingIssue("预览生成失败：\(error.localizedDescription)")
            }
        }
    }

    func updateLastRecordingPictureInPictureGeometry(_ geometry: ProgramPictureInPictureGeometry?) {
        guard let geometry,
              let session = lastRecordingSession else {
            return
        }

        updateRecordingSessionManifest(
            session: session,
            manifest: session.manifest.updatingPictureInPictureGeometry(geometry)
        )
    }

    func updateLastRecordingPictureInPictureKeyframes(_ keyframes: [RecordingPiPKeyframe]) {
        guard !keyframes.isEmpty,
              let session = lastRecordingSession else {
            return
        }

        updateRecordingSessionManifest(
            session: session,
            manifest: session.manifest.updatingPictureInPictureKeyframes(keyframes)
        )
    }

    func updateLastRecordingPresenterVideoEffects(_ effects: PresenterVideoEffects) {
        guard let session = lastRecordingSession else {
            return
        }

        updateRecordingSessionManifest(
            session: session,
            manifest: session.manifest.updatingPresenterVideoEffects(effects)
        )
    }

    func finalizeLastRecordingTimeline(
        durationMilliseconds: Int,
        pictureInPictureKeyframes keyframes: [RecordingPiPKeyframe],
        layoutKeyframes: [RecordingLayoutKeyframe] = []
    ) {
        guard let session = lastRecordingSession else {
            return
        }

        var manifest = session.manifest.updatingTimelineDuration(milliseconds: durationMilliseconds)
        if !layoutKeyframes.isEmpty {
            manifest = manifest.updatingLayoutKeyframes(layoutKeyframes)
        }
        if !keyframes.isEmpty {
            manifest = manifest.updatingPictureInPictureKeyframes(keyframes)
        }

        updateRecordingSessionManifest(session: session, manifest: manifest)
    }

    private func updateRecordingSessionManifest(
        session: RecordingSessionRecord,
        manifest updatedManifest: RecordingProjectManifest
    ) {
        guard updatedManifest != session.manifest else {
            return
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(updatedManifest).write(to: session.manifestURL, options: .atomic)
            let updatedSession = session.replacingManifest(updatedManifest)
            lastRecordingSession = updatedSession
            if activeRecordingSession?.url == session.url {
                activeRecordingSession = updatedSession
            }
            if FileManager.default.fileExists(atPath: session.programOutputURL.path) {
                try? FileManager.default.removeItem(at: session.programOutputURL)
            }
        } catch {
            reportRecordingIssue("画中画合成位置保存失败：\(error.localizedDescription)")
        }
    }

    #if DEBUG
    func replaceLastRecordingSessionForTesting(_ session: RecordingSessionRecord) {
        lastRecordingSession = session
        activeRecordingSession = nil
    }
    #endif

    private func openProgramPreview(_ url: URL) {
        programPreviewRequest = ProgramPreviewRequest(url: url)
        lastActionDescription = "合成视频预览已打开"
        lastDeliveryBackend = "录制工程"
        lastDeliveryDetail = url.path
    }

    func importRecordingProject() {
        let panel = NSOpenPanel()
        panel.title = "导入灵演项目"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json, .folder]
        panel.directoryURL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let session = try projectStore.load(from: url)
            lastRecordingSession = session
            activeRecordingSession = nil
            lastActionDescription = "录制项目已导入"
            lastDeliveryBackend = "录制工程"
            lastDeliveryDetail = session.url.path
        } catch {
            reportRecordingIssue("导入失败：\(error.localizedDescription)")
        }
    }

    func exportRecordingProject() {
        guard let session = lastRecordingSession else {
            reportRecordingIssue("尚未创建录制项目")
            return
        }

        let panel = NSSavePanel()
        panel.title = "导出灵演项目"
        panel.nameFieldStringValue = session.url.lastPathComponent
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try projectStore.copyProject(session: session, to: url)
            lastActionDescription = "录制项目已导出"
            lastDeliveryBackend = "录制工程"
            lastDeliveryDetail = url.path
        } catch {
            reportRecordingIssue("导出项目失败：\(error.localizedDescription)")
        }
    }

    func exportProgramVideo(
        settings: RecordingExportSettings = .presentationDefault,
        selectedRange: TimelineExportRange? = nil,
        onProgress: (@MainActor (ProgramVideoRenderProgress) -> Void)? = nil,
        completion: (@MainActor (Result<ProgramVideoExportResult, Error>) -> Void)? = nil
    ) {
        guard let session = lastRecordingSession else {
            reportRecordingIssue("尚未创建录制项目")
            completion?(.failure(PresentationCommandControllerError.noRecordingSession))
            return
        }
        guard validateRawTracksForRendering(session: session) else {
            completion?(.failure(PresentationCommandControllerError.rawTrackValidationFailed))
            return
        }

        let panel = NSSavePanel()
        panel.title = selectedRange == nil ? "导出合成视频" : "导出选区视频"
        panel.nameFieldStringValue = exportFileName(settings: settings, selectedRange: selectedRange)
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            completion?(.failure(PresentationCommandControllerError.exportCancelled))
            return
        }

        lastActionDescription = "合成视频导出中"
        lastDeliveryBackend = "录制工程"
        lastDeliveryDetail = "\(settings.userFacingSummary) → \(url.path)"
        let progressCache = ProgramVideoExportProgressCache()

        Task { @MainActor in
            do {
                let outputURL = try await ProgramVideoRenderer().render(
                    session: session,
                    settings: settings,
                    outputURL: url,
                    selectedRange: selectedRange,
                    progress: { progress in
                        progressCache.store(progress)
                        Task { @MainActor in
                            onProgress?(progress)
                        }
                    }
                )
                let fileSize = fileSize(at: outputURL)
                let finalProgress = progressCache.load()
                let finalWidth = finalProgress?.width ?? settings.exportWidthFallback
                let finalHeight = finalProgress?.height ?? settings.exportHeightFallback
                lastActionDescription = "合成视频已导出"
                lastDeliveryBackend = "录制工程"
                lastDeliveryDetail = outputURL.path
                completion?(
                    .success(
                        ProgramVideoExportResult(
                            url: outputURL,
                            width: finalWidth,
                            height: finalHeight,
                            fileSize: fileSize,
                            settings: settings
                        )
                    )
                )
            } catch {
                reportRecordingIssue("导出视频失败：\(error.localizedDescription)")
                completion?(.failure(error))
            }
        }
    }

    private func fileSize(at url: URL) -> Int64 {
        let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        return size?.int64Value ?? 0
    }

    private func validateRawTracksForRendering(session: RecordingSessionRecord) -> Bool {
        let requiredFiles: [(label: String, url: URL)] = [
            session.requiresSlidesScreenTrack ? ("PPT/屏幕原始轨", session.slidesScreenURL) : nil,
            session.requiresPresenterCameraTrack ? ("讲者摄像头原始轨", session.presenterCameraURL) : nil
        ].compactMap { $0 }

        for item in requiredFiles {
            guard FileManager.default.fileExists(atPath: item.url.path) else {
                reportRecordingIssue("\(item.label)不存在，无法合成：\(item.url.path)")
                return false
            }
            let size = (try? FileManager.default.attributesOfItem(atPath: item.url.path)[.size] as? NSNumber)?
                .int64Value ?? 0
            guard size > 0 else {
                reportRecordingIssue("\(item.label)为空，无法合成。请重新选择录制源后再录制。")
                return false
            }
        }

        return true
    }

    func handle(_ gesture: GestureIntent, target: PresentationTarget, swipeVelocity: Double? = nil) {
        refreshAccessibilityStatus()
        // #region debug-point C:handle-gesture
        debugReport(
            hypothesisId: "C",
            location: "PresentationCommandController.handle",
            message: "[DEBUG] controller received gesture",
            data: [
                "gesture": gesture.rawValue,
                "target": target.debugLabel
            ]
        )
        // #endregion
        let command = director.command(for: gesture, target: target)
        let result = sendCommand(command.presentationAction, target: target, swipeVelocity: swipeVelocity)
        lastActionDescription = result.userFacingAction(action: command.presentationAction)
        // #region debug-point C:handle-result
        debugReport(
            hypothesisId: "C",
            location: "PresentationCommandController.handle",
            message: "[DEBUG] controller handled gesture",
            data: [
                "gesture": gesture.rawValue,
                "action": command.presentationAction.label,
                "transport": command.transport.debugLabel,
                "backend": result.backend,
                "succeeded": result.succeeded
            ]
        )
        // #endregion
    }

    func setZoom(_ scale: Double, target: PresentationTarget) {
        refreshAccessibilityStatus()
        let boundedScale = min(3.0, max(0.30, scale))
        let result = sendCommand(.setZoom(boundedScale), target: target)
        lastActionDescription = result.succeeded
            ? "缩放到 \(Int((boundedScale * 100).rounded()))%"
            : "缩放已尝试发送"
    }

    func setPan(x: Double, y: Double, target: PresentationTarget) {
        refreshAccessibilityStatus()
        let boundedX = min(1, max(-1, x))
        let boundedY = min(1, max(-1, y))
        let result = sendCommand(.setPan(x: boundedX, y: boundedY), target: target)
        lastActionDescription = result.succeeded
            ? "移动视图"
            : "移动已尝试发送"
    }

    func testNextSlide(target: PresentationTarget) {
        refreshAccessibilityStatus()
        lastActionDescription = "3 秒后测试下一页：已开始倒计时"
        lastDeliveryBackend = "倒计时"
        lastDeliveryDetail = "等待 3 秒后发送下一页命令"
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            let result = sendCommand(.nextSlide, target: target)
            lastActionDescription = result.userFacingAction(action: .nextSlide, prefix: "测试")
        }
    }

    func sendDebugNextSlideNow(target: PresentationTarget) {
        refreshAccessibilityStatus()
        let result = sendCommand(.nextSlide, target: target)
        lastActionDescription = result.userFacingAction(action: .nextSlide, prefix: "测试")
    }

    func toggleRehearsal(target: PresentationTarget) {
        isRehearsing.toggle()
        let action: PresentationAction = isRehearsing ? .startPresentation : .exitPresentation
        let result = sendCommand(action, target: target)
        let state = isRehearsing ? "彩排已开始" : "彩排已结束"
        lastActionDescription = "\(state)：\(result.detail)"
    }

    func toggleRecording(
        scenario: RecordingScenario = .stagePresentation,
        cameraName: String = "未连接",
        mode: RecordingMode = .cameraAndScreen,
        layout: RecordingLayout = .screenWithCameraPictureInPicture(corner: .bottomRight),
        pictureInPictureGeometry: ProgramPictureInPictureGeometry? = nil,
        presenterVideoEffects: PresenterVideoEffects = .default
    ) {
        let result = sendCommand(
            .toggleRecording,
            target: .genericKeyboard,
            recordingScenario: scenario,
            cameraName: cameraName,
            recordingMode: mode,
            recordingLayout: layout,
            pictureInPictureGeometry: pictureInPictureGeometry,
            presenterVideoEffects: presenterVideoEffects
        )
        lastActionDescription = result.userFacingAction(action: .toggleRecording)
    }

    @discardableResult
    private func sendCommand(
        _ action: PresentationAction,
        target: PresentationTarget,
        swipeVelocity: Double? = nil,
        recordingScenario: RecordingScenario = .stagePresentation,
        cameraName: String = "未连接",
        recordingMode: RecordingMode = .cameraAndScreen,
        recordingLayout: RecordingLayout = .screenWithCameraPictureInPicture(corner: .bottomRight),
        pictureInPictureGeometry: ProgramPictureInPictureGeometry? = nil,
        presenterVideoEffects: PresenterVideoEffects = .default
    ) -> CommandDeliveryResult {
        updateFrontmostApplication()

        if action == .toggleRecording {
            return finishDelivery(
                toggleRecordingSession(
                    scenario: recordingScenario,
                    cameraName: cameraName,
                    mode: recordingMode,
                    layout: recordingLayout,
                    pictureInPictureGeometry: pictureInPictureGeometry,
                    presenterVideoEffects: presenterVideoEffects
                )
            )
        }

        if case .html = target {
            let localBridgeResult = sendLocalDemoBridgeCommand(action, swipeVelocity: swipeVelocity)
            if localBridgeResult.succeeded {
                return finishDelivery(localBridgeResult)
            }

            let htmlResult = sendHTMLCommand(action, swipeVelocity: swipeVelocity)
            if htmlResult.succeeded {
                return finishDelivery(htmlResult)
            }

            let fallback = sendKeyboardCommand(for: action, target: target)
            return finishDelivery(fallback.mergingFallbackReason(htmlResult.detail))
        }

        return finishDelivery(sendKeyboardCommand(for: action, target: target))
    }

    private func finishDelivery(_ result: CommandDeliveryResult) -> CommandDeliveryResult {
        lastDeliveryBackend = result.backend
        lastDeliveryDetail = result.detail
        // #region debug-point D:finish-delivery
        debugReport(
            hypothesisId: "D",
            location: "PresentationCommandController.finishDelivery",
            message: "[DEBUG] command delivery finished",
            data: [
                "backend": result.backend,
                "detail": result.detail,
                "succeeded": result.succeeded
            ]
        )
        // #endregion
        return result
    }

    private func updateFrontmostApplication() {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            frontmostApplication = "未检测"
            return
        }
        frontmostApplication = [app.localizedName, app.bundleIdentifier]
            .compactMap { $0 }
            .joined(separator: " / ")
    }

    private func sendKeyboardCommand(for action: PresentationAction, target: PresentationTarget) -> CommandDeliveryResult {
        switch action {
        case .nextSlide:
            return postKey(.rightArrow, target: target)
        case .previousSlide:
            return postKey(.leftArrow, target: target)
        case .zoomIn:
            return postKey(.equals, modifiers: .maskCommand, target: target)
        case .zoomOut:
            return postKey(.minus, modifiers: .maskCommand, target: target)
        case .setZoom(let scale):
            if scale >= 1 {
                return postKey(.equals, modifiers: .maskCommand, target: target)
            }
            return postKey(.minus, modifiers: .maskCommand, target: target)
        case .setPan:
            return .skipped(backend: "未实现", detail: "\(action.label) 暂未接入当前目标")
        case .startPresentation:
            return postKey(.returnKey, modifiers: .maskCommand, target: target)
        case .exitPresentation:
            return postKey(.escape, target: target)
        case .toggleAnnotation, .drawAnnotation, .clearAnnotations, .none:
            return .skipped(backend: "未实现", detail: "\(action.label) 暂未接入当前目标")
        case .toggleRecording:
            return toggleRecordingSession()
        }
    }

    private func toggleRecordingSession(
        scenario: RecordingScenario = .stagePresentation,
        cameraName: String = "未连接",
        mode: RecordingMode = .cameraAndScreen,
        layout: RecordingLayout = .screenWithCameraPictureInPicture(corner: .bottomRight),
        pictureInPictureGeometry: ProgramPictureInPictureGeometry? = nil,
        presenterVideoEffects: PresenterVideoEffects = .default
    ) -> CommandDeliveryResult {
        if isRecording {
            isRecording = false
            let detail = activeRecordingSession.map {
                "录制状态：关闭；工程已保留在 \($0.url.path)"
            } ?? "录制状态：关闭；当前版本未生成视频文件"
            activeRecordingSession = nil
            return .success(backend: "录制工程", detail: detail)
        }

        do {
            let session = try recordingSessionService.start(
                scenario: scenario,
                cameraName: cameraName,
                mode: mode,
                layout: layout,
                pictureInPictureGeometry: pictureInPictureGeometry,
                presenterVideoEffects: presenterVideoEffects
            )
            activeRecordingSession = session
            lastRecordingSession = session
            isRecording = true
            return .success(
                backend: "录制工程",
                detail: "录制状态：开启；已创建工程 \(session.manifestURL.path)，正在写入 \(session.manifest.project.rawTracks.count) 条原始轨"
            )
        } catch {
            isRecording = false
            activeRecordingSession = nil
            return .failed(backend: "录制工程", detail: "录制工程创建失败：\(error.localizedDescription)")
        }
    }

    private func exportFileName(settings: RecordingExportSettings, selectedRange: TimelineExportRange? = nil) -> String {
        let rangeSuffix: String
        if let selectedRange {
            rangeSuffix = "-selection-\(selectedRange.startMilliseconds)ms-\(selectedRange.endMilliseconds)ms"
        } else {
            rangeSuffix = ""
        }
        return "program\(rangeSuffix)-\(settings.fileNameSuffix).mp4"
    }

    private func sendHTMLCommand(_ action: PresentationAction, swipeVelocity: Double? = nil) -> CommandDeliveryResult {
        guard let javascript = action.htmlJavaScript(swipeVelocity: swipeVelocity) else {
            return .skipped(backend: "HTML 直连", detail: "\(action.label) 暂无 HTML 测试页命令")
        }
        let compactJavaScript = javascript
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let escapedJavaScript = compactJavaScript.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let source = """
        tell application "Google Chrome"
            if (count of windows) is 0 then error "Chrome 没有打开窗口"

            repeat with chromeWindow in windows
                repeat with tabIndex from 1 to (count of tabs of chromeWindow)
                    set chromeTab to tab tabIndex of chromeWindow
                    if ((URL of chromeTab contains "wondershow-demo.html") or (title of chromeTab contains "灵演 WonderShow")) then
                        set active tab index of chromeWindow to tabIndex
                        set index of chromeWindow to 1
                        tell chromeTab to execute javascript "\(escapedJavaScript)"
                        return "sent to wondershow-demo"
                    end if
                end repeat
            end repeat

            tell active tab of front window to execute javascript "\(escapedJavaScript)"
            return "sent to active tab"
        end tell
        """

        return runChromeAutomationScript(source, actionLabel: action.label)
    }

    private func sendLocalDemoBridgeCommand(_ action: PresentationAction, swipeVelocity: Double? = nil) -> CommandDeliveryResult {
        if case .setZoom(let scale) = action {
            do {
                try DemoControlServer.shared.enqueueZoom(scale: scale)
                // #region debug-point C:bridge-send-zoom
                debugReport(
                    hypothesisId: "C",
                    location: "PresentationCommandController.sendLocalDemoBridgeCommand",
                    message: "[DEBUG] local demo bridge queued zoom",
                    data: [
                        "action": action.label,
                        "scale": scale
                    ]
                )
                // #endregion
                return .success(
                    backend: "本地测试页桥接",
                    detail: "缩放到 \(Int((scale * 100).rounded()))% 已发送到 \(DemoControlServer.shared.demoDisplayURL.absoluteString)"
                )
            } catch {
                return .failed(backend: "本地测试页桥接", detail: "无法启动本地测试页桥接：\(error.localizedDescription)")
            }
        }

        if case .setPan(let x, let y) = action {
            do {
                try DemoControlServer.shared.enqueuePan(x: x, y: y)
                return .success(
                    backend: "本地测试页桥接",
                    detail: "视图移动已发送到 \(DemoControlServer.shared.demoDisplayURL.absoluteString)"
                )
            } catch {
                return .failed(backend: "本地测试页桥接", detail: "无法启动本地测试页桥接：\(error.localizedDescription)")
            }
        }

        guard let command = action.demoBridgeCommand else {
            return .skipped(backend: "本地测试页桥接", detail: "\(action.label) 暂无测试页命令")
        }

        if action == .nextSlide || action == .previousSlide, let swipeVelocity {
            do {
                try DemoControlServer.shared.enqueue(command, swipeVelocity: swipeVelocity)
                return .success(
                    backend: "本地测试页桥接",
                    detail: "\(action.label) 已发送到 \(DemoControlServer.shared.demoDisplayURL.absoluteString)"
                )
            } catch {
                return .failed(backend: "本地测试页桥接", detail: "无法启动本地测试页桥接：\(error.localizedDescription)")
            }
        }

        do {
            try DemoControlServer.shared.enqueue(command)
            // #region debug-point C:bridge-send-command
            debugReport(
                hypothesisId: "C",
                location: "PresentationCommandController.sendLocalDemoBridgeCommand",
                message: "[DEBUG] local demo bridge queued command",
                data: [
                    "action": action.label,
                    "command": command
                ]
            )
            // #endregion
            return .success(
                backend: "本地测试页桥接",
                detail: "\(action.label) 已发送到 \(DemoControlServer.shared.demoDisplayURL.absoluteString)"
            )
        } catch {
            return .failed(backend: "本地测试页桥接", detail: "无法启动本地测试页桥接：\(error.localizedDescription)")
        }
    }

    @discardableResult
    private func runChromeAutomationScript(_ source: String, actionLabel: String? = nil) -> CommandDeliveryResult {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            return .failed(backend: "Chrome HTML 直连", detail: "无法创建 AppleScript")
        }

        let output = script.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "\(error)"
            if message.localizedCaseInsensitiveContains("not authorized")
                || message.localizedCaseInsensitiveContains("not permitted")
                || message.localizedCaseInsensitiveContains("apple events") {
                automationStatus = .missing
                return .failed(
                    backend: "Chrome 自动化权限",
                    detail: "需要允许“灵演”控制 Google Chrome；请在弹窗点允许，或到 系统设置 > 隐私与安全性 > 自动化 中打开。原始错误：\(message)"
                )
            }
            return .failed(backend: "Chrome HTML 直连", detail: message)
        }

        automationStatus = .granted
        let result = output.stringValue ?? "已发送"
        if let actionLabel {
            return .success(backend: "Chrome HTML 直连", detail: "\(actionLabel) 已发送：\(result)")
        }
        return .success(backend: "Chrome 自动化权限", detail: result)
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
            "sessionId": "gesture-regression-loop",
            "runId": "post-fix",
            "hypothesisId": hypothesisId,
            "location": location,
            "msg": message,
            "data": data,
            "ts": Int(Date().timeIntervalSince1970 * 1_000)
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

    private func postKey(_ key: VirtualKey, modifiers: CGEventFlags = [], target: PresentationTarget) -> CommandDeliveryResult {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: key.rawValue, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: key.rawValue, keyDown: false)
        else {
            return .failed(backend: "通用键盘", detail: "无法创建键盘事件")
        }

        down.flags = modifiers
        up.flags = modifiers

        if let app = target.runningApplication ?? NSWorkspace.shared.frontmostApplication,
           let pid = Optional(app.processIdentifier) {
            down.postToPid(pid)
            up.postToPid(pid)
            let appName = [app.localizedName, app.bundleIdentifier].compactMap { $0 }.joined(separator: " / ")
            return .success(backend: "目标进程键盘", detail: "已发送到 \(appName)")
        }

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return .success(backend: "系统键盘兜底", detail: "已发送到系统事件队列")
    }
}

enum AccessibilityStatus: String {
    case unknown = "未检测"
    case granted = "已授权"
    case missing = "需要授权"
}

enum AutomationStatus: String {
    case unknown = "未检测"
    case granted = "已授权"
    case missing = "需要授权"
}

private enum VirtualKey: CGKeyCode {
    case leftArrow = 0x7B
    case rightArrow = 0x7C
    case minus = 0x1B
    case equals = 0x18
    case escape = 0x35
    case returnKey = 0x24
}

private final class ProgramVideoExportProgressCache: @unchecked Sendable {
    private let lock = NSLock()
    private var progress: ProgramVideoRenderProgress?

    func store(_ progress: ProgramVideoRenderProgress) {
        lock.lock()
        self.progress = progress
        lock.unlock()
    }

    func load() -> ProgramVideoRenderProgress? {
        lock.lock()
        defer { lock.unlock() }
        return progress
    }
}

private extension PresentationTarget {
    var debugLabel: String {
        switch self {
        case .powerPoint:
            return "powerPoint"
        case .wps:
            return "wps"
        case .keynote:
            return "keynote"
        case .word:
            return "word"
        case .excel:
            return "excel"
        case .pdfViewer:
            return "pdfViewer"
        case .genericKeyboard:
            return "genericKeyboard"
        case .html(let engine):
            switch engine {
            case .revealJS:
                return "html:revealJS"
            case .slidev:
                return "html:slidev"
            case .custom:
                return "html:custom"
            }
        }
    }

    var bundleIdentifiers: [String] {
        switch self {
        case .powerPoint:
            return ["com.microsoft.Powerpoint", "com.microsoft.PowerPoint"]
        case .wps:
            return ["com.kingsoft.wpsoffice.mac", "com.kingsoft.wpsoffice"]
        case .keynote:
            return ["com.apple.iWork.Keynote"]
        case .word:
            return ["com.microsoft.Word"]
        case .excel:
            return ["com.microsoft.Excel"]
        case .pdfViewer:
            return ["com.apple.Preview", "com.adobe.Reader"]
        case .genericKeyboard, .html:
            return []
        }
    }

    var runningApplication: NSRunningApplication? {
        for bundleIdentifier in bundleIdentifiers {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
                return app
            }
        }
        return nil
    }
}

private extension RecordingExportSettings {
    var fileNameSuffix: String {
        [
            resolution.fileNameToken,
            "\(frameRate.rawValue)fps",
            quality.fileNameToken,
            codec.rawValue
        ].joined(separator: "-")
    }

    var userFacingSummary: String {
        "\(resolution.label) / \(frameRate.rawValue)fps / \(quality.label) / \(codec.label)"
    }

    var exportWidthFallback: Int {
        resolution.pixelSize?.width ?? 0
    }

    var exportHeightFallback: Int {
        resolution.pixelSize?.height ?? 0
    }
}

private extension RecordingExportResolution {
    var label: String {
        switch self {
        case .source:
            return "源分辨率"
        case .hd1080:
            return "1080p"
        case .qhd1440:
            return "1440p"
        case .uhd4k:
            return "4K"
        }
    }

    var fileNameToken: String {
        switch self {
        case .source:
            return "source"
        case .hd1080:
            return "1080p"
        case .qhd1440:
            return "1440p"
        case .uhd4k:
            return "4k"
        }
    }
}

private extension RecordingExportQuality {
    var label: String {
        switch self {
        case .standard:
            return "标准"
        case .high:
            return "高"
        case .archival:
            return "归档"
        }
    }

    var fileNameToken: String {
        rawValue
    }
}

private extension RecordingExportCodec {
    var label: String {
        switch self {
        case .h264:
            return "H.264"
        case .hevc:
            return "HEVC"
        }
    }
}

private extension CommandTransport {
    var debugLabel: String {
        switch self {
        case .keyboardShortcut:
            return "keyboardShortcut"
        case .accessibilityAutomation:
            return "accessibilityAutomation"
        case .htmlBridge:
            return "htmlBridge"
        case .internalOverlay:
            return "internalOverlay"
        }
    }
}

private extension PresentationAction {
    var label: String {
        switch self {
        case .nextSlide:
            return "下一页"
        case .previousSlide:
            return "上一页"
        case .zoomIn:
            return "放大演示"
        case .zoomOut:
            return "缩小演示"
        case .setZoom(let scale):
            return "缩放到 \(Int((scale * 100).rounded()))%"
        case .setPan:
            return "移动视图"
        case .startPresentation:
            return "开始播放"
        case .exitPresentation:
            return "退出播放"
        case .toggleRecording:
            return "切换录制"
        case .toggleAnnotation:
            return "开关标注"
        case .drawAnnotation:
            return "绘制标注"
        case .clearAnnotations:
            return "清除标注"
        case .none:
            return "无动作"
        }
    }

    func htmlJavaScript(swipeVelocity: Double? = nil) -> String? {
        switch self {
        case .nextSlide:
            let velocity = swipeVelocity ?? 0
            return """
            (() => {
              if (typeof window.wonderShowCommand === 'function') {
                window.wonderShowCommand('next', { velocity: \(velocity) });
                return 'next';
              }
              const slides = Array.from(document.querySelectorAll('.slide'));
              const current = Math.max(0, slides.findIndex(slide => slide.classList.contains('active')));
              const next = Math.min(slides.length - 1, current + 1);
              slides.forEach((slide, index) => slide.classList.toggle('active', index === next));
              return `${next + 1} / ${slides.length}`;
            })()
            """
        case .previousSlide:
            let velocity = swipeVelocity ?? 0
            return """
            (() => {
              if (typeof window.wonderShowCommand === 'function') {
                window.wonderShowCommand('previous', { velocity: \(velocity) });
                return 'previous';
              }
              const slides = Array.from(document.querySelectorAll('.slide'));
              const current = Math.max(0, slides.findIndex(slide => slide.classList.contains('active')));
              const next = Math.max(0, current - 1);
              slides.forEach((slide, index) => slide.classList.toggle('active', index === next));
              return `${next + 1} / ${slides.length}`;
            })()
            """
        case .zoomIn:
            return """
            (() => {
              if (typeof window.wonderShowCommand === 'function') {
                window.wonderShowCommand('zoomIn', null);
                return 'zoomIn';
              }
              const stage = document.getElementById('stage');
              const current = Number(stage.dataset.wonderShowZoom || '1');
              const next = Math.min(3.0, current + 0.12);
              stage.dataset.wonderShowZoom = String(next);
              stage.style.transform = `scale(${next})`;
              return `zoom ${next.toFixed(2)}`;
            })()
            """
        case .zoomOut:
            return """
            (() => {
              if (typeof window.wonderShowCommand === 'function') {
                window.wonderShowCommand('zoomOut', null);
                return 'zoomOut';
              }
              const stage = document.getElementById('stage');
              const current = Number(stage.dataset.wonderShowZoom || '1');
              const next = Math.max(0.30, current - 0.12);
              stage.dataset.wonderShowZoom = String(next);
              stage.style.transform = `scale(${next})`;
              return `zoom ${next.toFixed(2)}`;
            })()
            """
        case .setZoom(let scale):
            return """
            (() => {
              if (typeof window.wonderShowCommand === 'function') {
                window.wonderShowCommand('setZoom', \(scale));
                return 'setZoom';
              }
              const stage = document.getElementById('stage');
              const next = Math.max(0.30, Math.min(3.0, \(scale)));
              stage.dataset.wonderShowZoom = String(next);
              stage.style.transform = `scale(${next})`;
              return `zoom ${next.toFixed(2)}`;
            })()
            """
        case .setPan(let x, let y):
            return """
            (() => {
              if (typeof window.wonderShowCommand !== 'function') return 'no wondershow command';
              window.wonderShowCommand('setPan', JSON.stringify({x: \(x), y: \(y)}));
              return 'pan';
            })()
            """
        case .startPresentation:
            return "document.body.classList.add('presenting'); 'presenting'"
        case .exitPresentation:
            return "document.body.classList.remove('presenting'); 'exited'"
        case .toggleAnnotation:
            return "document.body.classList.toggle('annotating'); 'annotation toggled'"
        case .clearAnnotations:
            return "document.querySelectorAll('[data-wondershow-annotation]').forEach(node => node.remove()); 'annotations cleared'"
        case .drawAnnotation, .toggleRecording, .none:
            return nil
        }
    }
}

private struct CommandDeliveryResult {
    let succeeded: Bool
    let backend: String
    let detail: String

    static func success(backend: String, detail: String) -> CommandDeliveryResult {
        CommandDeliveryResult(succeeded: true, backend: backend, detail: detail)
    }

    static func failed(backend: String, detail: String) -> CommandDeliveryResult {
        CommandDeliveryResult(succeeded: false, backend: backend, detail: detail)
    }

    static func skipped(backend: String, detail: String) -> CommandDeliveryResult {
        CommandDeliveryResult(succeeded: false, backend: backend, detail: detail)
    }

    func mergingFallbackReason(_ reason: String) -> CommandDeliveryResult {
        CommandDeliveryResult(
            succeeded: succeeded,
            backend: "\(backend)（HTML 失败后兜底）",
            detail: "\(detail)；HTML 直连未生效：\(reason)"
        )
    }

    func userFacingAction(action: PresentationAction, prefix: String? = nil) -> String {
        let actionText = [prefix, action.label].compactMap { $0 }.joined()
        return succeeded ? actionText : "\(actionText)已尝试发送"
    }
}
