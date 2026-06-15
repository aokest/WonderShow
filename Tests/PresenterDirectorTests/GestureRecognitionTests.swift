import Foundation
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

@Test func easyTestingProfileAllowsNaturalHandSwipe() {
    let recognizer = FrameGestureRecognizer(profile: .easyTesting)
    let naturalHandSwipe = recognizer.recognize(
        start: [.init(x: 0.25, y: 0.5, shape: .natural)],
        end: [.init(x: 0.12, y: 0.5, shape: .natural)],
        durationMilliseconds: 1_100
    )

    #expect(naturalHandSwipe == .swipeLeft)
}

@Test func streamingRecognizerDetectsFastSwipeWithoutWaitingForFullWindow() {
    let recognizer = StreamingGestureRecognizer(profile: .easyTesting)
    let frames = [
        GestureFrameSnapshot(points: [.init(x: 0.72, y: 0.5, shape: .natural)], timestampMilliseconds: 0),
        GestureFrameSnapshot(points: [.init(x: 0.66, y: 0.5, shape: .natural)], timestampMilliseconds: 60),
        GestureFrameSnapshot(points: [.init(x: 0.58, y: 0.5, shape: .natural)], timestampMilliseconds: 120),
        GestureFrameSnapshot(points: [.init(x: 0.47, y: 0.5, shape: .natural)], timestampMilliseconds: 190)
    ]

    #expect(recognizer.recognize(frames: frames) == .swipeLeft)
}

@Test func streamingRecognizerDetectsFastSwipeRightWithoutWaitingForFullWindow() {
    let recognizer = StreamingGestureRecognizer(profile: .easyTesting)
    let frames = [
        GestureFrameSnapshot(points: [.init(x: 0.28, y: 0.5, shape: .natural)], timestampMilliseconds: 0),
        GestureFrameSnapshot(points: [.init(x: 0.36, y: 0.5, shape: .natural)], timestampMilliseconds: 60),
        GestureFrameSnapshot(points: [.init(x: 0.45, y: 0.5, shape: .natural)], timestampMilliseconds: 120),
        GestureFrameSnapshot(points: [.init(x: 0.56, y: 0.5, shape: .natural)], timestampMilliseconds: 190)
    ]

    #expect(recognizer.recognize(frames: frames) == .swipeRight)
}

@Test func streamingRecognizerRejectsJitteryBackAndForthMotion() {
    let recognizer = StreamingGestureRecognizer(profile: .easyTesting, minimumDirectionConsistency: 0.70)
    let frames = [
        GestureFrameSnapshot(points: [.init(x: 0.52, y: 0.5, shape: .natural)], timestampMilliseconds: 0),
        GestureFrameSnapshot(points: [.init(x: 0.46, y: 0.5, shape: .natural)], timestampMilliseconds: 60),
        GestureFrameSnapshot(points: [.init(x: 0.54, y: 0.5, shape: .natural)], timestampMilliseconds: 120),
        GestureFrameSnapshot(points: [.init(x: 0.43, y: 0.5, shape: .natural)], timestampMilliseconds: 190)
    ]

    #expect(recognizer.recognize(frames: frames) == nil)
}

@Test func personalizedRecognizerMatchesRecordedSwipeTemplate() {
    let recorded = [
        GestureFrameSnapshot(points: [.init(x: 0.72, y: 0.50, shape: .natural)], timestampMilliseconds: 0),
        GestureFrameSnapshot(points: [.init(x: 0.64, y: 0.49, shape: .natural)], timestampMilliseconds: 80),
        GestureFrameSnapshot(points: [.init(x: 0.55, y: 0.51, shape: .natural)], timestampMilliseconds: 160),
        GestureFrameSnapshot(points: [.init(x: 0.44, y: 0.50, shape: .natural)], timestampMilliseconds: 240),
        GestureFrameSnapshot(points: [.init(x: 0.34, y: 0.49, shape: .natural)], timestampMilliseconds: 320)
    ]
    var library = PersonalizedGestureLibrary()
    library.add(GestureTemplate(intent: .swipeLeft, frames: recorded, createdAtMilliseconds: 0))

    let live = [
        GestureFrameSnapshot(points: [.init(x: 0.68, y: 0.52, shape: .natural)], timestampMilliseconds: 1_000),
        GestureFrameSnapshot(points: [.init(x: 0.60, y: 0.50, shape: .natural)], timestampMilliseconds: 1_090),
        GestureFrameSnapshot(points: [.init(x: 0.51, y: 0.52, shape: .natural)], timestampMilliseconds: 1_170),
        GestureFrameSnapshot(points: [.init(x: 0.40, y: 0.51, shape: .natural)], timestampMilliseconds: 1_250),
        GestureFrameSnapshot(points: [.init(x: 0.31, y: 0.50, shape: .natural)], timestampMilliseconds: 1_330)
    ]

    #expect(PersonalizedGestureRecognizer(library: library).recognize(frames: live) == .swipeLeft)
}

