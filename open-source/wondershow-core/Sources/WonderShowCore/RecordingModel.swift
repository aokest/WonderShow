import Foundation

public enum WonderShowProjectSchema {
    public static let currentVersion = 1
}

public struct WonderShowProjectManifest: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var project: WonderShowProject
    public var mediaAssets: [WonderShowMediaAsset]

    public init(
        schemaVersion: Int = WonderShowProjectSchema.currentVersion,
        project: WonderShowProject,
        mediaAssets: [WonderShowMediaAsset]
    ) {
        self.schemaVersion = schemaVersion
        self.project = project
        self.mediaAssets = mediaAssets
    }
}

public struct WonderShowProject: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var scenario: WonderShowRecordingScenario
    public var sourceSlots: [WonderShowSourceSlot]
    public var timeline: WonderShowTimeline
    public var exportSettings: WonderShowExportSettings
    public var presenterEffects: WonderShowPresenterVideoEffects

    public init(
        id: String,
        title: String,
        scenario: WonderShowRecordingScenario,
        sourceSlots: [WonderShowSourceSlot],
        timeline: WonderShowTimeline,
        exportSettings: WonderShowExportSettings = .standard1080p,
        presenterEffects: WonderShowPresenterVideoEffects = .disabled
    ) {
        self.id = id
        self.title = title
        self.scenario = scenario
        self.sourceSlots = sourceSlots
        self.timeline = timeline
        self.exportSettings = exportSettings
        self.presenterEffects = presenterEffects
    }
}

public enum WonderShowRecordingScenario: String, Codable, CaseIterable, Sendable {
    case stagePresentation
    case trainingCourse
    case screenTutorial
    case cameraOnly
}

public struct WonderShowSourceSlot: Codable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var role: WonderShowMediaRole
    public var inputKind: WonderShowInputKind

    public init(id: String, label: String, role: WonderShowMediaRole, inputKind: WonderShowInputKind) {
        self.id = id
        self.label = label
        self.role = role
        self.inputKind = inputKind
    }
}

public enum WonderShowInputKind: String, Codable, CaseIterable, Sendable {
    case camera
    case screen
    case window
    case microphone
    case generated
}

public struct WonderShowMediaAsset: Codable, Equatable, Sendable {
    public var id: String
    public var role: WonderShowMediaRole
    public var relativePath: String
    public var mediaType: WonderShowMediaType

    public init(id: String, role: WonderShowMediaRole, relativePath: String, mediaType: WonderShowMediaType) {
        self.id = id
        self.role = role
        self.relativePath = relativePath
        self.mediaType = mediaType
    }
}

public enum WonderShowMediaRole: String, Codable, CaseIterable, Sendable {
    case presenterCamera
    case slidesScreen
    case microphoneAudio
    case programVideo
    case sidecarMetadata
}

public enum WonderShowMediaType: String, Codable, CaseIterable, Sendable {
    case video
    case audio
    case json
    case image
}

public struct WonderShowTimeline: Codable, Equatable, Sendable {
    public var durationMilliseconds: Int
    public var segments: [WonderShowTimelineSegment]

    public init(durationMilliseconds: Int, segments: [WonderShowTimelineSegment]) {
        self.durationMilliseconds = durationMilliseconds
        self.segments = segments
    }
}

public struct WonderShowTimelineSegment: Codable, Equatable, Sendable {
    public var startMilliseconds: Int
    public var endMilliseconds: Int
    public var scene: WonderShowScene

    public init(startMilliseconds: Int, endMilliseconds: Int, scene: WonderShowScene) {
        self.startMilliseconds = startMilliseconds
        self.endMilliseconds = endMilliseconds
        self.scene = scene
    }
}

public struct WonderShowScene: Codable, Equatable, Sendable {
    public var view: WonderShowProgramView
    public var layers: [WonderShowLayer]

    public init(view: WonderShowProgramView, layers: [WonderShowLayer]) {
        self.view = view
        self.layers = layers
    }
}

public enum WonderShowProgramView: String, Codable, CaseIterable, Sendable {
    case slidesFullScreen
    case speakerCloseUp
    case speakerFullBody
    case slidesWithSpeakerPictureInPicture
    case speakerWithSlidesPictureInPicture
    case sideBySide
}

