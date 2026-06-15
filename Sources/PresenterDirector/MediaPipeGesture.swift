/// Represents a single normalized landmark returned by MediaPipe.
/// - Parameters:
///   - x: Normalized horizontal position in the `0...1` range.
///   - y: Normalized vertical position in the `0...1` range.
///   - z: Relative depth value reported by MediaPipe.
public struct MediaPipeNormalizedLandmark: Hashable, Sendable, Codable {
    public let x: Double
    public let y: Double
    public let z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

/// Represents a gesture category predicted by MediaPipe.
/// - Parameters:
///   - name: Gesture label such as `Open_Palm` or `Pointing_Up`.
///   - score: Confidence score in the `0...1` range.
public struct MediaPipeGestureCategory: Hashable, Sendable, Codable {
    public let name: String
    public let score: Double

    enum CodingKeys: String, CodingKey {
        case name
        case score
    }

    public init(name: String, score: Double) {
        self.name = name
        self.score = score
    }
}

/// Represents a single hand prediction returned by MediaPipe.
/// - Parameters:
///   - handedness: Handedness label such as `Left` or `Right`.
///   - handednessScore: Confidence of the handedness classification.
///   - landmarks: Full 21-point hand landmark set.
///   - gestureCategories: Gesture classifier output sorted by descending score.
public struct MediaPipeHandPrediction: Hashable, Sendable, Codable {
    public let handedness: String
    public let handednessScore: Double
    public let landmarks: [MediaPipeNormalizedLandmark]
    public let gestureCategories: [MediaPipeGestureCategory]

    enum CodingKeys: String, CodingKey {
        case handedness
        case handednessScore = "handedness_score"
        case landmarks
        case gestureCategories = "gesture_categories"
    }

    public init(
        handedness: String,
        handednessScore: Double,
        landmarks: [MediaPipeNormalizedLandmark],
        gestureCategories: [MediaPipeGestureCategory]
    ) {
        self.handedness = handedness
        self.handednessScore = handednessScore
        self.landmarks = landmarks
        self.gestureCategories = gestureCategories
    }

    /// Returns the highest-confidence gesture category, if available.
    public var topGestureCategory: MediaPipeGestureCategory? {
        gestureCategories.max(by: { $0.score < $1.score })
    }
}

/// Represents an inference frame returned by the MediaPipe sidecar.
/// - Parameters:
///   - timestampMilliseconds: Echoed frame timestamp.
///   - hands: Zero, one, or two hand predictions for the frame.
public struct MediaPipeInferenceFrame: Hashable, Sendable, Codable {
    public let timestampMilliseconds: Int
    public let hands: [MediaPipeHandPrediction]

    enum CodingKeys: String, CodingKey {
        case timestampMilliseconds = "timestamp_ms"
        case hands
    }

    public init(timestampMilliseconds: Int, hands: [MediaPipeHandPrediction]) {
        self.timestampMilliseconds = timestampMilliseconds
        self.hands = hands
    }
}

/// Converts MediaPipe predictions into the existing lightweight gesture structures.
/// - Note: This adapter keeps the current Swift gesture pipeline working while upgrading
///   the detector from Vision anchors to MediaPipe landmarks.
public enum MediaPipeGestureAdapter {
    /// Converts MediaPipe hands into full 21-point geometries sorted from left to right.
    /// - Parameter hands: MediaPipe hand predictions sorted in any order.
    /// - Returns: Stable geometries consumed by the v0.7 gesture engine.
    public static func handGeometries(from hands: [MediaPipeHandPrediction]) -> [MediaPipeHandGeometry] {
        hands
            .compactMap(MediaPipeHandGeometry.init(prediction:))
            .sorted { $0.palmCenter.x < $1.palmCenter.x }
    }

    /// Projects MediaPipe hands into anchor-based points consumed by the current gesture pipeline.
    /// - Parameter hands: MediaPipe hand predictions sorted in any order.
    /// - Returns: Hand anchor points sorted from left to right.
    public static func handPoints(from hands: [MediaPipeHandPrediction]) -> [HandPoint] {
        hands
            .compactMap { hand -> HandPoint? in
                guard let anchor = anchorPoint(for: hand) else { return nil }
                return HandPoint(x: anchor.x, y: anchor.y, shape: shape(for: hand))
            }
            .sorted { $0.x < $1.x }
    }

