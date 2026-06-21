import Foundation

struct ScreenSourceSelectionResult: Equatable, Sendable {
    let selectedIDs: Set<ScreenCaptureSourceID>
    let sourcePreference: ScreenCaptureSourcePreference
}

enum ScreenSourceSelectionResolver {
    static func resolve(
        options: [ScreenCaptureWindowOption],
        selectedIDs: Set<ScreenCaptureSourceID>
    ) -> ScreenSourceSelectionResult? {
        let selectedOptions = options.filter { selectedIDs.contains($0.id) }
        guard !selectedOptions.isEmpty else {
            return nil
        }

        if let displayID = selectedOptions.compactMap(\.id.displayID).first {
            return ScreenSourceSelectionResult(
                selectedIDs: [.display(displayID)],
                sourcePreference: .selectedDisplay(displayID)
            )
        }

        let windowIDs = selectedOptions.compactMap(\.id.windowID)
        guard !windowIDs.isEmpty else {
            return nil
        }
        return ScreenSourceSelectionResult(
            selectedIDs: Set(windowIDs.map(ScreenCaptureSourceID.window)),
            sourcePreference: .selectedWindows(windowIDs)
        )
    }
}
