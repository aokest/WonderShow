/// Describes the current lifecycle phase of a gesture mode recognizer.
public enum GesturePhase: String, Hashable, Sendable, Codable {
    case idle
    case candidate
    case dwell
    case active
    case grace
    case cooldown
}

/// Describes the mutually exclusive interaction mode chosen for the current frame.
public enum GestureMode: String, Hashable, Sendable, Codable {
    case idle
    case swipe
    case zoom
}

/// Defines the entry, exit, dwell, grace, and cooldown tuning for one gesture mode.
/// - Parameters:
///   - enterThreshold: Signal magnitude required to enter the candidate phase.
///   - exitThreshold: Lower signal threshold used to keep the mode stable with hysteresis.
///   - dwellMilliseconds: Minimum stable time before the mode becomes active.
///   - graceMilliseconds: Time the mode may stay alive after the signal briefly disappears.
///   - cooldownMilliseconds: Time during which the mode refuses to re-enter after an emission.
public struct GestureModeProfile: Hashable, Sendable, Codable {
    public let enterThreshold: Double
    public let exitThreshold: Double
    public let dwellMilliseconds: Int
    public let graceMilliseconds: Int
    public let cooldownMilliseconds: Int

    public init(
        enterThreshold: Double,
        exitThreshold: Double,
        dwellMilliseconds: Int,
        graceMilliseconds: Int,
        cooldownMilliseconds: Int
    ) {
        self.enterThreshold = enterThreshold
        self.exitThreshold = exitThreshold
        self.dwellMilliseconds = dwellMilliseconds
        self.graceMilliseconds = graceMilliseconds
        self.cooldownMilliseconds = cooldownMilliseconds
    }

    public static let swipeDefault = GestureModeProfile(
        enterThreshold: 0.18,
        exitThreshold: 0.04,
        dwellMilliseconds: 90,
        graceMilliseconds: 200,
        cooldownMilliseconds: 280
    )

    public static let zoomDefault = GestureModeProfile(
        enterThreshold: 0.06,
        exitThreshold: 0.02,
        dwellMilliseconds: 110,
        graceMilliseconds: 250,
        cooldownMilliseconds: 200
    )
}

/// Reports the latest state after a gesture-state-machine observation.
/// - Parameters:
///   - phase: The current state-machine phase after processing the new sample.
///   - didEnterActive: Whether the gesture became active on this exact observation.
///   - isBlocking: Whether the caller should keep blocking competing modes.
public struct GestureRecognitionOutcome: Hashable, Sendable {
    public let phase: GesturePhase
    public let didEnterActive: Bool
    public let isBlocking: Bool

    public init(phase: GesturePhase, didEnterActive: Bool, isBlocking: Bool) {
        self.phase = phase
        self.didEnterActive = didEnterActive
        self.isBlocking = isBlocking
    }
}

/// Implements a small finite-state machine with enter/exit hysteresis, dwell, grace, and cooldown.
/// - Parameters:
///   - profile: Timing and threshold configuration for the current mode.
/// - Note: The state machine is signal-agnostic and can be reused for swipe gating or zoom-pose gating.
public struct GestureRecognitionStateMachine: Sendable {
    public let profile: GestureModeProfile

    private var phase: GesturePhase
    private var candidateSinceMilliseconds: Int?
    private var graceSinceMilliseconds: Int?
    private var cooldownUntilMilliseconds: Int?

    public init(profile: GestureModeProfile) {
        self.profile = profile
        phase = .idle
    }

    /// Processes a new signal sample and advances the state machine.
    /// - Parameters:
    ///   - signal: Current normalized signal magnitude for this mode.
    ///   - isEligible: Whether the pose/category prerequisites are currently satisfied.
    ///   - timestampMilliseconds: Current frame timestamp in milliseconds.
    /// - Returns: The updated phase plus whether this mode should block competing modes.
    public mutating func observe(
        signal: Double,
        isEligible: Bool,
        timestampMilliseconds: Int
    ) -> GestureRecognitionOutcome {
        if let cooldownUntilMilliseconds, timestampMilliseconds < cooldownUntilMilliseconds {
            phase = .cooldown
            return GestureRecognitionOutcome(phase: .cooldown, didEnterActive: false, isBlocking: false)
        }

        let passesEnter = isEligible && signal >= profile.enterThreshold
        let passesExit = isEligible && signal >= profile.exitThreshold

        switch phase {
        case .idle, .cooldown:
            guard passesEnter else {
                phase = .idle
                candidateSinceMilliseconds = nil
                graceSinceMilliseconds = nil
                return GestureRecognitionOutcome(phase: .idle, didEnterActive: false, isBlocking: false)
            }
            phase = profile.dwellMilliseconds > 0 ? .candidate : .active
            candidateSinceMilliseconds = timestampMilliseconds
            return transitionFromCandidate(timestampMilliseconds: timestampMilliseconds)

        case .candidate, .dwell:
            guard passesExit else {
                reset()
                return GestureRecognitionOutcome(phase: .idle, didEnterActive: false, isBlocking: false)
            }
            return transitionFromCandidate(timestampMilliseconds: timestampMilliseconds)

        case .active:
            guard passesExit else {
                phase = .grace
                graceSinceMilliseconds = timestampMilliseconds
                return GestureRecognitionOutcome(phase: .grace, didEnterActive: false, isBlocking: true)
            }
            return GestureRecognitionOutcome(phase: .active, didEnterActive: false, isBlocking: true)

        case .grace:
            if passesEnter {
                phase = .active
                graceSinceMilliseconds = nil
                return GestureRecognitionOutcome(phase: .active, didEnterActive: false, isBlocking: true)
            }

            guard let graceSinceMilliseconds else {
                reset()
                return GestureRecognitionOutcome(phase: .idle, didEnterActive: false, isBlocking: false)
            }
            if timestampMilliseconds - graceSinceMilliseconds <= profile.graceMilliseconds {
                return GestureRecognitionOutcome(phase: .grace, didEnterActive: false, isBlocking: true)
            }
            reset()
            return GestureRecognitionOutcome(phase: .idle, didEnterActive: false, isBlocking: false)
        }
    }

