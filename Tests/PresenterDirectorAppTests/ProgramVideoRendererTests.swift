@testable import PresenterDirector
@testable import PresenterDirectorApp
@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import Testing

@Suite(.serialized)
struct ProgramVideoRendererTests {
@Test func programVideoRendererWritesSelectedVideoCodecResolutionAndFrameRate() async throws {
    let fileManager = FileManager.default
    let rootURL = fileManager.temporaryDirectory
        .appendingPathComponent("lingyan-program-renderer-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(at: rootURL.appendingPathComponent("Raw", isDirectory: true), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: rootURL.appendingPathComponent("Exports", isDirectory: true), withIntermediateDirectories: true)
    defer {
        try? fileManager.removeItem(at: rootURL)
    }

    let cameraURL = rootURL.appendingPathComponent("Raw/presenter-camera.mov")
    let screenURL = rootURL.appendingPathComponent("Raw/slides-screen.mov")
    let microphoneURL = rootURL.appendingPathComponent("Raw/microphone.m4a")
    try makeTestVideo(url: cameraURL, size: CGSize(width: 640, height: 360), color: .camera)
    try makeTestVideo(url: screenURL, size: CGSize(width: 960, height: 540), color: .screen)
    try makeSilentAudio(url: microphoneURL)

    let project = RecordingProjectFactory().makeProject(
        scenario: .trainingCourse,
        camera: .builtInFaceTime,
        screen: .mainDisplay,
        mode: .cameraAndScreen,
        layout: .screenWithCameraPictureInPicture(corner: .bottomRight),
        durationMilliseconds: 1_000
    )
    let session = RecordingSessionRecord(
        url: rootURL,
        manifestURL: rootURL.appendingPathComponent("project.json"),
        presenterCameraURL: cameraURL,
        slidesScreenURL: screenURL,
        microphoneAudioURL: microphoneURL,
        programOutputURL: rootURL.appendingPathComponent("Exports/program.mp4"),
        manifest: RecordingProjectManifestFactory().makeManifest(project: project)
    )

    let h264URL = rootURL.appendingPathComponent("Exports/h264-1080p.mp4")
    let h264Settings = RecordingExportSettings(
        resolution: .hd1080,
        frameRate: .fps30,
        quality: .high,
        codec: .h264
    )
    _ = try await ProgramVideoRenderer().render(session: session, settings: h264Settings, outputURL: h264URL)
    let h264Probe = try await probe(url: h264URL)
    #expect(h264Probe.codec == AVVideoCodecType.h264.rawValue)
    #expect(h264Probe.width == 1920)
    #expect(h264Probe.height == 1080)
    #expect(abs(h264Probe.frameRate - 30) < 0.5)
    #expect(h264Probe.hasAudio)
    #expect(h264Probe.audioDurationSeconds > 0.9)

    let hevcURL = rootURL.appendingPathComponent("Exports/hevc-1440p.mp4")
    let hevcSettings = RecordingExportSettings(
        resolution: .qhd1440,
        frameRate: .fps60,
        quality: .standard,
        codec: .hevc
    )
    _ = try await ProgramVideoRenderer().render(session: session, settings: hevcSettings, outputURL: hevcURL)
    let hevcProbe = try await probe(url: hevcURL)
    #expect(hevcProbe.codec == AVVideoCodecType.hevc.rawValue)
    #expect(hevcProbe.width == 2560)
    #expect(hevcProbe.height == 1440)
    #expect(abs(hevcProbe.frameRate - 60) < 0.5)
    #expect(hevcProbe.hasAudio)
    #expect(hevcProbe.audioDurationSeconds > 0.9)
}

@Test func programVideoRendererExportsSelectedTimelineRange() async throws {
    let fileManager = FileManager.default
    let rootURL = fileManager.temporaryDirectory
        .appendingPathComponent("lingyan-program-renderer-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(at: rootURL.appendingPathComponent("Raw", isDirectory: true), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: rootURL.appendingPathComponent("Exports", isDirectory: true), withIntermediateDirectories: true)
    defer {
        try? fileManager.removeItem(at: rootURL)
    }

    let cameraURL = rootURL.appendingPathComponent("Raw/presenter-camera.mov")
    let screenURL = rootURL.appendingPathComponent("Raw/slides-screen.mov")
    try makeTestVideo(url: cameraURL, size: CGSize(width: 640, height: 360), color: .camera, duration: 2)
    try makeTestVideo(url: screenURL, size: CGSize(width: 960, height: 540), color: .screen, duration: 2)

    let project = RecordingProjectFactory().makeProject(
        scenario: .trainingCourse,
        camera: .builtInFaceTime,
        screen: .mainDisplay,
        mode: .cameraAndScreen,
        layout: .screenWithCameraPictureInPicture(corner: .bottomRight),
        durationMilliseconds: 2_000
    )
    let session = RecordingSessionRecord(
        url: rootURL,
        manifestURL: rootURL.appendingPathComponent("project.json"),
        presenterCameraURL: cameraURL,
        slidesScreenURL: screenURL,
        microphoneAudioURL: rootURL.appendingPathComponent("Raw/microphone.m4a"),
        programOutputURL: rootURL.appendingPathComponent("Exports/program.mp4"),
        manifest: RecordingProjectManifestFactory().makeManifest(project: project)
    )

    let outputURL = rootURL.appendingPathComponent("Exports/selection.mp4")
    _ = try await ProgramVideoRenderer().render(
        session: session,
        settings: RecordingExportSettings(resolution: .source, frameRate: .fps30, quality: .high, codec: .h264),
        outputURL: outputURL,
        selectedRange: TimelineExportRange(startMilliseconds: 400, endMilliseconds: 1_200)
    )

    let asset = AVURLAsset(url: outputURL)
    let duration = try await asset.load(.duration).seconds
    #expect(duration > 0.65)
    #expect(duration < 0.95)
}

@Test func programVideoRendererUsesManifestPictureInPictureGeometry() async throws {
    let fileManager = FileManager.default
    let rootURL = fileManager.temporaryDirectory
        .appendingPathComponent("lingyan-program-renderer-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(at: rootURL.appendingPathComponent("Raw", isDirectory: true), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: rootURL.appendingPathComponent("Exports", isDirectory: true), withIntermediateDirectories: true)
    defer {
        try? fileManager.removeItem(at: rootURL)
    }

    let cameraURL = rootURL.appendingPathComponent("Raw/presenter-camera.mov")
    let screenURL = rootURL.appendingPathComponent("Raw/slides-screen.mov")
    try makeTestVideo(url: cameraURL, size: CGSize(width: 640, height: 360), color: .camera)
    try makeTestVideo(url: screenURL, size: CGSize(width: 960, height: 540), color: .screen)

    let geometry = ProgramPictureInPictureGeometry(
        centerX: 0.25,
        centerY: 0.30,
        width: 0.20,
        height: 0.20,
        shape: .square
    )
    let project = RecordingProjectFactory().makeProject(
        scenario: .trainingCourse,
        camera: .builtInFaceTime,
        screen: .mainDisplay,
        mode: .cameraAndScreen,
        layout: .screenWithCameraPictureInPicture(corner: .bottomRight),
        durationMilliseconds: 1_000,
        pictureInPictureGeometry: geometry
    )
    let session = RecordingSessionRecord(
        url: rootURL,
        manifestURL: rootURL.appendingPathComponent("project.json"),
        presenterCameraURL: cameraURL,
        slidesScreenURL: screenURL,
        microphoneAudioURL: rootURL.appendingPathComponent("Raw/microphone.m4a"),
        programOutputURL: rootURL.appendingPathComponent("Exports/program.mp4"),
        manifest: RecordingProjectManifestFactory().makeManifest(project: project)
    )

    let outputURL = rootURL.appendingPathComponent("Exports/custom-pip.mp4")
    let settings = RecordingExportSettings(
        resolution: .source,
        frameRate: .fps30,
        quality: .high,
        codec: .h264
    )
    _ = try await ProgramVideoRenderer().render(session: session, settings: settings, outputURL: outputURL)

    let image = try firstFrameImage(from: outputURL)
    let pipPixel = try #require(pixel(in: image, x: 240, y: 162))
    let backgroundPixel = try #require(pixel(in: image, x: 850, y: 470))

    #expect(pipPixel.red > 170)
    #expect(pipPixel.blue < 140)
    #expect(backgroundPixel.blue > 180)
}

@Test func programVideoRendererAppliesCircularPictureInPictureMask() async throws {
    let fileManager = FileManager.default
    let rootURL = fileManager.temporaryDirectory
        .appendingPathComponent("lingyan-program-renderer-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(at: rootURL.appendingPathComponent("Raw", isDirectory: true), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: rootURL.appendingPathComponent("Exports", isDirectory: true), withIntermediateDirectories: true)
    defer {
        try? fileManager.removeItem(at: rootURL)
    }

    let cameraURL = rootURL.appendingPathComponent("Raw/presenter-camera.mov")
    let screenURL = rootURL.appendingPathComponent("Raw/slides-screen.mov")
    try makeTestVideo(url: cameraURL, size: CGSize(width: 640, height: 360), color: .camera)
    try makeTestVideo(url: screenURL, size: CGSize(width: 960, height: 540), color: .screen)

    let geometry = ProgramPictureInPictureGeometry(
        centerX: 0.50,
        centerY: 0.50,
        width: 0.24,
        height: 0.24,
        shape: .circle
    )
    let project = RecordingProjectFactory().makeProject(
        scenario: .trainingCourse,
        camera: .builtInFaceTime,
        screen: .mainDisplay,
        mode: .cameraAndScreen,
        layout: .screenWithCameraPictureInPicture(corner: .bottomRight),
        durationMilliseconds: 1_000,
        pictureInPictureGeometry: geometry
    )
    let session = RecordingSessionRecord(
        url: rootURL,
        manifestURL: rootURL.appendingPathComponent("project.json"),
        presenterCameraURL: cameraURL,
        slidesScreenURL: screenURL,
        microphoneAudioURL: rootURL.appendingPathComponent("Raw/microphone.m4a"),
        programOutputURL: rootURL.appendingPathComponent("Exports/program.mp4"),
        manifest: RecordingProjectManifestFactory().makeManifest(project: project)
    )

    let outputURL = rootURL.appendingPathComponent("Exports/circle-pip.mp4")
    _ = try await ProgramVideoRenderer().render(
        session: session,
        settings: RecordingExportSettings(resolution: .source, frameRate: .fps30, quality: .high, codec: .h264),
        outputURL: outputURL
    )

    let image = try firstFrameImage(from: outputURL)
    let centerPixel = try #require(pixel(in: image, x: 480, y: 270))
    let cornerPixel = try #require(pixel(in: image, x: 370, y: 160))

    #expect(centerPixel.red > 170)
    #expect(cornerPixel.blue > 180)
}

@Test func programVideoRendererUsesPictureInPictureKeyframeTimeline() async throws {
    let fileManager = FileManager.default
    let rootURL = fileManager.temporaryDirectory
        .appendingPathComponent("lingyan-program-renderer-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(at: rootURL.appendingPathComponent("Raw", isDirectory: true), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: rootURL.appendingPathComponent("Exports", isDirectory: true), withIntermediateDirectories: true)
    defer {
        try? fileManager.removeItem(at: rootURL)
    }

    let cameraURL = rootURL.appendingPathComponent("Raw/presenter-camera.mov")
    let screenURL = rootURL.appendingPathComponent("Raw/slides-screen.mov")
    try makeTestVideo(url: cameraURL, size: CGSize(width: 640, height: 360), color: .camera)
    try makeTestVideo(url: screenURL, size: CGSize(width: 960, height: 540), color: .screen)

    let leftGeometry = ProgramPictureInPictureGeometry(
        centerX: 0.25,
        centerY: 0.50,
        width: 0.18,
        height: 0.18,
        shape: .square
    )
    let rightGeometry = ProgramPictureInPictureGeometry(
        centerX: 0.75,
        centerY: 0.50,
        width: 0.18,
        height: 0.18,
        shape: .square
    )
    let project = RecordingProjectFactory().makeProject(
        scenario: .trainingCourse,
        camera: .builtInFaceTime,
        screen: .mainDisplay,
        mode: .cameraAndScreen,
        layout: .screenWithCameraPictureInPicture(corner: .bottomRight),
        durationMilliseconds: 1_000,
        pictureInPictureGeometry: leftGeometry
    )
    let manifest = RecordingProjectManifestFactory()
        .makeManifest(project: project)
        .updatingPictureInPictureKeyframes([
            RecordingPiPKeyframe(milliseconds: 0, geometry: leftGeometry),
            RecordingPiPKeyframe(milliseconds: 500, geometry: rightGeometry)
        ])
    let session = RecordingSessionRecord(
        url: rootURL,
        manifestURL: rootURL.appendingPathComponent("project.json"),
        presenterCameraURL: cameraURL,
        slidesScreenURL: screenURL,
        microphoneAudioURL: rootURL.appendingPathComponent("Raw/microphone.m4a"),
        programOutputURL: rootURL.appendingPathComponent("Exports/program.mp4"),
        manifest: manifest
    )

    let outputURL = rootURL.appendingPathComponent("Exports/keyframed-pip.mp4")
    _ = try await ProgramVideoRenderer().render(
        session: session,
        settings: RecordingExportSettings(resolution: .source, frameRate: .fps30, quality: .high, codec: .h264),
        outputURL: outputURL
    )

    let firstHalfImage = try frameImage(from: outputURL, seconds: 0.2)
    let secondHalfImage = try frameImage(from: outputURL, seconds: 0.8)
    let leftFirstPixel = try #require(pixel(in: firstHalfImage, x: 240, y: 270))
    let rightFirstPixel = try #require(pixel(in: firstHalfImage, x: 720, y: 270))
    let leftSecondPixel = try #require(pixel(in: secondHalfImage, x: 240, y: 270))
    let rightSecondPixel = try #require(pixel(in: secondHalfImage, x: 720, y: 270))

    #expect(leftFirstPixel.red > 170)
    #expect(rightFirstPixel.blue > 160)
    #expect(leftSecondPixel.blue > 160)
    #expect(rightSecondPixel.red > 170)
}

@Test func programVideoRendererUsesLayoutKeyframeTimeline() async throws {
    let fileManager = FileManager.default
    let rootURL = fileManager.temporaryDirectory
        .appendingPathComponent("lingyan-program-renderer-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(at: rootURL.appendingPathComponent("Raw", isDirectory: true), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: rootURL.appendingPathComponent("Exports", isDirectory: true), withIntermediateDirectories: true)
    defer {
        try? fileManager.removeItem(at: rootURL)
    }

    let cameraURL = rootURL.appendingPathComponent("Raw/presenter-camera.mov")
    let screenURL = rootURL.appendingPathComponent("Raw/slides-screen.mov")
    try makeTestVideo(url: cameraURL, size: CGSize(width: 640, height: 360), color: .camera)
    try makeTestVideo(url: screenURL, size: CGSize(width: 960, height: 540), color: .screen)

    let screenMainGeometry = ProgramPictureInPictureGeometry(
        centerX: 0.78,
        centerY: 0.72,
        width: 0.18,
        height: 0.18,
        shape: .square
    )
    let speakerMainGeometry = ProgramPictureInPictureGeometry(
        centerX: 0.78,
        centerY: 0.72,
        width: 0.18,
        height: 0.18,
        shape: .square
    )
    let project = RecordingProjectFactory().makeProject(
        scenario: .trainingCourse,
        camera: .builtInFaceTime,
        screen: .mainDisplay,
        mode: .cameraAndScreen,
        layout: .screenWithCameraPictureInPicture(corner: .bottomRight),
        durationMilliseconds: 1_000,
        pictureInPictureGeometry: screenMainGeometry
    )
    let manifest = RecordingProjectManifestFactory()
        .makeManifest(project: project)
        .updatingLayoutKeyframes([
            RecordingLayoutKeyframe(
                milliseconds: 0,
                mode: .cameraAndScreen,
                layout: .screenWithCameraPictureInPicture(corner: .bottomRight),
                pictureInPictureGeometry: screenMainGeometry
            ),
            RecordingLayoutKeyframe(
                milliseconds: 500,
                mode: .cameraAndScreen,
                layout: .cameraWithScreenPictureInPicture(corner: .topRight),
                pictureInPictureGeometry: speakerMainGeometry
            )
        ])
    let session = RecordingSessionRecord(
        url: rootURL,
        manifestURL: rootURL.appendingPathComponent("project.json"),
        presenterCameraURL: cameraURL,
        slidesScreenURL: screenURL,
        microphoneAudioURL: rootURL.appendingPathComponent("Raw/microphone.m4a"),
        programOutputURL: rootURL.appendingPathComponent("Exports/program.mp4"),
        manifest: manifest
    )

    let outputURL = rootURL.appendingPathComponent("Exports/layout-keyframed.mp4")
    _ = try await ProgramVideoRenderer().render(
        session: session,
        settings: RecordingExportSettings(resolution: .source, frameRate: .fps30, quality: .high, codec: .h264),
        outputURL: outputURL
    )

    let firstHalfImage = try frameImage(from: outputURL, seconds: 0.2)
    let secondHalfImage = try frameImage(from: outputURL, seconds: 0.8)
    let firstMainPixel = try #require(pixel(in: firstHalfImage, x: 120, y: 120))
    let secondMainPixel = try #require(pixel(in: secondHalfImage, x: 120, y: 120))

    #expect(firstMainPixel.blue > 160)
    #expect(secondMainPixel.red > 170)
}

@Test func manifestPictureInPictureKeyframesSplitTimelineSegments() {
    let initial = ProgramPictureInPictureGeometry(
        centerX: 0.72,
        centerY: 0.76,
        width: 0.24,
        height: 0.18,
        shape: .roundedRectangle
    )
    let moved = ProgramPictureInPictureGeometry(
        centerX: 0.34,
        centerY: 0.44,
        width: 0.24,
        height: 0.18,
        shape: .circle
    )
    let resized = ProgramPictureInPictureGeometry(
        centerX: 0.40,
        centerY: 0.48,
        width: 0.16,
        height: 0.16,
        shape: .square
    )
    let project = RecordingProjectFactory().makeProject(
        scenario: .trainingCourse,
        camera: .builtInFaceTime,
        screen: .mainDisplay,
        mode: .cameraAndScreen,
        layout: .screenWithCameraPictureInPicture(corner: .bottomRight),
        durationMilliseconds: 10_000,
        pictureInPictureGeometry: initial
    )
    let manifest = RecordingProjectManifestFactory().makeManifest(project: project)

    let updated = manifest.updatingPictureInPictureKeyframes([
        RecordingPiPKeyframe(milliseconds: 0, geometry: initial),
        RecordingPiPKeyframe(milliseconds: 3_200, geometry: moved),
        RecordingPiPKeyframe(milliseconds: 7_600, geometry: resized)
    ])
    let segments = updated.project.timeline.segments

    #expect(updated.project.timeline.isContiguous)
    #expect(segments.map(\.startMilliseconds) == [0, 3_200, 7_600])
    #expect(segments.map(\.endMilliseconds) == [3_200, 7_600, 10_000])
    #expect(customPiPGeometry(in: segments[0].scene) == initial)
    #expect(customPiPGeometry(in: segments[1].scene) == moved)
    #expect(customPiPGeometry(in: segments[2].scene) == resized)
}

@Test func programVideoRendererAppliesPresenterMirrorEffect() async throws {
    let fileManager = FileManager.default
    let rootURL = fileManager.temporaryDirectory
        .appendingPathComponent("lingyan-program-renderer-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(at: rootURL.appendingPathComponent("Raw", isDirectory: true), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: rootURL.appendingPathComponent("Exports", isDirectory: true), withIntermediateDirectories: true)
    defer {
        try? fileManager.removeItem(at: rootURL)
    }

    let cameraURL = rootURL.appendingPathComponent("Raw/presenter-camera.mov")
    let screenURL = rootURL.appendingPathComponent("Raw/slides-screen.mov")
    try makeTestVideo(url: cameraURL, size: CGSize(width: 640, height: 360), color: .cameraSplit)
    try makeTestVideo(url: screenURL, size: CGSize(width: 960, height: 540), color: .screen)

    let project = RecordingProjectFactory().makeProject(
        scenario: .trainingCourse,
        camera: .builtInFaceTime,
        screen: .mainDisplay,
        mode: .cameraOnly,
        layout: .speakerFullBody,
        durationMilliseconds: 1_000
    )
    let manifest = RecordingProjectManifestFactory().makeManifest(
        project: project,
        presenterVideoEffects: PresenterVideoEffects(isMirrored: true)
    )
    let session = RecordingSessionRecord(
        url: rootURL,
        manifestURL: rootURL.appendingPathComponent("project.json"),
        presenterCameraURL: cameraURL,
        slidesScreenURL: screenURL,
        microphoneAudioURL: rootURL.appendingPathComponent("Raw/microphone.m4a"),
        programOutputURL: rootURL.appendingPathComponent("Exports/program.mp4"),
        manifest: manifest
    )

    let outputURL = rootURL.appendingPathComponent("Exports/mirrored.mp4")
    _ = try await ProgramVideoRenderer().render(
        session: session,
        settings: RecordingExportSettings(resolution: .source, frameRate: .fps30, quality: .high, codec: .h264),
        outputURL: outputURL
    )

    let image = try firstFrameImage(from: outputURL)
    let leftPixel = try #require(pixel(in: image, x: 120, y: 180))
    let rightPixel = try #require(pixel(in: image, x: 520, y: 180))

    #expect(leftPixel.green > 170)
    #expect(rightPixel.red > 170)
}

@Test func programVideoRendererAppliesPresenterBrightnessAndContrastEffect() async throws {
    let fileManager = FileManager.default
    let rootURL = fileManager.temporaryDirectory
        .appendingPathComponent("lingyan-program-renderer-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(at: rootURL.appendingPathComponent("Raw", isDirectory: true), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: rootURL.appendingPathComponent("Exports", isDirectory: true), withIntermediateDirectories: true)
    defer {
        try? fileManager.removeItem(at: rootURL)
    }

    let cameraURL = rootURL.appendingPathComponent("Raw/presenter-camera.mov")
    let screenURL = rootURL.appendingPathComponent("Raw/slides-screen.mov")
    try makeTestVideo(url: cameraURL, size: CGSize(width: 640, height: 360), color: .cameraDim)
    try makeTestVideo(url: screenURL, size: CGSize(width: 960, height: 540), color: .screen)

    let project = RecordingProjectFactory().makeProject(
        scenario: .trainingCourse,
        camera: .builtInFaceTime,
        screen: .mainDisplay,
        mode: .cameraOnly,
        layout: .speakerFullBody,
        durationMilliseconds: 1_000
    )
    let manifest = RecordingProjectManifestFactory().makeManifest(
        project: project,
        presenterVideoEffects: PresenterVideoEffects(brightness: 0.25, contrast: 1.2, beauty: 0.2)
    )
    let session = RecordingSessionRecord(
        url: rootURL,
        manifestURL: rootURL.appendingPathComponent("project.json"),
        presenterCameraURL: cameraURL,
        slidesScreenURL: screenURL,
        microphoneAudioURL: rootURL.appendingPathComponent("Raw/microphone.m4a"),
        programOutputURL: rootURL.appendingPathComponent("Exports/program.mp4"),
        manifest: manifest
    )

    let outputURL = rootURL.appendingPathComponent("Exports/brighter.mp4")
    _ = try await ProgramVideoRenderer().render(
        session: session,
        settings: RecordingExportSettings(resolution: .source, frameRate: .fps30, quality: .high, codec: .h264),
        outputURL: outputURL
    )

    let image = try firstFrameImage(from: outputURL)
    let centerPixel = try #require(pixel(in: image, x: 320, y: 180))

    #expect(centerPixel.red > 130)
    #expect(centerPixel.green > 130)
    #expect(centerPixel.blue > 130)
}

@Test func manifestLayoutKeyframesSplitTimelineSegments() {
    let firstGeometry = ProgramPictureInPictureGeometry(
        centerX: 0.78,
        centerY: 0.76,
        width: 0.22,
        height: 0.18,
        shape: .roundedRectangle
    )
    let secondGeometry = ProgramPictureInPictureGeometry(
        centerX: 0.24,
        centerY: 0.26,
        width: 0.18,
        height: 0.18,
        shape: .circle
    )
    let project = RecordingProjectFactory().makeProject(
        scenario: .trainingCourse,
        camera: .builtInFaceTime,
        screen: .mainDisplay,
        mode: .cameraAndScreen,
        layout: .screenWithCameraPictureInPicture(corner: .bottomRight),
        durationMilliseconds: 10_000,
        pictureInPictureGeometry: firstGeometry
    )
    let manifest = RecordingProjectManifestFactory().makeManifest(project: project)

    let updated = manifest.updatingLayoutKeyframes([
        RecordingLayoutKeyframe(
            milliseconds: 0,
            mode: .cameraAndScreen,
            layout: .screenWithCameraPictureInPicture(corner: .bottomRight),
            pictureInPictureGeometry: firstGeometry
        ),
        RecordingLayoutKeyframe(
            milliseconds: 4_000,
            mode: .cameraAndScreen,
            layout: .cameraWithScreenPictureInPicture(corner: .topRight),
            pictureInPictureGeometry: secondGeometry
        )
    ])
    let segments = updated.project.timeline.segments

    #expect(updated.project.timeline.isContiguous)
    #expect(segments.map(\.startMilliseconds) == [0, 4_000])
    #expect(segments.map(\.endMilliseconds) == [4_000, 10_000])
    #expect(segments[0].scene.view == .slidesWithSpeakerPictureInPicture)
    #expect(segments[1].scene.view == .speakerWithSlidesPictureInPicture)
    #expect(customPiPGeometry(in: segments[0].scene) == firstGeometry)
    #expect(customPiPGeometry(in: segments[1].scene) == secondGeometry)
}

@Test func manifestTimelineDurationCanBeFinalizedToActualRecordingLength() {
    let project = RecordingProjectFactory().makeProject(
        scenario: .trainingCourse,
        camera: .builtInFaceTime,
        screen: .mainDisplay,
        mode: .cameraAndScreen,
        layout: .screenWithCameraPictureInPicture(corner: .bottomRight),
        durationMilliseconds: 30 * 60 * 1_000
    )
    let manifest = RecordingProjectManifestFactory().makeManifest(project: project)

    let updated = manifest.updatingTimelineDuration(milliseconds: 52_400)

    #expect(updated.project.timeline.durationMilliseconds == 52_400)
    #expect(updated.project.timeline.isContiguous)
    #expect(updated.project.timeline.segments.first?.startMilliseconds == 0)
    #expect(updated.project.timeline.segments.last?.endMilliseconds == 52_400)
}

@Test func screenCapturePixelSizeUsesRetinaScaleFactor() {
    let size = ScreenArchiveRecorder.capturePixelSize(
        width: 1470,
        height: 956,
        frame: nil,
        displays: [],
        scaleFactor: 2
    )

    #expect(size.width == 2940)
    #expect(size.height == 1912)
}

@Test func screenCaptureStreamOutputSizeUsesNewSourceSizeDuringRecordingSourceSwitch() {
    let switchedWindowSize = ScreenArchiveRecorder.streamOutputSize(
        selectionWidth: 1080,
        selectionHeight: 720
    )

    #expect(switchedWindowSize == ScreenArchiveRecorder.CapturePixelSize(width: 1080, height: 720))
}

@Test func screenCaptureAspectFitRectFillsRecordingCanvasWithoutShifting() {
    let rect = ScreenArchiveRecorder.aspectFitRect(
        sourceSize: CGSize(width: 1080, height: 720),
        targetSize: CGSize(width: 2940, height: 1912)
    )

    #expect(abs(rect.width - 2868) < 0.5)
    #expect(abs(rect.height - 1912) < 0.5)
    #expect(abs(rect.minX - 36) < 0.5)
    #expect(abs(rect.minY) < 0.5)
}

@Test func screenCaptureContentRectUsesRetinaScaleFactorBeforeRecordingNormalization() {
    let rect = ScreenArchiveRecorder.normalizedContentRect(
        CGRect(x: 18, y: 24, width: 540, height: 360),
        pixelSize: CGSize(width: 2940, height: 1912),
        scaleFactor: 2
    )

    #expect(rect == CGRect(x: 36, y: 48, width: 1080, height: 720))
}

@Test func screenCaptureContentRectIgnoresFullFrameAttachment() {
    let rect = ScreenArchiveRecorder.normalizedContentRect(
        CGRect(x: 0, y: 0, width: 1920, height: 1080),
        pixelSize: CGSize(width: 1920, height: 1080),
        scaleFactor: 1
    )

    #expect(rect == nil)
}

@Test func screenCaptureContentRectClampsToPixelBufferBounds() {
    let rect = ScreenArchiveRecorder.normalizedContentRect(
        CGRect(x: 100, y: 50, width: 2000, height: 1200),
        pixelSize: CGSize(width: 1280, height: 720),
        scaleFactor: nil
    )

    #expect(rect == CGRect(x: 100, y: 50, width: 1180, height: 670))
}

@MainActor
@Test func previewReportsEmptyScreenTrackInsteadOfSilentlyDoingNothing() throws {
    let fileManager = FileManager.default
    let rootURL = fileManager.temporaryDirectory
        .appendingPathComponent("lingyan-empty-screen-track-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(at: rootURL.appendingPathComponent("Raw", isDirectory: true), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: rootURL.appendingPathComponent("Exports", isDirectory: true), withIntermediateDirectories: true)
    defer {
        try? fileManager.removeItem(at: rootURL)
    }

    let cameraURL = rootURL.appendingPathComponent("Raw/presenter-camera.mov")
    let screenURL = rootURL.appendingPathComponent("Raw/slides-screen.mov")
    try makeTestVideo(url: cameraURL, size: CGSize(width: 640, height: 360), color: .camera)
    fileManager.createFile(atPath: screenURL.path, contents: Data())

    let project = RecordingProjectFactory().makeProject(
        scenario: .trainingCourse,
        camera: .builtInFaceTime,
        screen: .mainDisplay,
        mode: .cameraAndScreen,
        layout: .screenWithCameraPictureInPicture(corner: .bottomRight),
        durationMilliseconds: 1_000
    )
    let session = RecordingSessionRecord(
        url: rootURL,
        manifestURL: rootURL.appendingPathComponent("project.json"),
        presenterCameraURL: cameraURL,
        slidesScreenURL: screenURL,
        microphoneAudioURL: rootURL.appendingPathComponent("Raw/microphone.m4a"),
        programOutputURL: rootURL.appendingPathComponent("Exports/program.mp4"),
        manifest: RecordingProjectManifestFactory().makeManifest(project: project)
    )
    let controller = PresentationCommandController()

    controller.replaceLastRecordingSessionForTesting(session)
    controller.previewLastProgramExport()

    #expect(controller.lastDeliveryBackend == "录制工程")
    #expect(controller.lastDeliveryDetail.contains("PPT/屏幕原始轨为空"))
    #expect(controller.programPreviewRequest == nil)
}
}

private enum TestVideoColor {
    case camera
    case cameraDim
    case cameraSplit
    case screen
}

private func makeTestVideo(url: URL, size: CGSize, color: TestVideoColor, duration: Int = 1) throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(
        mediaType: .video,
        outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]
    )
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ]
    )
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    let frameCount = max(1, duration) * 30
    for frame in 0..<frameCount {
        while !input.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.002)
        }
        guard let pixelBuffer = makePixelBuffer(size: size, color: color, frame: frame) else {
            continue
        }
        adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
    }
    input.markAsFinished()

    let semaphore = DispatchSemaphore(value: 0)
    writer.finishWriting {
        semaphore.signal()
    }
    semaphore.wait()
    if writer.status != .completed {
        throw writer.error ?? ProgramVideoRendererError.exportFailed("测试视频创建失败")
    }
}

private func makePixelBuffer(size: CGSize, color: TestVideoColor, frame: Int) -> CVPixelBuffer? {
    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(
        kCFAllocatorDefault,
        Int(size.width),
        Int(size.height),
        kCVPixelFormatType_32BGRA,
        nil,
        &buffer
    )
    guard let buffer else {
        return nil
    }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer {
        CVPixelBufferUnlockBaseAddress(buffer, [])
    }
    guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
        return nil
    }
    let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)
    let pulse = UInt8((frame * 5) % 160)

    for y in 0..<height {
        for x in 0..<width {
            let offset = y * bytesPerRow + x * 4
            switch color {
            case .camera:
                pointer[offset] = 90
                pointer[offset + 1] = 80 &+ pulse
                pointer[offset + 2] = 220
            case .cameraDim:
                pointer[offset] = 72
                pointer[offset + 1] = 72
                pointer[offset + 2] = 72
            case .cameraSplit:
                if x < width / 2 {
                    pointer[offset] = 40
                    pointer[offset + 1] = 40
                    pointer[offset + 2] = 220
                } else {
                    pointer[offset] = 40
                    pointer[offset + 1] = 220
                    pointer[offset + 2] = 40
                }
            case .screen:
                pointer[offset] = 210
                pointer[offset + 1] = UInt8((x * 255) / max(1, width - 1))
                pointer[offset + 2] = UInt8((y * 255) / max(1, height - 1))
            }
            pointer[offset + 3] = 255
        }
    }
    return buffer
}

private func makeSilentAudio(url: URL) throws {
    let sampleRate: Double = 48_000
    let channelCount: AVAudioChannelCount = 1
    let durationSeconds: Double = 1
    let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buffer.frameLength = frameCount
    if let channel = buffer.floatChannelData?[0] {
        for index in 0..<Int(frameCount) {
            channel[index] = 0
        }
    }

    let file = try AVAudioFile(
        forWriting: url,
        settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: Int(channelCount),
            AVSampleRateKey: sampleRate,
            AVEncoderBitRateKey: 128_000
        ]
    )
    try file.write(from: buffer)
}

