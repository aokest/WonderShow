import Foundation
import Testing
@testable import WonderShowCore

@Test func projectManifestRoundTripsThroughJSON() throws {
    let manifest = sampleManifest()

    let data = try JSONEncoder().encode(manifest)
    let decoded = try JSONDecoder().decode(WonderShowProjectManifest.self, from: data)

    #expect(decoded == manifest)
}

@Test func manifestValidatorAcceptsCompleteTimeline() throws {
    try WonderShowManifestValidator.validate(sampleManifest())
}

@Test func manifestValidatorRejectsMissingSourceSlot() throws {
    var manifest = sampleManifest()
    manifest.project.timeline.segments[0].scene.layers[0].sourceSlotId = "missing-slot"

    var rejected = false
    do {
        try WonderShowManifestValidator.validate(manifest)
    } catch WonderShowManifestValidationError.missingSourceSlot("missing-slot") {
        rejected = true
    }

    #expect(rejected)
}

@Test func presenterEffectsStoreEmojiScaleSeparatelyFromEnablement() throws {
    let effects = WonderShowPresenterVideoEffects(
        enabled: true,
        beauty: .disabled,
        background: WonderShowBackgroundSettings(effect: .blur, strength: 0.45),
        faceReplacement: WonderShowFaceReplacementSettings(enabled: true, emoji: "🙂", scale: 1.3)
    )

    #expect(effects.faceReplacement.enabled)
    #expect(effects.faceReplacement.emoji == "🙂")
    #expect(effects.faceReplacement.scale == 1.3)
}

private func sampleManifest() -> WonderShowProjectManifest {
    let slides = WonderShowSourceSlot(
        id: "slides",
        label: "Slides",
        role: .slidesScreen,
        inputKind: .window
    )
    let presenter = WonderShowSourceSlot(
        id: "presenter",
        label: "Presenter",
        role: .presenterCamera,
        inputKind: .camera
    )
    let scene = WonderShowScene(
        view: .slidesWithSpeakerPictureInPicture,
        layers: [
            WonderShowLayer(sourceSlotId: slides.id, placement: .fullCanvas),
            WonderShowLayer(
                sourceSlotId: presenter.id,
                placement: .pictureInPicture(corner: .bottomRight, size: .medium)
            )
        ]
    )
    let timeline = WonderShowTimeline(
        durationMilliseconds: 60_000,
        segments: [
            WonderShowTimelineSegment(startMilliseconds: 0, endMilliseconds: 60_000, scene: scene)
        ]
    )
    let project = WonderShowProject(
        id: "demo",
        title: "Demo Presentation",
        scenario: .stagePresentation,
        sourceSlots: [slides, presenter],
        timeline: timeline
    )

    return WonderShowProjectManifest(
        project: project,
        mediaAssets: [
            WonderShowMediaAsset(
                id: "presenter-video",
                role: .presenterCamera,
                relativePath: "Raw/presenter-camera.mov",
                mediaType: .video
            ),
            WonderShowMediaAsset(
                id: "slides-video",
                role: .slidesScreen,
                relativePath: "Raw/slides-screen.mov",
                mediaType: .video
            )
        ]
    )
}

