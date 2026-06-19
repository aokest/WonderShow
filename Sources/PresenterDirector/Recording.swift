public enum CameraDevice: Codable, Hashable, Sendable {
    case pocket3
    case builtInFaceTime
    case external(name: String)
}

public enum ScreenSource: Codable, Hashable, Sendable {
    case mainDisplay
    case display(id: UInt32)
    case window(id: UInt32)
}

public enum RecordingInput: Codable, Hashable, Sendable {
    case camera(CameraDevice)
    case screen(ScreenSource)
    case microphone(name: String)
}

public enum RecordingOutput: Codable, Hashable, Sendable {
    case cameraArchive
    case screenArchive
    case microphoneArchive
    case programRecording
}

public enum PiPCorner: Codable, Hashable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

public enum RecordingMode: Codable, Hashable, Sendable {
    case cameraOnly
    case screenOnly
    case cameraAndScreen
}

public enum RecordingLayout: Codable, Hashable, Sendable {
    case speakerCloseUp
    case speakerFullBody
    case screenOnly
    case screenWithCameraPictureInPicture(corner: PiPCorner)
    case cameraWithScreenPictureInPicture(corner: PiPCorner)
    case sideBySide
}

public enum RecordingExportResolution: String, Codable, CaseIterable, Hashable, Sendable {
    case source
    case hd1080
    case qhd1440
    case uhd4k

    public var pixelSize: (width: Int, height: Int)? {
        switch self {
        case .source:
            return nil
        case .hd1080:
            return (1920, 1080)
        case .qhd1440:
            return (2560, 1440)
        case .uhd4k:
            return (3840, 2160)
        }
    }
}

public enum RecordingExportFrameRate: Int, Codable, CaseIterable, Hashable, Sendable {
    case fps30 = 30
    case fps60 = 60
}

public enum RecordingExportQuality: String, Codable, CaseIterable, Hashable, Sendable {
    case standard
    case high
    case archival
}

public enum RecordingExportCodec: String, Codable, CaseIterable, Hashable, Sendable {
    case h264
    case hevc
}

public struct RecordingExportSettings: Codable, Hashable, Sendable {
    public var resolution: RecordingExportResolution
    public var frameRate: RecordingExportFrameRate
    public var quality: RecordingExportQuality
    public var codec: RecordingExportCodec

    public init(
        resolution: RecordingExportResolution,
        frameRate: RecordingExportFrameRate,
        quality: RecordingExportQuality,
        codec: RecordingExportCodec
    ) {
        self.resolution = resolution
        self.frameRate = frameRate
        self.quality = quality
        self.codec = codec
    }

    public static let presentationDefault = RecordingExportSettings(
        resolution: .source,
        frameRate: .fps30,
        quality: .high,
        codec: .h264
    )

    public var bitrateBitsPerSecond: Int {
        let base: Int
        switch resolution {
        case .source, .hd1080:
            base = 12_000_000
        case .qhd1440:
            base = 24_000_000
        case .uhd4k:
            base = 48_000_000
        }

        let qualityMultiplier: Double
        switch quality {
        case .standard:
            qualityMultiplier = 0.7
        case .high:
            qualityMultiplier = 1.0
        case .archival:
            qualityMultiplier = 1.6
        }

        let frameMultiplier = frameRate == .fps60 ? 1.6 : 1.0
        let codecMultiplier = codec == .hevc ? 0.65 : 1.0
        return Int(Double(base) * qualityMultiplier * frameMultiplier * codecMultiplier)
    }

    public var audioBitrateBitsPerSecond: Int {
        switch quality {
        case .standard:
            return 128_000
        case .high:
            return 192_000
        case .archival:
            return 256_000
        }
    }
}

public struct PresenterVideoEffects: Codable, Hashable, Sendable {
    public var isMirrored: Bool
    public var brightness: Double
    public var contrast: Double
    public var beauty: Double

    public init(
        isMirrored: Bool = false,
        brightness: Double = 0,
        contrast: Double = 1,
        beauty: Double = 0
    ) {
        self.isMirrored = isMirrored
        self.brightness = Self.clamp(brightness, lower: -0.5, upper: 0.5)
        self.contrast = Self.clamp(contrast, lower: 0.5, upper: 1.5)
        self.beauty = Self.clamp(beauty, lower: 0, upper: 1)
    }

