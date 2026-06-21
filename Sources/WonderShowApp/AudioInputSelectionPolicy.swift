import Foundation

struct AudioInputSelectionResult: Equatable, Sendable {
    let selectedDeviceID: String
    let warning: String?
}

enum AudioInputSelectionPolicy {
    static func resolve(
        currentDeviceID: String,
        requestedDeviceID: String,
        isRecording: Bool
    ) -> AudioInputSelectionResult {
        guard isRecording, requestedDeviceID != currentDeviceID else {
            return AudioInputSelectionResult(selectedDeviceID: requestedDeviceID, warning: nil)
        }

        return AudioInputSelectionResult(
            selectedDeviceID: currentDeviceID,
            warning: "录制中不能切换音频输入；请停止录制后再切换，避免音画不同步。"
        )
    }
}
