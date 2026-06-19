@testable import PresenterDirectorApp
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