@Test func personalizedRecognizerRejectsOppositeDirectionFromTemplate() {
    let recorded = [
        GestureFrameSnapshot(points: [.init(x: 0.72, y: 0.50, shape: .natural)], timestampMilliseconds: 0),
        GestureFrameSnapshot(points: [.init(x: 0.60, y: 0.50, shape: .natural)], timestampMilliseconds: 80),
        GestureFrameSnapshot(points: [.init(x: 0.48, y: 0.50, shape: .natural)], timestampMilliseconds: 160),
        GestureFrameSnapshot(points: [.init(x: 0.36, y: 0.50, shape: .natural)], timestampMilliseconds: 240)
    ]
    var library = PersonalizedGestureLibrary()
    library.add(GestureTemplate(intent: .swipeLeft, frames: recorded, createdAtMilliseconds: 0))

    let opposite = [
        GestureFrameSnapshot(points: [.init(x: 0.30, y: 0.50, shape: .natural)], timestampMilliseconds: 1_000),
        GestureFrameSnapshot(points: [.init(x: 0.42, y: 0.50, shape: .natural)], timestampMilliseconds: 1_080),
        GestureFrameSnapshot(points: [.init(x: 0.54, y: 0.50, shape: .natural)], timestampMilliseconds: 1_160),
        GestureFrameSnapshot(points: [.init(x: 0.66, y: 0.50, shape: .natural)], timestampMilliseconds: 1_240)
    ]

    #expect(PersonalizedGestureRecognizer(library: library).recognize(frames: opposite) == nil)
}

@Test func personalizedRecognizerRejectsAmbiguousCompetingTemplates() {
    let leftTemplate = [
        GestureFrameSnapshot(points: [.init(x: 0.72, y: 0.50, shape: .natural)], timestampMilliseconds: 0),
        GestureFrameSnapshot(points: [.init(x: 0.62, y: 0.50, shape: .natural)], timestampMilliseconds: 80),
        GestureFrameSnapshot(points: [.init(x: 0.52, y: 0.50, shape: .natural)], timestampMilliseconds: 160),
        GestureFrameSnapshot(points: [.init(x: 0.42, y: 0.50, shape: .natural)], timestampMilliseconds: 240)
    ]
    let alternateLeftTemplate = [
        GestureFrameSnapshot(points: [.init(x: 0.72, y: 0.50, shape: .natural)], timestampMilliseconds: 0),
        GestureFrameSnapshot(points: [.init(x: 0.63, y: 0.52, shape: .natural)], timestampMilliseconds: 80),
        GestureFrameSnapshot(points: [.init(x: 0.51, y: 0.47, shape: .natural)], timestampMilliseconds: 160),
        GestureFrameSnapshot(points: [.init(x: 0.42, y: 0.51, shape: .natural)], timestampMilliseconds: 240)
    ]
    var library = PersonalizedGestureLibrary()
    library.add(GestureTemplate(intent: .swipeLeft, frames: leftTemplate, createdAtMilliseconds: 0))
    library.add(GestureTemplate(intent: .pinchToggle, frames: alternateLeftTemplate, createdAtMilliseconds: 0))

    let live = [
        GestureFrameSnapshot(points: [.init(x: 0.72, y: 0.50, shape: .natural)], timestampMilliseconds: 1_000),
        GestureFrameSnapshot(points: [.init(x: 0.625, y: 0.51, shape: .natural)], timestampMilliseconds: 1_080),
        GestureFrameSnapshot(points: [.init(x: 0.515, y: 0.49, shape: .natural)], timestampMilliseconds: 1_160),
        GestureFrameSnapshot(points: [.init(x: 0.42, y: 0.50, shape: .natural)], timestampMilliseconds: 1_240)
    ]

    let recognizer = PersonalizedGestureRecognizer(
        library: library,
        maximumDistance: 0.18,
        minimumConfidence: 0.20,
        minimumWinningMargin: 0.03
    )

    #expect(recognizer.recognize(frames: live) == nil)
}