    public static let `default` = PresenterVideoEffects()

    public var isDefault: Bool {
        self == .default
    }

    private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}

public enum ProgramComposition: Codable, Hashable, Sendable {
    case singleCamera
    case screenOnly
    case pictureInPicture(corner: PiPCorner)
    case cameraWithPictureInPicture(corner: PiPCorner)
    case sideBySide
}

public struct RecordingPipeline: Codable, Hashable, Sendable {
    public let inputs: [RecordingInput]
    public let outputs: [RecordingOutput]
    public let composition: ProgramComposition

    public init(inputs: [RecordingInput], outputs: [RecordingOutput], composition: ProgramComposition) {
        self.inputs = inputs
        self.outputs = outputs
        self.composition = composition
    }
}

public struct RecordingPipelineFactory: Sendable {
    public init() {}

    public func makePipeline(
        mode: RecordingMode,
        camera: CameraDevice,
        screen: ScreenSource?,
        layout: RecordingLayout
    ) -> RecordingPipeline {
        switch mode {
        case .cameraOnly:
            return RecordingPipeline(
                inputs: [.camera(camera)],
                outputs: [.cameraArchive, .programRecording],
                composition: .singleCamera
            )

        case .screenOnly:
            var inputs: [RecordingInput] = []
            if let screen {
                inputs.append(.screen(screen))
            }

            return RecordingPipeline(
                inputs: inputs,
                outputs: [.screenArchive, .programRecording],
                composition: .screenOnly
            )

        case .cameraAndScreen:
            var inputs: [RecordingInput] = [.camera(camera)]
            if let screen {
                inputs.append(.screen(screen))
            }

            return RecordingPipeline(
                inputs: inputs,
                outputs: [.cameraArchive, .screenArchive, .programRecording],
                composition: composition(for: layout)
            )
        }
    }

    private func composition(for layout: RecordingLayout) -> ProgramComposition {
        switch layout {
        case .speakerCloseUp:
            return .singleCamera
        case .speakerFullBody:
            return .singleCamera
        case .screenOnly:
            return .screenOnly
        case .screenWithCameraPictureInPicture(let corner):
            return .pictureInPicture(corner: corner)
        case .cameraWithScreenPictureInPicture(let corner):
            return .cameraWithPictureInPicture(corner: corner)
        case .sideBySide:
            return .sideBySide
        }
    }
}

public enum RecordingScenario: Codable, Hashable, Sendable {
    case stagePresentation
    case trainingCourse
}

public enum RecordingTrackRole: Codable, Hashable, Sendable {
    case presenterCamera
    case slidesScreen
    case microphoneAudio
}

public struct RecordingRawTrack: Codable, Hashable, Sendable {
    public let role: RecordingTrackRole
    public let input: RecordingInput
    public let archiveOutput: RecordingOutput

    public init(role: RecordingTrackRole, input: RecordingInput, archiveOutput: RecordingOutput) {
        self.role = role
        self.input = input
        self.archiveOutput = archiveOutput
    }
}

public enum SpeakerShot: Codable, Hashable, Sendable {
    case fullBody
    case closeUp
}

public enum PictureInPictureSize: Codable, Hashable, Sendable {
    case small
    case medium
    case large
}

public enum ProgramPictureInPictureShape: String, Codable, Hashable, Sendable {
    case roundedRectangle
    case square
    case circle
}

public struct ProgramPictureInPictureGeometry: Codable, Hashable, Sendable {
    public let centerX: Double
    public let centerY: Double
    public let width: Double
    public let height: Double
    public let shape: ProgramPictureInPictureShape

    public init(
        centerX: Double,
        centerY: Double,
        width: Double,
        height: Double,
        shape: ProgramPictureInPictureShape
    ) {
        self.centerX = Self.clamp(centerX, lower: 0, upper: 1)
        self.centerY = Self.clamp(centerY, lower: 0, upper: 1)
        self.width = Self.clamp(width, lower: 0.04, upper: 1)
        self.height = Self.clamp(height, lower: 0.04, upper: 1)
        self.shape = shape
    }