    /// Builds a gesture frame snapshot using MediaPipe-derived anchor points.
    /// - Parameters:
    ///   - frame: MediaPipe inference frame.
    /// - Returns: A normalized snapshot compatible with the current recognizers.
    public static func snapshot(from frame: MediaPipeInferenceFrame) -> GestureFrameSnapshot {
        GestureFrameSnapshot(
            points: handPoints(from: frame.hands),
            timestampMilliseconds: frame.timestampMilliseconds
        )
    }

    /// Maps MediaPipe gesture categories to the local hand-shape vocabulary.
    /// - Parameter hand: A MediaPipe hand prediction.
    /// - Returns: The closest matching local hand shape.
    public static func shape(for hand: MediaPipeHandPrediction) -> HandShape {
        switch hand.topGestureCategory?.name {
        case "Open_Palm":
            return .openPalm
        case "Closed_Fist":
            return .fist
        case "Pointing_Up":
            return .fingerGun
        case "Victory":
            return .lShape
        case "Thumb_Up", "Thumb_Down", "ILoveYou":
            return .natural
        default:
            return MediaPipeHandGeometry(prediction: hand)?.primaryShape ?? .natural
        }
    }

    /// Computes a stable anchor point from the wrist and MCP joints.
    /// - Parameter landmarks: Full 21-point MediaPipe hand landmarks.
    /// - Returns: A single anchor point or `nil` when landmarks are incomplete.
    public static func anchorPoint(for hand: MediaPipeHandPrediction) -> (x: Double, y: Double)? {
        let landmarks = hand.landmarks
        guard landmarks.count >= 18 else { return nil }

        if hand.topGestureCategory?.name == "Pointing_Up" {
            return blend(
                primary: landmarks[8],
                secondary: landmarks[5],
                primaryWeight: 0.7
            )
        }

        if hand.topGestureCategory?.name == "Victory" {
            let tipMidpoint = midpoint(landmarks[4], landmarks[8])
            return blend(primary: tipMidpoint, secondary: landmarks[5], primaryWeight: 0.8)
        }

        return centroid(of: [landmarks[0], landmarks[5], landmarks[9], landmarks[13], landmarks[17]])
    }

    /// Blends two landmarks into a single weighted anchor to keep motion responsive while reducing jitter.
    /// - Parameters:
    ///   - primary: Landmark that should dominate the resulting anchor.
    ///   - secondary: Landmark used to stabilize the anchor.
    ///   - primaryWeight: Weight applied to the dominant landmark in the `0...1` range.
    /// - Returns: A weighted anchor point.
    private static func blend(
        primary: MediaPipeNormalizedLandmark,
        secondary: MediaPipeNormalizedLandmark,
        primaryWeight: Double
    ) -> (x: Double, y: Double) {
        let clampedWeight = min(1, max(0, primaryWeight))
        let secondaryWeight = 1 - clampedWeight
        return (
            x: primary.x * clampedWeight + secondary.x * secondaryWeight,
            y: primary.y * clampedWeight + secondary.y * secondaryWeight
        )
    }

    /// Computes the midpoint between two landmarks.
    /// - Parameters:
    ///   - lhs: First landmark.
    ///   - rhs: Second landmark.
    /// - Returns: The center point between both landmarks.
    private static func midpoint(
        _ lhs: MediaPipeNormalizedLandmark,
        _ rhs: MediaPipeNormalizedLandmark
    ) -> MediaPipeNormalizedLandmark {
        MediaPipeNormalizedLandmark(
            x: (lhs.x + rhs.x) / 2,
            y: (lhs.y + rhs.y) / 2,
            z: (lhs.z + rhs.z) / 2
        )
    }

    /// Computes the centroid of a small landmark set used as a stable palm anchor.
    /// - Parameter landmarks: Landmarks that should contribute equally to the anchor.
    /// - Returns: The centroid of the provided landmarks.
    private static func centroid(
        of landmarks: [MediaPipeNormalizedLandmark]
    ) -> (x: Double, y: Double) {
        let x = landmarks.map(\.x).reduce(0, +) / Double(landmarks.count)
        let y = landmarks.map(\.y).reduce(0, +) / Double(landmarks.count)
        return (x, y)
    }
}
