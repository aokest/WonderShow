import AppKit
import PresenterDirector

@MainActor
final class PresentationCommandController: ObservableObject {
    @Published private(set) var accessibilityStatus: AccessibilityStatus = .unknown
    @Published private(set) var lastActionDescription = "尚未触发"
    @Published private(set) var lastDeliveryBackend = "未发送"
    @Published private(set) var frontmostApplication = "未检测"
    @Published private(set) var lastDeliveryDetail = "等待命令"
    @Published private(set) var isRecording = false

    private let director = PresentationDirector()

    func refreshAccessibilityStatus() {
        accessibilityStatus = AXIsProcessTrusted() ? .granted : .missing
    }

    func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(options)
        accessibilityStatus = granted ? .granted : .missing
    }

    func handle(_ gesture: GestureIntent, target: PresentationTarget) {
        refreshAccessibilityStatus()
        let command = director.command(for: gesture, target: target)
        let result = sendCommand(command.presentationAction, target: target)
        lastActionDescription = result.userFacingAction(action: command.presentationAction)
    }

    func testNextSlide(target: PresentationTarget) {
        refreshAccessibilityStatus()
        lastActionDescription = "3 秒后测试下一页"
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

    @discardableResult
    private func sendCommand(_ action: PresentationAction, target: PresentationTarget) -> CommandDeliveryResult {
        updateFrontmostApplication()

        if action == .toggleRecording {
            isRecording.toggle()
            return finishDelivery(.success(backend: "内部状态", detail: isRecording ? "录制状态：开启" : "录制状态：关闭"))
        }

        if case .html = target {
            let htmlResult = sendHTMLCommand(action)
            if htmlResult.succeeded {
                return finishDelivery(htmlResult)
            }

            let fallback = sendKeyboardCommand(for: action)
            return finishDelivery(fallback.mergingFallbackReason(htmlResult.detail))
        }

        return finishDelivery(sendKeyboardCommand(for: action))
    }

    private func finishDelivery(_ result: CommandDeliveryResult) -> CommandDeliveryResult {
        lastDeliveryBackend = result.backend
        lastDeliveryDetail = result.detail
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

    private func sendKeyboardCommand(for action: PresentationAction) -> CommandDeliveryResult {
        switch action {
        case .nextSlide:
            return postKey(.rightArrow)
        case .previousSlide:
            return postKey(.leftArrow)
        case .zoomIn:
            return postKey(.equals, modifiers: .maskCommand)
        case .zoomOut:
            return postKey(.minus, modifiers: .maskCommand)
        case .startPresentation:
            return postKey(.returnKey, modifiers: .maskCommand)
        case .exitPresentation:
            return postKey(.escape)
        case .toggleAnnotation, .drawAnnotation, .clearAnnotations, .none:
            return .skipped(backend: "未实现", detail: "\(action.label) 暂未接入当前目标")
        case .toggleRecording:
            isRecording.toggle()
            return .success(backend: "内部状态", detail: isRecording ? "录制状态：开启" : "录制状态：关闭")
        }
    }

    private func sendHTMLCommand(_ action: PresentationAction) -> CommandDeliveryResult {
        guard let javascript = action.htmlJavaScript else {
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

        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            return .failed(backend: "Chrome HTML 直连", detail: "无法创建 AppleScript")
        }

        let output = script.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "\(error)"
            return .failed(backend: "Chrome HTML 直连", detail: message)
        }

        let result = output.stringValue ?? "已发送"
        return .success(backend: "Chrome HTML 直连", detail: "\(action.label) 已发送：\(result)")
    }

    private func postKey(_ key: VirtualKey, modifiers: CGEventFlags = []) -> CommandDeliveryResult {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: key.rawValue, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: key.rawValue, keyDown: false)
        else {
            return .failed(backend: "通用键盘", detail: "无法创建键盘事件")
        }

        down.flags = modifiers
        up.flags = modifiers

        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            down.postToPid(pid)
            up.postToPid(pid)
            return .success(backend: "目标进程键盘", detail: "已发送到 \(frontmostApplication)")
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

private enum VirtualKey: CGKeyCode {
    case leftArrow = 0x7B
    case rightArrow = 0x7C
    case minus = 0x1B
    case equals = 0x18
    case escape = 0x35
    case returnKey = 0x24
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

    var htmlJavaScript: String? {
        switch self {
        case .nextSlide:
            return """
            (() => {
              const slides = Array.from(document.querySelectorAll('.slide'));
              const current = Math.max(0, slides.findIndex(slide => slide.classList.contains('active')));
              const next = Math.min(slides.length - 1, current + 1);
              slides.forEach((slide, index) => slide.classList.toggle('active', index === next));
              return `${next + 1} / ${slides.length}`;
            })()
            """
        case .previousSlide:
            return """
            (() => {
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
              const stage = document.getElementById('stage');
              const current = Number(stage.dataset.wonderShowZoom || '1');
              const next = Math.min(1.8, current + 0.12);
              stage.dataset.wonderShowZoom = String(next);
              stage.style.transform = `scale(${next})`;
              return `zoom ${next.toFixed(2)}`;
            })()
            """
        case .zoomOut:
            return """
            (() => {
              const stage = document.getElementById('stage');
              const current = Number(stage.dataset.wonderShowZoom || '1');
              const next = Math.max(0.75, current - 0.12);
              stage.dataset.wonderShowZoom = String(next);
              stage.style.transform = `scale(${next})`;
              return `zoom ${next.toFixed(2)}`;
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
