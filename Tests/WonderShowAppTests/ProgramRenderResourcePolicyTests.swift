@testable import WonderShow
@testable import WonderShowApp
import Testing

@Test func previewRenderPolicyCapsUHDWidescreenTo1080pEnvelope() {
    let exportSettings = RecordingExportSettings(
        resolution: .uhd4k,
        frameRate: .fps60,
        quality: .archival,
        codec: .hevc,
        customPixelSize: RecordingExportPixelSize(width: 3840, height: 2160)
    )

    let previewSettings = ProgramRenderResourcePolicy.previewSettings(from: exportSettings)

    #expect(previewSettings.effectivePixelSize?.width == 1920)
    #expect(previewSettings.effectivePixelSize?.height == 1080)
    #expect(previewSettings.frameRate == .fps30)
    #expect(previewSettings.quality == .standard)
    #expect(previewSettings.codec == .h264)
    #expect(exportSettings.effectivePixelSize?.width == 3840)
    #expect(exportSettings.effectivePixelSize?.height == 2160)
}

@Test func defaultProgramPolicyCapsAutomaticProgramTo1080pEnvelope() {
    let exportSettings = RecordingExportSettings(
        resolution: .uhd4k,
        frameRate: .fps60,
        quality: .archival,
        codec: .hevc,
        customPixelSize: RecordingExportPixelSize(width: 7680, height: 2160)
    )

    let automaticProgramSettings = ProgramRenderResourcePolicy.defaultProgramSettings(from: exportSettings)

    #expect(automaticProgramSettings.effectivePixelSize?.width == 1920)
    #expect(automaticProgramSettings.effectivePixelSize?.height == 540)
    #expect(automaticProgramSettings.frameRate == .fps30)
    #expect(automaticProgramSettings.codec == .h264)
    #expect(automaticProgramSettings.quality == .archival)
    #expect(exportSettings.effectivePixelSize?.width == 7680)
    #expect(exportSettings.effectivePixelSize?.height == 2160)
}

@Test func defaultProgramPolicyFallsBackSourceResolutionTo1080p() {
    let sourceSizedSettings = RecordingExportSettings(
        resolution: .source,
        frameRate: .fps60,
        quality: .high,
        codec: .hevc
    )

    let automaticProgramSettings = ProgramRenderResourcePolicy.defaultProgramSettings(from: sourceSizedSettings)

    #expect(automaticProgramSettings.effectivePixelSize?.width == 1920)
    #expect(automaticProgramSettings.effectivePixelSize?.height == 1080)
    #expect(automaticProgramSettings.frameRate == .fps30)
    #expect(automaticProgramSettings.codec == .h264)
    #expect(sourceSizedSettings.effectivePixelSize == nil)
}

@Test func previewRenderPolicyPreservesPortraitAspectInside1080pEnvelope() {
    let exportSettings = RecordingExportSettings(
        resolution: .uhd4k,
        frameRate: .fps30,
        quality: .high,
        codec: .h264,
        customPixelSize: RecordingExportPixelSize(width: 2160, height: 3840)
    )

    let previewSettings = ProgramRenderResourcePolicy.previewSettings(from: exportSettings)

    #expect(previewSettings.effectivePixelSize?.width == 1080)
    #expect(previewSettings.effectivePixelSize?.height == 1920)
}

@Test func previewRenderPolicyKeepsManualUHDExportAvailable() {
    let manualExportSettings = RecordingExportSettings(
        resolution: .uhd4k,
        frameRate: .fps30,
        quality: .high,
        codec: .h264
    )

    let previewSettings = ProgramRenderResourcePolicy.previewSettings(from: manualExportSettings)

    #expect(manualExportSettings.effectivePixelSize?.width == 3840)
    #expect(manualExportSettings.effectivePixelSize?.height == 2160)
    #expect(previewSettings.effectivePixelSize?.width == 1920)
    #expect(previewSettings.effectivePixelSize?.height == 1080)
}
