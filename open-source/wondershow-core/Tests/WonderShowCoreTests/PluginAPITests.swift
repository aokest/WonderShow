import Foundation
import Testing
@testable import WonderShowCore

@Test func pluginManifestDefaultsToCurrentAPIVersion() {
    let manifest = WonderShowPluginManifest(
        identifier: "studio.wondershow.example",
        displayName: "Example Plugin",
        vendor: "WonderShow",
        version: "0.1.0",
        capabilities: [.effectCatalog, .exportDestination]
    )

    #expect(manifest.apiVersion == WonderShowPluginAPI.version)
    #expect(manifest.capabilities.contains(.effectCatalog))
}

@Test func effectDescriptorsCanDescribePresenterBeautyControls() throws {
    let descriptor = WonderShowEffectDescriptor(
        identifier: "studio.wondershow.beauty.natural",
        displayName: "Natural Beauty",
        category: .presenterBeauty,
        parameters: [
            WonderShowEffectParameter(
                identifier: "skinSmoothing",
                displayName: "Skin Smoothing",
                valueKind: .number,
                defaultValue: "0.25"
            )
        ]
    )

    let data = try JSONEncoder().encode(descriptor)
    let decoded = try JSONDecoder().decode(WonderShowEffectDescriptor.self, from: data)

    #expect(decoded == descriptor)
    #expect(decoded.parameters.first?.valueKind == .number)
}

@Test func exportRequestCarriesDestinationAndSettings() {
    let request = WonderShowExportRequest(
        destinationURL: URL(fileURLWithPath: "/tmp/program.mp4"),
        settings: WonderShowExportSettings(
            resolution: .uhd4k,
            frameRate: .fps60,
            quality: .archival,
            codec: .hevc
        )
    )

    #expect(request.destinationURL.lastPathComponent == "program.mp4")
    #expect(request.settings.resolution == .uhd4k)
}