@Test func personalizedLibraryReportsStableCalibrationCoverage() {
    let left = [
        GestureFrameSnapshot(points: [.init(x: 0.70, y: 0.5)], timestampMilliseconds: 0),
        GestureFrameSnapshot(points: [.init(x: 0.60, y: 0.5)], timestampMilliseconds: 80),
        GestureFrameSnapshot(points: [.init(x: 0.48, y: 0.5)], timestampMilliseconds: 160),
        GestureFrameSnapshot(points: [.init(x: 0.36, y: 0.5)], timestampMilliseconds: 240)
    ]
    let right = [
        GestureFrameSnapshot(points: [.init(x: 0.30, y: 0.5)], timestampMilliseconds: 0),
        GestureFrameSnapshot(points: [.init(x: 0.42, y: 0.5)], timestampMilliseconds: 80),
        GestureFrameSnapshot(points: [.init(x: 0.54, y: 0.5)], timestampMilliseconds: 160),
        GestureFrameSnapshot(points: [.init(x: 0.66, y: 0.5)], timestampMilliseconds: 240)
    ]
    var library = PersonalizedGestureLibrary()
    library.add(GestureTemplate(intent: .swipeLeft, frames: left, createdAtMilliseconds: 0))
    library.add(GestureTemplate(intent: .swipeRight, frames: right, createdAtMilliseconds: 0))

    #expect(!library.hasStableCalibration(for: [.swipeLeft, .swipeRight]))

    library.add(GestureTemplate(intent: .swipeLeft, frames: left, createdAtMilliseconds: 1))
    library.add(GestureTemplate(intent: .swipeRight, frames: right, createdAtMilliseconds: 1))

    #expect(library.hasStableCalibration(for: [.swipeLeft, .swipeRight]))
}

@Test func continuousZoomTrackerEmitsPreciseScaleAfterMeaningfulTwoHandChange() {
    var tracker = ContinuousZoomTracker(minimumRelativeChange: 0.04, minimumScaleStep: 0.02)

    let initial = tracker.update(
        points: [
            .init(x: 0.30, y: 0.5, shape: .lShape),
            .init(x: 0.70, y: 0.5, shape: .lShape)
        ],
        currentScale: 1
    )
    let tiny = tracker.update(
        points: [
            .init(x: 0.295, y: 0.5, shape: .lShape),
            .init(x: 0.705, y: 0.5, shape: .lShape)
        ],
        currentScale: 1
    )
    let larger = tracker.update(
        points: [
            .init(x: 0.24, y: 0.5, shape: .lShape),
            .init(x: 0.76, y: 0.5, shape: .lShape)
        ],
        currentScale: 1
    )

    #expect(initial == nil)
    #expect(tiny == nil)
    #expect((larger?.scale ?? 0) > 1.0)
    #expect((larger?.scale ?? 0) <= 1.05)
}

