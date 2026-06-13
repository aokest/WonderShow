import AppKit
import PresenterDirector

@MainActor
final class PresentationCommandController: ObservableObject {
    @Published private(set) var accessibilityStatus: AccessibilityStatus = .unknown
    @Published private(set) var lastActionDescription = "尚未触发"

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
        sendKeyboardCommand(for: command.presentationAction)
        lastActionDescription = command.presentationAction.label
    }

    private func sendKeyboardCommand(for action: PresentationAction) {
        switch action {
        case .nextSlide:
            postKey(.rightArrow)
        case .previousSlide:
            postKey(.leftArrow)
        case .zoomIn:
            postKey(.equals, modifiers: .maskCommand)
        case .zoomOut:
            postKey(.minus, modifiers: .maskCommand)
        case .toggleAnnotation, .drawAnnotation, .clearAnnotations, .none:
            break
        }
    }

    private func postKey(_ key: VirtualKey, modifiers: CGEventFlags = []) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: key.rawValue, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: key.rawValue, keyDown: false)
        else {
            return
        }

        down.flags = modifiers
        up.flags = modifiers
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
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
}
