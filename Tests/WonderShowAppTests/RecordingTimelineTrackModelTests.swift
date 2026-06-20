@testable import WonderShow
@testable import WonderShowApp
import Foundation
import Testing

@Test func timelineTrackModelBuildsRowsFromManifestAssetsAndSegments() {
    let project = RecordingProjectFactory().makeProject(
        scenario: .trainingCourse,
        camera: .builtInFaceTime,
        screen: .mainDisplay,
        durationMilliseconds: 10_000
    )
    let manifest = RecordingProjectManifestFactory().makeManifest(project: project)
    let rows = RecordingTimelineTrackModel.rows(
        manifest: manifest,
        fileStates: [
            "Raw/presenter-camera.mov": .ready,
            "Raw/slides-screen.mov": .writing,
            "Raw/microphone.m4a": .missing,
            "Exports/program.mp4": .missing
        ],
        fallbackDurationMilliseconds: 10_000
    )

    #expect(rows.map(\.role) == [.slidesScreen, .presenterCamera, .microphoneAudio, nil])
    #expect(rows[0].segments.map(\.fraction) == [0.7, 0.2, 0.1])
    #expect(rows[0].segments.map(\.startMilliseconds) == [0, 7_000, 9_000])
    #expect(rows[0].segments.map(\.endMilliseconds) == [7_000, 9_000, 10_000])
    #expect(rows[0].state == .writing)
    #expect(rows[1].state == .ready)
    #expect(rows[2].state == .missing)
}

@Test func timelineSelectionClampsExportRangesToTimelineDuration() {
    let selection = TimelineSelection(
        ranges: [
            TimelineExportRange(startMilliseconds: -200, endMilliseconds: 2_000),
            TimelineExportRange(startMilliseconds: 8_000, endMilliseconds: 12_000),
            TimelineExportRange(startMilliseconds: 4_000, endMilliseconds: 3_000)
        ]
    )

    #expect(selection.normalized(durationMilliseconds: 10_000).ranges == [
        TimelineExportRange(startMilliseconds: 0, endMilliseconds: 2_000),
        TimelineExportRange(startMilliseconds: 8_000, endMilliseconds: 10_000)
    ])
}
