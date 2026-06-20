import Testing
@testable import WonderShow

@Test func mapsDirectionalGesturesToUniversalSlideKeys() {
    let director = PresentationDirector()

    #expect(director.command(for: .swipeLeft, target: .powerPoint).presentationAction == .previousSlide)
    #expect(director.command(for: .swipeRight, target: .wps).presentationAction == .nextSlide)
    #expect(director.command(for: .swipeLeft, target: .html(engine: .revealJS)).transport == .htmlBridge)
    #expect(director.command(for: .swipeLeft, target: .genericKeyboard).transport == .keyboardShortcut)
    #expect(director.command(for: .swipeLeft, target: .word).transport == .keyboardShortcut)
    #expect(director.command(for: .swipeLeft, target: .excel).transport == .keyboardShortcut)
}

@Test func protectsAgainstAccidentalRepeatedGestures() {
    let director = PresentationDirector(cooldownMilliseconds: 800)
    let first = director.accepts(.swipeLeft, atMilliseconds: 1_000)
    let repeated = director.accepts(.swipeLeft, atMilliseconds: 1_400)
    let afterCooldown = director.accepts(.swipeLeft, atMilliseconds: 1_900)

    #expect(first)
    #expect(!repeated)
    #expect(afterCooldown)
}

@Test func choosesHtmlCanvasForAnnotationWhenAvailable() {
    let director = PresentationDirector()

    let html = director.annotationStrategy(for: .html(engine: .slidev))
    let powerpoint = director.annotationStrategy(for: .powerPoint)
    let wps = director.annotationStrategy(for: .wps)

    #expect(html == .inSlideCanvas)
    #expect(powerpoint == .systemOverlay)
    #expect(wps == .systemOverlay)
}

@Test func buildsRecordingPipelineForCameraOnly() {
    let pipeline = RecordingPipelineFactory().makePipeline(
        mode: .cameraOnly,
        camera: .pocket3,
        screen: nil,
        layout: .speakerCloseUp
    )

    #expect(pipeline.inputs == [.camera(.pocket3)])
    #expect(pipeline.outputs.contains(.cameraArchive))
    #expect(pipeline.outputs.contains(.programRecording))
    #expect(pipeline.composition == .singleCamera)
}

@Test func buildsRecordingPipelineForScreenAndCamera() {
    let pipeline = RecordingPipelineFactory().makePipeline(
        mode: .cameraAndScreen,
        camera: .pocket3,
        screen: .mainDisplay,
        layout: .screenWithCameraPictureInPicture(corner: .bottomRight)
    )

    #expect(pipeline.inputs == [.camera(.pocket3), .screen(.mainDisplay)])
    #expect(pipeline.outputs == [.cameraArchive, .screenArchive, .programRecording])
    #expect(pipeline.composition == .pictureInPicture(corner: .bottomRight))
}

@Test func describesPocket3AsVideoInputNotGimbalSdkDependency() {
    let capability = DeviceCapability.pocket3

    #expect(capability.captureInterface == .uvcCamera)
    #expect(capability.requiresPrivateGimbalSDK == false)
    #expect(capability.recommendedTrackingMode == .hardwareFaceTrackConfiguredOnDevice)
}

@Test func modelsMultipleSupportedCameraInputTypes() {
    let examples = DeviceCapability.supportedExamples

    #expect(examples.contains(.pocket3))
    #expect(examples.contains(.builtInCamera))
    #expect(examples.contains { $0.name.contains("Insta360") })
    #expect(examples.contains { $0.name.contains("海康威视") })
    #expect(examples.allSatisfy { !$0.requiresPrivateGimbalSDK })
}
