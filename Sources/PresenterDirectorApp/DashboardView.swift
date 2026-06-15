import PresenterDirector
import SwiftUI

struct DashboardView: View {
    private static let appVersion = "v0.6.0"

    @StateObject private var camera = CameraPreviewService()
    @StateObject private var commandController = PresentationCommandController()
    @State private var target: PresentationTarget = .powerPoint
    @State private var mode: RecordingMode = .cameraAndScreen
    @State private var layout: RecordingLayout = .screenWithCameraPictureInPicture(corner: .bottomRight)
    @State private var calibrationFlow: CalibrationFlow?
    @State private var showsDiagnostics = false

    private let copy = AppLocalization().copy()
    private let director = PresentationDirector()
    private let pipelineFactory = RecordingPipelineFactory()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.08, blue: 0.13),
                    Color(red: 0.07, green: 0.11, blue: 0.17),
                    Color(red: 0.03, green: 0.05, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    headlineBar
                    statusStrip
                    mainWorkspace
                }
                .padding(24)
            }
        }
        .onAppear {
            commandController.refreshAccessibilityStatus()
            updateGestureHandler()
            camera.start()
        }
        .onChange(of: target) {
            updateGestureHandler()
        }
        .onDisappear {
            camera.stop()
        }
    }

    /// Wires gesture callbacks to the current presentation target.
    /// - Note: Captures the active target so command routing stays stable during a gesture.
    private func updateGestureHandler() {
        let currentTarget = target
        camera.onGestureRecognized = { gesture in
            commandController.handle(gesture, target: currentTarget)
        }
        camera.onZoomChanged = { scale in
            commandController.setZoom(scale, target: currentTarget)
        }
        camera.onPanChanged = { x, y in
            commandController.setPan(x: x, y: y, target: currentTarget)
        }
    }

    private var headlineBar: some View {
        HStack(alignment: .center, spacing: 18) {
            Image("AppIcon", bundle: .module)
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(copy.productName)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(Self.appVersion)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
                Text("导演台模式：把预览、演示控制和手势工作区放到同一个主流程里")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
            }

            Spacer()

            HStack(spacing: 12) {
                Button(commandController.isRehearsing ? "结束彩排" : copy.rehearsalButton) {
                    commandController.toggleRehearsal(target: target)
                }
                .buttonStyle(ActionButtonStyle(color: Color(red: 0.16, green: 0.56, blue: 0.70)))

                Button(commandController.isRecording ? "停止录制" : copy.recordButton) {
                    commandController.toggleRecording()
                }
                .buttonStyle(ActionButtonStyle(color: Color(red: 0.82, green: 0.24, blue: 0.22)))
            }
        }
        .panelSurface(padding: 20, backgroundOpacity: 0.12)
    }

    private var statusStrip: some View {
        HStack(spacing: 14) {
            SummaryPill(icon: "video.fill", title: "摄像头", value: camera.status.label, accent: Color(red: 0.34, green: 0.81, blue: 0.89))
            SummaryPill(icon: "hand.raised.fill", title: "手势", value: camera.gestureSessionLabel, accent: Color(red: 0.58, green: 0.86, blue: 0.58))
            SummaryPill(icon: "rectangle.3.group.fill", title: "演示目标", value: target.label, accent: Color(red: 0.95, green: 0.72, blue: 0.33))
            SummaryPill(icon: "record.circle.fill", title: "录制", value: commandController.isRecording ? "进行中" : "待机", accent: Color(red: 0.92, green: 0.37, blue: 0.36))
        }
    }

    private var mainWorkspace: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 18) {
                previewWorkspace
                insightsPanel
            }

            VStack(spacing: 18) {
                quickStartPanel
                presentationPanel
                gesturePanel
                devicePanel
                diagnosticsPanel
            }
            .frame(width: 390)
        }
    }

    private var previewWorkspace: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(copy.programPreview)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                    Text("当前设备：\(camera.activeDeviceName)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                Spacer()
                LiveBadge(isOn: camera.status == .running)
            }

            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.black.opacity(0.92))

                CameraPreviewView(session: camera.session)
                    .clipShape(RoundedRectangle(cornerRadius: 24))

                HandPointOverlay(
                    points: camera.latestHandPoints,
                    isCalibrating: calibrationFlow != nil,
                    isZoneActive: camera.gestureZoneLabel == "热区已进入"
                )
                .clipShape(RoundedRectangle(cornerRadius: 24))

                if camera.status != .running {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 46, weight: .medium))
                        Text(copy.cameraNotConnected)
                            .font(.system(size: 20, weight: .bold))
                        Text(camera.status.detail)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.74))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 420)
                        Button("重新连接") {
                            camera.start()
                        }
                        .buttonStyle(ActionButtonStyle(color: Color(red: 0.16, green: 0.56, blue: 0.70)))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SmallOverlayTag(icon: "scope", text: camera.gestureZoneLabel)
                    SmallOverlayTag(icon: "sparkles.rectangle.stack", text: camera.gestureGuidance)
                    SmallOverlayTag(icon: "command", text: "最近动作：\(commandController.lastActionDescription)")
                }
                .padding(18)
            }
            .aspectRatio(16 / 9, contentMode: .fit)
        }
        .panelSurface(padding: 20, backgroundOpacity: 0.10)
    }

    private var insightsPanel: some View {
        let pipeline = pipelineFactory.makePipeline(
            mode: mode,
            camera: .external(name: camera.activeDeviceName),
            screen: mode == .cameraAndScreen ? .mainDisplay : nil,
            layout: layout
        )

        return VStack(alignment: .leading, spacing: 14) {
            Text("当前导演摘要")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                InsightTile(title: "命令通道", value: commandSummary, accent: Color(red: 0.36, green: 0.74, blue: 0.93))
                InsightTile(title: "标注方式", value: annotationSummary, accent: Color(red: 0.49, green: 0.84, blue: 0.59))
                InsightTile(title: "输出素材", value: pipeline.outputs.map(\.label).joined(separator: "、"), accent: Color(red: 0.97, green: 0.72, blue: 0.34))
                InsightTile(title: "最终布局", value: pipeline.composition.label, accent: Color(red: 0.88, green: 0.45, blue: 0.48))
            }
        }
        .panelSurface(padding: 20, backgroundOpacity: 0.08)
    }

    private var quickStartPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            SidebarTitle(icon: "bolt.fill", text: "快速开始")

            DetailLine(label: "彩排状态", value: commandController.isRehearsing ? "进行中" : "未开始")
            DetailLine(label: "录制状态", value: commandController.isRecording ? "进行中" : "未开始")
            DetailLine(label: "当前设备", value: camera.activeDeviceName)
            DetailLine(label: "当前手型", value: camera.detectedHandShapes)
            DetailLine(label: "缩放比例", value: "\(Int((camera.zoomScale * 100).rounded()))%")

            HStack(spacing: 10) {
                Button("刷新设备") {
                    camera.refreshDevicesAndRestart()
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("3 秒后测试翻页") {
                    commandController.testNextSlide(target: target)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .sidebarCard()
    }

    private var presentationPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            SidebarTitle(icon: "play.rectangle.on.rectangle", text: "演示控制")

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel("演示软件")
                Picker("", selection: $target) {
                    Text("PowerPoint").tag(PresentationTarget.powerPoint)
                    Text("WPS").tag(PresentationTarget.wps)
                    Text("Keynote").tag(PresentationTarget.keynote)
                    Text("Word").tag(PresentationTarget.word)
                    Text("Excel").tag(PresentationTarget.excel)
                    Text("PDF").tag(PresentationTarget.pdfViewer)
                    Text("HTML").tag(PresentationTarget.html(engine: .revealJS))
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .menuField()
            }

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel("录制模式")
                Picker("", selection: $mode) {
                    Text("只录人像").tag(RecordingMode.cameraOnly)
                    Text("人像 + 屏幕").tag(RecordingMode.cameraAndScreen)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .environment(\.colorScheme, .dark)
            }

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel("画面布局")
                Picker("", selection: $layout) {
                    Text("人物特写").tag(RecordingLayout.speakerCloseUp)
                    Text("画中画").tag(RecordingLayout.screenWithCameraPictureInPicture(corner: .bottomRight))
                    Text("左右分屏").tag(RecordingLayout.sideBySide)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .menuField()
            }

            Button("打开测试演示页") {
                target = .html(engine: .custom)
                commandController.reportDemoDeckOpenResult(DemoDeckLauncher.openDemoDeck())
            }
            .buttonStyle(ActionButtonStyle(color: Color(red: 0.20, green: 0.45, blue: 0.70)))

            Text("HTML 测试页优先使用本地桥接；PowerPoint、WPS、Keynote 会通过目标窗口快捷键发送命令。")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.66))
        }
        .sidebarCard()
    }

    private var gesturePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            SidebarTitle(icon: "hand.raised.fill", text: "手势工作区")

            HStack(spacing: 12) {
                FieldLabel("启用手势控制")
                Spacer(minLength: 12)
                Toggle("", isOn: $camera.gestureControlEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: camera.gestureControlEnabled) {
                        commandController.refreshAccessibilityStatus()
                    }
            }
            .controlRowSurface()

            DetailLine(label: "识别状态", value: camera.gestureStatus.rawValue)
            DetailLine(label: "当前会话", value: camera.gestureSessionLabel)
            DetailLine(label: "引擎", value: camera.gestureEngineLabel)
            DetailLine(label: "热区", value: camera.gestureZoneLabel)
            DetailLine(label: "引导", value: camera.gestureGuidance)
            DetailLine(label: "个人校准", value: camera.calibrationStatus)
            DetailLine(label: "最近动作", value: commandController.lastActionDescription)

            VStack(spacing: 10) {
                Button {
                    calibrationFlow = CalibrationFlow()
                    camera.gestureControlEnabled = true
                    camera.gestureCalibrationProfile = .easyTesting
                } label: {
                    Label("个人手势校准", systemImage: "person.crop.circle.badge.checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ActionButtonStyle(color: Color(red: 0.18, green: 0.60, blue: 0.55)))

                Button {
                    camera.gestureCalibrationProfile = .easyTesting
                    commandController.reportCalibrationMode("易触发测试模式已启用：更适合近距离验证流程，不建议正式演讲使用。")
                } label: {
                    Label("切换易触发测试模式", systemImage: "speedometer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    camera.clearPersonalizedCalibration()
                    commandController.reportCalibrationMode("已清空旧校准样本，当前回到实时识别。")
                } label: {
                    Label("清空旧校准", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            VStack(spacing: 8) {
                GestureHintRow(icon: "hand.raised", gesture: "开掌停留", action: "解锁手势窗口")
                GestureHintRow(icon: "arrow.left", gesture: "左挥", action: "上一页")
                GestureHintRow(icon: "arrow.right", gesture: "右挥", action: "下一页")
                GestureHintRow(icon: "arrow.up.left.and.arrow.down.right", gesture: "双手分开", action: "放大")
                GestureHintRow(icon: "arrow.down.right.and.arrow.up.left", gesture: "双手合拢", action: "缩小")
            }
        }
        .sidebarCard()
        .sheet(item: $calibrationFlow) { flow in
            calibrationSheet(flow)
        }
    }

    private var devicePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            SidebarTitle(icon: "camera.fill", text: "设备与投递")

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel("输入设备")
                Picker("", selection: Binding(
                    get: { camera.selectedDeviceID },
                    set: { camera.selectDevice(id: $0) }
                )) {
                    ForEach(camera.availableDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .menuField()
            }

            DetailLine(label: "连接状态", value: camera.status.detail)
            DetailLine(label: "设备说明", value: selectedDeviceDetail)
            DetailLine(label: "已发现输入", value: discoveredDeviceSummary)
            DetailLine(label: "接入方式", value: "AVFoundation / UVC")
            DetailLine(label: "前台应用", value: commandController.frontmostApplication)
            DetailLine(label: "投递通道", value: commandController.lastDeliveryBackend)
            DetailLine(label: "投递结果", value: commandController.lastDeliveryDetail)
        }
        .sidebarCard()
    }

    private var diagnosticsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SidebarTitle(icon: "stethoscope", text: "高级诊断")

            DisclosureGroup("查看权限与自动化诊断", isExpanded: $showsDiagnostics) {
                VStack(alignment: .leading, spacing: 10) {
                    DetailLine(label: "辅助功能", value: commandController.accessibilityStatus.rawValue)
                    DetailLine(label: "Chrome 自动化", value: commandController.automationStatus.rawValue)
                    DetailLine(label: "扫描明细", value: camera.deviceScanSummary)
                    DetailLine(label: "兼容示例", value: supportedDeviceSummary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                        Button("辅助功能设置") {
                            commandController.openAccessibilitySettings()
                        }
                        Button("请求辅助功能") {
                            commandController.requestAccessibilityPermission()
                        }
                        Button("Chrome 授权") {
                            commandController.requestChromeAutomationPermission()
                        }
                        Button("自动化设置") {
                            commandController.openAutomationSettings()
                        }
                        Button("刷新状态") {
                            commandController.refreshAccessibilityStatus()
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.top, 8)
            }
            .tint(.white)
        }
        .sidebarCard()
    }

    /// Builds the personalized calibration sheet.
    /// - Parameter flow: Current calibration progress state.
    /// - Returns: The calibration modal content.
    private func calibrationSheet(_ flow: CalibrationFlow) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            SidebarTitle(icon: "hand.point.up.left.fill", text: "个人手势校准")
            Text(flow.currentGesture.instruction)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            Text("第 \(flow.currentSample) / 3 次。点击开始后看着摄像头完成动作，系统会自动判断成功并进入下一次。")
                .foregroundStyle(Color.white.opacity(0.72))

            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.black)
                CameraPreviewView(session: camera.session)
                HandPointOverlay(points: camera.latestHandPoints, isCalibrating: true, isZoneActive: true)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 18))

            ProgressView(value: camera.calibrationProgress)
                .progressViewStyle(.linear)
                .tint(Color(red: 0.40, green: 0.78, blue: 0.88))

            Text(camera.calibrationStatus)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14))

            HStack(spacing: 12) {
                Button("开始自动采样") {
                    runAutomaticCalibrationSample(flow)
                }
                .buttonStyle(ActionButtonStyle(color: Color(red: 0.16, green: 0.56, blue: 0.70)))

                Button("结束") {
                    calibrationFlow = nil
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            DetailLine(label: "当前手型", value: camera.detectedHandShapes)
        }
        .padding(24)
        .frame(width: 560)
        .background(Color(red: 0.07, green: 0.10, blue: 0.15))
    }

    /// Runs timed sampling and advances the personalized calibration flow on success.
    /// - Parameter flow: Current calibration flow state.
    private func runAutomaticCalibrationSample(_ flow: CalibrationFlow) {
        Task { @MainActor in
            let success = await camera.autoCaptureCalibration(
                intent: flow.currentGesture.intent,
                sampleIndex: flow.currentSample
            )
            guard success else {
                commandController.reportCalibrationMode("采样不足，请保持手在画面中并重做这次动作")
                return
            }

            if calibrationFlow?.isLastSample == true {
                commandController.reportCalibrationMode("个人手势校准完成，后续识别会优先使用你的动作模板")
                calibrationFlow = nil
            } else {
                calibrationFlow?.advance()
            }
        }
    }

    private var commandSummary: String {
        director.command(for: .swipeLeft, target: target).transport.label
    }

    private var annotationSummary: String {
        director.annotationStrategy(for: target).label
    }

    private var supportedDeviceSummary: String {
        "内置、DJI、Insta360、采集卡、网络摄像头"
    }

    private var discoveredDeviceSummary: String {
        let count = max(0, camera.availableDevices.count - 1)
        return count == 0 ? "未发现可采集摄像头" : "\(count) 个输入设备"
    }

    private var selectedDeviceDetail: String {
        camera.availableDevices.first(where: { $0.id == camera.selectedDeviceID })?.detail ?? "设备列表待刷新"
    }
}

