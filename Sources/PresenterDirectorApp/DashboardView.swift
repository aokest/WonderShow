import Combine
import PresenterDirector
import SwiftUI

struct DashboardView: View {
    private static let appVersion = "v0.6.0"

    @StateObject private var camera = CameraPreviewService()
    @StateObject private var commandController = PresentationCommandController()
    @State private var target: PresentationTarget = .keynote
    @State private var mode: RecordingMode = .cameraAndScreen
    @State private var layout: RecordingLayout = .screenWithCameraPictureInPicture(corner: .bottomRight)
    @State private var calibrationFlow: CalibrationFlow?
    @State private var showsDiagnostics = false
    @State private var showsAboutCard = false
    @State private var showsGestureCheatsheet = false
    @State private var displayLanguage: DisplayLanguageTab = .simplified
    @State private var quickStartCollapsed = false
    @State private var presentationCollapsed = false
    @State private var gestureCollapsed = false
    @State private var devicesCollapsed = false
    @State private var elapsedSeconds = 0

    private var copy: AppCopy {
        let appLanguage: AppLanguage
        switch displayLanguage {
        case .simplified:
            appLanguage = .zhHans
        case .traditional:
            appLanguage = .zhHant
        case .english:
            appLanguage = .en
        }
        return AppLocalization().copy(for: appLanguage)
    }
    private let director = PresentationDirector()
    private let pipelineFactory = RecordingPipelineFactory()
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
        .onAppear {
            commandController.refreshAccessibilityStatus()
            updateGestureHandler()
            camera.start()
        }
        .onChange(of: target) {
            updateGestureHandler()
        }
        .onChange(of: commandController.isRecording) {
            if commandController.isRecording {
                elapsedSeconds = 0
            }
        }
        .onReceive(recordingClock) { _ in
            guard commandController.isRecording else {
                return
            }
            elapsedSeconds += 1
        }
        .onDisappear {
            camera.stop()
        }
    }

    /// 将当前手势和缩放回调绑定到选中的演示目标，避免目标切换时投递错位。
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
                    Text("WONDERSHOW")
                        .font(.system(size: 13, weight: .bold, design: .serif))
                        .foregroundStyle(ConsolePalette.textPrimary)
                        .tracking(2.2)
                    Text("STUDIO")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(ConsolePalette.textTertiary)
                        .tracking(2.4)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                ConsoleStatusPill(
                    icon: "camera",
                    title: "摄像头",
                    value: camera.status == .running ? "已连接" : camera.status.label,
                    isActive: camera.status == .running,
                    isRecording: false
                )
                ConsoleStatusPill(
                    icon: "hand.raised",
                    title: "手势",
                    value: camera.gestureControlEnabled ? "识别中" : "待命",
                    isActive: camera.gestureControlEnabled,
                    isRecording: false
                )
                ConsoleStatusPill(
                    icon: "rectangle.on.rectangle",
                    title: "目标",
                    value: target.label,
                    isActive: true,
                    isRecording: false
                )
                ConsoleStatusPill(
                    icon: "record.circle",
                    title: "录制",
                    value: commandController.isRecording ? "进行中" : "就绪",
                    isActive: commandController.isRecording,
                    isRecording: true
                )
            }

            Spacer(minLength: 12)

            HStack(spacing: 12) {
                HStack(spacing: 0) {
                    ForEach(DisplayLanguageTab.allCases) { tab in
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

                Button(commandController.isRehearsing ? "结束彩排" : copy.rehearsalButton) {
                    commandController.toggleRehearsal(target: target)
                }
                .buttonStyle(ConsoleGradientButtonStyle(variant: .gold, expands: false))

                Button(commandController.isRecording ? "停止录制" : copy.recordButton) {
                    commandController.toggleRecording()
                }
                .buttonStyle(ConsoleGradientButtonStyle(variant: .danger, expands: false))
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .background(ConsolePalette.background)
    }

    private var mainWorkspace: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 10) {
                previewWorkspace
                directorSummaryStrip
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    quickStartPanel
                    presentationPanel
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
                CameraPreviewView(session: camera.session)
                    .opacity(camera.status == .running ? 0.76 : 0)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                ConsolePalette.previewGlow
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if camera.status == .running {
                    HandPointOverlay(
                        points: camera.latestHandPoints,
                        isCalibrating: calibrationFlow != nil,
                        isZoneActive: camera.gestureZoneLabel.contains("热区") && !camera.gestureZoneLabel.contains("待")
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if camera.status != .running {
                    VStack(spacing: 10) {
                        Image(systemName: "camera.slash")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(ConsolePalette.textTertiary)
                        Text(copy.cameraNotConnected)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ConsolePalette.textSecondary)
                        Text(camera.status.detail)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ConsolePalette.textTertiary)
                        Button("重新连接") {
                            camera.start()
                        }
                        .buttonStyle(ConsoleGradientButtonStyle(variant: .outline, expands: false))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(commandController.isRecording ? ConsolePalette.record : ConsolePalette.teal)
                        .frame(width: 6, height: 6)
                    Text("直播")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ConsolePalette.textPrimary)
                        .tracking(1.2)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding([.top, .leading], 12)
                .frame(maxHeight: .infinity, alignment: .topLeading)

                Spacer()

                VStack(alignment: .leading, spacing: 5) {
                    PreviewChip(icon: "hand.raised", text: camera.gestureZoneLabel)
                    PreviewChip(icon: "arrow.up.forward", text: commandController.lastActionDescription)
                    PreviewChip(icon: "sparkles", text: camera.detectedHandShapes)
                }
                .padding([.leading, .bottom], 12)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
    }

    private var directorSummaryStrip: some View {
        let pipeline = pipelineFactory.makePipeline(
            mode: mode,
            camera: .external(name: camera.activeDeviceName),
            screen: mode == .cameraAndScreen ? .mainDisplay : nil,
            layout: layout
        )

        return HStack(spacing: 0) {
            SummaryCell(label: "录制模式", value: mode.label, monospaced: false, showsTrailingDivider: true)
            SummaryCell(label: "布局", value: layout.label, monospaced: false, showsTrailingDivider: true)
            SummaryCell(label: "输出轨道", value: "\(pipeline.outputs.count) 轨道", monospaced: false, showsTrailingDivider: true)
            SummaryCell(label: "已用时长", value: elapsedTime, monospaced: true, showsTrailingDivider: false)
        }
        .frame(height: 50)
        .background(ConsolePalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(ConsolePalette.border, lineWidth: 1)
        )
    }

    private var quickStartPanel: some View {
        VStack(spacing: 0) {
            CardHeader(title: "快速启动", hint: "实时", isCollapsed: quickStartCollapsed) {
                quickStartCollapsed.toggle()
            }

            if !quickStartCollapsed {
                VStack(alignment: .leading, spacing: 10) {
                    ConsoleDetailLine(label: "演练状态", value: commandController.isRehearsing ? "进行中" : "就绪")
                    ConsoleDetailLine(label: "录制状态", value: commandController.isRecording ? "进行中" : "待机")
                    ConsoleDetailLine(label: "活跃设备", value: camera.activeDeviceName)
                    ConsoleDetailLine(label: "当前手势", value: camera.detectedHandShapes)

                    ConsoleDivider()

                    HStack(spacing: 7) {
                        Button("刷新设备") {
                            camera.refreshDevicesAndRestart()
                        }
                        .buttonStyle(ConsoleGradientButtonStyle(variant: .gold, expands: true))

                        Button("测试投影片") {
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

    private var presentationPanel: some View {
        VStack(spacing: 0) {
            CardHeader(title: "演示设定", hint: "自动", isCollapsed: presentationCollapsed) {
                presentationCollapsed.toggle()
            }

            if !presentationCollapsed {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        ConsoleFieldLabel("目标应用")
                        Menu {
                            Button("PowerPoint") { target = .powerPoint }
                            Button("WPS") { target = .wps }
                            Button("Keynote") { target = .keynote }
                            Button("Word") { target = .word }
                            Button("Excel") { target = .excel }
                            Button("PDF") { target = .pdfViewer }
                            Button("HTML") { target = .html(engine: .revealJS) }
                        } label: {
                            MenuFieldLabel(text: target.label)
                        }
                        .menuStyle(.borderlessButton)
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        ConsoleFieldLabel("录制模式")
                        Menu {
                            Button("摄像头") { mode = .cameraOnly }
                            Button("摄像头 + 萤幕") { mode = .cameraAndScreen }
                        } label: {
                            MenuFieldLabel(text: mode.label)
                        }
                        .menuStyle(.borderlessButton)
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        ConsoleFieldLabel("布局")
                        Menu {
                            Button("人物特写") { layout = .speakerCloseUp }
                            Button("子母画面 · 右下角") { layout = .screenWithCameraPictureInPicture(corner: .bottomRight) }
                            Button("左右分屏") { layout = .sideBySide }
                        } label: {
                            MenuFieldLabel(text: layout.label)
                        }
                        .menuStyle(.borderlessButton)
                        .buttonStyle(.plain)
                    }

                    ConsoleDivider()

                    Button("打开测试演示文稿") {
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
            CardHeader(title: "手势工作区", hint: "最近 5 分钟", isCollapsed: gestureCollapsed) {
                gestureCollapsed.toggle()
            }

            if !gestureCollapsed {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("启用手势识别")
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

                    ConsoleDetailLine(label: "识别状态", value: camera.gestureStatus.rawValue)
                    ConsoleDetailLine(label: "本次会话", value: camera.gestureSessionLabel)
                    ConsoleDetailLine(label: "识别引擎", value: camera.gestureEngineLabel, monospaced: true)
                    ConsoleDetailLine(label: "手势区域", value: camera.gestureZoneLabel)

                    ConsoleDivider()

                    HStack {
                        Button("校准我的手势") {
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
                                Text("手势速查")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(ConsolePalette.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }

                    if showsGestureCheatsheet {
                        VStack(spacing: 0) {
                            GestureCheatsheetRow(icon: "hand.point.right", gesture: "剑指右挥", action: "下一张")
                            GestureCheatsheetRow(icon: "hand.point.left", gesture: "剑指左挥", action: "上一张")
                            GestureCheatsheetRow(icon: "hand.raised", gesture: "张开手掌", action: "暂停")
                            GestureCheatsheetRow(icon: "arrow.up.left.and.arrow.down.right", gesture: "双手分开", action: "放大")
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
            CardHeader(title: "设备与输出", hint: "自动扫描", isCollapsed: devicesCollapsed) {
                devicesCollapsed.toggle()
            }

            if !devicesCollapsed {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        ConsoleFieldLabel("输入设备")
                        HStack(spacing: 7) {
                            Menu {
                                ForEach(camera.availableDevices) { device in
                                    Button(device.name) {
                                        camera.selectDevice(id: device.id)
                                    }
                                }
                            } label: {
                                MenuFieldLabel(text: selectedDeviceTitle)
                            }
                            .menuStyle(.borderlessButton)
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)

                            Button("扫描") {
                                camera.refreshDevicesAndRestart()
                            }
                            .buttonStyle(ConsoleGradientButtonStyle(variant: .gold, expands: false, compact: true))
                        }
                    }

                    ConsoleDivider()

                    ConsoleDetailLine(label: "状态", value: camera.status == .running ? "已连接" : camera.status.label)
                    ConsoleDetailLine(label: "设备详情", value: selectedDeviceDetail, monospaced: true)
                    ConsoleDetailLine(label: "检测输入", value: discoveredDeviceSummary)
                    ConsoleDetailLine(label: "输出协议", value: commandSummary, monospaced: true)
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
                        Text("\(Self.appVersion) · 导演模式")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(ConsolePalette.textTertiary)

                        Button("关于") {
                            showsAboutCard.toggle()
                            if showsAboutCard {
                                showsDiagnostics = false
                            }
                        }
                        .buttonStyle(.plain)
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
                            Text("高级诊断")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(showsDiagnostics ? ConsolePalette.textSecondary : ConsolePalette.textTertiary)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    HStack(spacing: 6) {
                        Circle()
                            .fill(ConsolePalette.teal)
                            .frame(width: 6, height: 6)
                        Text(camera.status == .running ? "已连接" : "等待连接")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(ConsolePalette.textSecondary)
                    }
                }
                .padding(.horizontal, 20)
                .frame(height: 40)

                if showsAboutCard {
                    AboutPopoverCard()
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

    private var diagnosticsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 32) {
                DiagnosticsLine(label: "辅助功能", value: commandController.accessibilityStatus.rawValue)
                DiagnosticsLine(label: "Chrome 自动化", value: commandController.automationStatus.rawValue)
                DiagnosticsLine(label: "扫描摘要", value: camera.deviceScanSummary)
                DiagnosticsLine(label: "兼容示例", value: supportedDeviceSummary)
            }

            HStack(spacing: 7) {
                Button("权限设置") {
                    commandController.openAccessibilitySettings()
                }
                .buttonStyle(FooterGhostButtonStyle())

                Button("请求权限") {
                    commandController.requestAccessibilityPermission()
                }
                .buttonStyle(FooterGhostButtonStyle())

                Button("Chrome 授权") {
                    commandController.requestChromeAutomationPermission()
                }
                .buttonStyle(FooterGhostButtonStyle())

                Button("刷新状态") {
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

    private var commandSummary: String {
        director.command(for: .swipeLeft, target: target).transport.label
    }

    private var supportedDeviceSummary: String {
        "内置 / DJI / Insta360 / 采集卡 / 网络摄像头"
    }

    private var discoveredDeviceSummary: String {
        let count = max(0, camera.availableDevices.count - 1)
        return count == 0 ? "未发现可采集摄像头" : "\(count) 路输入"
    }

    private var selectedDeviceTitle: String {
        camera.availableDevices.first(where: { $0.id == camera.selectedDeviceID })?.name ?? "选择输入设备"
    }

    private var selectedDeviceDetail: String {
        camera.availableDevices.first(where: { $0.id == camera.selectedDeviceID })?.detail ?? "设备列表待刷新"
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
            Text("个人手势校准")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(ConsolePalette.textPrimary)

            Text(flow.currentGesture.instruction)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(ConsolePalette.textPrimary)

            Text("第 \(flow.currentSample) / 3 次。点击开始后看着摄像头完成动作，系统会自动判断成功并进入下一次。")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ConsolePalette.textSecondary)

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ConsolePalette.previewBase)
                CameraPreviewView(session: camera.session)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                HandPointOverlay(points: camera.latestHandPoints, isCalibrating: true, isZoneActive: true)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(ConsolePalette.border, lineWidth: 1)
            )

            ProgressView(value: camera.calibrationProgress)
                .tint(ConsolePalette.gold)

            Text(camera.calibrationStatus)
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
                Button("开始自动采样") {
                    runAutomaticCalibrationSample(flow)
                }
                .buttonStyle(ConsoleGradientButtonStyle(variant: .gold, expands: true))

                Button("结束") {
                    calibrationFlow = nil
                }
                .buttonStyle(ConsoleGradientButtonStyle(variant: .outline, expands: true))
            }

            ConsoleDetailLine(label: "当前手型", value: camera.detectedHandShapes)
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
}

private enum DisplayLanguageTab: String, CaseIterable, Identifiable {
    case simplified
    case english
    case traditional

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .simplified:
            return "简"
        case .english:
            return "EN"
        case .traditional:
            return "繁"
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
                    Color(red: 46 / 255, green: 32 / 255, blue: 16 / 255).opacity(0.85),
                    Color(red: 20 / 255, green: 16 / 255, blue: 10 / 255).opacity(0.5),
                    Color.clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 260
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

private struct ConsoleFieldLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(ConsolePalette.textTertiary)
            .tracking(0.8)
    }
}

private struct MenuFieldLabel: View {
    let text: String

    var body: some View {
        HStack {
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ConsolePalette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(ConsolePalette.textTertiary)
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 32 / 255, green: 26 / 255, blue: 12 / 255),
                    ConsolePalette.surface
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color(red: 90 / 255, green: 68 / 255, blue: 40 / 255), lineWidth: 1)
        )
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
        .buttonStyle(.plain)
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
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("关于灵演")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ConsolePalette.textPrimary)
                Spacer()
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(ConsolePalette.textTertiary)
            }

            ConsoleDivider()

            VStack(alignment: .leading, spacing: 8) {
                Text("作者")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ConsolePalette.textTertiary)
                Text("傲客")
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
                Text("v0.6.0")
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

                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(ConsolePalette.textPrimary.opacity(0.72))
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.82), lineWidth: 1)
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
                return "做你的‘下一页’左挥手势"
            case .swipeRight:
                return "做你的‘上一页’右挥手势"
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
        .buttonStyle(.plain)
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

private extension RecordingMode {
    var label: String {
        switch self {
        case .cameraOnly:
            return "摄像头"
        case .cameraAndScreen:
            return "摄像头 + 萤幕"
        }
    }
}

private extension RecordingLayout {
    var label: String {
        switch self {
        case .speakerCloseUp:
            return "人物特写"
        case .screenWithCameraPictureInPicture(let corner):
            return "子母画面 · \(corner.label)"
        case .sideBySide:
            return "左右分屏"
        }
    }
}

private extension PiPCorner {
    var label: String {
        switch self {
        case .topLeft:
            return "左上角"
        case .topRight:
            return "右上角"
        case .bottomLeft:
            return "左下角"
        case .bottomRight:
            return "右下角"
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
