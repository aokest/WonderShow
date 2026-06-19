import Foundation
import Testing
@testable import PresenterDirector

@Test func buildsStagePresentationRecordingProjectWithRawPresenterAndSlideTracks() {
    let project = RecordingProjectFactory().makeProject(
        scenario: .stagePresentation,
        camera: .external(name: "DJI Osmo Pocket 3"),
        screen: .mainDisplay,
        durationMilliseconds: 600_000
    )

    #expect(project.scenario == .stagePresentation)
    #expect(project.pipeline.inputs == [.camera(.external(name: "DJI Osmo Pocket 3")), .screen(.mainDisplay)])
    #expect(project.rawTracks.map(\.role) == [.presenterCamera, .slidesScreen])
    #expect(project.rawTracks.map(\.archiveOutput) == [.cameraArchive, .screenArchive])
    #expect(project.programOutput == .programRecording)
    #expect(project.timeline.isContiguous)
    #expect(project.timeline.durationMilliseconds == 600_000)
}

@Test func stagePresentationTemplateIncludesSpeakerAndSlideProgramViews() {
    let project = RecordingProjectFactory().makeProject(
        scenario: .stagePresentation,
        camera: .pocket3,
        screen: .mainDisplay,
        durationMilliseconds: 300_000
    )

    #expect(project.timeline.views.contains(.speakerFullBody))
    #expect(project.timeline.views.contains(.speakerCloseUp))
    #expect(project.timeline.views.contains(.slidesWithSpeakerPictureInPicture))
    #expect(project.timeline.views.contains(.slidesFullScreen))

    let pipScene = project.timeline.firstScene(for: .slidesWithSpeakerPictureInPicture)
    #expect(pipScene?.layers.first == .slidesFullCanvas)
    #expect(pipScene?.speakerLayer?.source == .presenterCamera)
    #expect(pipScene?.speakerLayer?.placement == .pictureInPicture(corner: .bottomRight, size: .large))
    #expect(pipScene?.speakerLayer?.speakerShot == .fullBody)
}

@Test func trainingCourseProjectUsesSameCaptureModelWithTrainingSpecificFraming() {
    let factory = RecordingProjectFactory()
    let stageProject = factory.makeProject(
        scenario: .stagePresentation,
        camera: .builtInFaceTime,
        screen: .mainDisplay,
        durationMilliseconds: 300_000
    )
    let trainingProject = factory.makeProject(
        scenario: .trainingCourse,
        camera: .builtInFaceTime,
        screen: .mainDisplay,
        durationMilliseconds: 300_000
    )

    #expect(trainingProject.scenario == .trainingCourse)
    #expect(trainingProject.rawTracks.map(\.role) == stageProject.rawTracks.map(\.role))
    #expect(trainingProject.pipeline.inputs == stageProject.pipeline.inputs)
    #expect(trainingProject.timeline.views.contains(.slidesWithSpeakerPictureInPicture))
    #expect(trainingProject.timeline.views.contains(.slidesFullScreen))

    let trainingPiP = trainingProject.timeline.firstScene(for: .slidesWithSpeakerPictureInPicture)
    #expect(trainingPiP?.speakerLayer?.placement == .pictureInPicture(corner: .topRight, size: .small))
    #expect(trainingPiP?.speakerLayer?.speakerShot == .closeUp)
}

@Test func slidesFullScreenSceneKeepsPPTAsTheOnlyProgramLayer() {
    let project = RecordingProjectFactory().makeProject(
        scenario: .trainingCourse,
        camera: .builtInFaceTime,
        screen: .window(id: 42),
        durationMilliseconds: 180_000
    )

    let slidesScene = project.timeline.firstScene(for: .slidesFullScreen)

    #expect(slidesScene?.layers == [.slidesFullCanvas])
    #expect(slidesScene?.layers.contains { $0.source == .presenterCamera } == false)
}

@Test func timelineSegmentsResolveTheActiveSceneAtAGivenTime() {
    let project = RecordingProjectFactory().makeProject(
        scenario: .trainingCourse,
        camera: .builtInFaceTime,
        screen: .mainDisplay,
        durationMilliseconds: 100_000
    )

    #expect(project.timeline.segment(containingMilliseconds: 0)?.scene.view == .slidesWithSpeakerPictureInPicture)
    #expect(project.timeline.segment(containingMilliseconds: 80_000)?.scene.view == .slidesFullScreen)
    #expect(project.timeline.segment(containingMilliseconds: 99_999)?.scene.view == .speakerCloseUp)
    #expect(project.timeline.segment(containingMilliseconds: 100_000) == nil)
}

