public enum GestureIntent: String, Hashable, Sendable, Codable, CaseIterable {
    case swipeLeft
    case swipeRight
    case zoomIn
    case zoomOut
    case startPresentation
    case exitPresentation
    case toggleRecording
    case pinchToggle
    case pinchDrag
    case openPalmHold
}

public enum PresentationAction: Hashable, Sendable {
    case nextSlide
    case previousSlide
    case toggleAnnotation
    case drawAnnotation
    case clearAnnotations
    case zoomIn
    case zoomOut
    case setZoom(Double)
    case setPan(x: Double, y: Double)
    case startPresentation
    case exitPresentation
    case toggleRecording
    case none
}

public enum CommandTransport: Hashable, Sendable {
    case keyboardShortcut
    case accessibilityAutomation
    case htmlBridge
    case internalOverlay
}

public struct GestureMotion: Hashable, Sendable {
    public let horizontalTravel: Double
    public let verticalTravel: Double
    public let durationMilliseconds: Int

    public init(horizontalTravel: Double, verticalTravel: Double, durationMilliseconds: Int) {
        self.horizontalTravel = horizontalTravel
        self.verticalTravel = verticalTravel
        self.durationMilliseconds = durationMilliseconds
    }
}

public struct GestureCalibrationSample: Hashable, Sendable {
    public let intent: GestureIntent
    public let horizontalTravel: Double
    public let verticalTravel: Double
    public let durationMilliseconds: Int

    public init(
        intent: GestureIntent,
        horizontalTravel: Double,
        verticalTravel: Double,
        durationMilliseconds: Int
    ) {
        self.intent = intent
        self.horizontalTravel = horizontalTravel
        self.verticalTravel = verticalTravel
        self.durationMilliseconds = durationMilliseconds
    }
}

public struct GestureProfile: Hashable, Sendable {
    public let minimumHorizontalTravel: Double
    public let minimumZoomDistanceChange: Double
    public let maximumGestureDurationMilliseconds: Int
    public let acceptsNaturalHandSwipe: Bool

    public init(
        minimumHorizontalTravel: Double,
        minimumZoomDistanceChange: Double,
        maximumGestureDurationMilliseconds: Int,
        acceptsNaturalHandSwipe: Bool = false
    ) {
        self.minimumHorizontalTravel = minimumHorizontalTravel
        self.minimumZoomDistanceChange = minimumZoomDistanceChange
        self.maximumGestureDurationMilliseconds = maximumGestureDurationMilliseconds
        self.acceptsNaturalHandSwipe = acceptsNaturalHandSwipe
    }

    public static let `default` = GestureProfile(
        minimumHorizontalTravel: 0.18,
        minimumZoomDistanceChange: 0.14,
        maximumGestureDurationMilliseconds: 800
    )

    public static let easyTesting = GestureProfile(
        minimumHorizontalTravel: 0.10,
        minimumZoomDistanceChange: 0.10,
        maximumGestureDurationMilliseconds: 1_400,
        acceptsNaturalHandSwipe: true
    )
}

public struct GestureCalibration: Sendable {
    public let samples: [GestureCalibrationSample]

    public init(samples: [GestureCalibrationSample]) {
        self.samples = samples
    }

    public func makeProfile() -> GestureProfile {
        let horizontalSamples = samples
            .filter { $0.intent == .swipeLeft || $0.intent == .swipeRight }
            .map { abs($0.horizontalTravel) }

        let horizontalAverage = horizontalSamples.average ?? GestureProfile.default.minimumHorizontalTravel

        return GestureProfile(
            minimumHorizontalTravel: max(0.16, horizontalAverage * 0.72),
            minimumZoomDistanceChange: GestureProfile.default.minimumZoomDistanceChange,
            maximumGestureDurationMilliseconds: GestureProfile.default.maximumGestureDurationMilliseconds
        )
    }
}

public struct MotionGestureRecognizer: Sendable {
    public let profile: GestureProfile

    public init(profile: GestureProfile) {
        self.profile = profile
    }

