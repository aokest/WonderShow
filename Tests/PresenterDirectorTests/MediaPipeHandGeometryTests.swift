import Foundation
import Testing
@testable import PresenterDirector

@Test func mediaPipeHandGeometryRecognizesSwordPoseForSwipe() {
    let geometry = MediaPipeHandGeometry(
        prediction: makeHandPrediction(
            pose: .sword,
            centerX: 0.42,
            centerY: 0.62,
            scale: 1.0,
            handedness: "Right"
        )
    )

    #expect(geometry?.primaryShape == .sword)
}

@Test func mediaPipeHandGeometryAcceptsSwordWithSoftFoldedRingAndPinky() {
    let base = makeHandPrediction(
        pose: .sword,
        centerX: 0.42,
        centerY: 0.62,
        scale: 1.0,
        handedness: "Right"
    )
    var landmarks = base.landmarks
    landmarks[16] = point(0.49, 0.59)
    landmarks[20] = point(0.54, 0.59)
    let prediction = MediaPipeHandPrediction(
        handedness: base.handedness,
        handednessScore: base.handednessScore,
        landmarks: landmarks,
        gestureCategories: []
    )
    let geometry = MediaPipeHandGeometry(prediction: prediction)

    #expect(geometry?.ringExtended == true)
    #expect(geometry?.pinkyExtended == true)
    #expect(geometry?.primaryShape == .sword)
}

@Test func mediaPipeHandGeometryRecognizesStrictLShapeForZoom() {
    let geometry = MediaPipeHandGeometry(
        prediction: makeHandPrediction(
            pose: .strictLShape,
            centerX: 0.42,
            centerY: 0.62,
            scale: 1.0,
            handedness: "Right"
        )
    )

    #expect(geometry?.primaryShape == .lShape)
}

@Test func mediaPipeHandGeometryRecognizesLShapeWhenThumbDirectionDoesNotMatchHandedness() {
    let base = makeHandPrediction(
        pose: .strictLShape,
        centerX: 0.42,
        centerY: 0.62,
        scale: 1.0,
        handedness: "Right"
    )
    var landmarks = base.landmarks
    landmarks[4] = point(0.60, 0.60)
    let prediction = MediaPipeHandPrediction(
        handedness: base.handedness,
        handednessScore: base.handednessScore,
        landmarks: landmarks,
        gestureCategories: []
    )
    let geometry = MediaPipeHandGeometry(prediction: prediction)

    #expect(geometry?.thumbExtended == false)
    #expect(geometry?.thumbSpread == true)
    #expect(geometry?.primaryShape == .lShape)
}

@Test func gestureModeCoordinatorPrioritizesZoomOverSwipe() {
    var coordinator = GestureModeCoordinator(
        swipeProfile: .swipeDefault,
        zoomProfile: .zoomDefault
    )

    let enteredZoom = coordinator.update(
        swipeReady: true,
        zoomReady: true,
        timestampMilliseconds: 0
    )
    let activeZoom = coordinator.update(
        swipeReady: true,
        zoomReady: true,
        timestampMilliseconds: 140
    )
    let graceZoom = coordinator.update(
        swipeReady: true,
        zoomReady: false,
        timestampMilliseconds: 240
    )

    #expect(enteredZoom == .zoom)
    #expect(activeZoom == .zoom)
    #expect(graceZoom == .zoom)
}

@Test func twoHandZoomPoseDetectorRejectsNonZoomHands() {
    let detector = TwoHandZoomPoseDetector()
    let geometries = [
        MediaPipeHandGeometry(
            prediction: makeHandPrediction(
                pose: .strictLShape,
                centerX: 0.32,
                centerY: 0.62,
                scale: 1.0,
                handedness: "Left"
            )
        ),
        MediaPipeHandGeometry(
            prediction: makeHandPrediction(
                pose: .openPalm,
                centerX: 0.68,
                centerY: 0.62,
                scale: 1.0,
                handedness: "Right"
            )
        )
    ].compactMap { $0 }

    #expect(detector.isZoomReady(geometries: geometries) == false)
}

@Test func twoHandZoomPoseDetectorAllowsHandsToComeCloseForZoomOut() {
    let detector = TwoHandZoomPoseDetector()
    let geometries = [
        MediaPipeHandGeometry(
            prediction: makeHandPrediction(
                pose: .strictLShape,
                centerX: 0.45,
                centerY: 0.62,
                scale: 1.0,
                handedness: "Left"
            )
        ),
        MediaPipeHandGeometry(
            prediction: makeHandPrediction(
                pose: .strictLShape,
                centerX: 0.55,
                centerY: 0.62,
                scale: 1.0,
                handedness: "Right"
            )
        )
    ].compactMap { $0 }

    #expect(geometries.count == 2)
    #expect(geometries[0].normalizedDistance(to: geometries[1]) < 1.2)
    #expect(detector.isZoomReady(geometries: geometries))
}