public struct WonderShowLayer: Codable, Equatable, Sendable {
    public var sourceSlotId: String
    public var placement: WonderShowLayerPlacement
    public var opacity: Double

    public init(sourceSlotId: String, placement: WonderShowLayerPlacement, opacity: Double = 1) {
        self.sourceSlotId = sourceSlotId
        self.placement = placement
        self.opacity = opacity
    }
}

public struct WonderShowLayerPlacement: Codable, Equatable, Sendable {
    public var kind: WonderShowLayerPlacementKind
    public var frame: WonderShowNormalizedRect?
    public var corner: WonderShowPiPCorner?
    public var size: WonderShowPiPSize?

    public init(
        kind: WonderShowLayerPlacementKind,
        frame: WonderShowNormalizedRect? = nil,
        corner: WonderShowPiPCorner? = nil,
        size: WonderShowPiPSize? = nil
    ) {
        self.kind = kind
        self.frame = frame
        self.corner = corner
        self.size = size
    }

    public static let fullCanvas = WonderShowLayerPlacement(kind: .fullCanvas)
    public static let leftHalf = WonderShowLayerPlacement(
        kind: .customFrame,
        frame: WonderShowNormalizedRect(x: 0, y: 0, width: 0.5, height: 1)
    )
    public static let rightHalf = WonderShowLayerPlacement(
        kind: .customFrame,
        frame: WonderShowNormalizedRect(x: 0.5, y: 0, width: 0.5, height: 1)
    )

    public static func pictureInPicture(
        corner: WonderShowPiPCorner,
        size: WonderShowPiPSize
    ) -> WonderShowLayerPlacement {
        WonderShowLayerPlacement(kind: .pictureInPicture, corner: corner, size: size)
    }
}

public enum WonderShowLayerPlacementKind: String, Codable, CaseIterable, Sendable {
    case fullCanvas
    case customFrame
    case pictureInPicture
}

public struct WonderShowNormalizedRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum WonderShowPiPCorner: String, Codable, CaseIterable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

public enum WonderShowPiPSize: String, Codable, CaseIterable, Sendable {
    case small
    case medium
    case large
}

public struct WonderShowExportSettings: Codable, Equatable, Sendable {
    public var resolution: WonderShowExportResolution
    public var frameRate: WonderShowExportFrameRate
    public var quality: WonderShowExportQuality
    public var codec: WonderShowExportCodec

    public init(
        resolution: WonderShowExportResolution,
        frameRate: WonderShowExportFrameRate,
        quality: WonderShowExportQuality,
        codec: WonderShowExportCodec
    ) {
        self.resolution = resolution
        self.frameRate = frameRate
        self.quality = quality
        self.codec = codec
    }

    public static let standard1080p = WonderShowExportSettings(
        resolution: .hd1080p,
        frameRate: .fps30,
        quality: .high,
        codec: .h264
    )
}

public enum WonderShowExportResolution: String, Codable, CaseIterable, Sendable {
    case hd720p
    case hd1080p
    case uhd4k
}

public enum WonderShowExportFrameRate: String, Codable, CaseIterable, Sendable {
    case fps24
    case fps30
    case fps60
}

public enum WonderShowExportQuality: String, Codable, CaseIterable, Sendable {
    case draft
    case standard
    case high
    case archival
}

public enum WonderShowExportCodec: String, Codable, CaseIterable, Sendable {
    case h264
    case hevc
    case proRes422
}

public struct WonderShowPresenterVideoEffects: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var beauty: WonderShowBeautySettings
    public var background: WonderShowBackgroundSettings
    public var faceReplacement: WonderShowFaceReplacementSettings

    public init(
        enabled: Bool,
        beauty: WonderShowBeautySettings,
        background: WonderShowBackgroundSettings,
        faceReplacement: WonderShowFaceReplacementSettings
    ) {
        self.enabled = enabled
        self.beauty = beauty
        self.background = background
        self.faceReplacement = faceReplacement
    }

    public static let disabled = WonderShowPresenterVideoEffects(
        enabled: false,
        beauty: .disabled,
        background: .none,
        faceReplacement: .none
    )
}