private struct VideoProbe {
    let codec: String
    let width: Int
    let height: Int
    let frameRate: Double
    let hasAudio: Bool
    let audioDurationSeconds: Double
}

private func probe(url: URL) async throws -> VideoProbe {
    let asset = AVURLAsset(url: url)
    let videoTrack = try #require(try await asset.loadTracks(withMediaType: .video).first)
    let formatDescription = try #require((try await videoTrack.load(.formatDescriptions)).first)
    let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
    let codec = fourCharacterCodeString(CMFormatDescriptionGetMediaSubType(formatDescription))
    let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
    let audioDurationSeconds = try await audioTracks.first?.load(.timeRange).duration.seconds ?? 0
    return VideoProbe(
        codec: codec,
        width: Int(dimensions.width),
        height: Int(dimensions.height),
        frameRate: Double(nominalFrameRate),
        hasAudio: !audioTracks.isEmpty,
        audioDurationSeconds: audioDurationSeconds
    )
}

private func fourCharacterCodeString(_ code: FourCharCode) -> String {
    let bytes = [
        UInt8((code >> 24) & 0xff),
        UInt8((code >> 16) & 0xff),
        UInt8((code >> 8) & 0xff),
        UInt8(code & 0xff)
    ]
    return String(bytes: bytes, encoding: .macOSRoman) ?? ""
}

private struct Pixel {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8
}

private func firstFrameImage(from url: URL) throws -> CGImage {
    try frameImage(from: url, seconds: 0.2)
}

private func frameImage(from url: URL, seconds: Double) throws -> CGImage {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    return try generator.copyCGImage(
        at: CMTime(seconds: seconds, preferredTimescale: 600),
        actualTime: nil
    )
}

private func pixel(in image: CGImage, x: Int, y: Int) -> Pixel? {
    guard x >= 0, y >= 0, x < image.width, y < image.height else {
        return nil
    }
    let bytesPerPixel = 4
    let bytesPerRow = image.width * bytesPerPixel
    var data = [UInt8](repeating: 0, count: image.height * bytesPerRow)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: &data,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let offset = y * bytesPerRow + x * bytesPerPixel
    return Pixel(
        red: data[offset],
        green: data[offset + 1],
        blue: data[offset + 2],
        alpha: data[offset + 3]
    )
}

private func customPiPGeometry(in scene: ProgramScene) -> ProgramPictureInPictureGeometry? {
    for layer in scene.layers {
        if case .customPictureInPicture(let geometry) = layer.placement {
            return geometry
        }
    }
    return nil
}
