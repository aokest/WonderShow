@testable import PresenterDirectorApp
import AppKit
import Testing

@Test func sourceSlotsAcceptZeroThroughNine() {
    var slots = RecordingSourceSlots()
    let option = makeWindowOption(id: 42, title: "Demo")

    let invalidLow = slots.assign(option, to: -1)
    let invalidHigh = slots.assign(option, to: 10)
    let assignedZero = slots.assign(option, to: 0)
    let assignedNine = slots.assign(option, to: 9)

    #expect(invalidLow == false)
    #expect(invalidHigh == false)
    #expect(assignedZero)
    #expect(assignedNine)
    #expect(slots.assignment(for: 0) == nil)
    #expect(slots.assignment(for: 9)?.sourceID == .window(42))
    #expect(slots.assignment(for: -1) == nil)
    #expect(slots.assignment(for: 10) == nil)
}

@Test func sourceSlotsMoveSourceWhenAssignedToANewSlot() {
    var slots = RecordingSourceSlots()
    let option = makeWindowOption(id: 42, title: "Demo")

    let firstAssign = slots.assign(option, to: 1)
    let secondAssign = slots.assign(option, to: 3)

    #expect(firstAssign)
    #expect(secondAssign)

    #expect(slots.assignment(for: 1) == nil)
    #expect(slots.assignment(for: 3)?.sourceID == .window(42))
    #expect(slots.slot(for: .window(42)) == 3)
}

@Test func sourceSlotsReplaceExistingSlotAssignment() {
    var slots = RecordingSourceSlots()
    let first = makeWindowOption(id: 10, title: "Slides")
    let second = makeDisplayOption(id: 99, title: "Screen 1")

    let firstAssign = slots.assign(first, to: 2)
    let secondAssign = slots.assign(second, to: 2)

    #expect(firstAssign)
    #expect(secondAssign)

    #expect(slots.assignment(for: 2)?.sourceID == .display(99))
    #expect(slots.slot(for: .window(10)) == nil)
}

@Test func sourceSlotsRejectManualConflictWithoutReplacingExistingAssignment() {
    var slots = RecordingSourceSlots()
    let first = makeWindowOption(id: 10, title: "Slides")
    let second = makeWindowOption(id: 20, title: "Notes")

    #expect(slots.assignWithoutReplacingOccupiedSlot(first, to: 1) == .assigned)
    let result = slots.assignWithoutReplacingOccupiedSlot(second, to: 1)

    guard case .slotOccupied(let existing) = result else {
        Issue.record("Expected slot conflict")
        return
    }

    #expect(existing.sourceID == .window(10))
    #expect(slots.assignment(for: 1)?.sourceID == .window(10))
    #expect(slots.slot(for: .window(20)) == nil)
}

@Test func sourceSlotsAutoAssignAvailableSourcesWithoutOverwritingCustomSlots() {
    let first = makeWindowOption(id: 10, title: "Slides")
    let second = makeWindowOption(id: 20, title: "Notes")
    let third = makeWindowOption(id: 30, title: "Browser")
    var slots = RecordingSourceSlots()

    #expect(slots.assignWithoutReplacingOccupiedSlot(second, to: 3) == .assigned)
    let changed = slots.assignDefaultSlots(
        for: [first, second, third],
        featureTier: .vip
    )

    #expect(changed)
    #expect(slots.assignment(for: 1)?.sourceID == .window(10))
    #expect(slots.assignment(for: 2)?.sourceID == .window(30))
    #expect(slots.assignment(for: 3)?.sourceID == .window(20))
}

@Test func sourceSlotsAutoAssignPrioritizesWindowsBeforeDisplays() {
    var slots = RecordingSourceSlots()
    let display = makeDisplayOption(id: 99, title: "Ultra Wide")
    let browser = makeWindowOption(id: 10, title: "Browser")
    let notes = makeWindowOption(id: 20, title: "Notes")

    let changed = slots.assignDefaultSlots(
        for: [display, browser, notes],
        featureTier: .vip
    )

    #expect(changed)
    #expect(slots.assignment(for: 1)?.sourceID == .window(10))
    #expect(slots.assignment(for: 2)?.sourceID == .window(20))
    #expect(slots.assignment(for: 3)?.sourceID == .display(99))
}

@Test func sourceSlotsRebalancesLegacyAutoDisplaySlotsToWindowFirstDefaults() {
    let display = makeDisplayOption(id: 99, title: "Ultra Wide")
    let browser = makeWindowOption(id: 10, title: "Browser")
    let notes = makeWindowOption(id: 20, title: "Notes")
    let legacyAutoAssignments = [
        RecordingSourceSlotAssignment(slot: 1, option: display, isUserDefined: false),
        RecordingSourceSlotAssignment(slot: 2, option: browser, isUserDefined: false)
    ]
    var slots = RecordingSourceSlots(assignments: legacyAutoAssignments)

    let changed = slots.assignDefaultSlots(
        for: [display, browser, notes],
        featureTier: .vip
    )

    #expect(changed)
    #expect(slots.assignment(for: 1)?.sourceID == .window(10))
    #expect(slots.assignment(for: 2)?.sourceID == .window(20))
    #expect(slots.assignment(for: 3)?.sourceID == .display(99))
}