    public func recognize(_ motion: GestureMotion) -> GestureIntent? {
        guard motion.durationMilliseconds <= profile.maximumGestureDurationMilliseconds else {
            return nil
        }

        let horizontal = motion.horizontalTravel
        let vertical = motion.verticalTravel

        if abs(horizontal) >= profile.minimumHorizontalTravel, abs(horizontal) > abs(vertical) * 1.35 {
            return horizontal < 0 ? .swipeLeft : .swipeRight
        }

        return nil
    }
}

public struct HandPoint: Hashable, Sendable, Codable {
    public let x: Double
    public let y: Double
    public let shape: HandShape

    public init(x: Double, y: Double, shape: HandShape = .unknown) {
        self.x = x
        self.y = y
        self.shape = shape
    }

    public func distance(to other: HandPoint) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

public struct GestureFrameSnapshot: Hashable, Sendable, Codable {
    public let points: [HandPoint]
    public let timestampMilliseconds: Int

    public init(points: [HandPoint], timestampMilliseconds: Int) {
        self.points = points
        self.timestampMilliseconds = timestampMilliseconds
    }
}

public enum HandShape: String, Hashable, Sendable, Codable {
    case unknown
    case natural
    case openPalm
    case fist
    case fingerGun
    case lShape

    public var allowsSwipe: Bool {
        self == .fingerGun || self == .lShape || self == .unknown
    }

    public func allowsSwipe(profile: GestureProfile) -> Bool {
        allowsSwipe || (profile.acceptsNaturalHandSwipe && self == .natural)
    }

    public var allowsZoom: Bool {
        self == .lShape || self == .fingerGun || self == .unknown
    }
}

public struct GestureTemplate: Hashable, Sendable, Codable {
    public let intent: GestureIntent
    public let frames: [GestureFrameSnapshot]
    public let createdAtMilliseconds: Int

    public init(intent: GestureIntent, frames: [GestureFrameSnapshot], createdAtMilliseconds: Int) {
        self.intent = intent
        self.frames = Self.normalized(frames)
        self.createdAtMilliseconds = createdAtMilliseconds
    }

    public var isUsable: Bool {
        frames.count >= 4 && primaryTravel >= 0.08
    }

    public var primaryTravel: Double {
        guard let first = frames.first?.points.first, let last = frames.last?.points.first else {
            return 0
        }
        return first.distance(to: last)
    }

    public var primaryHorizontalTravel: Double {
        guard let first = frames.first?.points.first, let last = frames.last?.points.first else {
            return 0
        }
        return last.x - first.x
    }

    public var primaryVerticalTravel: Double {
        guard let first = frames.first?.points.first, let last = frames.last?.points.first else {
            return 0
        }
        return last.y - first.y
    }

    public var twoHandDistanceChange: Double? {
        guard
            let firstFrame = frames.first,
            let lastFrame = frames.last,
            firstFrame.points.count >= 2,
            lastFrame.points.count >= 2
        else {
            return nil
        }

        return lastFrame.points[0].distance(to: lastFrame.points[1])
            - firstFrame.points[0].distance(to: firstFrame.points[1])
    }

    private static func normalized(_ frames: [GestureFrameSnapshot]) -> [GestureFrameSnapshot] {
        guard
            let first = frames.first,
            let firstPoint = first.points.first,
            let firstTime = frames.first?.timestampMilliseconds
        else {
            return frames
        }

        return frames.map { frame in
            GestureFrameSnapshot(
                points: frame.points.map { point in
                    HandPoint(
                        x: point.x - firstPoint.x,
                        y: point.y - firstPoint.y,
                        shape: point.shape
                    )
                },
                timestampMilliseconds: frame.timestampMilliseconds - firstTime
            )
        }
    }
}

public struct PersonalizedGestureLibrary: Hashable, Sendable, Codable {
    public private(set) var templates: [GestureTemplate]

    public init(templates: [GestureTemplate] = []) {
        self.templates = templates.filter(\.isUsable)
    }

    public mutating func add(_ template: GestureTemplate) {
        guard template.isUsable else { return }
        templates.append(template)
    }

    public func templates(for intent: GestureIntent) -> [GestureTemplate] {
        templates.filter { $0.intent == intent }
    }

