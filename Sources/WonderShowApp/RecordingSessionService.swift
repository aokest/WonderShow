import Foundation
import WonderShow

struct RecordingSessionRecord: Equatable {
    let url: URL
    let manifestURL: URL
    let presenterCameraURL: URL
    let slidesScreenURL: URL
    let microphoneAudioURL: URL
    let programOutputURL: URL
    let manifest: RecordingProjectManifest
    let presenterCameraSegmentURLs: [URL]
    let slidesScreenSegmentURLs: [URL]
    let microphoneAudioSegmentURLs: [URL]

    init(
        url: URL,
        manifestURL: URL,
        presenterCameraURL: URL,
        slidesScreenURL: URL,
        microphoneAudioURL: URL,
        programOutputURL: URL,
        manifest: RecordingProjectManifest,
        presenterCameraSegmentURLs: [URL]? = nil,
        slidesScreenSegmentURLs: [URL]? = nil,
        microphoneAudioSegmentURLs: [URL]? = nil
    ) {
        self.url = url
        self.manifestURL = manifestURL
        self.presenterCameraURL = presenterCameraURL
        self.slidesScreenURL = slidesScreenURL
        self.microphoneAudioURL = microphoneAudioURL
        self.programOutputURL = programOutputURL
        self.manifest = manifest
        self.presenterCameraSegmentURLs = presenterCameraSegmentURLs ?? [presenterCameraURL]
        self.slidesScreenSegmentURLs = slidesScreenSegmentURLs ?? [slidesScreenURL]
        self.microphoneAudioSegmentURLs = microphoneAudioSegmentURLs ?? [microphoneAudioURL]
    }
}

extension RecordingSessionRecord {
    func replacingManifest(_ manifest: RecordingProjectManifest) -> RecordingSessionRecord {
        RecordingSessionRecord(
            url: url,
            manifestURL: manifestURL,
            presenterCameraURL: presenterCameraURL,
            slidesScreenURL: slidesScreenURL,
            microphoneAudioURL: microphoneAudioURL,
            programOutputURL: programOutputURL,
            manifest: manifest,
            presenterCameraSegmentURLs: presenterCameraSegmentURLs,
            slidesScreenSegmentURLs: slidesScreenSegmentURLs,
            microphoneAudioSegmentURLs: microphoneAudioSegmentURLs
        )
    }

    func appendingArchiveSegment(
        presenterCameraURL: URL?,
        slidesScreenURL: URL?,
        microphoneAudioURL: URL?
    ) -> RecordingSessionRecord {
        RecordingSessionRecord(
            url: url,
            manifestURL: manifestURL,
            presenterCameraURL: self.presenterCameraURL,
            slidesScreenURL: self.slidesScreenURL,
            microphoneAudioURL: self.microphoneAudioURL,
            programOutputURL: programOutputURL,
            manifest: manifest,
            presenterCameraSegmentURLs: presenterCameraURL.map { presenterCameraSegmentURLs + [$0] } ?? presenterCameraSegmentURLs,
            slidesScreenSegmentURLs: slidesScreenURL.map { slidesScreenSegmentURLs + [$0] } ?? slidesScreenSegmentURLs,
            microphoneAudioSegmentURLs: microphoneAudioURL.map { microphoneAudioSegmentURLs + [$0] } ?? microphoneAudioSegmentURLs
        )
    }

    func archiveURLs(forSegment index: Int) -> RecordingArchiveSegmentURLs {
        guard index > 1 else {
            return RecordingArchiveSegmentURLs(
                presenterCameraURL: presenterCameraURL,
                slidesScreenURL: slidesScreenURL,
                microphoneAudioURL: microphoneAudioURL
            )
        }
        return RecordingArchiveSegmentURLs(
            presenterCameraURL: url.appendingPathComponent("Raw/presenter-camera-\(index).mov"),
            slidesScreenURL: url.appendingPathComponent("Raw/slides-screen-\(index).mov"),
            microphoneAudioURL: url.appendingPathComponent("Raw/microphone-\(index).m4a")
        )
    }

    var requiresPresenterCameraTrack: Bool {
        manifest.project.rawTracks.contains { $0.role == .presenterCamera }
    }

    var requiresSlidesScreenTrack: Bool {
        manifest.project.rawTracks.contains { $0.role == .slidesScreen }
    }
}

struct RecordingArchiveSegmentURLs: Equatable, Sendable {
    let presenterCameraURL: URL
    let slidesScreenURL: URL
    let microphoneAudioURL: URL
}

