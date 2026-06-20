@testable import WonderShow
@testable import WonderShowApp
import Foundation
import Testing

@Test func demoControlServerRequiresLocalTokenForBridgeAPIs() {
    let unauthorizedData = DemoControlServer.shared.responseForTesting("""
    GET /api/command HTTP/1.1\r
    Host: 127.0.0.1\r
    \r

    """)
    let unauthorized = String(data: unauthorizedData, encoding: .utf8) ?? ""
    #expect(unauthorized.contains("401 Unauthorized"))
    #expect(unauthorized.contains("Unauthorized"))

    let authorizedData = DemoControlServer.shared.responseForTesting("""
    GET /api/status HTTP/1.1\r
    Host: 127.0.0.1\r
    \(WonderShowLocalSecurity.headerName): \(WonderShowLocalSecurity.sharedToken)\r
    \r

    """)
    let authorized = String(data: authorizedData, encoding: .utf8) ?? ""
    #expect(authorized.contains("200 OK"))
    #expect(authorized.contains(#"{"ok":true}"#))
}

@Test func demoControlServerDoesNotExposeTokenInDisplayURL() {
    #expect(DemoControlServer.shared.demoURL.fragment?.contains("token=") == true)
    #expect(!DemoControlServer.shared.demoURL.absoluteString.contains("?token="))
    #expect(!DemoControlServer.shared.demoDisplayURL.absoluteString.contains("token="))
}

@Test func recordingProjectStoreRejectsUnsupportedManifestSchema() throws {
    let rootURL = try temporaryProjectDirectory()
    defer {
        try? FileManager.default.removeItem(at: rootURL)
    }

    let project = RecordingProjectFactory().makeProject(
        scenario: .trainingCourse,
        camera: .builtInFaceTime,
        screen: .mainDisplay,
        durationMilliseconds: 1_000
    )
    let manifest = RecordingProjectManifest(
        schemaVersion: 99,
        project: project,
        mediaAssets: []
    )
    let manifestURL = rootURL.appendingPathComponent("project.json")
    try JSONEncoder().encode(manifest).write(to: manifestURL)

    var rejected = false
    do {
        _ = try RecordingProjectStore().load(from: rootURL)
    } catch RecordingProjectStoreError.unsupportedSchemaVersion(let version) {
        rejected = version == 99
    } catch {
        rejected = false
    }

    #expect(rejected)
}

@Test func recordingProjectStoreRejectsOversizedManifest() throws {
    let rootURL = try temporaryProjectDirectory()
    defer {
        try? FileManager.default.removeItem(at: rootURL)
    }

    let manifestURL = rootURL.appendingPathComponent("project.json")
    let oversizedData = Data(repeating: UInt8(ascii: "{"), count: 2 * 1_024 * 1_024 + 1)
    try oversizedData.write(to: manifestURL)

    var rejected = false
    do {
        _ = try RecordingProjectStore().load(from: rootURL)
    } catch RecordingProjectStoreError.manifestTooLarge(_, let size) {
        rejected = size == Int64(oversizedData.count)
    } catch {
        rejected = false
    }

    #expect(rejected)
}

private func temporaryProjectDirectory() throws -> URL {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("wondershow-security-boundary-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    return rootURL
}
