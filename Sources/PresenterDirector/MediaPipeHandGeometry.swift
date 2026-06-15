/// Represents a normalized 2D point derived from MediaPipe landmarks.
/// - Parameters:
///   - x: Normalized horizontal coordinate in the `0...1` range.
///   - y: Normalized vertical coordinate in the `0...1` range.
public struct GestureNormalizedPoint: Hashable, Sendable, Codable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// Computes the Euclidean distance to another normalized point.
    /// - Parameter other: Another normalized point in the same coordinate space.
    /// - Returns: The scalar distance between both points.
    public func distance(to other: GestureNormalizedPoint) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// Encapsulates 21-point MediaPipe geometry and derived pose heuristics for one hand.
/// - Parameters:
///   - prediction: The raw MediaPipe prediction returned by the local sidecar.
/// - Important: All derived values are normalized by palm size so the same thresholds
///   keep working across different camera distances.
public struct MediaPipeHandGeometry: Hashable, Sendable, Codable {
    public let handedness: String
    public let handednessScore: Double
    public let landmarks: [MediaPipeNormalizedLandmark]
    public let gestureCategory: String?

    public init?(prediction: MediaPipeHandPrediction) {
        guard prediction.landmarks.count >= 21 else {
            return nil
        }
        handedness = prediction.handedness
        handednessScore = prediction.handednessScore
        landmarks = prediction.landmarks
        gestureCategory = prediction.topGestureCategory?.name
    }

    /// Returns the wrist point for the current hand.
    /// - Returns: The wrist landmark in normalized coordinates.
    public var wrist: GestureNormalizedPoint {
        point(at: 0)
    }

    /// Returns the palm center computed from the wrist and MCP joints.
    /// - Returns: The palm center used as a stable hand anchor.
    public var palmCenter: GestureNormalizedPoint {
        let anchors = [0, 5, 9, 13, 17].map(point(at:))
        let x = anchors.map(\.x).reduce(0, +) / Double(anchors.count)
        let y = anchors.map(\.y).reduce(0, +) / Double(anchors.count)
        return GestureNormalizedPoint(x: x, y: y)
    }

    /// Returns the normalized palm size used as the dynamic unit for thresholds.
    /// - Returns: The wrist-to-middle-MCP distance with a tiny lower bound.
    public var palmSize: Double {
        max(0.0001, point(at: 0).distance(to: point(at: 9)))
    }

    /// Returns the thumb tip point.
    /// - Returns: The thumb tip in normalized coordinates.
    public var thumbTip: GestureNormalizedPoint {
        point(at: 4)
    }

    /// Returns the index finger tip point.
    /// - Returns: The index tip in normalized coordinates.
    public var indexTip: GestureNormalizedPoint {
        point(at: 8)
    }

    /// Returns the middle finger tip point.
    /// - Returns: The middle tip in normalized coordinates.
    public var middleTip: GestureNormalizedPoint {
        point(at: 12)
    }

    /// Returns the normalized thumb-to-index distance.
    /// - Returns: The pinch distance expressed in palm-size units.
    public var thumbIndexPinch: Double {
        point(at: 4).distance(to: point(at: 8)) / palmSize
    }

    /// Returns whether the index finger is clearly extended.
    /// - Returns: `true` when the wrist-to-tip ratio exceeds the extension threshold.
    public var indexExtended: Bool {
        extensionRatio(tip: 8, mcp: 5) > 1.45
    }

    /// Returns whether the middle finger is clearly extended.
    /// - Returns: `true` when the wrist-to-tip ratio exceeds the extension threshold.
    public var middleExtended: Bool {
        extensionRatio(tip: 12, mcp: 9) > 1.45
    }

    /// Returns whether the ring finger is clearly extended.
    /// - Returns: `true` when the wrist-to-tip ratio exceeds the extension threshold.
    public var ringExtended: Bool {
        extensionRatio(tip: 16, mcp: 13) > 1.45
    }

    /// Returns whether the pinky finger is clearly extended.
    /// - Returns: `true` when the wrist-to-tip ratio exceeds the extension threshold.
    public var pinkyExtended: Bool {
        extensionRatio(tip: 20, mcp: 17) > 1.45
    }

    /// Returns whether the thumb is extended sideways using handedness-aware geometry.
    /// - Returns: `true` when the thumb tip clearly leaves the palm on the handedness side.
    public var thumbExtended: Bool {
        let ip = point(at: 3)
        let tip = point(at: 4)
        let threshold = max(0.035, palmSize * 0.22)
        let delta = tip.x - ip.x
        let label = handedness.lowercased()

        if label.contains("right") {
            return delta < -threshold
        }
        if label.contains("left") {
            return delta > threshold
        }
        return abs(delta) > threshold
    }

    /// Returns whether the hand looks like a deliberate sword pose.
    /// - Returns: `true` when index and middle fingers are extended together while the others stay folded.
    public var isSwordPose: Bool {
        guard indexExtended, middleExtended, !ringExtended, !pinkyExtended else {
            return false
        }
        let verticalGap = abs(indexTip.y - middleTip.y)
        let horizontalGap = abs(indexTip.x - middleTip.x)
        return verticalGap <= palmSize * 0.35 && horizontalGap <= palmSize * 0.45
    }

    /// Returns whether the hand looks like a strict L shape for two-hand zoom.
    /// - Returns: `true` when thumb and index are extended but middle, ring, and pinky stay folded.
    public var isStrictLShape: Bool {
        thumbExtended && indexExtended && !middleExtended && !ringExtended && !pinkyExtended
    }

    /// Returns whether the hand looks like a one-finger pointing pose.
    /// - Returns: `true` when only the index finger is extended.
    public var isPointingPose: Bool {
        indexExtended && !middleExtended && !ringExtended && !pinkyExtended
    }