private struct HandPointOverlay: View {
    let points: [HandPoint]
    let isCalibrating: Bool
    let isZoneActive: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isCalibrating ? Color.yellow.opacity(0.85) : zoneColor.opacity(0.82),
                        style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                    )
                    .frame(width: proxy.size.width * 0.64, height: proxy.size.height * 0.62)

                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(pointColor(point.shape))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 1)
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
        isZoneActive ? Color(red: 0.38, green: 0.85, blue: 0.78) : Color.white.opacity(0.56)
    }

    private func pointColor(_ shape: HandShape) -> Color {
        switch shape {
        case .fingerGun:
            return Color.green
        case .lShape:
            return Color.yellow
        case .natural:
            return Color.cyan
        case .openPalm:
            return Color(red: 0.53, green: 0.83, blue: 0.99)
        case .fist:
            return Color(red: 0.98, green: 0.57, blue: 0.42)
        case .unknown:
            return Color.orange
        }
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

        var instruction: String {
            switch self {
            case .swipeLeft:
                return "做你的“下一页”左挥手势"
            case .swipeRight:
                return "做你的“上一页”右挥手势"
            case .zoomIn:
                return "双手八字分开，作为放大"
            case .zoomOut:
                return "双手八字合拢，作为缩小"
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

    mutating func advance() {
        if currentSample < 3 {
            currentSample += 1
            return
        }
        currentSample = 1
        stepIndex = min(stepIndex + 1, GestureStep.allCases.count - 1)
    }
}

private struct SidebarTitle: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
    }
}

