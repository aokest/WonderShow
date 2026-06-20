import Foundation
import Testing

@Test func wondershowCoreReleaseKitContainsPublicBoundaryFiles() throws {
    let releaseRoot = repositoryRoot.appendingPathComponent("open-source/wondershow-core", isDirectory: true)
    let requiredFiles = [
        "Package.swift",
        "README.md",
        "LICENSE",
        "NOTICE",
        "COMMERCIAL.md",
        "PACKAGE_BOUNDARY.md",
        "CONTRIBUTING.md",
        "SECURITY.md",
        "ROADMAP.md",
        "Sources/WonderShowCore/RecordingModel.swift",
        "Sources/WonderShowCore/MediaPipeProtocol.swift",
        "Sources/WonderShowCore/PluginAPI.swift",
        "Tests/WonderShowCoreTests/RecordingModelTests.swift",
        "Tests/WonderShowCoreTests/MediaPipeProtocolTests.swift",
        "Tests/WonderShowCoreTests/PluginAPITests.swift",
        "examples/sample-project/project.json",
        "examples/sidecar-response.json",
        "examples/PluginSkeleton.swift"
    ]

    for relativePath in requiredFiles {
        let fileURL = releaseRoot.appendingPathComponent(relativePath)
        #expect(FileManager.default.fileExists(atPath: fileURL.path), "\(relativePath) should be included")
    }
}

@Test func wondershowCoreReleaseKitDocumentsCommercialBoundary() throws {
    let releaseRoot = repositoryRoot.appendingPathComponent("open-source/wondershow-core", isDirectory: true)
    let readme = try String(
        contentsOf: releaseRoot.appendingPathComponent("README.md"),
        encoding: .utf8
    )
    let commercial = try String(
        contentsOf: releaseRoot.appendingPathComponent("COMMERCIAL.md"),
        encoding: .utf8
    )
    let boundary = try String(
        contentsOf: releaseRoot.appendingPathComponent("PACKAGE_BOUNDARY.md"),
        encoding: .utf8
    )

    #expect(readme.contains("WonderShow Core"))
    #expect(readme.contains("Apache-2.0"))
    #expect(readme.contains("commercial macOS app is not included"))
    #expect(!readme.contains("Lingyan"))
    #expect(commercial.contains("paid"))
    #expect(commercial.contains("signed macOS app"))
    #expect(boundary.contains("Not Included"))
    #expect(boundary.contains("ScreenCaptureKit"))
}

@Test func wondershowCoreReleaseKitExcludesCommercialAppImplementation() throws {
    let releaseRoot = repositoryRoot.appendingPathComponent("open-source/wondershow-core", isDirectory: true)
    let subpaths = try FileManager.default.subpathsOfDirectory(atPath: releaseRoot.path)
    let forbiddenFileNames = [
        "DashboardView.swift",
        "ScreenArchiveRecorder.swift",
        "ScreenPreviewService.swift",
        "ProgramVideoRenderer.swift",
        "RecordingSessionService.swift",
        "CameraPreviewService.swift",
        "Licensing"
    ]

    for forbidden in forbiddenFileNames {
        #expect(!subpaths.contains { $0.contains(forbidden) }, "\(forbidden) should stay out of the open-source kit")
    }
}

@Test func openSourcePackagingScriptTargetsWonderShowCoreArchive() throws {
    let scriptURL = repositoryRoot.appendingPathComponent("scripts/package-open-source-kit.sh")
    let script = try String(contentsOf: scriptURL, encoding: .utf8)

    #expect(script.contains("open-source/wondershow-core"))
    #expect(script.contains("PACKAGE_NAME=\"wondershow-core-${VERSION}-${BUILD_VERSION}\""))
    #expect(script.contains("OUTPUT_ZIP=\"$OUTPUT_DIR/$PACKAGE_NAME.zip\""))
    #expect(!script.contains("lingyan-core"))
}

private var repositoryRoot: URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