struct RecordingPiPKeyframe: Equatable, Hashable, Sendable {
    let milliseconds: Int
    let geometry: ProgramPictureInPictureGeometry

    init(milliseconds: Int, geometry: ProgramPictureInPictureGeometry) {
        self.milliseconds = max(0, milliseconds)
        self.geometry = geometry
    }
}

struct RecordingLayoutKeyframe: Equatable, Hashable, Sendable {
    let milliseconds: Int
    let mode: RecordingMode
    let layout: RecordingLayout
    let pictureInPictureGeometry: ProgramPictureInPictureGeometry?
    let screenCrop: ProgramLayerSourceCrop?
    let cameraCrop: ProgramLayerSourceCrop?
    let canvasPixelSize: RecordingExportPixelSize?

    init(
        milliseconds: Int,
        mode: RecordingMode,
        layout: RecordingLayout,
        pictureInPictureGeometry: ProgramPictureInPictureGeometry? = nil,
        screenCrop: ProgramLayerSourceCrop? = nil,
        cameraCrop: ProgramLayerSourceCrop? = nil,
        canvasPixelSize: RecordingExportPixelSize? = nil
    ) {
        self.milliseconds = max(0, milliseconds)
        self.mode = mode
        self.layout = layout
        self.pictureInPictureGeometry = pictureInPictureGeometry
        self.screenCrop = screenCrop
        self.cameraCrop = cameraCrop
        self.canvasPixelSize = canvasPixelSize
    }
}

extension RecordingProjectManifest {
    func updatingTimelineDuration(milliseconds durationMilliseconds: Int) -> RecordingProjectManifest {
        let duration = max(1, durationMilliseconds)
        let sourceSegments = project.timeline.segments
        guard !sourceSegments.isEmpty,
              project.timeline.durationMilliseconds != duration else {
            return self
        }

        let oldDuration = max(1, project.timeline.durationMilliseconds)
        var updatedSegments: [TimelineSegment] = []
        for (index, segment) in sourceSegments.enumerated() {
            let start = index == 0
                ? 0
                : min(duration - 1, max(0, (segment.startMilliseconds * duration) / oldDuration))
            let end = index == sourceSegments.count - 1
                ? duration
                : min(duration, max(start + 1, (segment.endMilliseconds * duration) / oldDuration))
            guard start < end else {
                continue
            }
            updatedSegments.append(
                TimelineSegment(
                    startMilliseconds: start,
                    endMilliseconds: end,
                    scene: segment.scene
                )
            )
        }

        guard !updatedSegments.isEmpty else {
            return self
        }

        let updatedProject = RecordingProject(
            scenario: project.scenario,
            pipeline: project.pipeline,
            rawTracks: project.rawTracks,
            programOutput: project.programOutput,
            timeline: RecordingTimeline(segments: updatedSegments)
        )
        return RecordingProjectManifest(
            schemaVersion: schemaVersion,
            project: updatedProject,
            mediaAssets: mediaAssets,
            presenterVideoEffects: presenterVideoEffects
        )
    }

    func updatingLayoutKeyframes(_ keyframes: [RecordingLayoutKeyframe]) -> RecordingProjectManifest {
        let duration = max(1, project.timeline.durationMilliseconds)
        let normalizedKeyframes = normalizedLayoutKeyframes(keyframes, durationMilliseconds: duration)
        guard !normalizedKeyframes.isEmpty else {
            return self
        }

        var updatedSegments: [TimelineSegment] = []
        for (index, keyframe) in normalizedKeyframes.enumerated() {
            let start = keyframe.milliseconds
            let end = index == normalizedKeyframes.count - 1
                ? duration
                : min(duration, max(start + 1, normalizedKeyframes[index + 1].milliseconds))
            guard start < end else {
                continue
            }
            updatedSegments.append(
                TimelineSegment(
                    startMilliseconds: start,
                    endMilliseconds: end,
                    scene: Self.programScene(
                        mode: keyframe.mode,
                        layout: keyframe.layout,
                        geometry: keyframe.pictureInPictureGeometry,
                        screenCrop: keyframe.screenCrop,
                        cameraCrop: keyframe.cameraCrop,
                        canvasPixelSize: keyframe.canvasPixelSize
                    )
                )
            )
        }

        guard !updatedSegments.isEmpty else {
            return self
        }

        let updatedProject = RecordingProject(
            scenario: project.scenario,
            pipeline: project.pipeline,
            rawTracks: project.rawTracks,
            programOutput: project.programOutput,
            timeline: RecordingTimeline(segments: updatedSegments)
        )
        return RecordingProjectManifest(
            schemaVersion: schemaVersion,
            project: updatedProject,
            mediaAssets: mediaAssets,
            presenterVideoEffects: presenterVideoEffects
        )
    }

