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

@Test func pluginContextOnlyExposesExplicitlyAllowedEnvironmentValues() {
    let hostEnvironment = [
        "PATH": "/usr/bin:/bin",
        "WONDERSHOW_PLUGIN_MODE": "sandbox",
        "SECRET_API_KEY": "should-not-leak",
        "TOKEN": "should-not-leak",
    ]

    let context = WonderShowPluginContext(
        hostAppVersion: "1.0.0",
        projectDirectory: nil,
        environment: hostEnvironment,
        allowedEnvironmentKeys: ["WONDERSHOW_PLUGIN_MODE"]
    )

    #expect(context.environment == ["WONDERSHOW_PLUGIN_MODE": "sandbox"])
    #expect(context.environment["SECRET_API_KEY"] == nil)
    #expect(context.environment["TOKEN"] == nil)
}

@Test func pluginContextDefaultsToEmptyEnvironment() {
    let context = WonderShowPluginContext(hostAppVersion: "1.0.0")

    #expect(context.environment.isEmpty)
}

@Test func exportDestinationSecurityRejectsEscapingPaths() throws {
    let root = URL(fileURLWithPath: "/tmp/wondershow-project", isDirectory: true)
    let safe = try WonderShowPluginPathSecurity.authorizedDestinationURL(
        URL(fileURLWithPath: "/tmp/wondershow-project/Exports/program.mp4"),
        allowedDirectory: root
    )
    #expect(safe.path.hasSuffix("/tmp/wondershow-project/Exports/program.mp4"))

    #expect(throws: WonderShowPluginPathSecurityError.self) {
        _ = try WonderShowPluginPathSecurity.authorizedDestinationURL(
            URL(fileURLWithPath: "/tmp/other/program.mp4"),
            allowedDirectory: root
        )
    }
}

@Test func exportDestinationSecurityRejectsDirectoryDestination() throws {
    let root = URL(fileURLWithPath: "/tmp/wondershow-project", isDirectory: true)

    #expect(throws: WonderShowPluginPathSecurityError.self) {
        _ = try WonderShowPluginPathSecurity.authorizedDestinationURL(
            URL(fileURLWithPath: "/tmp/wondershow-project/Exports", isDirectory: true),
            allowedDirectory: root
        )
    }
}
