@testable import WonderShowApp
import Testing

private struct DisplayDeviceOption: Identifiable, Equatable {
    let id: String
    let name: String
}

@Test func inputDeviceDisplaySelectionUsesAvailableSelectedOptionFirst() {
    let selected = DisplayDeviceOption(id: "camera-b", name: "Camera B")
    let result = InputDeviceDisplaySelectionPolicy.resolve(
        selectedID: selected.id,
        availableOptions: [
            DisplayDeviceOption(id: "camera-a", name: "Camera A"),
            selected
        ],
        rememberedOption: DisplayDeviceOption(id: selected.id, name: "Old Camera B"),
        fallback: DisplayDeviceOption(id: "automatic", name: "Automatic")
    )

    #expect(result == selected)
}

@Test func inputDeviceDisplaySelectionKeepsRememberedOptionDuringRefreshGap() {
    let remembered = DisplayDeviceOption(id: "camera-b", name: "Camera B")
    let result = InputDeviceDisplaySelectionPolicy.resolve(
        selectedID: remembered.id,
        availableOptions: [
            DisplayDeviceOption(id: "camera-a", name: "Camera A")
        ],
        rememberedOption: remembered,
        fallback: DisplayDeviceOption(id: "automatic", name: "Automatic")
    )

    #expect(result == remembered)
}

@Test func inputDeviceDisplaySelectionFallsBackWhenSelectionIsUnknown() {
    let fallback = DisplayDeviceOption(id: "automatic", name: "Automatic")
    let result = InputDeviceDisplaySelectionPolicy.resolve(
        selectedID: "missing",
        availableOptions: [
            DisplayDeviceOption(id: "camera-a", name: "Camera A")
        ],
        rememberedOption: DisplayDeviceOption(id: "camera-b", name: "Camera B"),
        fallback: fallback
    )

    #expect(result == fallback)
}