    func updatingPictureInPictureGeometry(_ geometry: ProgramPictureInPictureGeometry) -> RecordingProjectManifest {
        updatingPictureInPictureKeyframes([
            RecordingPiPKeyframe(milliseconds: 0, geometry: geometry)
        ])
    }

    func updatingPictureInPictureKeyframes(_ keyframes: [RecordingPiPKeyframe]) -> RecordingProjectManifest {
        let normalizedKeyframes = normalizedPictureInPictureKeyframes(keyframes)
        guard let firstGeometry = normalizedKeyframes.first?.geometry else {
            return self
        }

        let updatedSegments = project.timeline.segments.flatMap { segment -> [TimelineSegment] in
            guard segment.scene.hasPictureInPictureLayer else {
                return [segment]
            }

            var activeGeometry = normalizedKeyframes
                .last { $0.milliseconds <= segment.startMilliseconds }?
                .geometry ?? firstGeometry
            var cursor = segment.startMilliseconds
            var pieces: [TimelineSegment] = []

            for keyframe in normalizedKeyframes
                where keyframe.milliseconds > segment.startMilliseconds
                    && keyframe.milliseconds < segment.endMilliseconds {
                if cursor < keyframe.milliseconds {
                    pieces.append(
                        TimelineSegment(
                            startMilliseconds: cursor,
                            endMilliseconds: keyframe.milliseconds,
                            scene: segment.scene.updatingPictureInPictureGeometry(activeGeometry)
                        )
                    )
                }
                activeGeometry = keyframe.geometry
                cursor = keyframe.milliseconds
            }

            if cursor < segment.endMilliseconds {
                pieces.append(
                    TimelineSegment(
                        startMilliseconds: cursor,
                        endMilliseconds: segment.endMilliseconds,
                        scene: segment.scene.updatingPictureInPictureGeometry(activeGeometry)
                    )
                )
            }

            return pieces
        }
        let updatedProject = RecordingProject(
            scenario: project.scenario,
            pipeline: project.pipeline,
            rawTracks: project.rawTracks,
            programOutput: project.programOutput,
            timeline: RecordingTimeline(segments: updatedSegments)
        )
        return RecordingProjectManifest(
            schemaVersion: schemaVersion,
            project: updatedProject,
            mediaAssets: mediaAssets,
            presenterVideoEffects: presenterVideoEffects
        )
    }

    func updatingPresenterVideoEffects(_ effects: PresenterVideoEffects) -> RecordingProjectManifest {
        RecordingProjectManifest(
            schemaVersion: schemaVersion,
            project: project,
            mediaAssets: mediaAssets,
            presenterVideoEffects: effects
        )
    }

    private func normalizedPictureInPictureKeyframes(_ keyframes: [RecordingPiPKeyframe]) -> [RecordingPiPKeyframe] {
        var normalized: [RecordingPiPKeyframe] = []
        for keyframe in keyframes.sorted(by: { $0.milliseconds < $1.milliseconds }) {
            if let last = normalized.last, last.milliseconds == keyframe.milliseconds {
                normalized[normalized.count - 1] = keyframe
                continue
            }
            if normalized.last?.geometry == keyframe.geometry {
                continue
            }
            normalized.append(keyframe)
        }
        return normalized
    }

    private func normalizedLayoutKeyframes(
        _ keyframes: [RecordingLayoutKeyframe],
        durationMilliseconds: Int
    ) -> [RecordingLayoutKeyframe] {
        var normalized: [RecordingLayoutKeyframe] = []
        for keyframe in keyframes.sorted(by: { $0.milliseconds < $1.milliseconds }) {
            guard keyframe.milliseconds < durationMilliseconds else {
                continue
            }
            if let last = normalized.last, last.milliseconds == keyframe.milliseconds {
                normalized[normalized.count - 1] = keyframe
                continue
            }
            if let last = normalized.last,
               last.mode == keyframe.mode,
               last.layout == keyframe.layout,
               last.pictureInPictureGeometry == keyframe.pictureInPictureGeometry,
               last.screenCrop == keyframe.screenCrop,
               last.cameraCrop == keyframe.cameraCrop,
               last.canvasPixelSize == keyframe.canvasPixelSize {
                continue
            }
            normalized.append(keyframe)
        }

        guard let first = normalized.first else {
            return []
        }
        if first.milliseconds > 0 {
            normalized.insert(
                RecordingLayoutKeyframe(
                    milliseconds: 0,
                    mode: first.mode,
                    layout: first.layout,
                    pictureInPictureGeometry: first.pictureInPictureGeometry,
                    screenCrop: first.screenCrop,
                    cameraCrop: first.cameraCrop,
                    canvasPixelSize: first.canvasPixelSize
                ),
                at: 0
            )
        }
        return normalized
    }