@Test func recordingManifestDefinesStableRawAndProgramAssetPaths() {
    let project = RecordingProjectFactory().makeProject(
        scenario: .stagePresentation,
        camera: .pocket3,
        screen: .mainDisplay,
        durationMilliseconds: 120_000
    )
    let manifest = RecordingProjectManifestFactory().makeManifest(project: project)

    #expect(manifest.mediaAssets.map(\.relativePath) == [
        "Raw/presenter-camera.mov",
        "Raw/slides-screen.mov",
        "Raw/microphone.m4a",
        "Exports/program.mp4"
    ])
    #expect(manifest.mediaAssets[0].trackRole == .presenterCamera)
    #expect(manifest.mediaAssets[1].trackRole == .slidesScreen)
    #expect(manifest.mediaAssets[2].trackRole == .microphoneAudio)
    #expect(manifest.mediaAssets[2].output == .microphoneArchive)
    #expect(manifest.mediaAssets[3].trackRole == nil)
    #expect(manifest.mediaAssets[3].output == .programRecording)
}

@Test func explicitScreenOnlyProjectRecordsOnlyTheScreenTrack() {
    let project = RecordingProjectFactory().makeProject(
        scenario: .trainingCourse,
        camera: .builtInFaceTime,
        screen: .mainDisplay,
        mode: .screenOnly,
        layout: .screenOnly,
        durationMilliseconds: 180_000
    )

    #expect(project.pipeline.inputs == [.screen(.mainDisplay)])
    #expect(project.rawTracks.map(\.role) == [.slidesScreen])
    #expect(project.timeline.views == [.slidesFullScreen])
    #expect(project.timeline.segments.first?.scene.layers == [.slidesFullCanvas])
}

@Test func explicitCameraOnlyProjectRecordsOnlyThePresenterTrack() {
    let project = RecordingProjectFactory().makeProject(
        scenario: .trainingCourse,
        camera: .external(name: "USB Camera"),
        screen: .mainDisplay,
        mode: .cameraOnly,
        layout: .speakerCloseUp,
        durationMilliseconds: 180_000
    )

    #expect(project.pipeline.inputs == [.camera(.external(name: "USB Camera"))])
    #expect(project.rawTracks.map(\.role) == [.presenterCamera])
    #expect(project.timeline.views == [.speakerCloseUp])
}

@Test func explicitSpeakerMainProjectPutsSlidesInPictureInPicture() {
    let project = RecordingProjectFactory().makeProject(
        scenario: .stagePresentation,
        camera: .pocket3,
        screen: .window(id: 7),
        mode: .cameraAndScreen,
        layout: .cameraWithScreenPictureInPicture(corner: .topLeft),
        durationMilliseconds: 180_000
    )

    let scene = project.timeline.firstScene(for: .speakerWithSlidesPictureInPicture)
    #expect(scene?.layers.first?.source == .presenterCamera)
    #expect(scene?.layers.first?.placement == .fullCanvas)
    #expect(scene?.layers.last?.source == .slidesScreen)
    #expect(scene?.layers.last?.placement == .pictureInPicture(corner: .topLeft, size: .medium))
}

@Test func explicitPictureInPictureGeometryIsStoredInProgramTimeline() {
    let geometry = ProgramPictureInPictureGeometry(
        centerX: 0.34,
        centerY: 0.42,
        width: 0.24,
        height: 0.18,
        shape: .circle
    )
    let project = RecordingProjectFactory().makeProject(
        scenario: .stagePresentation,
        camera: .pocket3,
        screen: .window(id: 7),
        mode: .cameraAndScreen,
        layout: .screenWithCameraPictureInPicture(corner: .bottomRight),
        durationMilliseconds: 180_000,
        pictureInPictureGeometry: geometry
    )

    let scene = project.timeline.firstScene(for: .slidesWithSpeakerPictureInPicture)
    #expect(scene?.speakerLayer?.placement == .customPictureInPicture(geometry))
}

@Test func explicitSideBySideProjectKeepsPresenterAndSlidesAligned() {
    let project = RecordingProjectFactory().makeProject(
        scenario: .stagePresentation,
        camera: .pocket3,
        screen: .mainDisplay,
        mode: .cameraAndScreen,
        layout: .sideBySide,
        durationMilliseconds: 180_000
    )

    let scene = project.timeline.firstScene(for: .sideBySide)
    #expect(scene?.layers.map(\.placement) == [.leftHalf, .rightHalf])
    #expect(scene?.layers.map(\.source) == [.slidesScreen, .presenterCamera])
}