@Test func mediaPipePalmAnchorsKeepZoomHandsInZoneWhenLegacyTipAnchorWouldExit() {
    let zone = GestureActivationZone(minX: 0.18, maxX: 0.82, minY: 0.20, maxY: 0.82)
    let prediction = makeHandPrediction(
        pose: .strictLShape,
        centerX: 0.32,
        centerY: 0.22,
        scale: 1.0,
        handedness: "Right",
        categories: [.init(name: "Victory", score: 0.96)]
    )

    let legacyAnchor = MediaPipeGestureAdapter.handPoints(from: [prediction]).first
    let palmAnchor = MediaPipeGestureAdapter.palmHandPoints(from: [prediction]).first

    #expect(legacyAnchor != nil)
    #expect(palmAnchor != nil)
    #expect(zone.contains(legacyAnchor!) == false)
    #expect(zone.contains(palmAnchor!) == true)
    #expect(palmAnchor?.shape == .lShape)
}

@Test func continuousZoomTrackerDoesNotReverseDirectionOnTinyJitter() {
    var tracker = ContinuousZoomTracker(
        minimumRelativeChange: 0.006,
        minimumScaleStep: 0.003,
        quietFramesToRebase: 3,
        maximumScaleDeltaPerUpdate: 0.05
    )

    _ = tracker.update(
        points: [
            .init(x: 0.34, y: 0.5, shape: .lShape),
            .init(x: 0.66, y: 0.5, shape: .lShape)
        ],
        currentScale: 1,
        timestampMilliseconds: 0
    )
    _ = tracker.update(
        points: [
            .init(x: 0.30, y: 0.5, shape: .lShape),
            .init(x: 0.70, y: 0.5, shape: .lShape)
        ],
        currentScale: 1,
        timestampMilliseconds: 120
    )
    let stableZoom = tracker.update(
        points: [
            .init(x: 0.24, y: 0.5, shape: .lShape),
            .init(x: 0.76, y: 0.5, shape: .lShape)
        ],
        currentScale: 1,
        timestampMilliseconds: 240
    )
    let jitter = tracker.update(
        points: [
            .init(x: 0.245, y: 0.5, shape: .lShape),
            .init(x: 0.755, y: 0.5, shape: .lShape)
        ],
        currentScale: stableZoom?.scale ?? 1,
        timestampMilliseconds: 320
    )

    #expect(stableZoom?.relativeDistanceChange ?? 0 > 0)
    #expect(jitter == nil || (jitter?.relativeDistanceChange ?? 0) >= 0)
}

@Test func continuousZoomTrackerRecognizesFastOutwardMotion() {
    var tracker = ContinuousZoomTracker(
        minimumRelativeChange: 0.006,
        minimumScaleStep: 0.003,
        quietFramesToRebase: 3,
        maximumScaleDeltaPerUpdate: 0.05
    )

    _ = tracker.update(
        points: [
            .init(x: 0.36, y: 0.5, shape: .lShape),
            .init(x: 0.64, y: 0.5, shape: .lShape)
        ],
        currentScale: 1,
        timestampMilliseconds: 0
    )
    _ = tracker.update(
        points: [
            .init(x: 0.34, y: 0.5, shape: .lShape),
            .init(x: 0.66, y: 0.5, shape: .lShape)
        ],
        currentScale: 1,
        timestampMilliseconds: 120
    )
    let fast = tracker.update(
        points: [
            .init(x: 0.16, y: 0.5, shape: .lShape),
            .init(x: 0.84, y: 0.5, shape: .lShape)
        ],
        currentScale: 1,
        timestampMilliseconds: 240
    )

    #expect((fast?.scale ?? 0) > 1)
    #expect((fast?.relativeDistanceChange ?? 0) > 0)
}

