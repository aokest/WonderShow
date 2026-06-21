@testable import WonderShowApp
import Testing

@Test func screenSourceSelectionResolvesSelectedWindowsInOptionOrder() {
    let first = makeSelectionWindowOption(id: 10, title: "Slides")
    let second = makeSelectionWindowOption(id: 20, title: "Notes")

    let result = ScreenSourceSelectionResolver.resolve(
        options: [first, second],
        selectedIDs: [.window(20), .window(10)]
    )

    #expect(result?.selectedIDs == [.window(10), .window(20)])
    #expect(result?.sourcePreference == .selectedWindows([10, 20]))
}

@Test func screenSourceSelectionPrefersDisplayWhenDisplayIsSelected() {
    let display = makeSelectionDisplayOption(id: 99)
    let window = makeSelectionWindowOption(id: 10, title: "Slides")

    let result = ScreenSourceSelectionResolver.resolve(
        options: [window, display],
        selectedIDs: [.window(10), .display(99)]
    )

    #expect(result?.selectedIDs == [.display(99)])
    #expect(result?.sourcePreference == .selectedDisplay(99))
}

@Test func screenSourceSelectionIgnoresStaleUnavailableSelections() {
    let window = makeSelectionWindowOption(id: 10, title: "Slides")

    let result = ScreenSourceSelectionResolver.resolve(
        options: [window],
        selectedIDs: [.window(20)]
    )

    #expect(result == nil)
}

private func makeSelectionWindowOption(id: UInt32, title: String) -> ScreenCaptureWindowOption {
    ScreenCaptureWindowOption(
        id: .window(id),
        applicationName: "Keynote",
        title: title,
        width: 1280,
        height: 720
    )
}

private func makeSelectionDisplayOption(id: UInt32) -> ScreenCaptureWindowOption {
    ScreenCaptureWindowOption(
        id: .display(id),
        applicationName: "Display",
        title: "Display \(id)",
        width: 1920,
        height: 1080
    )
}