@Test func continuousZoomTrackerScalesFineAndFastMotionsWithDifferentStepSizes() {
    var tracker = ContinuousZoomTracker(
        minimumRelativeChange: 0.02,
        minimumScaleStep: 0.004,
        scaleSensitivity: 0.55,
        minimumScaleDeltaPerUpdate: 0.008,
        maximumScaleDeltaPerUpdate: 0.03,
        dynamicScaleDeltaMultiplier: 0.12
    )

    _ = tracker.update(
        points: [
            .init(x: 0.30, y: 0.5, shape: .lShape),
            .init(x: 0.70, y: 0.5, shape: .lShape)
        ],
        currentScale: 1
    )
    let fine = tracker.update(
        points: [
            .init(x: 0.295, y: 0.5, shape: .lShape),
            .init(x: 0.705, y: 0.5, shape: .lShape)
        ],
        currentScale: 1
    )

    tracker.reset(currentScale: 1)
    _ = tracker.update(
        points: [
            .init(x: 0.30, y: 0.5, shape: .lShape),
            .init(x: 0.70, y: 0.5, shape: .lShape)
        ],
        currentScale: 1
    )
    let fast = tracker.update(
        points: [
            .init(x: 0.22, y: 0.5, shape: .lShape),
            .init(x: 0.78, y: 0.5, shape: .lShape)
        ],
        currentScale: 1
    )

    #expect((fine?.scale ?? 0) > 1.0)
    #expect((fine?.scale ?? 0) < (fast?.scale ?? 0))
    #expect((fast?.scale ?? 0) <= 1.03)
}

@Test func continuousZoomTrackerResetsWhenZoomPoseDisappears() {
    var tracker = ContinuousZoomTracker(minimumRelativeChange: 0.04, minimumScaleStep: 0.02)

    _ = tracker.update(
        points: [
            .init(x: 0.30, y: 0.5, shape: .lShape),
            .init(x: 0.70, y: 0.5, shape: .lShape)
        ],
        currentScale: 1
    )
    #expect(tracker.update(points: [.init(x: 0.50, y: 0.5, shape: .natural)], currentScale: 1) == nil)
    #expect(tracker.update(
        points: [
            .init(x: 0.20, y: 0.5, shape: .lShape),
            .init(x: 0.80, y: 0.5, shape: .lShape)
        ],
        currentScale: 1
    ) == nil)
}

@Test func continuousZoomCandidateRequiresZoomCapablePoseOnBothHands() {
    let evaluator = ContinuousZoomCandidateEvaluator(profile: .easyTesting)
    let start = [
        HandPoint(x: 0.30, y: 0.5, shape: .natural),
        HandPoint(x: 0.70, y: 0.5, shape: .natural)
    ]
    let end = [
        HandPoint(x: 0.22, y: 0.5, shape: .natural),
        HandPoint(x: 0.78, y: 0.5, shape: .natural)
    ]

    #expect(evaluator.shouldPrioritizeZoom(start: start, end: end) == false)
}

@Test func continuousZoomCandidatePrioritizesOppositeMovingZoomPose() {
    let evaluator = ContinuousZoomCandidateEvaluator(profile: .easyTesting)
    let start = [
        HandPoint(x: 0.34, y: 0.5, shape: .lShape),
        HandPoint(x: 0.66, y: 0.5, shape: .lShape)
    ]
    let end = [
        HandPoint(x: 0.22, y: 0.5, shape: .lShape),
        HandPoint(x: 0.78, y: 0.5, shape: .lShape)
    ]

    #expect(evaluator.shouldPrioritizeZoom(start: start, end: end))
}

@Test func discreteGestureSuppressionEvaluatorUsesIncomingZoomFrameImmediately() {
    let evaluator = DiscreteGestureSuppressionEvaluator()
    let existingFrames = [
        GestureFrameSnapshot(
            points: [
                .init(x: 0.34, y: 0.5, shape: .lShape),
                .init(x: 0.66, y: 0.5, shape: .lShape)
            ],
            timestampMilliseconds: 0
        )
    ]
    let incomingFrame = GestureFrameSnapshot(
        points: [
            .init(x: 0.30, y: 0.5, shape: .lShape),
            .init(x: 0.70, y: 0.5, shape: .lShape)
        ],
        timestampMilliseconds: 80
    )

    #expect(
        evaluator.shouldSuppressDiscreteGesture(
            existingFrames: existingFrames,
            incomingFrame: incomingFrame,
            zoomPoseStreak: 0
        )
    )
}