    private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}

public enum ProgramView: Codable, Hashable, Sendable {
    case speakerFullBody
    case speakerCloseUp
    case slidesWithSpeakerPictureInPicture
    case speakerWithSlidesPictureInPicture
    case sideBySide
    case slidesFullScreen
}

public enum ProgramLayerSource: Codable, Hashable, Sendable {
    case presenterCamera
    case slidesScreen
}

public enum ProgramLayerPlacement: Codable, Hashable, Sendable {
    case fullCanvas
    case pictureInPicture(corner: PiPCorner, size: PictureInPictureSize)
    case customPictureInPicture(ProgramPictureInPictureGeometry)
    case leftHalf
    case rightHalf
}

public struct ProgramLayer: Codable, Hashable, Sendable {
    public let source: ProgramLayerSource
    public let placement: ProgramLayerPlacement
    public let speakerShot: SpeakerShot?

    public init(
        source: ProgramLayerSource,
        placement: ProgramLayerPlacement,
        speakerShot: SpeakerShot? = nil
    ) {
        self.source = source
        self.placement = placement
        self.speakerShot = speakerShot
    }

    public static let slidesFullCanvas = ProgramLayer(
        source: .slidesScreen,
        placement: .fullCanvas
    )

    public static let speakerFullBodyCanvas = ProgramLayer(
        source: .presenterCamera,
        placement: .fullCanvas,
        speakerShot: .fullBody
    )

    public static let speakerCloseUpCanvas = ProgramLayer(
        source: .presenterCamera,
        placement: .fullCanvas,
        speakerShot: .closeUp
    )
}

public struct ProgramScene: Codable, Hashable, Sendable {
    public let view: ProgramView
    public let layers: [ProgramLayer]

    public init(view: ProgramView, layers: [ProgramLayer]) {
        self.view = view
        self.layers = layers
    }

    public var speakerLayer: ProgramLayer? {
        layers.first { $0.source == .presenterCamera }
    }
}

public struct TimelineSegment: Codable, Hashable, Sendable {
    public let startMilliseconds: Int
    public let endMilliseconds: Int
    public let scene: ProgramScene

    public init(startMilliseconds: Int, endMilliseconds: Int, scene: ProgramScene) {
        self.startMilliseconds = startMilliseconds
        self.endMilliseconds = endMilliseconds
        self.scene = scene
    }

    public func contains(milliseconds: Int) -> Bool {
        startMilliseconds <= milliseconds && milliseconds < endMilliseconds
    }
}

public struct RecordingTimeline: Codable, Hashable, Sendable {
    public let segments: [TimelineSegment]

    public init(segments: [TimelineSegment]) {
        self.segments = segments
    }

    public var views: [ProgramView] {
        var seen: Set<ProgramView> = []
        var orderedViews: [ProgramView] = []
        for segment in segments {
            guard !seen.contains(segment.scene.view) else {
                continue
            }
            seen.insert(segment.scene.view)
            orderedViews.append(segment.scene.view)
        }
        return orderedViews
    }

    public var durationMilliseconds: Int {
        segments.last?.endMilliseconds ?? 0
    }

    public var isContiguous: Bool {
        guard segments.first?.startMilliseconds == 0 else {
            return false
        }

        for index in segments.indices.dropFirst() {
            guard segments[index - 1].endMilliseconds == segments[index].startMilliseconds else {
                return false
            }
        }

        return segments.allSatisfy { $0.startMilliseconds < $0.endMilliseconds }
    }

    public func firstScene(for view: ProgramView) -> ProgramScene? {
        segments.first { $0.scene.view == view }?.scene
    }

    public func segment(containingMilliseconds milliseconds: Int) -> TimelineSegment? {
        segments.first { $0.contains(milliseconds: milliseconds) }
    }
}

public struct RecordingProject: Codable, Hashable, Sendable {
    public let scenario: RecordingScenario
    public let pipeline: RecordingPipeline
    public let rawTracks: [RecordingRawTrack]
    public let programOutput: RecordingOutput
    public let timeline: RecordingTimeline

