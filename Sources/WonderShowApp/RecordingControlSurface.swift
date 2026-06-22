import AppKit
import Foundation

enum RecordingControlState: Hashable, Sendable {
    case idle
    case starting
    case recording
    case paused

    func acceptsLiveConfigurationUpdates(
        isFinishConfirmationVisible: Bool,
        includePaused: Bool = false
    ) -> Bool {
        guard !isFinishConfirmationVisible else {
            return false
        }
        switch self {
        case .starting, .recording:
            return true
        case .paused:
            return includePaused
        case .idle:
            return false
        }
    }
}

enum RecordingControlSurfaceAction: Hashable, Sendable {
    case start
    case cancelStart
    case pause
    case resume
}

enum RecordingControlHotKeyAction: Hashable, Sendable {
    case toggleStartPauseResume
    case pauseResume
    case finish
}

enum RecordingControlHotKey {
    static func action(
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> RecordingControlHotKeyAction? {
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command),
              flags.contains(.option),
              !flags.contains(.shift),
              !flags.contains(.control),
              let characters = charactersIgnoringModifiers?.lowercased(),
              characters.count == 1 else {
            return nil
        }

        switch characters {
        case "r":
            return .toggleStartPauseResume
        case "p":
            return .pauseResume
        case ".":
            return .finish
        default:
            return nil
        }
    }

    static func action(for event: NSEvent) -> RecordingControlHotKeyAction? {
        action(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifierFlags: event.modifierFlags
        )
    }
}

struct RecordingControlSurfaceState: Hashable, Sendable {
    let controlState: RecordingControlState
    let elapsedSeconds: Int

    var primaryAction: RecordingControlSurfaceAction {
        switch controlState {
        case .idle:
            return .start
        case .starting:
            return .cancelStart
        case .recording:
            return .pause
        case .paused:
            return .resume
        }
    }

    var stopEnabled: Bool {
        controlState == .recording || controlState == .paused
    }

    var elapsedTimecode: String {
        let bounded = max(0, elapsedSeconds)
        let hours = bounded / 3600
        let minutes = (bounded % 3600) / 60
        let seconds = bounded % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
