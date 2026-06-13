public enum GestureIntent: Hashable, Sendable {
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

    public init(
        minimumHorizontalTravel: Double,
        minimumZoomDistanceChange: Double,
        maximumGestureDurationMilliseconds: Int
    ) {
        self.minimumHorizontalTravel = minimumHorizontalTravel
        self.minimumZoomDistanceChange = minimumZoomDistanceChange
        self.maximumGestureDurationMilliseconds = maximumGestureDurationMilliseconds
    }

    public static let `default` = GestureProfile(
        minimumHorizontalTravel: 0.18,
        minimumZoomDistanceChange: 0.14,
        maximumGestureDurationMilliseconds: 800
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

public struct HandPoint: Hashable, Sendable {
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

public enum HandShape: Hashable, Sendable {
    case unknown
    case natural
    case fingerGun
    case lShape

    public var allowsSwipe: Bool {
        self == .fingerGun || self == .lShape || self == .unknown
    }

    public var allowsZoom: Bool {
        self == .lShape || self == .fingerGun || self == .unknown
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
        }

        let motions = (0..<pairedCount).map { index in
            GestureMotion(
                horizontalTravel: end[index].x - start[index].x,
                verticalTravel: end[index].y - start[index].y,
                durationMilliseconds: durationMilliseconds
            )
        }

        if pairedCount == 1 {
            guard start[0].shape.allowsSwipe, end[0].shape.allowsSwipe else {
                return nil
            }
            return MotionGestureRecognizer(profile: profile).recognize(motions[0])
        }

        let significant = motions.enumerated().filter { index, motion in
            abs(motion.horizontalTravel) >= profile.minimumHorizontalTravel
                && start[index].shape.allowsSwipe
                && end[index].shape.allowsSwipe
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
