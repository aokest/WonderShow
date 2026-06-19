import Foundation

enum RecordingControlState: Hashable, Sendable {
    case idle
    case starting
    case recording
    case paused
}

enum RecordingControlSurfaceAction: Hashable, Sendable {
    case start
    case cancelStart
    case pause
    case resume
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
