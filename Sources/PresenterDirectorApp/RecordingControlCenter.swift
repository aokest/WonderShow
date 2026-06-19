import AppKit
import SwiftUI

@MainActor
final class RecordingControlCenter: ObservableObject {
    @Published var state = RecordingControlSurfaceState(controlState: .idle, elapsedSeconds: 0) {
        didSet {
            stateDidChange?()
        }
    }
    @Published var featureTier: RecordingFeatureTier = .svip {
        didSet {
            stateDidChange?()
        }
    }

    var stateDidChange: (() -> Void)?
    var primaryAction: (() -> Void)?
    var stopAction: (() -> Void)?
    var revealMainWindowAction: (() -> Void)?
    var showSourcePickerAction: (() -> Void)?
    var hideMiniToolbarAction: (() -> Void)?
    var switchSourceSlotAction: ((Int) -> Void)?
}

@MainActor
final class WonderShowAppCoordinator: NSObject, NSApplicationDelegate {
    let controlCenter = RecordingControlCenter()
    private var statusItem: NSStatusItem?
    private var miniToolbarPanel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()
        controlCenter.stateDidChange = { [weak self] in
            self?.updateStatusItem()
        }
        controlCenter.hideMiniToolbarAction = { [weak self] in
            self?.miniToolbarPanel?.orderOut(nil)
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "WonderShow")
        item.button?.imagePosition = .imageLeading
        item.button?.title = " 00:00:00"
        statusItem = item
        rebuildStatusMenu()
    }

    func updateStatusItem() {
        statusItem?.button?.title = " \(controlCenter.state.elapsedTimecode)"
        rebuildStatusMenu()
    }

    private func rebuildStatusMenu() {
        let menu = NSMenu()
        menu.addItem(menuItem(title: "显示灵演", action: #selector(showMainWindow)))
        menu.addItem(menuItem(title: "显示/隐藏迷你工具条", action: #selector(toggleMiniToolbar)))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: primaryTitle, action: #selector(performPrimaryAction)))
        let stopItem = menuItem(title: "终止录制", action: #selector(performStopAction))
        stopItem.isEnabled = controlCenter.state.stopEnabled
        menu.addItem(stopItem)
        menu.addItem(menuItem(title: "选择录制源", action: #selector(showSourcePicker)))
        let slotMenuItem = NSMenuItem(title: "切换源位", action: nil, keyEquivalent: "")
        let slotMenu = NSMenu()
        for slot in RecordingSourceSlots.validSlots {
            let item = menuItem(title: "源位 \(slot)", action: #selector(switchSourceSlotFromMenu(_:)))
            item.tag = slot
            item.isEnabled = controlCenter.state.stopEnabled && activeFeatureTier.permitsSourceSlot(slot)
            slotMenu.addItem(item)
        }
        menu.setSubmenu(slotMenu, for: slotMenuItem)
        menu.addItem(slotMenuItem)
        statusItem?.menu = menu
    }

    private func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private var primaryTitle: String {
        switch controlCenter.state.primaryAction {
        case .start:
            return "开始录制"
        case .cancelStart:
            return "取消倒计时"
        case .pause:
            return "暂停录制"
        case .resume:
            return "继续录制"
        }
    }

    private var activeFeatureTier: RecordingFeatureTier {
        controlCenter.featureTier
    }

    @objc private func showMainWindow() {
        controlCenter.revealMainWindowAction?()
    }

    @objc private func performPrimaryAction() {
        controlCenter.primaryAction?()
    }

    @objc private func performStopAction() {
        controlCenter.stopAction?()
    }

    @objc private func showSourcePicker() {
        controlCenter.showSourcePickerAction?()
    }

    @objc private func switchSourceSlotFromMenu(_ sender: NSMenuItem) {
        controlCenter.switchSourceSlotAction?(sender.tag)
    }

    @objc private func toggleMiniToolbar() {
        if let panel = miniToolbarPanel, panel.isVisible {
            panel.orderOut(nil)
            return
        }
        showMiniToolbar()
    }

    private func showMiniToolbar() {
        if miniToolbarPanel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 120, y: 120, width: 650, height: 78),
                styleMask: [.titled, .closable, .utilityWindow],
                backing: .buffered,
                defer: false
            )
            panel.title = "WonderShow Mini"
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.isMovableByWindowBackground = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true
            panel.contentView = NSHostingView(
                rootView: MiniRecordingToolbar(controlCenter: controlCenter)
            )
            miniToolbarPanel = panel
        }
        miniToolbarPanel?.orderFrontRegardless()
    }
}

private struct MiniRecordingToolbar: View {
    @ObservedObject var controlCenter: RecordingControlCenter
    private var activeFeatureTier: RecordingFeatureTier {
        controlCenter.featureTier
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(controlCenter.state.elapsedTimecode)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(ConsolePalette.textPrimary)
                .frame(width: 82, alignment: .leading)

            Button {
                controlCenter.primaryAction?()
            } label: {
                Image(systemName: primaryIcon)
            }
            .buttonStyle(MiniToolbarButtonStyle(isProminent: true))
            .help(primaryHelp)

            Button {
                controlCenter.stopAction?()
            } label: {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(MiniToolbarButtonStyle(isProminent: false))
            .disabled(!controlCenter.state.stopEnabled)
            .help("终止录制")

            Button {
                controlCenter.showSourcePickerAction?()
            } label: {
                Image(systemName: "rectangle.on.rectangle")
            }
            .buttonStyle(MiniToolbarButtonStyle(isProminent: false))
            .help("选择录制源")

            ForEach(Array(RecordingSourceSlots.validSlots), id: \.self) { slot in
                Button("\(slot)") {
                    controlCenter.switchSourceSlotAction?(slot)
                }
                .buttonStyle(MiniToolbarButtonStyle(isProminent: false))
                .disabled(!controlCenter.state.stopEnabled || !activeFeatureTier.permitsSourceSlot(slot))
                .help(activeFeatureTier.permitsSourceSlot(slot) ? "源位 \(slot)" : "当前权益不可用")
            }

            Divider()
                .frame(height: 24)
                .overlay(ConsolePalette.innerBorder)

            Button {
                controlCenter.hideMiniToolbarAction?()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(MiniToolbarButtonStyle(isProminent: false))
            .help("关闭")
        }
        .padding(.horizontal, 10)
        .frame(width: 630, height: 54)
        .background(ConsolePalette.surface.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(ConsolePalette.border, lineWidth: 1)
        )
    }

    private var primaryIcon: String {
        switch controlCenter.state.primaryAction {
        case .start:
            return "record.circle"
        case .cancelStart:
            return "xmark"
        case .pause:
            return "pause.fill"
        case .resume:
            return "play.fill"
        }
    }

    private var primaryHelp: String {
        switch controlCenter.state.primaryAction {
        case .start:
            return "开始录制"
        case .cancelStart:
            return "取消倒计时"
        case .pause:
            return "暂停录制"
        case .resume:
            return "继续录制"
        }
    }
}

private struct MiniToolbarButtonStyle: ButtonStyle {
    let isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(isProminent ? ConsolePalette.previewBase : ConsolePalette.textPrimary)
            .frame(width: 30, height: 30)
            .background(isProminent ? ConsolePalette.goldBright : ConsolePalette.overlay)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