    public func templateCount(for intent: GestureIntent) -> Int {
        templates(for: intent).count
    }

    public func hasStableCalibration(
        for intents: [GestureIntent],
        minimumTemplatesPerIntent: Int = 2
    ) -> Bool {
        intents.allSatisfy { templateCount(for: $0) >= minimumTemplatesPerIntent }
    }
}

public struct PersonalizedGestureMatch: Hashable, Sendable {
    public let intent: GestureIntent
    public let distance: Double
    public let confidence: Double
    public let winningMargin: Double?

    public init(intent: GestureIntent, distance: Double, confidence: Double, winningMargin: Double?) {
        self.intent = intent
        self.distance = distance
        self.confidence = confidence
        self.winningMargin = winningMargin
    }
}

public struct PersonalizedGestureRecognizer: Sendable {
    public let library: PersonalizedGestureLibrary
    public let maximumDistance: Double
    public let minimumConfidence: Double
    public let minimumWinningMargin: Double
    public let minimumDirectionalTravel: Double

    public init(
        library: PersonalizedGestureLibrary,
        maximumDistance: Double = 0.14,
        minimumConfidence: Double = 0.36,
        minimumWinningMargin: Double = 0.035,
        minimumDirectionalTravel: Double = 0.08
    ) {
        self.library = library
        self.maximumDistance = maximumDistance
        self.minimumConfidence = minimumConfidence
        self.minimumWinningMargin = minimumWinningMargin
        self.minimumDirectionalTravel = minimumDirectionalTravel
    }

    public func recognize(frames: [GestureFrameSnapshot]) -> GestureIntent? {
        recognizeMatch(frames: frames)?.intent
    }

    public func recognizeMatch(frames: [GestureFrameSnapshot]) -> PersonalizedGestureMatch? {
        let candidate = GestureTemplate(
            intent: .swipeLeft,
            frames: frames,
            createdAtMilliseconds: frames.last?.timestampMilliseconds ?? 0
        )
        guard candidate.isUsable else { return nil }

        let matches = library.templates.compactMap { template -> (GestureIntent, Double, Double)? in
            guard isDirectionallyCompatible(candidate: candidate, template: template) else {
                return nil
            }
            let distance = trajectoryDistance(candidate.frames, template.frames)
            let confidence = max(0, min(1, 1 - distance / maximumDistance))
            return distance <= maximumDistance && confidence >= minimumConfidence
                ? (template.intent, distance, confidence)
                : nil
        }
        .sorted { lhs, rhs in
            if lhs.1 == rhs.1 {
                return lhs.2 > rhs.2
            }
            return lhs.1 < rhs.1
        }

        guard let best = matches.first else { return nil }
        let nearestCompetingIntent = matches.first { $0.0 != best.0 }
        let margin = nearestCompetingIntent.map { $0.1 - best.1 }
        if let margin, margin < minimumWinningMargin {
            return nil
        }

        return PersonalizedGestureMatch(
            intent: best.0,
            distance: best.1,
            confidence: best.2,
            winningMargin: margin
        )
    }

    private func isDirectionallyCompatible(candidate: GestureTemplate, template: GestureTemplate) -> Bool {
        switch template.intent {
        case .swipeLeft:
            return candidate.primaryHorizontalTravel <= -minimumDirectionalTravel
                && template.primaryHorizontalTravel <= -minimumDirectionalTravel
                && abs(candidate.primaryHorizontalTravel) > abs(candidate.primaryVerticalTravel) * 1.25
        case .swipeRight:
            return candidate.primaryHorizontalTravel >= minimumDirectionalTravel
                && template.primaryHorizontalTravel >= minimumDirectionalTravel
                && abs(candidate.primaryHorizontalTravel) > abs(candidate.primaryVerticalTravel) * 1.25
        case .zoomIn:
            guard let candidateChange = candidate.twoHandDistanceChange,
                  let templateChange = template.twoHandDistanceChange else {
                return false
            }
            return candidateChange >= minimumDirectionalTravel
                && templateChange >= minimumDirectionalTravel
        case .zoomOut:
            guard let candidateChange = candidate.twoHandDistanceChange,
                  let templateChange = template.twoHandDistanceChange else {
                return false
            }
            return candidateChange <= -minimumDirectionalTravel
                && templateChange <= -minimumDirectionalTravel
        case .startPresentation, .exitPresentation, .toggleRecording, .pinchToggle, .pinchDrag, .openPalmHold:
            return true
        }
    }