@Test func discreteGestureSuppressionEvaluatorDoesNotSuppressTwoHandFingerGunSwipe() {
    let evaluator = DiscreteGestureSuppressionEvaluator()
    let existingFrames = [
        GestureFrameSnapshot(
            points: [
                .init(x: 0.34, y: 0.5, shape: .fingerGun),
                .init(x: 0.66, y: 0.5, shape: .fingerGun)
            ],
            timestampMilliseconds: 0
        )
    ]
    let incomingFrame = GestureFrameSnapshot(
        points: [
            .init(x: 0.24, y: 0.5, shape: .fingerGun),
            .init(x: 0.56, y: 0.5, shape: .fingerGun)
        ],
        timestampMilliseconds: 80
    )

    #expect(
        !evaluator.shouldSuppressDiscreteGesture(
            existingFrames: existingFrames,
            incomingFrame: incomingFrame,
            zoomPoseStreak: 0
        )
    )
}

@Test func handSelectorIgnoresExtraHandsOutsideZone() {
    let zone = GestureActivationZone(minX: 0.2, maxX: 0.8, minY: 0.2, maxY: 0.8)
    let selector = GestureHandSelector(zone: zone)
    let points = [
        HandPoint(x: 0.10, y: 0.50, shape: .lShape),
        HandPoint(x: 0.35, y: 0.55, shape: .lShape),
        HandPoint(x: 0.65, y: 0.55, shape: .lShape),
        HandPoint(x: 0.90, y: 0.50, shape: .lShape)
    ]

    let selected = selector.selectPrimaryHands(from: points)
    #expect(selected.count == 2)
    #expect(selected[0].x == 0.35)
    #expect(selected[1].x == 0.65)
}

@Test func handSelectorPrefersCenterWhenManyHandsInZone() {
    let zone = GestureActivationZone(minX: 0.0, maxX: 1.0, minY: 0.0, maxY: 1.0)
    let selector = GestureHandSelector(zone: zone)
    let points = [
        HandPoint(x: 0.10, y: 0.10, shape: .lShape),
        HandPoint(x: 0.90, y: 0.10, shape: .lShape),
        HandPoint(x: 0.45, y: 0.50, shape: .lShape),
        HandPoint(x: 0.55, y: 0.50, shape: .lShape)
    ]

    let selected = selector.selectPrimaryHands(from: points)
    #expect(selected.count == 2)
    #expect(selected[0].x == 0.45)
    #expect(selected[1].x == 0.55)
}

@Test func gestureTemplateRejectsTinyCalibrationMotion() {
    let tiny = [
        GestureFrameSnapshot(points: [.init(x: 0.50, y: 0.50, shape: .natural)], timestampMilliseconds: 0),
        GestureFrameSnapshot(points: [.init(x: 0.51, y: 0.50, shape: .natural)], timestampMilliseconds: 80),
        GestureFrameSnapshot(points: [.init(x: 0.52, y: 0.50, shape: .natural)], timestampMilliseconds: 160),
        GestureFrameSnapshot(points: [.init(x: 0.52, y: 0.50, shape: .natural)], timestampMilliseconds: 240)
    ]

    #expect(!GestureTemplate(intent: .swipeLeft, frames: tiny, createdAtMilliseconds: 0).isUsable)
}

@Test func allowsSwipeWhenHandShapeIsUncertain() {
    let recognizer = FrameGestureRecognizer(profile: .default)
    let uncertainSwipe = recognizer.recognize(
        start: [.init(x: 0.25, y: 0.5, shape: .unknown)],
        end: [.init(x: 0.02, y: 0.5, shape: .unknown)],
        durationMilliseconds: 420
    )

    #expect(uncertainSwipe == nil)
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

@Test func activationZoneRequiresAllHandsInsideConfiguredBounds() {
    let zone = GestureActivationZone(minX: 0.2, maxX: 0.8, minY: 0.2, maxY: 0.8)

    #expect(zone.contains(.init(x: 0.5, y: 0.5, shape: .openPalm)))
    #expect(!zone.contains(.init(x: 0.85, y: 0.5, shape: .openPalm)))
    #expect(zone.containsAll([
        .init(x: 0.3, y: 0.4, shape: .openPalm),
        .init(x: 0.6, y: 0.6, shape: .openPalm)
    ]))
    #expect(!zone.containsAll([
        .init(x: 0.3, y: 0.4, shape: .openPalm),
        .init(x: 0.9, y: 0.6, shape: .openPalm)
    ]))
}

