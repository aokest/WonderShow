import Testing
@testable import PresenterDirector

@Test func calibratesSwipeThresholdFromUserSamples() {
    let calibration = GestureCalibration(samples: [
        .init(intent: .swipeLeft, horizontalTravel: -0.31, verticalTravel: 0.02, durationMilliseconds: 420),
        .init(intent: .swipeLeft, horizontalTravel: -0.28, verticalTravel: 0.01, durationMilliseconds: 390),
        .init(intent: .swipeRight, horizontalTravel: 0.34, verticalTravel: -0.01, durationMilliseconds: 450),
        .init(intent: .swipeRight, horizontalTravel: 0.30, verticalTravel: 0.00, durationMilliseconds: 410)
    ])

    let profile = calibration.makeProfile()

    #expect(profile.minimumHorizontalTravel > 0.18)
    #expect(profile.maximumGestureDurationMilliseconds == 800)
}

@Test func recognizesSwipeDirectionsFromMotionWindow() {
    let recognizer = MotionGestureRecognizer(profile: .default)

    let left = recognizer.recognize(.init(horizontalTravel: -0.29, verticalTravel: 0.02, durationMilliseconds: 360))
    let right = recognizer.recognize(.init(horizontalTravel: 0.31, verticalTravel: -0.01, durationMilliseconds: 370))

    #expect(left == .swipeLeft)
    #expect(right == .swipeRight)
}

@Test func rejectsVerticalMotionAsScreenZoom() {
    let recognizer = MotionGestureRecognizer(profile: .default)

    let zoomIn = recognizer.recognize(.init(horizontalTravel: 0.02, verticalTravel: -0.30, durationMilliseconds: 420))
    let zoomOut = recognizer.recognize(.init(horizontalTravel: -0.01, verticalTravel: 0.32, durationMilliseconds: 430))

    #expect(zoomIn == nil)
    #expect(zoomOut == nil)
}

@Test func recognizesTwoHandDistanceChangeAsZoom() {
    let recognizer = TwoHandGestureRecognizer(profile: .default)

    let zoomIn = recognizer.recognize(.init(startDistance: 0.26, endDistance: 0.52, durationMilliseconds: 520))
    let zoomOut = recognizer.recognize(.init(startDistance: 0.58, endDistance: 0.31, durationMilliseconds: 540))

    #expect(zoomIn == .zoomIn)
    #expect(zoomOut == .zoomOut)
}

@Test func avoidsSingleHandSwipeWhenTwoHandsMoveAmbiguously() {
    let recognizer = FrameGestureRecognizer(profile: .default)
    let ambiguous = recognizer.recognize(
        start: [.init(x: 0.25, y: 0.5, shape: .fingerGun), .init(x: 0.72, y: 0.5, shape: .fingerGun)],
        end: [.init(x: 0.43, y: 0.5, shape: .fingerGun), .init(x: 0.90, y: 0.5, shape: .fingerGun)],
        durationMilliseconds: 420
    )

    #expect(ambiguous == nil)
}

@Test func allowsSingleHandSwipeWhenSecondHandIsStable() {
    let recognizer = FrameGestureRecognizer(profile: .default)
    let swipe = recognizer.recognize(
        start: [.init(x: 0.25, y: 0.5, shape: .fingerGun), .init(x: 0.72, y: 0.5, shape: .natural)],
        end: [.init(x: 0.03, y: 0.5, shape: .fingerGun), .init(x: 0.73, y: 0.5, shape: .natural)],
        durationMilliseconds: 420
    )

    #expect(swipe == .swipeLeft)
}

@Test func rejectsSwipeWithoutFingerGunShape() {
    let recognizer = FrameGestureRecognizer(profile: .default)
    let naturalHandSwipe = recognizer.recognize(
        start: [.init(x: 0.25, y: 0.5, shape: .natural)],
        end: [.init(x: 0.02, y: 0.5, shape: .natural)],
        durationMilliseconds: 420
    )

    #expect(naturalHandSwipe == nil)
}

@Test func requiresLShapeOnBothHandsForZoom() {
    let recognizer = FrameGestureRecognizer(profile: .default)
    let zoom = recognizer.recognize(
        start: [.init(x: 0.32, y: 0.5, shape: .lShape), .init(x: 0.66, y: 0.5, shape: .lShape)],
        end: [.init(x: 0.18, y: 0.5, shape: .lShape), .init(x: 0.80, y: 0.5, shape: .lShape)],
        durationMilliseconds: 420
    )
    let noZoom = recognizer.recognize(
        start: [.init(x: 0.32, y: 0.5, shape: .natural), .init(x: 0.66, y: 0.5, shape: .lShape)],
        end: [.init(x: 0.18, y: 0.5, shape: .natural), .init(x: 0.80, y: 0.5, shape: .lShape)],
        durationMilliseconds: 420
    )

    #expect(zoom == .zoomIn)
    #expect(noZoom == nil)
}

@Test func rejectsSlowOrTinyMotion() {
    let recognizer = MotionGestureRecognizer(profile: .default)

    let tooSmall = recognizer.recognize(.init(horizontalTravel: 0.08, verticalTravel: 0.01, durationMilliseconds: 300))
    let tooSlow = recognizer.recognize(.init(horizontalTravel: 0.40, verticalTravel: 0.00, durationMilliseconds: 1_200))

    #expect(tooSmall == nil)
    #expect(tooSlow == nil)
}

@Test func mapsZoomGesturesToPresentationActions() {
    let director = PresentationDirector()

    #expect(director.command(for: .zoomIn, target: .powerPoint).presentationAction == .zoomIn)
    #expect(director.command(for: .zoomOut, target: .html(engine: .custom)).presentationAction == .zoomOut)
}

@Test func mapsPresentationAndRecordingGesturesToActions() {
    let director = PresentationDirector()

    #expect(director.command(for: .startPresentation, target: .powerPoint).presentationAction == .startPresentation)
    #expect(director.command(for: .exitPresentation, target: .powerPoint).presentationAction == .exitPresentation)
    #expect(director.command(for: .toggleRecording, target: .powerPoint).presentationAction == .toggleRecording)
}