    private func trajectoryDistance(_ lhs: [GestureFrameSnapshot], _ rhs: [GestureFrameSnapshot]) -> Double {
        let lhsPoints = resampledPrimaryPoints(lhs, count: 12)
        let rhsPoints = resampledPrimaryPoints(rhs, count: 12)
        guard lhsPoints.count == rhsPoints.count, !lhsPoints.isEmpty else { return .infinity }

        let total = zip(lhsPoints, rhsPoints).reduce(0.0) { partial, pair in
            let dx = pair.0.x - pair.1.x
            let dy = pair.0.y - pair.1.y
            return partial + (dx * dx + dy * dy).squareRoot()
        }
        return total / Double(lhsPoints.count)
    }

    private func resampledPrimaryPoints(_ frames: [GestureFrameSnapshot], count: Int) -> [HandPoint] {
        let points = frames.compactMap(\.points.first)
        guard points.count >= 2, count > 1 else { return points }

        return (0..<count).map { index in
            let position = Double(index) * Double(points.count - 1) / Double(count - 1)
            let lower = Int(position.rounded(.down))
            let upper = min(points.count - 1, lower + 1)
            let fraction = position - Double(lower)
            let a = points[lower]
            let b = points[upper]
            return HandPoint(
                x: a.x + (b.x - a.x) * fraction,
                y: a.y + (b.y - a.y) * fraction,
                shape: b.shape
            )
        }
    }
}

public struct ContinuousZoomUpdate: Hashable, Sendable {
    public let scale: Double
    public let relativeDistanceChange: Double
    public let confidence: Double

    public init(scale: Double, relativeDistanceChange: Double, confidence: Double) {
        self.scale = scale
        self.relativeDistanceChange = relativeDistanceChange
        self.confidence = confidence
    }
}

public struct ContinuousZoomTracker: Sendable {
    public let minimumHandDistance: Double
    public let minimumRelativeChange: Double
    public let minimumScaleStep: Double
    public let scaleSensitivity: Double
    public let minimumScale: Double
    public let maximumScale: Double
    public let quietDistanceDeltaThreshold: Double
    public let quietFramesToRebase: Int
    public let minimumScaleDeltaPerUpdate: Double
    public let maximumScaleDeltaPerUpdate: Double
    public let dynamicScaleDeltaMultiplier: Double

    private var baselineDistance: Double?
    private var baselineScale: Double
    private var lastEmittedScale: Double
    private var lastDistance: Double?
    private var quietFrameCount: Int

    public init(
        minimumHandDistance: Double = 0.18,
        minimumRelativeChange: Double = 0.010,
        minimumScaleStep: Double = 0.0025,
        scaleSensitivity: Double = 0.75,
        minimumScale: Double = 0.75,
        maximumScale: Double = 1.8,
        quietDistanceDeltaThreshold: Double = 0.0018,
        quietFramesToRebase: Int = 6,
        minimumScaleDeltaPerUpdate: Double = 0.005,
        maximumScaleDeltaPerUpdate: Double = 0.04,
        dynamicScaleDeltaMultiplier: Double = 0.20
    ) {
        self.minimumHandDistance = minimumHandDistance
        self.minimumRelativeChange = minimumRelativeChange
        self.minimumScaleStep = minimumScaleStep
        self.scaleSensitivity = scaleSensitivity
        self.minimumScale = minimumScale
        self.maximumScale = maximumScale
        self.quietDistanceDeltaThreshold = quietDistanceDeltaThreshold
        self.quietFramesToRebase = quietFramesToRebase
        self.minimumScaleDeltaPerUpdate = minimumScaleDeltaPerUpdate
        self.maximumScaleDeltaPerUpdate = maximumScaleDeltaPerUpdate
        self.dynamicScaleDeltaMultiplier = dynamicScaleDeltaMultiplier
        baselineScale = 1
        lastEmittedScale = 1
        lastDistance = nil
        quietFrameCount = 0
    }