    private static func programScene(
        mode: RecordingMode,
        layout: RecordingLayout,
        geometry: ProgramPictureInPictureGeometry?,
        screenCrop: ProgramLayerSourceCrop? = nil,
        cameraCrop: ProgramLayerSourceCrop? = nil,
        canvasPixelSize: RecordingExportPixelSize? = nil
    ) -> ProgramScene {
        let scene: ProgramScene
        switch mode {
        case .screenOnly:
            scene = ProgramScene(view: .slidesFullScreen, layers: [.slidesFullCanvas])
        case .cameraOnly:
            if layout == .speakerFullBody {
                scene = ProgramScene(view: .speakerFullBody, layers: [.speakerFullBodyCanvas])
            } else {
                scene = ProgramScene(view: .speakerCloseUp, layers: [.speakerCloseUpCanvas])
            }
        case .cameraAndScreen:
            switch layout {
            case .screenOnly:
                scene = ProgramScene(view: .slidesFullScreen, layers: [.slidesFullCanvas])
            case .speakerFullBody:
                scene = ProgramScene(view: .speakerFullBody, layers: [.speakerFullBodyCanvas])
            case .speakerCloseUp:
                scene = ProgramScene(view: .speakerCloseUp, layers: [.speakerCloseUpCanvas])
            case .screenWithCameraPictureInPicture(let corner):
                scene = ProgramScene(
                    view: .slidesWithSpeakerPictureInPicture,
                    layers: [
                        .slidesFullCanvas,
                        ProgramLayer(
                            source: .presenterCamera,
                            placement: geometry.map(ProgramLayerPlacement.customPictureInPicture)
                                ?? .pictureInPicture(corner: corner, size: .medium),
                            speakerShot: .closeUp
                        )
                    ]
                )
            case .cameraWithScreenPictureInPicture(let corner):
                scene = ProgramScene(
                    view: .speakerWithSlidesPictureInPicture,
                    layers: [
                        ProgramLayer(
                            source: .presenterCamera,
                            placement: .fullCanvas,
                            speakerShot: .fullBody
                        ),
                        ProgramLayer(
                            source: .slidesScreen,
                            placement: geometry.map(ProgramLayerPlacement.customPictureInPicture)
                                ?? .pictureInPicture(corner: corner, size: .medium)
                        )
                    ]
                )
            case .sideBySide:
                scene = ProgramScene(
                    view: .sideBySide,
                    layers: [
                        ProgramLayer(source: .slidesScreen, placement: .leftHalf, sourceCrop: screenCrop),
                        ProgramLayer(
                            source: .presenterCamera,
                            placement: .rightHalf,
                            speakerShot: .closeUp,
                            sourceCrop: cameraCrop
                        )
                    ]
                )
            case .topBottom:
                scene = ProgramScene(
                    view: .topBottom,
                    layers: [
                        ProgramLayer(source: .slidesScreen, placement: .topHalf, sourceCrop: screenCrop),
                        ProgramLayer(
                            source: .presenterCamera,
                            placement: .bottomHalf,
                            speakerShot: .closeUp,
                            sourceCrop: cameraCrop
                        )
                    ]
                )
            }
        }
        return scene.withCanvasPixelSize(canvasPixelSize)
    }
}

private extension ProgramScene {
    var hasPictureInPictureLayer: Bool {
        layers.contains { layer in
            switch layer.placement {
            case .pictureInPicture, .customPictureInPicture:
                return true
            case .fullCanvas, .leftHalf, .rightHalf, .topHalf, .bottomHalf:
                return false
            }
        }
    }

    func updatingPictureInPictureGeometry(_ geometry: ProgramPictureInPictureGeometry) -> ProgramScene {
        let updatedLayers = layers.map { layer in
            switch layer.placement {
            case .pictureInPicture, .customPictureInPicture:
                return ProgramLayer(
                    source: layer.source,
                    placement: .customPictureInPicture(geometry),
                    speakerShot: layer.speakerShot,
                    sourceCrop: layer.sourceCrop
                )
            case .fullCanvas, .leftHalf, .rightHalf, .topHalf, .bottomHalf:
                return layer
            }
        }
        return ProgramScene(view: view, layers: updatedLayers, canvasPixelSize: canvasPixelSize)
    }

