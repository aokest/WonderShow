import Testing
@testable import WonderShow

@Test func screenCapturePlannerPrefersDisplayContainingPowerPointSlideShow() {
    let displays = [
        CaptureDisplayCandidate(id: 1, width: 1728, height: 1117),
        CaptureDisplayCandidate(id: 2, width: 1920, height: 1080)
    ]
    let windows = [
        CaptureWindowCandidate(
            id: 10,
            displayID: 1,
            title: "灵演",
            applicationName: "WonderShowApp",
            frameWidth: 1200,
            frameHeight: 800
        ),
        CaptureWindowCandidate(
            id: 11,
            displayID: 2,
            title: "Slide Show - Quarterly Review",
            applicationName: "Microsoft PowerPoint",
            frameWidth: 1920,
            frameHeight: 1080
        )
    ]

    let display = ScreenCapturePlanner().preferredDisplay(
        displays: displays,
        windows: windows,
        target: .powerPoint
    )

    #expect(display?.id == 2)
}

@Test func screenCapturePlannerPrefersPowerPointSlideShowWindowForDirectCapture() {
    let windows = [
        CaptureWindowCandidate(
            id: 30,
            displayID: 1,
            title: "Presenter View",
            applicationName: "Microsoft PowerPoint",
            frameWidth: 1920,
            frameHeight: 1080
        ),
        CaptureWindowCandidate(
            id: 31,
            displayID: 2,
            title: "Slide Show - Quarterly Review",
            applicationName: "Microsoft PowerPoint",
            frameWidth: 1920,
            frameHeight: 1080
        )
    ]

    let window = ScreenCapturePlanner().preferredWindow(
        windows: windows,
        target: .powerPoint
    )

    #expect(window?.id == 31)
}

@Test func screenCapturePlannerIgnoresSystemBackstopWhenChoosingDirectWindow() {
    let windows = [
        CaptureWindowCandidate(
            id: 40,
            displayID: 1,
            title: "Display 1 Backstop",
            applicationName: "",
            frameWidth: 3840,
            frameHeight: 2160
        ),
        CaptureWindowCandidate(
            id: 41,
            displayID: 1,
            title: "Client Brief",
            applicationName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            frameWidth: 1440,
            frameHeight: 900
        )
    ]

    let window = ScreenCapturePlanner().preferredWindow(
        windows: windows,
        target: .genericKeyboard
    )

    #expect(window?.id == 41)
}


@Test func screenCapturePlannerAvoidsPresenterViewWhenSlideShowExists() {
    let displays = [
        CaptureDisplayCandidate(id: 1, width: 1920, height: 1080),
        CaptureDisplayCandidate(id: 2, width: 1920, height: 1080)
    ]
    let windows = [
        CaptureWindowCandidate(
            id: 21,
            displayID: 1,
            title: "Presenter View",
            applicationName: "Microsoft PowerPoint",
            frameWidth: 1920,
            frameHeight: 1080
        ),
        CaptureWindowCandidate(
            id: 22,
            displayID: 2,
            title: "Slide Show",
            applicationName: "Microsoft PowerPoint",
            frameWidth: 1920,
            frameHeight: 1080
        )
    ]

    let display = ScreenCapturePlanner().preferredDisplay(
        displays: displays,
        windows: windows,
        target: .powerPoint
    )

    #expect(display?.id == 2)
}

@Test func screenCapturePlannerFallsBackToLargestDisplay() {
    let displays = [
        CaptureDisplayCandidate(id: 1, width: 1280, height: 720),
        CaptureDisplayCandidate(id: 2, width: 2560, height: 1440)
    ]

    let display = ScreenCapturePlanner().preferredDisplay(
        displays: displays,
        windows: [],
        target: .genericKeyboard
    )

    #expect(display?.id == 2)
}

@Test func screenSharingWindowFilterKeepsNormalApplicationWindows() {
    let filter = ScreenSharingWindowFilter()

    #expect(filter.isShareable(
        CaptureWindowCandidate(
            id: 50,
            displayID: 1,
            title: "API 密钥 - ccdan",
            applicationName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            frameWidth: 1635,
            frameHeight: 969
        )
    ))
    #expect(filter.isShareable(
        CaptureWindowCandidate(
            id: 51,
            displayID: 1,
            title: "",
            applicationName: "WPS Office",
            bundleIdentifier: "cn.wps.moffice",
            frameWidth: 2255,
            frameHeight: 929
        )
    ))
}

@Test func screenSharingWindowFilterRemovesSystemAndBackgroundSurfaces() {
    let filter = ScreenSharingWindowFilter()

    let blockedWindows = [
        CaptureWindowCandidate(
            id: 60,
            displayID: 1,
            title: "Menubar",
            applicationName: "",
            frameWidth: 3840,
            frameHeight: 30
        ),
        CaptureWindowCandidate(
            id: 61,
            displayID: 1,
            title: "Dock",
            applicationName: "程序坞",
            bundleIdentifier: "com.apple.dock",
            frameWidth: 1470,
            frameHeight: 956
        ),
        CaptureWindowCandidate(
            id: 62,
            displayID: 1,
            title: "Offscreen Wallpaper Window",
            applicationName: "墙纸",
            bundleIdentifier: "com.apple.wallpaper",
            frameWidth: 3840,
            frameHeight: 1080
        ),
        CaptureWindowCandidate(
            id: 63,
            displayID: 1,
            title: "com.electron.lark.helper",
            applicationName: "控制中心",
            bundleIdentifier: "com.apple.controlcenter",
            frameWidth: 48,
            frameHeight: 33
        ),
        CaptureWindowCandidate(
            id: 64,
            displayID: 1,
            title: "Codex",
            applicationName: "Codex",
            frameWidth: 35,
            frameHeight: 19
        ),
        CaptureWindowCandidate(
            id: 66,
            displayID: 1,
            title: "Display 1 Backstop",
            applicationName: "",
            frameWidth: 1470,
            frameHeight: 956
        ),
        CaptureWindowCandidate(
            id: 67,
            displayID: 1,
            title: "",
            applicationName: "访达",
            bundleIdentifier: "com.apple.finder",
            frameWidth: 3840,
            frameHeight: 1080
        )
    ]

    for window in blockedWindows {
        #expect(!filter.isShareable(window))
    }
}

@Test func screenSharingWindowFilterCanIncludeOwnApplicationForManualPicker() {
    let ownWindow = CaptureWindowCandidate(
        id: 65,
        displayID: 1,
        title: "灵演",
        applicationName: "WonderShow",
        bundleIdentifier: "com.wondershow.studio",
        frameWidth: 1674,
        frameHeight: 947
    )

    #expect(!ScreenSharingWindowFilter().isShareable(ownWindow))
    #expect(ScreenSharingWindowFilter(allowsOwnApplication: true).isShareable(ownWindow))
}