    public mutating func reset(currentScale: Double = 1) {
        baselineDistance = nil
        baselineScale = currentScale
        lastEmittedScale = currentScale
        lastDistance = nil
        quietFrameCount = 0
    }

    public mutating func update(points: [HandPoint], currentScale: Double) -> ContinuousZoomUpdate? {
        guard points.count >= 2 else {
            reset(currentScale: currentScale)
            return nil
        }

        let first = points[0]
        let second = points[1]
        guard first.shape != .fist, second.shape != .fist else {
            reset(currentScale: currentScale)
            return nil
        }

        let distance = first.distance(to: second)
        guard distance >= minimumHandDistance else {
            reset(currentScale: currentScale)
            return nil
        }

        if let lastDistance {
            let delta = abs(distance - lastDistance)
            if delta <= quietDistanceDeltaThreshold {
                quietFrameCount += 1
            } else {
                quietFrameCount = 0
            }
        }
        lastDistance = distance

        guard let baselineDistance else {
            self.baselineDistance = distance
            baselineScale = currentScale
            lastEmittedScale = currentScale
            return nil
        }

        if quietFrameCount >= quietFramesToRebase {
            self.baselineDistance = distance
            baselineScale = currentScale
            lastEmittedScale = currentScale
            quietFrameCount = 0
            return nil
        }

        let relativeChange = (distance - baselineDistance) / baselineDistance
        guard abs(relativeChange) >= minimumRelativeChange else {
            return nil
        }

        let unclampedScale = clamp(
            baselineScale * (1 + relativeChange * scaleSensitivity),
            minimumScale,
            maximumScale
        )
        let allowedScaleDelta = clamp(
            minimumScaleDeltaPerUpdate + abs(relativeChange) * dynamicScaleDeltaMultiplier,
            minimumScaleDeltaPerUpdate,
            maximumScaleDeltaPerUpdate
        )
        let nextScale = clamp(
            unclampedScale,
            lastEmittedScale - allowedScaleDelta,
            lastEmittedScale + allowedScaleDelta
        )
        guard abs(nextScale - lastEmittedScale) >= minimumScaleStep else {
            return nil
        }

        lastEmittedScale = nextScale
        self.baselineDistance = distance
        baselineScale = nextScale
        quietFrameCount = 0
        let confidence = max(0, min(1, abs(relativeChange) / 0.35))
        return ContinuousZoomUpdate(
            scale: nextScale,
            relativeDistanceChange: relativeChange,
            confidence: confidence
        )
    }

    private func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(upper, max(lower, value))
    }
}

public struct StreamingGestureRecognizer: Sendable {
    public let profile: GestureProfile
    public let minimumDecisionDurationMilliseconds: Int
    public let minimumDirectionConsistency: Double

    public init(
        profile: GestureProfile,
        minimumDecisionDurationMilliseconds: Int = 120,
        minimumDirectionConsistency: Double = 0.62
    ) {
        self.profile = profile
        self.minimumDecisionDurationMilliseconds = minimumDecisionDurationMilliseconds
        self.minimumDirectionConsistency = minimumDirectionConsistency
    }

    public func recognize(frames: [GestureFrameSnapshot]) -> GestureIntent? {
        guard frames.count >= 3, let last = frames.last else { return nil }

        let indexedFrames = Array(frames.enumerated())
        for (startIndex, start) in indexedFrames.dropLast().reversed() {
            let duration = last.timestampMilliseconds - start.timestampMilliseconds
            guard duration >= minimumDecisionDurationMilliseconds else { continue }
            guard duration <= profile.maximumGestureDurationMilliseconds else { break }

            guard let gesture = FrameGestureRecognizer(profile: profile).recognize(
                start: start.points,
                end: last.points,
                durationMilliseconds: duration
            ) else {
                continue
            }

            if isDirectionallyConsistent(
                gesture: gesture,
                frames: Array(frames[startIndex...])
            ) {
                return gesture
            }
        }

        return nil
    }

