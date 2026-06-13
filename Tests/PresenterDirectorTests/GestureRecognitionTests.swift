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
    #expect(profile.maximumGestureDurationMilliseconds == 650)
}

@Test func recognizesSwipeDirectionsFromMotionWindow() {
    let recognizer = MotionGestureRecognizer(profile: .default)

    let left = recognizer.recognize(.init(horizontalTravel: -0.29, verticalTravel: 0.02, durationMilliseconds: 360))
    let right = recognizer.recognize(.init(horizontalTravel: 0.31, verticalTravel: -0.01, durationMilliseconds: 370))

    #expect(left == .swipeLeft)
    #expect(right == .swipeRight)
}

@Test func recognizesVerticalMotionAsScreenZoom() {
    let recognizer = MotionGestureRecognizer(profile: .default)

    let zoomIn = recognizer.recognize(.init(horizontalTravel: 0.02, verticalTravel: -0.30, durationMilliseconds: 420))
    let zoomOut = recognizer.recognize(.init(horizontalTravel: -0.01, verticalTravel: 0.32, durationMilliseconds: 430))

    #expect(zoomIn == .zoomIn)
    #expect(zoomOut == .zoomOut)
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