@Test func holdRecognizerAcceptsStableOpenPalmHold() {
    let recognizer = GestureHoldRecognizer(requiredShape: .openPalm, minimumDurationMilliseconds: 280, maximumTravel: 0.05)
    let frames = [
        GestureFrameSnapshot(points: [.init(x: 0.48, y: 0.52, shape: .openPalm)], timestampMilliseconds: 0),
        GestureFrameSnapshot(points: [.init(x: 0.49, y: 0.52, shape: .openPalm)], timestampMilliseconds: 120),
        GestureFrameSnapshot(points: [.init(x: 0.50, y: 0.51, shape: .openPalm)], timestampMilliseconds: 320)
    ]

    #expect(recognizer.recognize(frames: frames) == .openPalmHold)
}

@Test func holdRecognizerRejectsMovingOrWrongShapeFrames() {
    let recognizer = GestureHoldRecognizer(requiredShape: .openPalm, minimumDurationMilliseconds: 280, maximumTravel: 0.05)
    let moving = [
        GestureFrameSnapshot(points: [.init(x: 0.30, y: 0.50, shape: .openPalm)], timestampMilliseconds: 0),
        GestureFrameSnapshot(points: [.init(x: 0.48, y: 0.50, shape: .openPalm)], timestampMilliseconds: 320),
        GestureFrameSnapshot(points: [.init(x: 0.62, y: 0.50, shape: .openPalm)], timestampMilliseconds: 420)
    ]
    let wrongShape = [
        GestureFrameSnapshot(points: [.init(x: 0.48, y: 0.52, shape: .openPalm)], timestampMilliseconds: 0),
        GestureFrameSnapshot(points: [.init(x: 0.49, y: 0.52, shape: .natural)], timestampMilliseconds: 120),
        GestureFrameSnapshot(points: [.init(x: 0.50, y: 0.51, shape: .openPalm)], timestampMilliseconds: 320)
    ]

    #expect(recognizer.recognize(frames: moving) == nil)
    #expect(recognizer.recognize(frames: wrongShape) == nil)
}

@Test func gestureSessionCoordinatorUnlocksEmitsAndCoolsDown() {
    var coordinator = GestureSessionCoordinator(activeWindowMilliseconds: 1_000, cooldownMilliseconds: 500)

    let initial = coordinator.refresh(at: 0)
    let unlock = coordinator.consume(.openPalmHold, at: 300)
    let emit = coordinator.consume(.swipeLeft, at: 500)
    let cooldown = coordinator.consume(.swipeRight, at: 700)
    let afterCooldown = coordinator.refresh(at: 1_100)
    let secondUnlock = coordinator.consume(.openPalmHold, at: 1_200)

    #expect(initial.state == .waiting)
    #expect(unlock.state == .armed)
    #expect(unlock.emittedGesture == nil)
    #expect(emit.state == .coolingDown)
    #expect(emit.emittedGesture == .swipeLeft)
    #expect(cooldown.emittedGesture == nil)
    #expect(afterCooldown.state == .waiting)
    #expect(secondUnlock.state == .armed)
}

@Test func swipeAndZoomCanEmitWithoutUnlockButCooldownStillApplies() {
    var coordinator = GestureSessionCoordinator(activeWindowMilliseconds: 1_000, cooldownMilliseconds: 500)

    let swipe = coordinator.consume(.swipeLeft, at: 100)
    let blockedByCooldown = coordinator.consume(.swipeRight, at: 200)
    let afterCooldown = coordinator.refresh(at: 700)
    let zoomAllowed = coordinator.consume(.zoomIn, at: 750)
    let unlock = coordinator.consume(.openPalmHold, at: 900)
    let zoomAllowedAfterUnlock = coordinator.consume(.zoomIn, at: 1_000)

    #expect(swipe.emittedGesture == .swipeLeft)
    #expect(swipe.state == .coolingDown)
    #expect(blockedByCooldown.emittedGesture == nil)
    #expect(afterCooldown.state == .waiting)
    #expect(zoomAllowed.emittedGesture == .zoomIn)
    #expect(unlock.state == .armed)
    #expect(zoomAllowedAfterUnlock.emittedGesture == .zoomIn)
}

