import PresenterDirector

enum PresenterExperimentalEffectsGate {
    static let isEnabled = false

    static func mask(_ effects: PresenterVideoEffects) -> PresenterVideoEffects {
        guard !isEnabled else {
            return effects
        }

        return PresenterVideoEffects(
            isMirrored: effects.isMirrored,
            brightness: effects.brightness,
            contrast: effects.contrast,
            beauty: 0,
            isSubjectAwareBeautyEnabled: false,
            skinSmoothing: 0,
            skinBrightening: 0,
            skinWhitening: 0,
            blemishReduction: 0,
            complexion: 0,
            beautyStyle: effects.beautyStyle,
            advancedBeautyEnabled: false,
            portraitSegmentationEnabled: false,
            backgroundEffect: .none,
            backgroundBlur: 0,
            faceLandmarkBeautyEnabled: false,
            faceSlimming: 0,
            eyeEnlargement: 0,
            emojiFaceReplacementEnabled: false,
            emojiFaceReplacementSymbol: effects.emojiFaceReplacementSymbol,
            emojiFaceReplacementStrength: 0,
            emojiFaceReplacementScale: 1
        )
    }
}
