@testable import WonderShowApp
import Testing

@Test func audioInputSelectionAllowsChangesBeforeRecording() {
    let result = AudioInputSelectionPolicy.resolve(
        currentDeviceID: "built-in",
        requestedDeviceID: "wireless",
        isRecording: false
    )

    #expect(result.selectedDeviceID == "wireless")
    #expect(result.warning == nil)
}

@Test func audioInputSelectionLocksCurrentDeviceDuringRecording() {
    let result = AudioInputSelectionPolicy.resolve(
        currentDeviceID: "built-in",
        requestedDeviceID: "wireless",
        isRecording: true
    )

    #expect(result.selectedDeviceID == "built-in")
    #expect(result.warning?.contains("音画不同步") == true)
}