    public init(
        scenario: RecordingScenario,
        pipeline: RecordingPipeline,
        rawTracks: [RecordingRawTrack],
        programOutput: RecordingOutput,
        timeline: RecordingTimeline
    ) {
        self.scenario = scenario
        self.pipeline = pipeline
        self.rawTracks = rawTracks
        self.programOutput = programOutput
        self.timeline = timeline
    }
}

public struct RecordingProjectFactory: Sendable {
    private let pipelineFactory: RecordingPipelineFactory

    public init(pipelineFactory: RecordingPipelineFactory = RecordingPipelineFactory()) {
        self.pipelineFactory = pipelineFactory
    }

    public func makeProject(
        scenario: RecordingScenario,
        camera: CameraDevice,
        screen: ScreenSource,
        durationMilliseconds: Int
    ) -> RecordingProject {
        let pipeline = pipelineFactory.makePipeline(
            mode: .cameraAndScreen,
            camera: camera,
            screen: screen,
            layout: .screenWithCameraPictureInPicture(corner: defaultPiPCorner(for: scenario))
        )

        return RecordingProject(
            scenario: scenario,
            pipeline: pipeline,
            rawTracks: [
                RecordingRawTrack(role: .presenterCamera, input: .camera(camera), archiveOutput: .cameraArchive),
                RecordingRawTrack(role: .slidesScreen, input: .screen(screen), archiveOutput: .screenArchive)
            ],
            programOutput: .programRecording,
            timeline: makeTimeline(scenario: scenario, durationMilliseconds: durationMilliseconds)
        )
    }

    public func makeProject(
        scenario: RecordingScenario,
        camera: CameraDevice,
        screen: ScreenSource,
        mode: RecordingMode,
        layout: RecordingLayout,
        durationMilliseconds: Int,
        pictureInPictureGeometry: ProgramPictureInPictureGeometry? = nil
    ) -> RecordingProject {
        let pipeline = pipelineFactory.makePipeline(
            mode: mode,
            camera: camera,
            screen: screen,
            layout: layout
        )

        return RecordingProject(
            scenario: scenario,
            pipeline: pipeline,
            rawTracks: rawTracks(for: pipeline.inputs),
            programOutput: .programRecording,
            timeline: makeTimeline(
                mode: mode,
                layout: layout,
                durationMilliseconds: durationMilliseconds,
                pictureInPictureGeometry: pictureInPictureGeometry
            )
        )
    }

    private func rawTracks(for inputs: [RecordingInput]) -> [RecordingRawTrack] {
        var tracks: [RecordingRawTrack] = []
        for input in inputs {
            switch input {
            case .camera:
                tracks.append(RecordingRawTrack(role: .presenterCamera, input: input, archiveOutput: .cameraArchive))
            case .screen:
                tracks.append(RecordingRawTrack(role: .slidesScreen, input: input, archiveOutput: .screenArchive))
            case .microphone:
                tracks.append(RecordingRawTrack(role: .microphoneAudio, input: input, archiveOutput: .microphoneArchive))
            }
        }
        return tracks
    }

    private func makeTimeline(scenario: RecordingScenario, durationMilliseconds: Int) -> RecordingTimeline {
        let duration = max(1, durationMilliseconds)
        switch scenario {
        case .stagePresentation:
            return RecordingTimeline.proportional(
                durationMilliseconds: duration,
                weightedScenes: [
                    (weight: 15, scene: .speakerFullBody),
                    (weight: 15, scene: .speakerCloseUp),
                    (weight: 50, scene: .stageSlidesWithSpeakerPictureInPicture),
                    (weight: 20, scene: .slidesFullScreen)
                ]
            )
        case .trainingCourse:
            return RecordingTimeline.proportional(
                durationMilliseconds: duration,
                weightedScenes: [
                    (weight: 70, scene: .trainingSlidesWithSpeakerPictureInPicture),
                    (weight: 20, scene: .slidesFullScreen),
                    (weight: 10, scene: .speakerCloseUp)
                ]
            )
        }
    }

