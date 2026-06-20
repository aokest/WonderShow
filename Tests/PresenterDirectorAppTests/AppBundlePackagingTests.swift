import Foundation
import Testing

@Test func buildAppScriptUsesFinderCompatibleIconMetadata() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let scriptURL = packageRoot.appendingPathComponent("scripts/build-app.sh")
    let script = try String(contentsOf: scriptURL, encoding: .utf8)

    #expect(script.contains("AppIcon.icns"))
    #expect(script.contains("PresenterDirector_PresenterDirectorApp.bundle"))
    #expect(script.contains("cp -R \"$RESOURCE_BUNDLE\" \"$BUNDLE_DIR/Contents/Resources/\""))
    #expect(script.contains("CFBundleIconFile -string \"AppIcon\""))
    #expect(script.contains("PkgInfo"))
    #expect(!script.contains("CFBundleIconName"))
}