public struct WonderShowBeautySettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var style: WonderShowBeautyStyle
    public var skinSmoothing: Double
    public var complexion: Double
    public var faceSlimming: Double
    public var eyeScale: Double

    public init(
        enabled: Bool,
        style: WonderShowBeautyStyle,
        skinSmoothing: Double,
        complexion: Double,
        faceSlimming: Double,
        eyeScale: Double
    ) {
        self.enabled = enabled
        self.style = style
        self.skinSmoothing = skinSmoothing
        self.complexion = complexion
        self.faceSlimming = faceSlimming
        self.eyeScale = eyeScale
    }

    public static let disabled = WonderShowBeautySettings(
        enabled: false,
        style: .natural,
        skinSmoothing: 0,
        complexion: 0,
        faceSlimming: 0,
        eyeScale: 0
    )
}

public enum WonderShowBeautyStyle: String, Codable, CaseIterable, Sendable {
    case natural
    case studio
    case cinematic
}

public struct WonderShowBackgroundSettings: Codable, Equatable, Sendable {
    public var effect: WonderShowBackgroundEffect
    public var strength: Double
    public var replacementAssetId: String?

    public init(effect: WonderShowBackgroundEffect, strength: Double = 0, replacementAssetId: String? = nil) {
        self.effect = effect
        self.strength = strength
        self.replacementAssetId = replacementAssetId
    }

    public static let none = WonderShowBackgroundSettings(effect: .none)
}

public enum WonderShowBackgroundEffect: String, Codable, CaseIterable, Sendable {
    case none
    case blur
    case imageReplacement
    case colorReplacement
}

public struct WonderShowFaceReplacementSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var emoji: String?
    public var scale: Double

    public init(enabled: Bool, emoji: String?, scale: Double = 1) {
        self.enabled = enabled
        self.emoji = emoji
        self.scale = scale
    }

    public static let none = WonderShowFaceReplacementSettings(enabled: false, emoji: nil, scale: 1)
}

public enum WonderShowManifestValidationError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case emptyProjectId
    case emptyTimeline
    case invalidDuration
    case invalidSegmentRange(index: Int)
    case missingSourceSlot(String)
    case invalidOpacity(index: Int)
    case invalidNormalizedFrame(index: Int)
}

public enum WonderShowManifestValidator {
    public static func validate(_ manifest: WonderShowProjectManifest) throws {
        guard manifest.schemaVersion == WonderShowProjectSchema.currentVersion else {
            throw WonderShowManifestValidationError.unsupportedSchemaVersion(manifest.schemaVersion)
        }
        guard !manifest.project.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WonderShowManifestValidationError.emptyProjectId
        }
        guard manifest.project.timeline.durationMilliseconds > 0 else {
            throw WonderShowManifestValidationError.invalidDuration
        }
        guard !manifest.project.timeline.segments.isEmpty else {
            throw WonderShowManifestValidationError.emptyTimeline
        }

        let sourceSlotIds = Set(manifest.project.sourceSlots.map(\.id))
        for (segmentIndex, segment) in manifest.project.timeline.segments.enumerated() {
            guard segment.startMilliseconds >= 0,
                  segment.endMilliseconds > segment.startMilliseconds,
                  segment.endMilliseconds <= manifest.project.timeline.durationMilliseconds else {
                throw WonderShowManifestValidationError.invalidSegmentRange(index: segmentIndex)
            }

            for (layerIndex, layer) in segment.scene.layers.enumerated() {
                guard sourceSlotIds.contains(layer.sourceSlotId) else {
                    throw WonderShowManifestValidationError.missingSourceSlot(layer.sourceSlotId)
                }
                guard (0...1).contains(layer.opacity) else {
                    throw WonderShowManifestValidationError.invalidOpacity(index: layerIndex)
                }
                if let frame = layer.placement.frame, !frame.isNormalized {
                    throw WonderShowManifestValidationError.invalidNormalizedFrame(index: layerIndex)
                }
            }
        }
    }
}

private extension WonderShowNormalizedRect {
    var isNormalized: Bool {
        x >= 0 &&
        y >= 0 &&
        width > 0 &&
        height > 0 &&
        x + width <= 1 &&
        y + height <= 1
    }
}

