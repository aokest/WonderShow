/// Describes the normalized camera area where gestures are allowed to trigger commands.
/// - Parameters:
///   - minX: Left boundary in normalized coordinates.
///   - maxX: Right boundary in normalized coordinates.
///   - minY: Bottom boundary in normalized coordinates.
///   - maxY: Top boundary in normalized coordinates.
/// - Note: Values are clamped by the caller and expected to be in the `0...1` range.
public struct GestureActivationZone: Hashable, Sendable, Codable {
    public let minX: Double
    public let maxX: Double
    public let minY: Double
    public let maxY: Double

    public init(minX: Double, maxX: Double, minY: Double, maxY: Double) {
        self.minX = minX
        self.maxX = maxX
        self.minY = minY
        self.maxY = maxY
    }

    /// Returns whether a point is inside the activation zone.
    /// - Parameter point: A normalized hand anchor point.
    /// - Returns: `true` when the point is inside the configured bounds.
    public func contains(_ point: HandPoint) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }

    /// Returns whether all points are inside the activation zone.
    /// - Parameter points: The current visible hand points.
    /// - Returns: `true` when every point is inside the zone.
    public func containsAll(_ points: [HandPoint]) -> Bool {
        !points.isEmpty && points.allSatisfy(contains)
    }

    public static let presentationDefault = GestureActivationZone(
        minX: 0.18,
        maxX: 0.82,
        minY: 0.20,
        maxY: 0.82
    )
}

public struct GestureHandSelector: Sendable {
    public let zone: GestureActivationZone

    public init(zone: GestureActivationZone) {
        self.zone = zone
    }

    public func selectPrimaryHands(from points: [HandPoint], maximumCount: Int = 2) -> [HandPoint] {
        guard maximumCount > 0 else { return [] }
        let inZone = points.filter(zone.contains)
        guard !inZone.isEmpty else { return [] }

        if inZone.count <= maximumCount {
            return inZone.sorted { $0.x < $1.x }
        }

        let sorted = inZone.sorted { lhs, rhs in
            let lhsScore = distanceToCenter(lhs)
            let rhsScore = distanceToCenter(rhs)
            if lhsScore == rhsScore {
                return lhs.x < rhs.x
            }
            return lhsScore < rhsScore
        }

        return Array(sorted.prefix(maximumCount)).sorted { $0.x < $1.x }
    }

    private func distanceToCenter(_ point: HandPoint) -> Double {
        let dx = point.x - 0.5
        let dy = point.y - 0.5
        return (dx * dx + dy * dy).squareRoot()
    }
}

public enum GestureSessionState: String, Hashable, Sendable, Codable {
    case waiting
    case armed
    case coolingDown
}

public struct GestureSessionUpdate: Hashable, Sendable {
    public let state: GestureSessionState
    public let emittedGesture: GestureIntent?
    public let message: String

    public init(state: GestureSessionState, emittedGesture: GestureIntent?, message: String) {
        self.state = state
        self.emittedGesture = emittedGesture
        self.message = message
    }
}

/// Coordinates gesture unlock, active window, and cooldown to reduce accidental triggers.
/// - Parameters:
///   - unlockGesture: Gesture used to enter the armed state.
///   - activeWindowMilliseconds: Time window after unlock where actions may trigger.
///   - cooldownMilliseconds: Delay applied after a command is emitted.
/// - Important: This type is intentionally pure so it can be covered by unit tests.
public struct GestureSessionCoordinator: Sendable {
    public let unlockGesture: GestureIntent
    public let activeWindowMilliseconds: Int
    public let cooldownMilliseconds: Int

    private var state: GestureSessionState
    private var armedUntilMilliseconds: Int?
    private var cooldownUntilMilliseconds: Int?

    public init(
        unlockGesture: GestureIntent = .openPalmHold,
        activeWindowMilliseconds: Int = 1_800,
        cooldownMilliseconds: Int = 650
    ) {
        self.unlockGesture = unlockGesture
        self.activeWindowMilliseconds = activeWindowMilliseconds
        self.cooldownMilliseconds = cooldownMilliseconds
        state = .waiting
    }

    /// Refreshes the internal timers without consuming a new gesture.
    /// - Parameter timestampMilliseconds: Current timestamp in milliseconds.
    /// - Returns: The updated session state and guidance message.
    public mutating func refresh(at timestampMilliseconds: Int) -> GestureSessionUpdate {
        updateTimers(at: timestampMilliseconds)

        switch state {
        case .waiting:
            return GestureSessionUpdate(
                state: .waiting,
                emittedGesture: nil,
                message: "先在中央热区张开手掌停留"
            )
        case .armed:
            let expiresIn = max(0, (armedUntilMilliseconds ?? timestampMilliseconds) - timestampMilliseconds)
            return GestureSessionUpdate(
                state: .armed,
                emittedGesture: nil,
                message: "已解锁，可在 \(expiresIn)ms 内执行动作"
            )
        case .coolingDown:
            let remaining = max(0, (cooldownUntilMilliseconds ?? timestampMilliseconds) - timestampMilliseconds)
            return GestureSessionUpdate(
                state: .coolingDown,
                emittedGesture: nil,
                message: "冷却中，\(remaining)ms 后可再次触发"
            )
        }
    }