private struct FieldLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color(red: 0.80, green: 0.86, blue: 0.95))
    }
}

private struct SummaryPill: View {
    let icon: String
    let title: String
    let value: String
    let accent: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 34, height: 34)
                .background(accent.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.64))
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct InsightTile: View {
    let title: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.64))
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle()
                .fill(accent)
                .frame(height: 4)
                .clipShape(Capsule())
        }
        .padding(16)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct DetailLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(Color.white.opacity(0.62))
            Spacer(minLength: 12)
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.white)
        }
        .font(.system(size: 13))
    }
}

private struct GestureHintRow: View {
    let icon: String
    let gesture: String
    let action: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 9))
            Text(gesture)
                .fontWeight(.medium)
                .foregroundStyle(.white)
            Spacer()
            Text(action)
                .foregroundStyle(Color.white.opacity(0.66))
        }
        .font(.system(size: 13))
    }
}

private struct SmallOverlayTag: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(text)
                .lineLimit(1)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.54))
        .clipShape(Capsule())
    }
}

private struct LiveBadge: View {
    let isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isOn ? Color.green : Color.orange)
                .frame(width: 10, height: 10)
            Text(isOn ? "实时预览" : "等待画面")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.10))
        .clipShape(Capsule())
    }
}

private struct ActionButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(
                LinearGradient(
                    colors: [
                        color.opacity(configuration.isPressed ? 0.80 : 0.96),
                        color.opacity(configuration.isPressed ? 0.66 : 0.84)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: color.opacity(0.24), radius: 12, x: 0, y: 8)
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.15, green: 0.20, blue: 0.29).opacity(configuration.isPressed ? 0.90 : 1),
                        Color(red: 0.11, green: 0.15, blue: 0.22).opacity(configuration.isPressed ? 0.82 : 0.96)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.14), radius: 8, x: 0, y: 4)
    }
}