    /// Moves the state machine into cooldown after a discrete gesture emission.
    /// - Parameter timestampMilliseconds: Current event timestamp in milliseconds.
    public mutating func markTriggered(at timestampMilliseconds: Int) {
        phase = .cooldown
        cooldownUntilMilliseconds = timestampMilliseconds + profile.cooldownMilliseconds
        candidateSinceMilliseconds = nil
        graceSinceMilliseconds = nil
    }

    /// Clears all internal state and returns the machine to idle.
    public mutating func reset() {
        phase = .idle
        candidateSinceMilliseconds = nil
        graceSinceMilliseconds = nil
        cooldownUntilMilliseconds = nil
    }

    /// Returns the current phase for diagnostics or tests.
    /// - Returns: The state-machine phase after the latest observation.
    public func currentPhase() -> GesturePhase {
        phase
    }

    /// Finalizes candidate-to-active transitions once dwell time has elapsed.
    /// - Parameter timestampMilliseconds: Current frame timestamp in milliseconds.
    /// - Returns: The updated state-machine outcome.
    private mutating func transitionFromCandidate(
        timestampMilliseconds: Int
    ) -> GestureRecognitionOutcome {
        guard let candidateSinceMilliseconds else {
            phase = .candidate
            self.candidateSinceMilliseconds = timestampMilliseconds
            return GestureRecognitionOutcome(phase: .candidate, didEnterActive: false, isBlocking: true)
        }

        let dwell = timestampMilliseconds - candidateSinceMilliseconds
        if dwell >= profile.dwellMilliseconds {
            phase = .active
            return GestureRecognitionOutcome(phase: .active, didEnterActive: true, isBlocking: true)
        }

        phase = .dwell
        return GestureRecognitionOutcome(phase: .dwell, didEnterActive: false, isBlocking: true)
    }
}

/// Arbitrates mutually exclusive swipe and zoom modes so zoom always wins once entered.
/// - Parameters:
///   - swipeProfile: State-machine profile for single-hand swipe readiness.
///   - zoomProfile: State-machine profile for two-hand zoom readiness.
public struct GestureModeCoordinator: Sendable {
    public let swipeProfile: GestureModeProfile
    public let zoomProfile: GestureModeProfile

    private var swipeStateMachine: GestureRecognitionStateMachine
    private var zoomStateMachine: GestureRecognitionStateMachine

    public init(
        swipeProfile: GestureModeProfile = .swipeDefault,
        zoomProfile: GestureModeProfile = .zoomDefault
    ) {
        self.swipeProfile = swipeProfile
        self.zoomProfile = zoomProfile
        swipeStateMachine = GestureRecognitionStateMachine(profile: swipeProfile)
        zoomStateMachine = GestureRecognitionStateMachine(profile: zoomProfile)
    }

    /// Updates the competing swipe and zoom modes using explicit pose-readiness signals.
    /// - Parameters:
    ///   - swipeReady: Whether the current frame is eligible to enter swipe mode.
    ///   - zoomReady: Whether the current frame is eligible to enter zoom mode.
    ///   - timestampMilliseconds: Current frame timestamp in milliseconds.
    /// - Returns: The dominant interaction mode after arbitration.
    public mutating func update(
        swipeReady: Bool,
        zoomReady: Bool,
        timestampMilliseconds: Int
    ) -> GestureMode {
        let zoomOutcome = zoomStateMachine.observe(
            signal: zoomReady ? zoomProfile.enterThreshold : 0,
            isEligible: zoomReady,
            timestampMilliseconds: timestampMilliseconds
        )
        if zoomOutcome.isBlocking {
            return .zoom
        }

        let swipeOutcome = swipeStateMachine.observe(
            signal: swipeReady ? swipeProfile.enterThreshold : 0,
            isEligible: swipeReady,
            timestampMilliseconds: timestampMilliseconds
        )
        if swipeOutcome.isBlocking {
            return .swipe
        }

        return .idle
    }

    /// Pushes the current mode into cooldown after a discrete swipe emission.
    /// - Parameter timestampMilliseconds: Current frame timestamp in milliseconds.
    public mutating func markSwipeTriggered(at timestampMilliseconds: Int) {
        swipeStateMachine.markTriggered(at: timestampMilliseconds)
    }

    /// Resets both internal state machines to idle.
    public mutating func reset() {
        swipeStateMachine.reset()
        zoomStateMachine.reset()
    }
}
