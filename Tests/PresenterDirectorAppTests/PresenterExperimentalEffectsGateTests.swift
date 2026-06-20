@testable import PresenterDirector
@testable import PresenterDirectorApp
import Testing

@Test func disabledExperimentalEffectsGateMasksBeautyBackgroundAndEmoji() {
    let effects = PresenterVideoEffects(
        isMirrored: true,
        brightness: 0.22,
        contrast: 1.18,
        beauty: 0.72,
        isSubjectAwareBeautyEnabled: true,
        skinSmoothing: 0.83,
        skinBrightening: 0.64,
        skinWhitening: 0.51,
        blemishReduction: 0.49,
        complexion: 0.36,
        beautyStyle: .cameraReady,
        advancedBeautyEnabled: true,
        portraitSegmentationEnabled: true,
        backgroundEffect: .replacement(colorHex: "#203040", strength: 0.86),
        backgroundBlur: 0.75,
        faceLandmarkBeautyEnabled: true,
        faceSlimming: 0.58,
        eyeEnlargement: 0.44,
        emojiFaceReplacementEnabled: true,
        emojiFaceReplacementSymbol: "🤖",
        emojiFaceReplacementStrength: 1,
        emojiFaceReplacementScale: 1.35
    )

    let masked = PresenterExperimentalEffectsGate.mask(effects)

    #expect(!PresenterExperimentalEffectsGate.isEnabled)
    #expect(masked.isMirrored)
    #expect(masked.brightness == effects.brightness)
    #expect(masked.contrast == effects.contrast)
    #expect(masked.beauty == 0)
    #expect(!masked.isSubjectAwareBeautyEnabled)
    #expect(masked.skinSmoothing == 0)
    #expect(masked.skinBrightening == 0)
    #expect(masked.skinWhitening == 0)
    #expect(masked.blemishReduction == 0)
    #expect(masked.complexion == 0)
    #expect(!masked.advancedBeautyEnabled)
    #expect(!masked.portraitSegmentationEnabled)
    #expect(masked.backgroundEffect == .none)
    #expect(masked.backgroundBlur == 0)
    #expect(!masked.faceLandmarkBeautyEnabled)
    #expect(masked.faceSlimming == 0)
    #expect(masked.eyeEnlargement == 0)
    #expect(!masked.emojiFaceReplacementEnabled)
    #expect(masked.emojiFaceReplacementStrength == 0)
    #expect(masked.emojiFaceReplacementScale == 1)
}