    func withCanvasPixelSize(_ canvasPixelSize: RecordingExportPixelSize?) -> ProgramScene {
        ProgramScene(view: view, layers: layers, canvasPixelSize: canvasPixelSize)
    }
}

enum RecordingSessionServiceError: Error, LocalizedError {
    case moviesDirectoryUnavailable

    var errorDescription: String? {
        switch self {
        case .moviesDirectoryUnavailable:
            return "无法定位影片目录"
        }
    }
}

struct RecordingSessionService {
    private let fileManager: FileManager
    private let projectFactory: RecordingProjectFactory
    private let manifestFactory: RecordingProjectManifestFactory
    private let calendar: Calendar

    init(
        fileManager: FileManager = .default,
        projectFactory: RecordingProjectFactory = RecordingProjectFactory(),
        manifestFactory: RecordingProjectManifestFactory = RecordingProjectManifestFactory(),
        calendar: Calendar = .current
    ) {
        self.fileManager = fileManager
        self.projectFactory = projectFactory
        self.manifestFactory = manifestFactory
        self.calendar = calendar
    }

    func start(
        scenario: RecordingScenario,
        cameraName: String,
        screen: ScreenSource = .mainDisplay,
        mode: RecordingMode = .cameraAndScreen,
        layout: RecordingLayout = .screenWithCameraPictureInPicture(corner: .bottomRight),
        pictureInPictureGeometry: ProgramPictureInPictureGeometry? = nil,
        presenterVideoEffects: PresenterVideoEffects = .default,
        expectedDurationMilliseconds: Int = 30 * 60 * 1_000
    ) throws -> RecordingSessionRecord {
        let project = projectFactory.makeProject(
            scenario: scenario,
            camera: cameraDevice(named: cameraName),
            screen: screen,
            mode: mode,
            layout: layout,
            durationMilliseconds: expectedDurationMilliseconds,
            pictureInPictureGeometry: pictureInPictureGeometry
        )
        let manifest = manifestFactory.makeManifest(
            project: project,
            presenterVideoEffects: presenterVideoEffects
        )
        let sessionURL = try makeSessionDirectory()

        try fileManager.createDirectory(
            at: sessionURL.appendingPathComponent("Raw", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: sessionURL.appendingPathComponent("Exports", isDirectory: true),
            withIntermediateDirectories: true
        )

        let manifestURL = sessionURL.appendingPathComponent("project.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

        return RecordingSessionRecord(
            url: sessionURL,
            manifestURL: manifestURL,
            presenterCameraURL: sessionURL.appendingPathComponent("Raw/presenter-camera.mov"),
            slidesScreenURL: sessionURL.appendingPathComponent("Raw/slides-screen.mov"),
            microphoneAudioURL: sessionURL.appendingPathComponent("Raw/microphone.m4a"),
            programOutputURL: sessionURL.appendingPathComponent("Exports/program.mp4"),
            manifest: manifest
        )
    }

    private func makeSessionDirectory() throws -> URL {
        guard let moviesURL = fileManager.urls(for: .moviesDirectory, in: .userDomainMask).first else {
            throw RecordingSessionServiceError.moviesDirectoryUnavailable
        }

        let rootURL = moviesURL.appendingPathComponent("WonderShow", isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let timestamp = timestampString()
        let sessionURL = rootURL.appendingPathComponent("WonderShow-\(timestamp).wondershow", isDirectory: true)
        try fileManager.createDirectory(at: sessionURL, withIntermediateDirectories: true)
        return sessionURL
    }

    private func timestampString() -> String {
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: Date()
        )
        return String(
            format: "%04d%02d%02d-%02d%02d%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
    }

    private func cameraDevice(named name: String) -> CameraDevice {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty, normalizedName != "未连接" else {
            return .builtInFaceTime
        }

        if normalizedName.localizedCaseInsensitiveContains("pocket 3")
            || normalizedName.localizedCaseInsensitiveContains("pocket3") {
            return .pocket3
        }

        if normalizedName.localizedCaseInsensitiveContains("facetime")
            || normalizedName.localizedCaseInsensitiveContains("built-in")
            || normalizedName.localizedCaseInsensitiveContains("内置") {
            return .builtInFaceTime
        }

        return .external(name: normalizedName)
    }
}
