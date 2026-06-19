@testable import PresenterDirectorApp
import AppKit
import Testing

@Test func recordingControlSurfaceFormatsElapsedTimeAndActions() {
    let idle = RecordingControlSurfaceState(controlState: .idle, elapsedSeconds: 0)
    let recording = RecordingControlSurfaceState(controlState: .recording, elapsedSeconds: 3_661)
    let paused = RecordingControlSurfaceState(controlState: .paused, elapsedSeconds: 65)

    #expect(idle.primaryAction == .start)
    #expect(idle.elapsedTimecode == "00:00:00")
    #expect(recording.primaryAction == .pause)
    #expect(recording.stopEnabled)
    #expect(recording.elapsedTimecode == "01:01:01")
    #expect(paused.primaryAction == .resume)
    #expect(paused.elapsedTimecode == "00:01:05")
}

@Test func recordingControlSurfaceKeepsStartingStateNonDestructive() {
    let state = RecordingControlSurfaceState(controlState: .starting, elapsedSeconds: 2)

    #expect(state.primaryAction == .cancelStart)
    #expect(state.stopEnabled == false)
}

@MainActor
@Test func miniToolbarDefaultsBelowTheMenuBarNearTopCenter() {
    let visibleFrame = NSRect(x: 0, y: 0, width: 1440, height: 840)
    let panelSize = NSSize(width: 350, height: 54)

    let frame = WonderShowAppCoordinator.defaultMiniToolbarFrame(
        visibleFrame: visibleFrame,
        panelSize: panelSize
    )

    #expect(frame.width == panelSize.width)
    #expect(frame.height == panelSize.height)
    #expect(frame.midX == visibleFrame.midX)
    #expect(frame.maxY == visibleFrame.maxY - 12)
}

@Test func recordingControlHotKeysUseExplicitNonSystemCombos() {
    #expect(
        RecordingControlHotKey.action(
            charactersIgnoringModifiers: "r",
            modifierFlags: [.command, .option]
        ) == .toggleStartPauseResume
    )
    #expect(
        RecordingControlHotKey.action(
            charactersIgnoringModifiers: "p",
            modifierFlags: [.command, .option]
        ) == .pauseResume
    )
    #expect(
        RecordingControlHotKey.action(
            charactersIgnoringModifiers: ".",
            modifierFlags: [.command, .option]
        ) == .finish
    )
}

@Test func recordingControlHotKeysRejectSourceSlotAndSystemLikeCombos() {
    #expect(
        RecordingControlHotKey.action(
            charactersIgnoringModifiers: "1",
            modifierFlags: [.command]
        ) == nil
    )
    #expect(
        RecordingControlHotKey.action(
            charactersIgnoringModifiers: "r",
            modifierFlags: [.command]
        ) == nil
    )
    #expect(
        RecordingControlHotKey.action(
            charactersIgnoringModifiers: "p",
            modifierFlags: [.command, .option, .shift]
        ) == nil
    )
}