private extension View {
    func menuField() -> some View {
        self
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .tint(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.13, green: 0.18, blue: 0.27),
                        Color(red: 0.10, green: 0.14, blue: 0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .environment(\.colorScheme, .dark)
    }

    func controlRowSurface() -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.13, green: 0.18, blue: 0.27),
                        Color(red: 0.10, green: 0.14, blue: 0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }

    func panelSurface(padding: CGFloat = 18, backgroundOpacity: Double = 0.10) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(backgroundOpacity))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 32, x: 0, y: 18)
    }

    func sidebarCard() -> some View {
        self
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.10, green: 0.15, blue: 0.23).opacity(0.92),
                        Color(red: 0.07, green: 0.10, blue: 0.17).opacity(0.90)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 10)
    }
}

private extension PresentationTarget {
    var label: String {
        switch self {
        case .powerPoint:
            return "PowerPoint"
        case .wps:
            return "WPS"
        case .keynote:
            return "Keynote"
        case .word:
            return "Word"
        case .excel:
            return "Excel"
        case .pdfViewer:
            return "PDF"
        case .genericKeyboard:
            return "通用"
        case .html:
            return "HTML"
        }
    }
}

private extension CommandTransport {
    var label: String {
        switch self {
        case .keyboardShortcut:
            return "键盘事件"
        case .accessibilityAutomation:
            return "辅助控制"
        case .htmlBridge:
            return "HTML 桥接"
        case .internalOverlay:
            return "应用浮层"
        }
    }
}

private extension AnnotationStrategy {
    var label: String {
        switch self {
        case .systemOverlay:
            return "系统浮层"
        case .inSlideCanvas:
            return "页面画布"
        }
    }
}

private extension RecordingOutput {
    var label: String {
        switch self {
        case .cameraArchive:
            return "人像"
        case .screenArchive:
            return "屏幕"
        case .programRecording:
            return "成片"
        }
    }
}

private extension ProgramComposition {
    var label: String {
        switch self {
        case .singleCamera:
            return "人物特写"
        case .pictureInPicture:
            return "画中画"
        case .sideBySide:
            return "左右分屏"
        }
    }
}