    private func makeTimeline(
        mode: RecordingMode,
        layout: RecordingLayout,
        durationMilliseconds: Int,
        pictureInPictureGeometry: ProgramPictureInPictureGeometry? = nil
    ) -> RecordingTimeline {
        let duration = max(1, durationMilliseconds)
        let scene: ProgramScene

        switch mode {
        case .screenOnly:
            scene = .slidesFullScreen
        case .cameraOnly:
            scene = layout == .speakerFullBody ? .speakerFullBody : .speakerCloseUp
        case .cameraAndScreen:
            switch layout {
            case .screenOnly:
                scene = .slidesFullScreen
            case .speakerFullBody:
                scene = .speakerFullBody
            case .speakerCloseUp:
                scene = .speakerCloseUp
            case .screenWithCameraPictureInPicture(let corner):
                scene = .slidesWithSpeakerPictureInPicture(
                    corner: corner,
                    size: .medium,
                    shot: .closeUp,
                    geometry: pictureInPictureGeometry
                )
            case .cameraWithScreenPictureInPicture(let corner):
                scene = .speakerWithSlidesPictureInPicture(
                    corner: corner,
                    size: .medium,
                    shot: .fullBody,
                    geometry: pictureInPictureGeometry
                )
            case .sideBySide:
                scene = .sideBySide
            }
        }

        return RecordingTimeline(
            segments: [
                TimelineSegment(
                    startMilliseconds: 0,
                    endMilliseconds: duration,
                    scene: scene
                )
            ]
        )
    }

    private func defaultPiPCorner(for scenario: RecordingScenario) -> PiPCorner {
        switch scenario {
        case .stagePresentation:
            return .bottomRight
        case .trainingCourse:
            return .topRight
        }
    }
}

public struct RecordingMediaAsset: Codable, Hashable, Sendable {
    public let relativePath: String
    public let output: RecordingOutput
    public let trackRole: RecordingTrackRole?
    public let input: RecordingInput?

    public init(
        relativePath: String,
        output: RecordingOutput,
        trackRole: RecordingTrackRole? = nil,
        input: RecordingInput? = nil
    ) {
        self.relativePath = relativePath
        self.output = output
        self.trackRole = trackRole
        self.input = input
    }
}

public struct RecordingProjectManifest: Codable, Hashable, Sendable {
    public let schemaVersion: Int
    public let project: RecordingProject
    public let mediaAssets: [RecordingMediaAsset]
    public let presenterVideoEffects: PresenterVideoEffects

    public init(
        schemaVersion: Int,
        project: RecordingProject,
        mediaAssets: [RecordingMediaAsset],
        presenterVideoEffects: PresenterVideoEffects = .default
    ) {
        self.schemaVersion = schemaVersion
        self.project = project
        self.mediaAssets = mediaAssets
        self.presenterVideoEffects = presenterVideoEffects
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case project
        case mediaAssets
        case presenterVideoEffects
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        project = try container.decode(RecordingProject.self, forKey: .project)
        mediaAssets = try container.decode([RecordingMediaAsset].self, forKey: .mediaAssets)
        presenterVideoEffects = try container.decodeIfPresent(
            PresenterVideoEffects.self,
            forKey: .presenterVideoEffects
        ) ?? .default
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(project, forKey: .project)
        try container.encode(mediaAssets, forKey: .mediaAssets)
        try container.encode(presenterVideoEffects, forKey: .presenterVideoEffects)
    }
}

public struct RecordingProjectManifestFactory: Sendable {
    public init() {}

    public func makeManifest(
        project: RecordingProject,
        presenterVideoEffects: PresenterVideoEffects = .default
    ) -> RecordingProjectManifest {
        var mediaAssets = project.rawTracks.map { track in
            RecordingMediaAsset(
                relativePath: relativePath(for: track.role),
                output: track.archiveOutput,
                trackRole: track.role,
                input: track.input
            )
        }

        mediaAssets.append(
            RecordingMediaAsset(
                relativePath: "Raw/microphone.m4a",
                output: .microphoneArchive,
                trackRole: .microphoneAudio,
                input: nil
            )
        )

        mediaAssets.append(
            RecordingMediaAsset(
                relativePath: "Exports/program.mp4",
                output: project.programOutput
            )
        )

        return RecordingProjectManifest(
            schemaVersion: 1,
            project: project,
            mediaAssets: mediaAssets,
            presenterVideoEffects: presenterVideoEffects
        )
    }