    private func isDirectionallyConsistent(
        gesture: GestureIntent,
        frames: [GestureFrameSnapshot]
    ) -> Bool {
        switch gesture {
        case .swipeLeft:
            return horizontalDirectionConsistency(frames: frames, expectedSign: -1)
        case .swipeRight:
            return horizontalDirectionConsistency(frames: frames, expectedSign: 1)
        case .zoomIn, .zoomOut:
            return true
        case .startPresentation, .exitPresentation, .toggleRecording, .pinchToggle, .pinchDrag, .openPalmHold:
            return true
        }
    }

    private func horizontalDirectionConsistency(
        frames: [GestureFrameSnapshot],
        expectedSign: Double
    ) -> Bool {
        guard frames.count >= 3 else { return false }
        let pairedCount = frames.map(\.points.count).min() ?? 0
        guard pairedCount > 0 else { return false }

        let handIndex = (0..<pairedCount).max { lhs, rhs in
            abs((frames.last?.points[lhs].x ?? 0) - frames[0].points[lhs].x)
                < abs((frames.last?.points[rhs].x ?? 0) - frames[0].points[rhs].x)
        } ?? 0

        let total = (frames.last?.points[handIndex].x ?? 0) - frames[0].points[handIndex].x
        guard total * expectedSign > 0 else { return false }

        var considered = 0
        var matching = 0
        for index in 1..<frames.count {
            let dx = frames[index].points[handIndex].x - frames[index - 1].points[handIndex].x
            guard abs(dx) >= profile.minimumHorizontalTravel * 0.08 else { continue }
            considered += 1
            if dx * expectedSign > 0 {
                matching += 1
            }
        }

        guard considered > 0 else { return false }
        return Double(matching) / Double(considered) >= minimumDirectionConsistency
    }
}

public struct TwoHandMotion: Hashable, Sendable {
    public let startDistance: Double
    public let endDistance: Double
    public let durationMilliseconds: Int

    public init(startDistance: Double, endDistance: Double, durationMilliseconds: Int) {
        self.startDistance = startDistance
        self.endDistance = endDistance
        self.durationMilliseconds = durationMilliseconds
    }
}

public struct TwoHandGestureRecognizer: Sendable {
    public let profile: GestureProfile

    public init(profile: GestureProfile) {
        self.profile = profile
    }

    public func recognize(_ motion: TwoHandMotion) -> GestureIntent? {
        guard motion.durationMilliseconds <= profile.maximumGestureDurationMilliseconds else {
            return nil
        }

        let change = motion.endDistance - motion.startDistance
        guard abs(change) >= profile.minimumZoomDistanceChange else {
            return nil
        }

        return change > 0 ? .zoomIn : .zoomOut
    }
}

public struct ContinuousZoomCandidateEvaluator: Sendable {
    public let profile: GestureProfile

    public init(profile: GestureProfile) {
        self.profile = profile
    }

    public func shouldPrioritizeZoom(start: [HandPoint], end: [HandPoint]) -> Bool {
        let pairedCount = min(start.count, end.count)
        guard pairedCount >= 2 else { return false }

        let startHands = Array(start.prefix(2))
        let endHands = Array(end.prefix(2))
        let canZoom = startHands.allSatisfy(\.shape.allowsZoom)
            && endHands.allSatisfy(\.shape.allowsZoom)
        guard canZoom else { return false }

        let leftTravel = endHands[0].x - startHands[0].x
        let rightTravel = endHands[1].x - startHands[1].x
        let distanceChange = endHands[0].distance(to: endHands[1])
            - startHands[0].distance(to: startHands[1])
        let minimumDistanceIntent = profile.minimumZoomDistanceChange * 0.28
        let minimumHandTravel = profile.minimumZoomDistanceChange * 0.24

        let strongDistanceChange = abs(distanceChange) >= minimumDistanceIntent
        if strongDistanceChange {
            return true
        }

        let oppositeDirections = leftTravel * rightTravel < 0
        let bilateralMotion = abs(leftTravel) >= minimumHandTravel
            && abs(rightTravel) >= minimumHandTravel

        return oppositeDirections && bilateralMotion
    }
}

