import WonderShow

enum ProgramRenderResourcePolicy {
    static let previewMaximumLongEdge = 1_920
    static let previewMaximumShortEdge = 1_080

    static func defaultProgramSettings(from settings: RecordingExportSettings) -> RecordingExportSettings {
        var output = settings
        output.frameRate = .fps30
        output.codec = .h264

        if let pixelSize = settings.effectivePixelSize {
            output.resolution = .hd1080
            output.customPixelSize = pixelSize.cappedForPreviewEnvelope(
                maximumLongEdge: previewMaximumLongEdge,
                maximumShortEdge: previewMaximumShortEdge
            )
        } else {
            output.resolution = .hd1080
            output.customPixelSize = nil
        }

        return output
    }

    static func previewSettings(from settings: RecordingExportSettings) -> RecordingExportSettings {
        var output = defaultProgramSettings(from: settings)
        output.quality = .standard
        return output
    }
}

private extension RecordingExportPixelSize {
    func cappedForPreviewEnvelope(
        maximumLongEdge: Int,
        maximumShortEdge: Int
    ) -> RecordingExportPixelSize {
        let width = max(2, self.width)
        let height = max(2, self.height)
        let longEdge = max(width, height)
        let shortEdge = min(width, height)
        let longScale = Double(maximumLongEdge) / Double(max(1, longEdge))
        let shortScale = Double(maximumShortEdge) / Double(max(1, shortEdge))
        let scale = min(1, longScale, shortScale)

        return RecordingExportPixelSize(
            width: max(2, Int((Double(width) * scale).rounded())),
            height: max(2, Int((Double(height) * scale).rounded()))
        )
    }
}