    /// Consumes a recognized gesture and determines whether it should emit a command.
    /// - Parameters:
    ///   - gesture: The recognized gesture intent.
    ///   - timestampMilliseconds: Current timestamp in milliseconds.
    /// - Returns: The new session state and an emitted gesture when the command should pass through.
    public mutating func consume(_ gesture: GestureIntent, at timestampMilliseconds: Int) -> GestureSessionUpdate {
        _ = refresh(at: timestampMilliseconds)

        if gesture == unlockGesture {
            state = .armed
            armedUntilMilliseconds = timestampMilliseconds + activeWindowMilliseconds
            cooldownUntilMilliseconds = nil
            return GestureSessionUpdate(
                state: .armed,
                emittedGesture: nil,
                message: "手势已解锁，请在短时间内执行动作"
            )
        }

        if state == .coolingDown {
            return GestureSessionUpdate(
                state: .coolingDown,
                emittedGesture: nil,
                message: "冷却中，忽略动作"
            )
        }

        if gesture.requiresUnlock, state != .armed {
            return GestureSessionUpdate(
                state: state,
                emittedGesture: nil,
                message: "未解锁，忽略动作"
            )
        }

        state = .coolingDown
        armedUntilMilliseconds = nil
        cooldownUntilMilliseconds = timestampMilliseconds + cooldownMilliseconds
        return GestureSessionUpdate(
            state: .coolingDown,
            emittedGesture: gesture,
            message: "动作已接收，进入冷却期"
        )
    }

    /// Resets the gesture session to its waiting state.
    /// - Note: Use this when capture is interrupted or the user exits calibration.
    public mutating func reset() {
        state = .waiting
        armedUntilMilliseconds = nil
        cooldownUntilMilliseconds = nil
    }

    private mutating func updateTimers(at timestampMilliseconds: Int) {
        if let armedUntilMilliseconds, timestampMilliseconds > armedUntilMilliseconds {
            state = .waiting
            self.armedUntilMilliseconds = nil
        }

        if let cooldownUntilMilliseconds, timestampMilliseconds > cooldownUntilMilliseconds {
            state = .waiting
            self.cooldownUntilMilliseconds = nil
        }
    }
}

private extension GestureIntent {
    var requiresUnlock: Bool {
        switch self {
        case .startPresentation, .exitPresentation, .toggleRecording, .pinchToggle, .pinchDrag:
            return true
        case .swipeLeft, .swipeRight, .openPalmHold:
            return false
        case .zoomIn, .zoomOut:
            return false
        }
    }
}

/// Recognizes a stable hold pose over a series of frames.
/// - Parameters:
///   - requiredShape: The hand shape that must appear in every frame.
///   - minimumDurationMilliseconds: Minimum hold duration required to accept the gesture.
///   - maximumTravel: Maximum allowed travel while holding the pose.
/// - Returns: A gesture intent when the hold is stable enough, otherwise `nil`.
public struct GestureHoldRecognizer: Sendable {
    public let requiredShape: HandShape
    public let minimumDurationMilliseconds: Int
    public let maximumTravel: Double

    public init(
        requiredShape: HandShape,
        minimumDurationMilliseconds: Int = 280,
        maximumTravel: Double = 0.05
    ) {
        self.requiredShape = requiredShape
        self.minimumDurationMilliseconds = minimumDurationMilliseconds
        self.maximumTravel = maximumTravel
    }

    public func recognize(frames: [GestureFrameSnapshot]) -> GestureIntent? {
        guard
            frames.count >= 3,
            let first = frames.first,
            let last = frames.last,
            let firstPoint = first.points.first,
            let lastPoint = last.points.first
        else {
            return nil
        }

        let duration = last.timestampMilliseconds - first.timestampMilliseconds
        guard duration >= minimumDurationMilliseconds else {
            return nil
        }

        guard frames.allSatisfy({ $0.points.first?.shape == requiredShape }) else {
            return nil
        }

        guard firstPoint.distance(to: lastPoint) <= maximumTravel else {
            return nil
        }

        if requiredShape == .openPalm {
            return .openPalmHold
        }

        return nil
    }
}