public struct TwoHandZoomPoseCoverage: Hashable, Sendable {
    public let frameCount: Int
    public let lShapeFrameCount: Int
    public let zoomPoseFrameCount: Int

    public init(frameCount: Int, lShapeFrameCount: Int, zoomPoseFrameCount: Int) {
        self.frameCount = frameCount
        self.lShapeFrameCount = lShapeFrameCount
        self.zoomPoseFrameCount = zoomPoseFrameCount
    }

    public var lShapeCoverage: Double {
        guard frameCount > 0 else { return 0 }
        return Double(lShapeFrameCount) / Double(frameCount)
    }

    public var zoomPoseCoverage: Double {
        guard frameCount > 0 else { return 0 }
        return Double(zoomPoseFrameCount) / Double(frameCount)
    }
}

public struct DiscreteGestureSuppressionEvaluator: Sendable {
    public let recentWindowSize: Int
    public let minimumZoomPoseStreak: Int
    public let minimumLShapeFrameCount: Int
    public let minimumLShapeCoverage: Double

    public init(
        recentWindowSize: Int = 8,
        minimumZoomPoseStreak: Int = 2,
        minimumLShapeFrameCount: Int = 2,
        minimumLShapeCoverage: Double = 0.34
    ) {
        self.recentWindowSize = recentWindowSize
        self.minimumZoomPoseStreak = minimumZoomPoseStreak
        self.minimumLShapeFrameCount = minimumLShapeFrameCount
        self.minimumLShapeCoverage = minimumLShapeCoverage
    }

    /// Returns whether the current incoming frame should block discrete swipe recognition.
    /// - Parameters:
    ///   - existingFrames: Recent gesture frames already stored in the recognition window.
    ///   - incomingFrame: Current frame that is about to be evaluated.
    ///   - zoomPoseStreak: Number of recent frames already handled as continuous zoom.
    /// - Returns: `true` when a stable two-hand zoom pose is active and swipe recognition should pause.
    public func shouldSuppressDiscreteGesture(
        existingFrames: [GestureFrameSnapshot],
        incomingFrame: GestureFrameSnapshot,
        zoomPoseStreak: Int
    ) -> Bool {
        guard currentFrameLooksZoomLike(incomingFrame) else { return false }

        let recentFrames = Array((existingFrames + [incomingFrame]).suffix(recentWindowSize))
        let coverage = twoHandZoomPoseCoverage(frames: recentFrames)
        return zoomPoseStreak >= minimumZoomPoseStreak
            || coverage.lShapeFrameCount >= minimumLShapeFrameCount
            || coverage.lShapeCoverage >= minimumLShapeCoverage
    }

    /// Summarizes how often a recent frame window looks like a deliberate two-hand zoom pose.
    /// - Parameter frames: Recent gesture snapshots ordered by time.
    /// - Returns: Coverage metrics used by zoom prioritization and swipe suppression.
    public func twoHandZoomPoseCoverage(frames: [GestureFrameSnapshot]) -> TwoHandZoomPoseCoverage {
        var totalFrames = 0
        var lShapeFrames = 0
        var zoomPoseFrames = 0

        for frame in frames {
            guard frame.points.count >= 2 else { continue }
            totalFrames += 1
            let currentPoints = Array(frame.points.prefix(2))
            if currentPoints.allSatisfy({ $0.shape == .lShape }) {
                lShapeFrames += 1
            }
            if currentFrameLooksZoomLike(frame) {
                zoomPoseFrames += 1
            }
        }

        return TwoHandZoomPoseCoverage(
            frameCount: totalFrames,
            lShapeFrameCount: lShapeFrames,
            zoomPoseFrameCount: zoomPoseFrames
        )
    }