@Test func continuousZoomTrackerEmitsInwardMotionAfterDwellAndKeepsShrinkingAtCloseDistance() {
    var tracker = ContinuousZoomTracker()
    let frames = [
        (0, 0.30, 0.70, 1.0),
        (60, 0.34, 0.66, 1.0),
        (120, 0.40, 0.60, 1.0),
        (180, 0.45, 0.55, 0.95)
    ]

    let updates = frames.compactMap { timestamp, leftX, rightX, currentScale in
        tracker.update(
            geometries: [
                MediaPipeHandGeometry(
                    prediction: makeHandPrediction(
                        pose: .strictLShape,
                        centerX: leftX,
                        centerY: 0.62,
                        scale: 1.0,
                        handedness: "Left"
                    )
                ),
                MediaPipeHandGeometry(
                    prediction: makeHandPrediction(
                        pose: .strictLShape,
                        centerX: rightX,
                        centerY: 0.62,
                        scale: 1.0,
                        handedness: "Right"
                    )
                )
            ].compactMap { $0 },
            currentScale: currentScale,
            timestampMilliseconds: timestamp
        )
    }

    #expect(updates.contains { $0.relativeDistanceChange < 0 && $0.scale < 1.0 })
    #expect(updates.last?.relativeDistanceChange ?? 0 < 0)
}

@Test func continuousZoomTrackerUsesScreenDistanceForGeometryDirectionWhenPalmSizeChanges() {
    var tracker = ContinuousZoomTracker()
    let frames = [
        (0, 0.26, 0.74, 0.75, 1.0),
        (60, 0.30, 0.70, 1.00, 1.0),
        (120, 0.36, 0.64, 1.20, 1.0),
        (180, 0.42, 0.58, 1.35, 0.96)
    ]

    let updates = frames.compactMap { timestamp, leftX, rightX, handScale, currentScale in
        tracker.update(
            geometries: [
                MediaPipeHandGeometry(
                    prediction: makeHandPrediction(
                        pose: .strictLShape,
                        centerX: leftX,
                        centerY: 0.62,
                        scale: handScale,
                        handedness: "Left"
                    )
                ),
                MediaPipeHandGeometry(
                    prediction: makeHandPrediction(
                        pose: .strictLShape,
                        centerX: rightX,
                        centerY: 0.62,
                        scale: handScale,
                        handedness: "Right"
                    )
                )
            ].compactMap { $0 },
            currentScale: currentScale,
            timestampMilliseconds: timestamp
        )
    }

    #expect(updates.contains { $0.relativeDistanceChange < 0 })
    #expect((updates.last?.scale ?? 1.0) < 1.0)
}

@Test func streamingGestureRecognizerTreatsPreviousAndNextSymmetrically() {
    let recognizer = StreamingGestureRecognizer(profile: .easyTesting)
    let leftFrames = [
        GestureFrameSnapshot(points: [.init(x: 0.70, y: 0.50, shape: .sword)], timestampMilliseconds: 0),
        GestureFrameSnapshot(points: [.init(x: 0.61, y: 0.50, shape: .sword)], timestampMilliseconds: 60),
        GestureFrameSnapshot(points: [.init(x: 0.50, y: 0.50, shape: .sword)], timestampMilliseconds: 120),
        GestureFrameSnapshot(points: [.init(x: 0.39, y: 0.50, shape: .sword)], timestampMilliseconds: 180)
    ]
    let rightFrames = [
        GestureFrameSnapshot(points: [.init(x: 0.30, y: 0.50, shape: .sword)], timestampMilliseconds: 0),
        GestureFrameSnapshot(points: [.init(x: 0.39, y: 0.50, shape: .sword)], timestampMilliseconds: 60),
        GestureFrameSnapshot(points: [.init(x: 0.50, y: 0.50, shape: .sword)], timestampMilliseconds: 120),
        GestureFrameSnapshot(points: [.init(x: 0.61, y: 0.50, shape: .sword)], timestampMilliseconds: 180)
    ]

    #expect(recognizer.recognize(frames: leftFrames) == .swipeLeft)
    #expect(recognizer.recognize(frames: rightFrames) == .swipeRight)
}

private enum TestHandPose {
    case natural
    case openPalm
    case sword
    case strictLShape
}

