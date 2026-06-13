public enum GestureIntent: Hashable, Sendable {
    case swipeLeft
    case swipeRight
    case zoomIn
    case zoomOut
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
    public let minimumVerticalTravel: Double
    public let maximumGestureDurationMilliseconds: Int

    public init(
        minimumHorizontalTravel: Double,
        minimumVerticalTravel: Double,
        maximumGestureDurationMilliseconds: Int
    ) {
        self.minimumHorizontalTravel = minimumHorizontalTravel
        self.minimumVerticalTravel = minimumVerticalTravel
        self.maximumGestureDurationMilliseconds = maximumGestureDurationMilliseconds
    }

    public static let `default` = GestureProfile(
        minimumHorizontalTravel: 0.22,
        minimumVerticalTravel: 0.24,
        maximumGestureDurationMilliseconds: 650
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

        let verticalSamples = samples
            .filter { $0.intent == .zoomIn || $0.intent == .zoomOut }
            .map { abs($0.verticalTravel) }

        let horizontalAverage = horizontalSamples.average ?? GestureProfile.default.minimumHorizontalTravel
        let verticalAverage = verticalSamples.average ?? GestureProfile.default.minimumVerticalTravel

        return GestureProfile(
            minimumHorizontalTravel: max(0.16, horizontalAverage * 0.72),
            minimumVerticalTravel: max(0.16, verticalAverage * 0.72),
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

        if abs(vertical) >= profile.minimumVerticalTravel, abs(vertical) > abs(horizontal) * 1.35 {
            return vertical < 0 ? .zoomIn : .zoomOut
        }

        return nil
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
