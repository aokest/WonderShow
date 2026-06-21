public struct CaptureDisplayCandidate: Hashable, Sendable {
    public let id: UInt32
    public let width: Int
    public let height: Int

    public init(id: UInt32, width: Int, height: Int) {
        self.id = id
        self.width = width
        self.height = height
    }
}

public struct CaptureWindowCandidate: Hashable, Sendable {
    public let id: UInt32
    public let displayID: UInt32
    public let title: String
    public let applicationName: String
    public let bundleIdentifier: String
    public let frameWidth: Int
    public let frameHeight: Int

    public init(
        id: UInt32,
        displayID: UInt32,
        title: String,
        applicationName: String,
        bundleIdentifier: String = "",
        frameWidth: Int,
        frameHeight: Int
    ) {
        self.id = id
        self.displayID = displayID
        self.title = title
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
    }
}

public struct ScreenSharingWindowFilter: Sendable {
    private let allowsOwnApplication: Bool

    public init(allowsOwnApplication: Bool = false) {
        self.allowsOwnApplication = allowsOwnApplication
    }

    public func isShareable(_ window: CaptureWindowCandidate) -> Bool {
        guard window.frameWidth >= 360, window.frameHeight >= 220 else {
            return false
        }

        let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let applicationName = window.applicationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let bundleIdentifier = window.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let combinedText = "\(applicationName) \(bundleIdentifier) \(title)".lowercased()

        guard !applicationName.isEmpty || !title.isEmpty else {
            return false
        }
        guard !isSystemSurface(applicationName: applicationName, bundleIdentifier: bundleIdentifier, title: title) else {
            return false
        }
        guard allowsOwnApplication || !isOwnApplication(
            applicationName: applicationName,
            bundleIdentifier: bundleIdentifier
        ) else {
            return false
        }
        guard !decorativeTitleMarkers.contains(where: { combinedText.contains($0) }) else {
            return false
        }
        guard !isDesktopBackstop(applicationName: applicationName, title: title) else {
            return false
        }

        return true
    }

    private func isSystemSurface(
        applicationName: String,
        bundleIdentifier: String,
        title: String
    ) -> Bool {
        let app = applicationName.lowercased()
        let bundle = bundleIdentifier.lowercased()
        let title = title.lowercased()

        let blockedAppNames = [
            "dock", "程序坞",
            "control center", "控制中心",
            "notification center", "通知中心",
            "wallpaper", "墙纸",
            "spotlight", "聚焦",
            "cursoruiviewservice",
            "window server",
            "搜狗输入法", "豆包输入法"
        ]
        if blockedAppNames.contains(where: { app.contains($0) }) {
            return true
        }

        let blockedBundles = [
            "com.apple.dock",
            "com.apple.controlcenter",
            "com.apple.notificationcenterui",
            "com.apple.systemuiserver",
            "com.apple.wallpaper",
            "com.apple.spotlight",
            "com.apple.textinput"
        ]
        if blockedBundles.contains(where: { bundle.contains($0) }) {
            return true
        }

        let blockedExactTitles = [
            "menubar", "dock", "statusindicator", "statusitem",
            "offscreen wallpaper window", "display safe area inset shield",
            "underbelly"
        ]
        return blockedExactTitles.contains(title)
    }

    private func isOwnApplication(applicationName: String, bundleIdentifier: String) -> Bool {
        let app = applicationName.lowercased()
        let bundle = bundleIdentifier.lowercased()
        return app == "灵演"
            || app.contains("wondershow")
            || bundle == "com.wondershow.studio"
            || bundle == "com.local.lingyan"
            || bundle.contains("presenterdirector")
    }

    private func isDesktopBackstop(applicationName: String, title: String) -> Bool {
        let app = applicationName.lowercased()
        let title = title.lowercased()
        return title.contains("backstop")
            || (app == "访达" || app == "finder") && title.isEmpty
    }

    private var decorativeTitleMarkers: [String] {
        [
            "menubar",
            "wallpaper",
            "safe area",
            "display 1 backstop",
            "display 2 backstop",
            "statusindicator",
            "statusitem",
            "bentobox",
            "userswitcher",
            "audiovideomodule",
            "item-0"
        ]
    }
}

public struct ScreenCapturePlanner: Sendable {
    public init() {}

    public func preferredWindow(
        windows: [CaptureWindowCandidate],
        target: PresentationTarget
    ) -> CaptureWindowCandidate? {
        preferredPresentationWindow(windows: windows, target: target)
    }

    public func preferredDisplay(
        displays: [CaptureDisplayCandidate],
        windows: [CaptureWindowCandidate],
        target: PresentationTarget
    ) -> CaptureDisplayCandidate? {
        guard !displays.isEmpty else {
            return nil
        }

        if let window = preferredPresentationWindow(windows: windows, target: target),
           let display = displays.first(where: { $0.id == window.displayID }) {
            return display
        }

        return displays.max { displayScore($0) < displayScore($1) }
    }

    private func preferredPresentationWindow(
        windows: [CaptureWindowCandidate],
        target: PresentationTarget
    ) -> CaptureWindowCandidate? {
        let filter = ScreenSharingWindowFilter()
        return windows
            .filter { $0.frameWidth >= 640 && $0.frameHeight >= 360 }
            .filter(filter.isShareable)
            .max { windowScore($0, target: target) < windowScore($1, target: target) }
    }

    private func windowScore(_ window: CaptureWindowCandidate, target: PresentationTarget) -> Int {
        let text = "\(window.applicationName) \(window.title)".lowercased()
        var score = window.frameWidth * window.frameHeight / 10_000

        for keyword in keywords(for: target) where text.contains(keyword) {
            score += 10_000
        }
        if text.contains("slide show") || text.contains("幻灯片放映") || text.contains("播放") || text.contains("演示") {
            score += 4_000
        }
        if text.contains("presenter") || text.contains("演讲者") || text.contains("presenter view") {
            score -= 5_000
        }
        return score
    }

    private func displayScore(_ display: CaptureDisplayCandidate) -> Int {
        display.width * display.height
    }

    private func keywords(for target: PresentationTarget) -> [String] {
        switch target {
        case .powerPoint:
            return ["powerpoint", "microsoft powerpoint", "ppt"]
        case .wps:
            return ["wps"]
        case .keynote:
            return ["keynote"]
        case .word:
            return ["word"]
        case .excel:
            return ["excel"]
        case .pdfViewer:
            return ["preview", "acrobat", "pdf"]
        case .genericKeyboard:
            return []
        case .html:
            return ["chrome", "safari", "arc", "edge", "firefox"]
        }
    }
}
