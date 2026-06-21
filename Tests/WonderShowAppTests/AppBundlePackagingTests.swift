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
    #expect(script.contains("APP_NAME=\"${APP_NAME:-灵演}\""))
    #expect(script.contains("APP_NAME=\"${APP_NAME:-灵演社区版}\""))
    #expect(script.contains("EXECUTABLE=\"WonderShowApp\""))
    #expect(script.contains("WonderShow_WonderShowApp.bundle"))
    #expect(script.contains("CFBundleIdentifier -string \"com.wondershow.studio\""))
    #expect(script.contains("cp -R \"$RESOURCE_BUNDLE\" \"$BUNDLE_DIR/Contents/Resources/\""))
    #expect(script.contains("WonderShowEdition"))
    #expect(script.contains("--options runtime"))
    #expect(script.contains("strip -S -x"))
    #expect(script.contains("CFBundleIconFile -string \"AppIcon\""))
    #expect(script.contains("PkgInfo"))
    #expect(!script.contains("CFBundleIconName"))
    #expect(!script.contains("com.local.LingYan"))
}