    private func relativePath(for role: RecordingTrackRole) -> String {
        switch role {
        case .presenterCamera:
            return "Raw/presenter-camera.mov"
        case .slidesScreen:
            return "Raw/slides-screen.mov"
        case .microphoneAudio:
            return "Raw/microphone.m4a"
        }
    }
}

private extension RecordingTimeline {
    static func proportional(
        durationMilliseconds: Int,
        weightedScenes: [(weight: Int, scene: ProgramScene)]
    ) -> RecordingTimeline {
        let totalWeight = max(1, weightedScenes.reduce(0) { $0 + max(0, $1.weight) })
        var cursor = 0
        var segments: [TimelineSegment] = []

        for (index, item) in weightedScenes.enumerated() {
            let end = index == weightedScenes.count - 1
                ? durationMilliseconds
                : max(cursor + 1, durationMilliseconds * (weightedScenes.prefix(index + 1).reduce(0) { $0 + max(0, $1.weight) }) / totalWeight)

            segments.append(
                TimelineSegment(
                    startMilliseconds: cursor,
                    endMilliseconds: min(durationMilliseconds, end),
                    scene: item.scene
                )
            )
            cursor = min(durationMilliseconds, end)
        }

        return RecordingTimeline(segments: segments.filter { $0.startMilliseconds < $0.endMilliseconds })
    }
}

private extension ProgramScene {
    static let speakerFullBody = ProgramScene(
        view: .speakerFullBody,
        layers: [.speakerFullBodyCanvas]
    )

    static let speakerCloseUp = ProgramScene(
        view: .speakerCloseUp,
        layers: [.speakerCloseUpCanvas]
    )

    static let slidesFullScreen = ProgramScene(
        view: .slidesFullScreen,
        layers: [.slidesFullCanvas]
    )

    static func slidesWithSpeakerPictureInPicture(
        corner: PiPCorner,
        size: PictureInPictureSize,
        shot: SpeakerShot,
        geometry: ProgramPictureInPictureGeometry? = nil
    ) -> ProgramScene {
        ProgramScene(
            view: .slidesWithSpeakerPictureInPicture,
            layers: [
                .slidesFullCanvas,
                ProgramLayer(
                    source: .presenterCamera,
                    placement: geometry.map(ProgramLayerPlacement.customPictureInPicture)
                        ?? .pictureInPicture(corner: corner, size: size),
                    speakerShot: shot
                )
            ]
        )
    }

    static func speakerWithSlidesPictureInPicture(
        corner: PiPCorner,
        size: PictureInPictureSize,
        shot: SpeakerShot,
        geometry: ProgramPictureInPictureGeometry? = nil
    ) -> ProgramScene {
        ProgramScene(
            view: .speakerWithSlidesPictureInPicture,
            layers: [
                ProgramLayer(
                    source: .presenterCamera,
                    placement: .fullCanvas,
                    speakerShot: shot
                ),
                ProgramLayer(
                    source: .slidesScreen,
                    placement: geometry.map(ProgramLayerPlacement.customPictureInPicture)
                        ?? .pictureInPicture(corner: corner, size: size)
                )
            ]
        )
    }

    static let sideBySide = ProgramScene(
        view: .sideBySide,
        layers: [
            ProgramLayer(source: .slidesScreen, placement: .leftHalf),
            ProgramLayer(
                source: .presenterCamera,
                placement: .rightHalf,
                speakerShot: .closeUp
            )
        ]
    )

    static let stageSlidesWithSpeakerPictureInPicture = ProgramScene(
        view: .slidesWithSpeakerPictureInPicture,
        layers: [
            .slidesFullCanvas,
            ProgramLayer(
                source: .presenterCamera,
                placement: .pictureInPicture(corner: .bottomRight, size: .large),
                speakerShot: .fullBody
            )
        ]
    )

    static let trainingSlidesWithSpeakerPictureInPicture = ProgramScene(
        view: .slidesWithSpeakerPictureInPicture,
        layers: [
            .slidesFullCanvas,
            ProgramLayer(
                source: .presenterCamera,
                placement: .pictureInPicture(corner: .topRight, size: .small),
                speakerShot: .closeUp
            )
        ]
    )
}