@Test func mediaPipeAdapterMapsOfficialCategoriesToLocalHandShapes() {
    let openPalm = MediaPipeHandPrediction(
        handedness: "Right",
        handednessScore: 0.99,
        landmarks: Array(repeating: .init(x: 0.5, y: 0.5, z: 0), count: 21),
        gestureCategories: [.init(name: "Open_Palm", score: 0.95)]
    )
    let pointingUp = MediaPipeHandPrediction(
        handedness: "Right",
        handednessScore: 0.95,
        landmarks: Array(repeating: .init(x: 0.5, y: 0.5, z: 0), count: 21),
        gestureCategories: [.init(name: "Pointing_Up", score: 0.88)]
    )
    let fist = MediaPipeHandPrediction(
        handedness: "Left",
        handednessScore: 0.94,
        landmarks: Array(repeating: .init(x: 0.5, y: 0.5, z: 0), count: 21),
        gestureCategories: [.init(name: "Closed_Fist", score: 0.92)]
    )

    #expect(MediaPipeGestureAdapter.shape(for: openPalm) == .openPalm)
    #expect(MediaPipeGestureAdapter.shape(for: pointingUp) == .fingerGun)
    #expect(MediaPipeGestureAdapter.shape(for: fist) == .fist)
}

@Test func mediaPipeAdapterBuildsAnchorPointsFromLandmarks() {
    var landmarks = Array(repeating: MediaPipeNormalizedLandmark(x: 0, y: 0, z: 0), count: 21)
    landmarks[0] = .init(x: 0.2, y: 0.6, z: 0)
    landmarks[5] = .init(x: 0.4, y: 0.5, z: 0)
    landmarks[9] = .init(x: 0.6, y: 0.4, z: 0)
    landmarks[13] = .init(x: 0.8, y: 0.3, z: 0)
    landmarks[17] = .init(x: 0.5, y: 0.45, z: 0)
    let hand = MediaPipeHandPrediction(
        handedness: "Right",
        handednessScore: 0.99,
        landmarks: landmarks,
        gestureCategories: [.init(name: "Open_Palm", score: 0.95)]
    )

    let point = MediaPipeGestureAdapter.handPoints(from: [hand]).first

    #expect(point?.shape == .openPalm)
    #expect(point?.x == 0.5)
    #expect(point?.y == 0.45)
}

@Test func mediaPipeAdapterPreservesTimestampAndSortsHandsLeftToRight() {
    var leftLandmarks = Array(repeating: MediaPipeNormalizedLandmark(x: 0, y: 0, z: 0), count: 21)
    leftLandmarks[0] = .init(x: 0.18, y: 0.58, z: 0)
    leftLandmarks[5] = .init(x: 0.22, y: 0.55, z: 0)
    leftLandmarks[9] = .init(x: 0.24, y: 0.52, z: 0)
    leftLandmarks[13] = .init(x: 0.26, y: 0.49, z: 0)

    var rightLandmarks = Array(repeating: MediaPipeNormalizedLandmark(x: 0, y: 0, z: 0), count: 21)
    rightLandmarks[0] = .init(x: 0.74, y: 0.58, z: 0)
    rightLandmarks[5] = .init(x: 0.78, y: 0.55, z: 0)
    rightLandmarks[8] = .init(x: 0.84, y: 0.36, z: 0)
    rightLandmarks[9] = .init(x: 0.82, y: 0.52, z: 0)
    rightLandmarks[13] = .init(x: 0.86, y: 0.49, z: 0)

    let frame = MediaPipeInferenceFrame(
        timestampMilliseconds: 1_234,
        hands: [
            .init(
                handedness: "Right",
                handednessScore: 0.98,
                landmarks: rightLandmarks,
                gestureCategories: [.init(name: "Pointing_Up", score: 0.89)]
            ),
            .init(
                handedness: "Left",
                handednessScore: 0.97,
                landmarks: leftLandmarks,
                gestureCategories: [.init(name: "Open_Palm", score: 0.94)]
            )
        ]
    )

    let snapshot = MediaPipeGestureAdapter.snapshot(from: frame)

    #expect(snapshot.timestampMilliseconds == 1_234)
    #expect(snapshot.points.count == 2)
    #expect(snapshot.points[0].x < snapshot.points[1].x)
    #expect(snapshot.points[0].shape == .openPalm)
    #expect(snapshot.points[1].shape == .fingerGun)
}