    /// Returns whether the hand looks like an open palm.
    /// - Returns: `true` when at least four fingers are extended.
    public var isOpenPalm: Bool {
        let extendedCount = [thumbExtended, indexExtended, middleExtended, ringExtended, pinkyExtended]
            .filter { $0 }
            .count
        return extendedCount >= 4
    }

    /// Returns whether the hand looks like a fist.
    /// - Returns: `true` when none of the non-thumb fingers are extended and the thumb stays tucked.
    public var isFist: Bool {
        !thumbExtended && !indexExtended && !middleExtended && !ringExtended && !pinkyExtended
    }

    /// Returns the primary local hand shape for downstream recognizers.
    /// - Returns: A stable `HandShape` derived from geometry rather than MediaPipe categories.
    public var primaryShape: HandShape {
        if isStrictLShape {
            return .lShape
        }
        if isSwordPose {
            return .sword
        }
        if isPointingPose {
            return .fingerGun
        }
        if isOpenPalm {
            return .openPalm
        }
        if isFist {
            return .fist
        }
        return .natural
    }

    /// Converts the geometry into the lightweight anchor used by existing strategy code.
    /// - Returns: A `HandPoint` anchored at the palm center with the derived shape attached.
    public func asHandPoint() -> HandPoint {
        HandPoint(x: palmCenter.x, y: palmCenter.y, shape: primaryShape)
    }

    /// Computes the normalized two-hand distance against another hand.
    /// - Parameter other: The other hand in the same frame.
    /// - Returns: Palm-center distance normalized by the larger palm size.
    public func normalizedDistance(to other: MediaPipeHandGeometry) -> Double {
        let denominator = max(palmSize, other.palmSize, 0.0001)
        return palmCenter.distance(to: other.palmCenter) / denominator
    }

    /// Returns a landmark converted to the local normalized-point helper type.
    /// - Parameter index: MediaPipe landmark index in the `0...20` range.
    /// - Returns: The requested landmark converted to `GestureNormalizedPoint`.
    public func point(at index: Int) -> GestureNormalizedPoint {
        let landmark = landmarks[index]
        return GestureNormalizedPoint(x: landmark.x, y: landmark.y)
    }

    /// Computes the extension ratio for a finger using wrist-to-tip and wrist-to-MCP distances.
    /// - Parameters:
    ///   - tip: MediaPipe tip landmark index.
    ///   - mcp: MediaPipe MCP landmark index.
    /// - Returns: A scale-normalized finger extension ratio.
    public func extensionRatio(tip: Int, mcp: Int) -> Double {
        let wrist = point(at: 0)
        let numerator = wrist.distance(to: point(at: tip))
        let denominator = max(0.0001, wrist.distance(to: point(at: mcp)))
        return numerator / denominator
    }
}

/// Detects whether the current hand configuration is eligible for single-hand swipe recognition.
/// - Parameters:
///   - acceptedShapes: Allowed swipe-ready shapes, ordered from most preferred to most legacy-compatible.
public struct SwipeReadyDetector: Sendable {
    public let acceptedShapes: [HandShape]

    public init(acceptedShapes: [HandShape] = [.sword, .fingerGun]) {
        self.acceptedShapes = acceptedShapes
    }

    /// Returns whether a single-hand frame is allowed to enter the swipe recognizer.
    /// - Parameter points: The current primary hand points after zone filtering.
    /// - Returns: `true` when exactly one hand is present and its shape is explicitly swipe-ready.
    public func isSwipeReady(points: [HandPoint]) -> Bool {
        guard points.count == 1 else {
            return false
        }
        return acceptedShapes.contains(points[0].shape)
    }

    /// Returns whether a single MediaPipe geometry is allowed to enter the swipe recognizer.
    /// - Parameter geometries: The current active hand geometries after zone filtering.
    /// - Returns: `true` when exactly one hand is present and its derived pose is swipe-ready.
    public func isSwipeReady(geometries: [MediaPipeHandGeometry]) -> Bool {
        guard geometries.count == 1 else {
            return false
        }
        return acceptedShapes.contains(geometries[0].primaryShape)
    }
}

/// Detects whether two hands form the strict zoom pose required by the v0.7 gesture engine.
/// - Parameters:
///   - minimumNormalizedHandDistance: Minimum palm-center separation in palm-size units.
public struct TwoHandZoomPoseDetector: Sendable {
    public let minimumNormalizedHandDistance: Double

    public init(minimumNormalizedHandDistance: Double = 1.2) {
        self.minimumNormalizedHandDistance = minimumNormalizedHandDistance
    }

    /// Returns whether two MediaPipe hands form a deliberate two-hand zoom pose.
    /// - Parameter geometries: The current active hands sorted from left to right.
    /// - Returns: `true` when both hands are strict L shapes and sufficiently separated.
    public func isZoomReady(geometries: [MediaPipeHandGeometry]) -> Bool {
        guard geometries.count >= 2 else {
            return false
        }

        let hands = Array(geometries.prefix(2))
        guard hands.allSatisfy(\.isStrictLShape) else {
            return false
        }

        return hands[0].normalizedDistance(to: hands[1]) >= minimumNormalizedHandDistance
    }

    /// Returns whether two lightweight hand points still look like the strict zoom pose.
    /// - Parameter points: The current active points sorted from left to right.
    /// - Returns: `true` when both points are already classified as `.lShape`.
    public func isZoomReady(points: [HandPoint]) -> Bool {
        guard points.count >= 2 else {
            return false
        }
        return Array(points.prefix(2)).allSatisfy { $0.shape == .lShape }
    }
}
