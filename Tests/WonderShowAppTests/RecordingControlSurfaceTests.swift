@testable import WonderShowApp
@testable import WonderShow
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

@MainActor
@Test func recordingControllerPersistsPresenterVideoEffectsUpdatesDuringActiveRecording() throws {
    let controller = PresentationCommandController()
    controller.toggleRecording(
        scenario: .trainingCourse,
        cameraName: "Built-in Camera",
        mode: .cameraOnly,
        layout: .speakerFullBody,
        presenterVideoEffects: PresenterVideoEffects(brightness: 0.1, contrast: 1.05, beauty: 0.1)
    )
    let startedSession = try #require(controller.lastRecordingSession)

    let updatedEffects = PresenterVideoEffects(
        brightness: 0.28,
        contrast: 1.24,
        beauty: 0.34,
        isSubjectAwareBeautyEnabled: true,
        skinSmoothing: 0.4,
        skinBrightening: 0.3,
        skinWhitening: 0.2,
        blemishReduction: 0.18,
        complexion: 0.16,
        beautyStyle: .bright
    )
    controller.updateLastRecordingPresenterVideoEffects(updatedEffects)

    let updatedSession = try #require(controller.lastRecordingSession)
    let manifestData = try Data(contentsOf: updatedSession.manifestURL)
    let manifest = try JSONDecoder().decode(RecordingProjectManifest.self, from: manifestData)

    #expect(updatedSession.url == startedSession.url)
    #expect(updatedSession.manifest.presenterVideoEffects == updatedEffects)
    #expect(manifest.presenterVideoEffects == updatedEffects)

    controller.toggleRecording()
    try? FileManager.default.removeItem(at: startedSession.url)
}
