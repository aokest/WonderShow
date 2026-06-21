@testable import WonderShowApp
import Testing
import WonderShow

@Test func screenCaptureSourceOptionsAreNotLimitedByShortcutSlotCount() {
    let windows = (0..<16).map { index in
        CaptureWindowCandidate(
            id: UInt32(100 + index),
            displayID: 1,
            title: "Document \(index)",
            applicationName: index.isMultiple(of: 2) ? "Keynote" : "Google Chrome",
            bundleIdentifier: index.isMultiple(of: 2) ? "com.apple.iWork.Keynote" : "com.google.Chrome",
            frameWidth: 1280,
            frameHeight: 720
        )
    }

    let options = ScreenCaptureSourceOptionBuilder.options(
        displays: [
            CaptureDisplayCandidate(id: 1, width: 1920, height: 1080)
        ],
        windows: windows,
        allowsOwnApplication: true
    )

    #expect(options.filter(\.id.isWindow).count == 16)
    #expect(options.count == 17)
}

@Test func screenCaptureSourceOptionsIncludeOwnWindowOnlyForManualPicker() {
    let ownWindow = CaptureWindowCandidate(
        id: 42,
        displayID: 1,
        title: "灵演社区版",
        applicationName: "WonderShow",
        bundleIdentifier: "com.wondershow.community",
        frameWidth: 1440,
        frameHeight: 900
    )

    let hiddenByDefault = ScreenCaptureSourceOptionBuilder.options(
        displays: [],
        windows: [ownWindow],
        allowsOwnApplication: false
    )
    let manualPickerOptions = ScreenCaptureSourceOptionBuilder.options(
        displays: [],
        windows: [ownWindow],
        allowsOwnApplication: true
    )

    #expect(hiddenByDefault.isEmpty)
    #expect(manualPickerOptions.map(\.id) == [.window(42)])
}

@Test func screenCaptureSourceOptionsFilterToolbarsAndWindowlessSurfaces() {
    let options = ScreenCaptureSourceOptionBuilder.options(
        displays: [],
        windows: [
            CaptureWindowCandidate(
                id: 10,
                displayID: 1,
                title: "Client Brief",
                applicationName: "Google Chrome",
                bundleIdentifier: "com.google.Chrome",
                frameWidth: 1280,
                frameHeight: 720
            ),
            CaptureWindowCandidate(
                id: 11,
                displayID: 1,
                title: "Menubar",
                applicationName: "",
                frameWidth: 3840,
                frameHeight: 30
            ),
            CaptureWindowCandidate(
                id: 12,
                displayID: 1,
                title: "",
                applicationName: "",
                frameWidth: 1280,
                frameHeight: 720
            ),
            CaptureWindowCandidate(
                id: 13,
                displayID: 1,
                title: "Dock",
                applicationName: "程序坞",
                bundleIdentifier: "com.apple.dock",
                frameWidth: 1470,
                frameHeight: 956
            )
        ],
        allowsOwnApplication: true
    )

    #expect(options.map(\.id) == [.window(10)])
}