@Test func sourceSlotsAutoAssignRespectsFeatureTier() {
    var slots = RecordingSourceSlots()
    let options = [
        makeWindowOption(id: 10, title: "One"),
        makeWindowOption(id: 20, title: "Two"),
        makeWindowOption(id: 30, title: "Three")
    ]

    let changed = slots.assignDefaultSlots(for: options, featureTier: .free)

    #expect(changed)
    #expect(slots.assignment(for: 1)?.sourceID == .window(10))
    #expect(slots.assignment(for: 2)?.sourceID == .window(20))
    #expect(slots.slot(for: .window(30)) == nil)
}

@Test func sourceSlotsResolveOnlyCurrentlyAvailableSources() {
    var slots = RecordingSourceSlots()
    let window = makeWindowOption(id: 42, title: "Demo")
    let display = makeDisplayOption(id: 99, title: "Screen 1")

    let windowAssign = slots.assign(window, to: 1)
    let displayAssign = slots.assign(display, to: 2)

    #expect(windowAssign)
    #expect(displayAssign)

    let available = [display]

    #expect(slots.resolvedPreference(for: 1, availableOptions: available) == nil)
    #expect(slots.resolvedPreference(for: 2, availableOptions: available) == .selectedDisplay(99))
}

@Test func sourceSlotsResolveWindowPreferenceThroughExistingScreenCapturePath() {
    var slots = RecordingSourceSlots()
    let option = makeWindowOption(id: 42, title: "Demo")

    let assigned = slots.assign(option, to: 4)

    #expect(assigned)

    #expect(slots.resolvedPreference(for: 4, availableOptions: [option]) == .selectedWindows([42]))
}

@Test func sourceSlotHotKeysAcceptCommandZeroThroughNine() {
    #expect(
        RecordingSourceSlotHotKey.slot(
            charactersIgnoringModifiers: "0",
            modifierFlags: .command
        ) == 0
    )
    #expect(
        RecordingSourceSlotHotKey.slot(
            charactersIgnoringModifiers: "1",
            modifierFlags: .command
        ) == 1
    )
    #expect(
        RecordingSourceSlotHotKey.slot(
            charactersIgnoringModifiers: "9",
            modifierFlags: .command
        ) == 9
    )
    #expect(
        RecordingSourceSlotHotKey.slot(
            charactersIgnoringModifiers: "-",
            modifierFlags: .command
        ) == nil
    )
    #expect(
        RecordingSourceSlotHotKey.slot(
            charactersIgnoringModifiers: "2",
            modifierFlags: [.command, .capsLock]
        ) == 2
    )
    #expect(
        RecordingSourceSlotHotKey.slot(
            charactersIgnoringModifiers: "1",
            modifierFlags: [.command, .option]
        ) == nil
    )
    #expect(
        RecordingSourceSlotHotKey.slot(
            charactersIgnoringModifiers: "r",
            modifierFlags: [.command, .option]
        ) == nil
    )
}

@Test func sourceSlotTiersGateShortcutDefinitions() {
    #expect(RecordingFeatureTier.free.sourceSlotRange == 1...2)
    #expect(RecordingFeatureTier.vip.sourceSlotRange == 1...6)
    #expect(RecordingFeatureTier.svip.sourceSlotRange == 0...9)

    #expect(RecordingFeatureTier.free.permitsSourceSlot(1))
    #expect(RecordingFeatureTier.free.permitsSourceSlot(2))
    #expect(!RecordingFeatureTier.free.permitsSourceSlot(0))
    #expect(!RecordingFeatureTier.free.permitsSourceSlot(3))

    #expect(RecordingFeatureTier.vip.permitsSourceSlot(6))
    #expect(!RecordingFeatureTier.vip.permitsSourceSlot(0))
    #expect(!RecordingFeatureTier.vip.permitsSourceSlot(7))

    #expect(RecordingFeatureTier.svip.permitsSourceSlot(0))
    #expect(RecordingFeatureTier.svip.permitsSourceSlot(9))
}

private func makeWindowOption(
    id: UInt32,
    title: String,
    app: String = "Keynote"
) -> ScreenCaptureWindowOption {
    ScreenCaptureWindowOption(
        id: .window(id),
        applicationName: app,
        title: title,
        width: 1280,
        height: 720
    )
}

private func makeDisplayOption(
    id: UInt32,
    title: String
) -> ScreenCaptureWindowOption {
    ScreenCaptureWindowOption(
        id: .display(id),
        applicationName: "Display",
        title: title,
        width: 3024,
        height: 1964
    )
}