/// Builds a synthetic MediaPipe hand prediction for unit tests.
/// - Parameters:
///   - pose: Target pose classification to synthesize.
///   - centerX: Approximate palm center x coordinate.
///   - centerY: Approximate palm center y coordinate.
///   - scale: Relative hand size multiplier.
///   - handedness: Handedness label used by thumb heuristics.
/// - Returns: A full 21-point prediction that matches the requested pose.
private func makeHandPrediction(
    pose: TestHandPose,
    centerX: Double,
    centerY: Double,
    scale: Double,
    handedness: String,
    categories: [MediaPipeGestureCategory] = []
) -> MediaPipeHandPrediction {
    var landmarks = Array(
        repeating: MediaPipeNormalizedLandmark(x: centerX, y: centerY, z: 0),
        count: 21
    )

    let wrist = point(centerX, centerY + 0.12 * scale)
    landmarks[0] = wrist

    let thumbDirection = handedness.lowercased().contains("left") ? 1.0 : -1.0
    let thumbMCP = point(centerX + thumbDirection * 0.10 * scale, centerY + 0.04 * scale)
    let thumbIP = point(centerX + thumbDirection * 0.13 * scale, centerY)
    let thumbTip: MediaPipeNormalizedLandmark
    switch pose {
    case .strictLShape:
        thumbTip = point(centerX + thumbDirection * 0.20 * scale, centerY - 0.02 * scale)
    case .natural, .openPalm, .sword:
        thumbTip = point(centerX + thumbDirection * 0.06 * scale, centerY + 0.06 * scale)
    }

    landmarks[1] = point(centerX + thumbDirection * 0.07 * scale, centerY + 0.08 * scale)
    landmarks[2] = thumbMCP
    landmarks[3] = thumbIP
    landmarks[4] = thumbTip

    applyFinger(
        to: &landmarks,
        mcpIndex: 5,
        pipIndex: 6,
        dipIndex: 7,
        tipIndex: 8,
        mcp: point(centerX - 0.05 * scale, centerY + 0.02 * scale),
        extended: true,
        horizontalOffset: pose == .sword ? -0.004 * scale : -0.01 * scale
    )
    applyFinger(
        to: &landmarks,
        mcpIndex: 9,
        pipIndex: 10,
        dipIndex: 11,
        tipIndex: 12,
        mcp: point(centerX, centerY),
        extended: pose == .sword || pose == .openPalm,
        horizontalOffset: 0
    )
    applyFinger(
        to: &landmarks,
        mcpIndex: 13,
        pipIndex: 14,
        dipIndex: 15,
        tipIndex: 16,
        mcp: point(centerX + 0.05 * scale, centerY + 0.02 * scale),
        extended: pose == .openPalm,
        horizontalOffset: 0.01 * scale
    )
    applyFinger(
        to: &landmarks,
        mcpIndex: 17,
        pipIndex: 18,
        dipIndex: 19,
        tipIndex: 20,
        mcp: point(centerX + 0.09 * scale, centerY + 0.05 * scale),
        extended: pose == .openPalm,
        horizontalOffset: 0.02 * scale
    )

    return MediaPipeHandPrediction(
        handedness: handedness,
        handednessScore: 0.99,
        landmarks: landmarks,
        gestureCategories: categories
    )
}

/// Populates a single finger chain for a synthetic test hand.
/// - Parameters:
///   - landmarks: Output 21-point landmark array.
///   - mcpIndex: MCP landmark index.
///   - pipIndex: PIP landmark index.
///   - dipIndex: DIP landmark index.
///   - tipIndex: TIP landmark index.
///   - mcp: MCP point for the finger.
///   - extended: Whether the finger should be synthesized as extended.
///   - horizontalOffset: Slight x offset used to separate adjacent fingers.
private func applyFinger(
    to landmarks: inout [MediaPipeNormalizedLandmark],
    mcpIndex: Int,
    pipIndex: Int,
    dipIndex: Int,
    tipIndex: Int,
    mcp: MediaPipeNormalizedLandmark,
    extended: Bool,
    horizontalOffset: Double
) {
    landmarks[mcpIndex] = mcp
    if extended {
        landmarks[pipIndex] = point(mcp.x + horizontalOffset * 0.4, mcp.y - 0.16)
        landmarks[dipIndex] = point(mcp.x + horizontalOffset * 0.8, mcp.y - 0.28)
        landmarks[tipIndex] = point(mcp.x + horizontalOffset, mcp.y - 0.38)
    } else {
        landmarks[pipIndex] = point(mcp.x + horizontalOffset * 0.1, mcp.y + 0.02)
        landmarks[dipIndex] = point(mcp.x + horizontalOffset * 0.2, mcp.y + 0.04)
        landmarks[tipIndex] = point(mcp.x + horizontalOffset * 0.3, mcp.y + 0.06)
    }
}

/// Builds a normalized landmark point used by synthetic test hands.
/// - Parameters:
///   - x: Normalized horizontal coordinate.
///   - y: Normalized vertical coordinate.
/// - Returns: A normalized MediaPipe landmark with zero depth.
private func point(_ x: Double, _ y: Double) -> MediaPipeNormalizedLandmark {
    MediaPipeNormalizedLandmark(x: x, y: y, z: 0)
}
