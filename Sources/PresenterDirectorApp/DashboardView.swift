import PresenterDirector
import SwiftUI

struct DashboardView: View {
    private static let appVersion = "v0.4.1"

    @StateObject private var camera = CameraPreviewService()
    @StateObject private var commandController = PresentationCommandController()
    @State private var target: PresentationTarget = .powerPoint
    @State private var mode: RecordingMode = .cameraAndScreen
    @State private var layout: RecordingLayout = .screenWithCameraPictureInPicture(corner: .bottomRight)

    private let copy = AppLocalization().copy()
    private let director = PresentationDirector()
    private let pipelineFactory = RecordingPipelineFactory()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.94, green: 0.96, blue: 0.98),
                    Color(red: 0.98, green: 0.96, blue: 0.91)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                topBar

                HStack(alignment: .top, spacing: 18) {
                    VStack(spacing: 18) {
                        previewPanel
                        presentationPanel
                    }

                    VStack(spacing: 18) {
                        cameraPanel
                        recordingPanel
                        gesturesPanel
                    }
                    .frame(width: 360)
                }
            }
            .padding(22)
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

    private func updateGestureHandler() {
        let currentTarget = target
        camera.onGestureRecognized = { gesture in
            commandController.handle(gesture, target: currentTarget)
        }
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(copy.productName)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.08, green: 0.1, blue: 0.13))
                    Text(Self.appVersion)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.72))
                        .clipShape(Capsule())
                }
                Text(copy.tagline)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 280, alignment: .leading)

            Spacer()

            StatusChip(icon: "video.fill", title: "摄像头", value: camera.status.label)
            StatusChip(icon: "hand.raised.fill", title: "手势", value: camera.gestureStatus.rawValue)
            StatusChip(icon: "rectangle.3.group.fill", title: "演示", value: target.label)

            Button(copy.rehearsalButton) {}
                .buttonStyle(PrimaryButtonStyle())
            Button(copy.recordButton) {}
                .buttonStyle(RecordButtonStyle())
        }
    }

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionTitle(icon: "rectangle.inset.filled.and.person.filled", text: copy.programPreview)
                Spacer()
                Text(camera.activeDeviceName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black)

                CameraPreviewView(session: camera.session)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if camera.status != .running {
                    VStack(spacing: 10) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 46, weight: .medium))
                        Text(copy.cameraNotConnected)
                            .font(.system(size: 18, weight: .semibold))
                        Text(camera.status.detail)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 420)
                        Button("重新连接") {
                            camera.start()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                HStack(spacing: 8) {
                    LiveDot(isOn: camera.status == .running)
                    Text(camera.status == .running ? "实时预览" : "预览待连接")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.black.opacity(0.52))
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .padding(14)
            }
            .aspectRatio(16 / 9, contentMode: .fit)
        }
        .surface()
    }

    private var presentationPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(icon: "play.rectangle.on.rectangle", text: "演示兼容")

            Picker("演示软件", selection: $target) {
                Text("PowerPoint").tag(PresentationTarget.powerPoint)
                Text("WPS").tag(PresentationTarget.wps)
                Text("Keynote").tag(PresentationTarget.keynote)
                Text("PDF").tag(PresentationTarget.pdfViewer)
                Text("HTML").tag(PresentationTarget.html(engine: .revealJS))
            }
            .pickerStyle(.segmented)

            HStack {
                Button("打开测试演示页") {
                    DemoDeckLauncher.openDemoDeck()
                }
                Text("测试时让浏览器或 PPT 保持前台，灵演会发送翻页/缩放快捷键。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                MetricTile(title: "翻页通道", value: commandSummary, icon: "keyboard")
                MetricTile(title: "标注方式", value: annotationSummary, icon: "pencil.and.scribble")
                MetricTile(title: "HTML 优势", value: htmlAdvantage, icon: "curlybraces")
            }
        }
        .surface()
    }

    private var cameraPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(icon: "camera.fill", text: "Pocket 3")
            DetailRow(label: "当前设备", value: camera.activeDeviceName)
            DetailRow(label: "连接状态", value: camera.status.detail)
            DetailRow(label: "接入方式", value: "UVC 摄像头")
            DetailRow(label: "跟踪策略", value: "机身 FaceTrack + 软件构图")
            DetailRow(label: "私有 SDK", value: "不依赖")
        }
        .surface()
    }

    private var recordingPanel: some View {
        let pipeline = pipelineFactory.makePipeline(
            mode: mode,
            camera: .pocket3,
            screen: mode == .cameraAndScreen ? .mainDisplay : nil,
            layout: layout
        )

        return VStack(alignment: .leading, spacing: 14) {
            SectionTitle(icon: "record.circle", text: "录制方案")

            Picker("录制模式", selection: $mode) {
                Text("只录人像").tag(RecordingMode.cameraOnly)
                Text("人像 + 屏幕").tag(RecordingMode.cameraAndScreen)
            }
            .pickerStyle(.segmented)

            Picker("画面布局", selection: $layout) {
                Text("人物特写").tag(RecordingLayout.speakerCloseUp)
                Text("画中画").tag(RecordingLayout.screenWithCameraPictureInPicture(corner: .bottomRight))
                Text("左右分屏").tag(RecordingLayout.sideBySide)
            }

            DetailRow(label: "输入源", value: "\(pipeline.inputs.count) 路")
            DetailRow(label: "输出素材", value: pipeline.outputs.map(\.label).joined(separator: "、"))
            DetailRow(label: "成片布局", value: pipeline.composition.label)
        }
        .surface()
    }

    private var gesturesPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(icon: "hand.raised.fill", text: "手势控制")
            Toggle("启用手势控制", isOn: $camera.gestureControlEnabled)
                .toggleStyle(.switch)
            DetailRow(label: "识别状态", value: camera.gestureStatus.rawValue)
            DetailRow(label: "当前手型", value: camera.detectedHandShapes)
            DetailRow(label: "最近动作", value: commandController.lastActionDescription)
            DetailRow(label: "辅助功能", value: commandController.accessibilityStatus.rawValue)

            HStack {
                Button("请求授权") {
                    commandController.requestAccessibilityPermission()
                }
                Button("快速校准") {
                    camera.gestureCalibrationProfile = GestureProfile(
                        minimumHorizontalTravel: 0.18,
                        minimumZoomDistanceChange: 0.15,
                        maximumGestureDurationMilliseconds: 750
                    )
                }
            }

            GestureRow(icon: "arrow.left", gesture: "指枪左挥", action: "下一页")
            GestureRow(icon: "arrow.right", gesture: "指枪右挥", action: "上一页")
            GestureRow(icon: "arrow.up.left.and.arrow.down.right", gesture: "双手八字分开", action: "放大演示")
            GestureRow(icon: "arrow.down.right.and.arrow.up.left", gesture: "双手八字合拢", action: "缩小演示")
            GestureRow(icon: "play.fill", gesture: "待录入", action: "开始播放")
            GestureRow(icon: "record.circle", gesture: "待录入", action: "开始/停止录制")
        }
        .surface()
    }

    private var commandSummary: String {
        director.command(for: .swipeLeft, target: target).transport.label
    }

    private var annotationSummary: String {
        director.annotationStrategy(for: target).label
    }

    private var htmlAdvantage: String {
        switch target {
        case .html:
            return "内嵌画布"
        default:
            return "可后续接入"
        }
    }
}