@Test func mediaPipePayloadDecodesSnakeCaseSidecarResponse() throws {
    let payload = """
    {
      "timestamp_ms": 1234,
      "hands": [
        {
          "handedness": "Right",
          "handedness_score": 0.98,
          "landmarks": [
            { "x": 0.1, "y": 0.2, "z": 0.0 }
          ],
          "gesture_categories": [
            { "name": "Pointing_Up", "score": 0.91 }
          ]
        }
      ]
    }
    """.data(using: .utf8)!

    let frame = try JSONDecoder().decode(MediaPipeInferenceFrame.self, from: payload)

    #expect(frame.timestampMilliseconds == 1_234)
    #expect(frame.hands.count == 1)
    #expect(frame.hands[0].handednessScore == 0.98)
    #expect(frame.hands[0].gestureCategories.first?.name == "Pointing_Up")
}

@Test func mediaPipeAdapterBlendsPointingAnchorForStability() {
    var landmarks = Array(repeating: MediaPipeNormalizedLandmark(x: 0.0, y: 0.0, z: 0.0), count: 21)
    landmarks[0] = .init(x: 0.50, y: 0.70, z: 0.0)
    landmarks[5] = .init(x: 0.48, y: 0.60, z: 0.0)
    landmarks[8] = .init(x: 0.18, y: 0.34, z: 0.0)
    landmarks[9] = .init(x: 0.52, y: 0.58, z: 0.0)
    landmarks[13] = .init(x: 0.54, y: 0.56, z: 0.0)

    let hand = MediaPipeHandPrediction(
        handedness: "Right",
        handednessScore: 0.99,
        landmarks: landmarks,
        gestureCategories: [.init(name: "Pointing_Up", score: 0.97)]
    )

    let point = MediaPipeGestureAdapter.handPoints(from: [hand]).first

    #expect(point?.shape == .fingerGun)
    #expect(abs((point?.x ?? 0) - 0.27) < 0.0001)
    #expect(abs((point?.y ?? 0) - 0.418) < 0.0001)
}

@Test func mediaPipeAdapterUsesLShapeTipsForZoomAnchor() {
    var landmarks = Array(repeating: MediaPipeNormalizedLandmark(x: 0.0, y: 0.0, z: 0.0), count: 21)
    landmarks[0] = .init(x: 0.44, y: 0.72, z: 0.0)
    landmarks[4] = .init(x: 0.24, y: 0.42, z: 0.0)
    landmarks[5] = .init(x: 0.38, y: 0.60, z: 0.0)
    landmarks[8] = .init(x: 0.68, y: 0.30, z: 0.0)
    landmarks[9] = .init(x: 0.48, y: 0.58, z: 0.0)
    landmarks[13] = .init(x: 0.54, y: 0.56, z: 0.0)

    let hand = MediaPipeHandPrediction(
        handedness: "Left",
        handednessScore: 0.98,
        landmarks: landmarks,
        gestureCategories: [.init(name: "Victory", score: 0.96)]
    )

    let point = MediaPipeGestureAdapter.handPoints(from: [hand]).first

    #expect(point?.shape == .lShape)
    #expect(abs((point?.x ?? 0) - 0.444) < 0.0001)
    #expect(abs((point?.y ?? 0) - 0.408) < 0.0001)
}