@Test func recordingProjectManifestRoundTripsThroughJSON() throws {
    let project = RecordingProjectFactory().makeProject(
        scenario: .trainingCourse,
        camera: .builtInFaceTime,
        screen: .window(id: 42),
        durationMilliseconds: 180_000
    )
    let manifest = RecordingProjectManifestFactory().makeManifest(project: project)

    let data = try JSONEncoder().encode(manifest)
    let decoded = try JSONDecoder().decode(RecordingProjectManifest.self, from: data)

    #expect(decoded == manifest)
    #expect(decoded.project.timeline.firstScene(for: .slidesFullScreen)?.layers == [.slidesFullCanvas])
}

@Test func recordingManifestStoresPresenterVideoEffects() throws {
    let project = RecordingProjectFactory().makeProject(
        scenario: .trainingCourse,
        camera: .builtInFaceTime,
        screen: .mainDisplay,
        durationMilliseconds: 180_000
    )
    let effects = PresenterVideoEffects(
        isMirrored: true,
        brightness: 0.2,
        contrast: 1.15,
        beauty: 0.35
    )
    let manifest = RecordingProjectManifestFactory().makeManifest(
        project: project,
        presenterVideoEffects: effects
    )

    let data = try JSONEncoder().encode(manifest)
    let decoded = try JSONDecoder().decode(RecordingProjectManifest.self, from: data)

    #expect(decoded.presenterVideoEffects == effects)
}

@Test func recordingManifestDecodesOldProjectsWithDefaultPresenterVideoEffects() throws {
    let project = RecordingProjectFactory().makeProject(
        scenario: .trainingCourse,
        camera: .builtInFaceTime,
        screen: .mainDisplay,
        durationMilliseconds: 180_000
    )
    let manifest = RecordingProjectManifestFactory().makeManifest(project: project)
    var json = try #require(String(data: JSONEncoder().encode(manifest), encoding: .utf8))
    json = json.replacingOccurrences(
        of: #"{"mediaAssets""#,
        with: #"{"_legacyMarker":true,"mediaAssets""#
    )
    json = json.replacingOccurrences(
        of: #","presenterVideoEffects":{[^}]+}"#,
        with: "",
        options: .regularExpression
    )

    let decoded = try JSONDecoder().decode(
        RecordingProjectManifest.self,
        from: try #require(json.data(using: .utf8))
    )

    #expect(decoded.presenterVideoEffects == .default)
}

@Test func exportSettingsMapResolutionFrameRateQualityAndCodecToStableEncodingParameters() {
    let defaultSettings = RecordingExportSettings.presentationDefault
    let socialHighMotion = RecordingExportSettings(
        resolution: .uhd4k,
        frameRate: .fps60,
        quality: .archival,
        codec: .hevc
    )

    #expect(defaultSettings.resolution.pixelSize?.width == 1920)
    #expect(defaultSettings.resolution.pixelSize?.height == 1080)
    #expect(defaultSettings.frameRate.rawValue == 30)
    #expect(defaultSettings.bitrateBitsPerSecond == 12_000_000)
    #expect(defaultSettings.audioBitrateBitsPerSecond == 192_000)

    #expect(socialHighMotion.resolution.pixelSize?.width == 3840)
    #expect(socialHighMotion.resolution.pixelSize?.height == 2160)
    #expect(socialHighMotion.frameRate.rawValue == 60)
    #expect(socialHighMotion.bitrateBitsPerSecond > defaultSettings.bitrateBitsPerSecond)
    #expect(socialHighMotion.audioBitrateBitsPerSecond == 256_000)

    let compactHevc = RecordingExportSettings(
        resolution: .hd1080,
        frameRate: .fps30,
        quality: .standard,
        codec: .hevc
    )
    #expect(compactHevc.bitrateBitsPerSecond < defaultSettings.bitrateBitsPerSecond)
    #expect(compactHevc.audioBitrateBitsPerSecond == 128_000)
}

@Test func recordingPipelineModelCanRepresentMultipleCameraAndMicrophoneInputs() {
    let pipeline = RecordingPipeline(
        inputs: [
            .camera(.builtInFaceTime),
            .camera(.external(name: "HDMI Capture")),
            .screen(.mainDisplay),
            .microphone(name: "MacBook Microphone"),
            .microphone(name: "Wireless Lavalier")
        ],
        outputs: [.cameraArchive, .screenArchive, .microphoneArchive, .programRecording],
        composition: .pictureInPicture(corner: .bottomRight)
    )

    #expect(pipeline.inputs.contains(.camera(.external(name: "HDMI Capture"))))
    #expect(pipeline.inputs.contains(.microphone(name: "Wireless Lavalier")))
    #expect(pipeline.outputs.contains(.microphoneArchive))
}