private struct SectionTitle: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color(red: 0.1, green: 0.12, blue: 0.16))
    }
}

private struct StatusChip: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(Color(red: 0.11, green: 0.38, blue: 0.47))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.8), lineWidth: 1)
        )
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
        .font(.system(size: 13))
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(Color(red: 0.88, green: 0.94, blue: 0.96))
                .foregroundStyle(Color(red: 0.07, green: 0.36, blue: 0.44))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.white.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct GestureRow: View {
    let icon: String
    let gesture: String
    let action: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 28, height: 28)
                .background(Color(red: 0.96, green: 0.92, blue: 0.82))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(gesture)
                .fontWeight(.medium)
            Spacer()
            Text(action)
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 13))
    }
}

private struct LiveDot: View {
    let isOn: Bool

    var body: some View {
        Circle()
            .fill(isOn ? Color.green : Color.orange)
            .frame(width: 8, height: 8)
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .frame(minWidth: 88)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color(red: 0.1, green: 0.36, blue: 0.44).opacity(configuration.isPressed ? 0.82 : 1))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct RecordButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .frame(minWidth: 88)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color(red: 0.78, green: 0.18, blue: 0.13).opacity(configuration.isPressed ? 0.82 : 1))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private extension View {
    func surface() -> some View {
        self
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.92), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 20, x: 0, y: 10)
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