    /// Checks whether a single frame already looks like an intentional two-hand zoom pose.
    /// - Parameter frame: Current gesture snapshot.
    /// - Returns: `true` when both hands are zoom-capable and at least one hand is clearly in an L-shape-like pose.
    public func currentFrameLooksZoomLike(_ frame: GestureFrameSnapshot) -> Bool {
        guard frame.points.count >= 2 else { return false }
        let currentPoints = Array(frame.points.prefix(2))
        let bothHandsAllowZoom = currentPoints.allSatisfy(\.shape.allowsZoom)
        let containsDistinctZoomPose = currentPoints.contains { point in
            point.shape == .lShape || point.shape == .unknown
        }
        return bothHandsAllowZoom && containsDistinctZoomPose
    }
}

public struct FrameGestureRecognizer: Sendable {
    public let profile: GestureProfile

    public init(profile: GestureProfile) {
        self.profile = profile
    }

    public func recognize(
        start: [HandPoint],
        end: [HandPoint],
        durationMilliseconds: Int
    ) -> GestureIntent? {
        guard durationMilliseconds <= profile.maximumGestureDurationMilliseconds else {
            return nil
        }

        let pairedCount = min(start.count, end.count)
        guard pairedCount > 0 else { return nil }

        if pairedCount >= 2 {
            let canZoom = start[0].shape.allowsZoom
                && start[1].shape.allowsZoom
                && end[0].shape.allowsZoom
                && end[1].shape.allowsZoom
            let zoomPoseEngaged = [start[0], start[1], end[0], end[1]].allSatisfy { point in
                point.shape == .lShape || point.shape == .unknown
            }
            let leftMotion = GestureMotion(
                horizontalTravel: end[0].x - start[0].x,
                verticalTravel: end[0].y - start[0].y,
                durationMilliseconds: durationMilliseconds
            )
            let rightMotion = GestureMotion(
                horizontalTravel: end[1].x - start[1].x,
                verticalTravel: end[1].y - start[1].y,
                durationMilliseconds: durationMilliseconds
            )

            let bothHandsMove = abs(leftMotion.horizontalTravel) >= profile.minimumZoomDistanceChange * 0.42
                && abs(rightMotion.horizontalTravel) >= profile.minimumZoomDistanceChange * 0.42
            let oppositeDirections = leftMotion.horizontalTravel * rightMotion.horizontalTravel < 0

            if canZoom, bothHandsMove, oppositeDirections {
                let twoHand = TwoHandMotion(
                    startDistance: start[0].distance(to: start[1]),
                    endDistance: end[0].distance(to: end[1]),
                    durationMilliseconds: durationMilliseconds
                )
                if let zoom = TwoHandGestureRecognizer(profile: profile).recognize(twoHand) {
                    return zoom
                }
            }

            if zoomPoseEngaged {
                let distanceChange = abs(end[0].distance(to: end[1]) - start[0].distance(to: start[1]))
                if distanceChange >= profile.minimumZoomDistanceChange * 0.18 {
                    return nil
                }
            }
        }

        let motions = (0..<pairedCount).map { index in
            GestureMotion(
                horizontalTravel: end[index].x - start[index].x,
                verticalTravel: end[index].y - start[index].y,
                durationMilliseconds: durationMilliseconds
            )
        }

        if pairedCount == 1 {
            guard start[0].shape.allowsSwipe(profile: profile), end[0].shape.allowsSwipe(profile: profile) else {
                return nil
            }
            return MotionGestureRecognizer(profile: profile).recognize(motions[0])
        }

        let significant = motions.enumerated().filter { index, motion in
            abs(motion.horizontalTravel) >= profile.minimumHorizontalTravel
                && start[index].shape.allowsSwipe(profile: profile)
                && end[index].shape.allowsSwipe(profile: profile)
        }
        guard significant.count == 1, let (_, motion) = significant.first else {
            return nil
        }

        return MotionGestureRecognizer(profile: profile).recognize(motion)
    }
}

private extension Array where Element == Double {
    var average: Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}

public struct DirectorCommand: Hashable, Sendable {
    public let presentationAction: PresentationAction
    public let transport: CommandTransport

    public init(presentationAction: PresentationAction, transport: CommandTransport) {
        self.presentationAction = presentationAction
        self.transport = transport
    }
}
