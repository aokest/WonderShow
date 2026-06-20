@testable import WonderShow
@testable import WonderShowApp
import Testing

@Test func previewPolicyRunsMediaPipeForPortraitEffectsWithoutGestureControl() {
    let effects = PresenterVideoEffects(
        advancedBeautyEnabled: true,
        portraitSegmentationEnabled: true,
        faceLandmarkBeautyEnabled: true,
        emojiFaceReplacementEnabled: true,
        emojiFaceReplacementStrength: 1,
        emojiFaceReplacementScale: 1.25
    )

    #expect(CameraPreviewMediaPipePolicy.requiresPortraitInference(for: effects))
    #expect(CameraPreviewMediaPipePolicy.shouldRunMediaPipe(gestureControlEnabled: false, effects: effects))
}

@Test func previewPolicyDoesNotRequireGestureRecognitionForBackgroundOrEmoji() {
    let backgroundEffects = PresenterVideoEffects(
        portraitSegmentationEnabled: true,
        backgroundEffect: .blur(strength: 0.65),
        backgroundBlur: 0.65
    )
    let emojiEffects = PresenterVideoEffects(
        emojiFaceReplacementEnabled: true,
        emojiFaceReplacementStrength: 1,
        emojiFaceReplacementScale: 1.25
    )

    #expect(CameraPreviewMediaPipePolicy.shouldRunMediaPipe(gestureControlEnabled: false, effects: backgroundEffects))
    #expect(CameraPreviewMediaPipePolicy.shouldRunMediaPipe(gestureControlEnabled: false, effects: emojiEffects))
}

@Test func previewPolicyKeepsMediaPipeOffForDefaultPreviewWhenGesturesAreOff() {
    #expect(!CameraPreviewMediaPipePolicy.shouldRunMediaPipe(
        gestureControlEnabled: false,
        effects: .default
    ))
    #expect(CameraPreviewMediaPipePolicy.shouldRunMediaPipe(
        gestureControlEnabled: true,
        effects: .default
    ))
}

@Test func previewPolicyDisablesSyntheticFallbackForLiveMonitorFrames() {
    let effects = PresenterVideoEffects(
        isSubjectAwareBeautyEnabled: true,
        skinSmoothing: 0.9,
        portraitSegmentationEnabled: true,
        backgroundEffect: .blur(strength: 0.65),
        backgroundBlur: 0.65,
        emojiFaceReplacementEnabled: true,
        emojiFaceReplacementStrength: 1,
        emojiFaceReplacementScale: 1.25
    )

    #expect(CameraPreviewMediaPipePolicy.shouldRunMediaPipe(
        gestureControlEnabled: false,
        effects: effects
    ))
    #expect(!CameraPreviewMediaPipePolicy.shouldUseSyntheticPortraitFallbackForLiveMonitor(effects))
    #expect(!CameraPreviewMediaPipePolicy.shouldRunSubjectAwareBeautyDetectionForLiveMonitor(effects))
}
