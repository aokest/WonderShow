@testable import WonderShow
@testable import WonderShowApp
import Foundation
import Testing

#if WONDERSHOW_COMMUNITY
@Test func communityEditionUsesPracticalBaseTierWithoutFeatureTierUI() {
    #expect(WonderShowDistribution.edition == "community")
    #expect(WonderShowDistribution.isCommunityEdition)
    #expect(WonderShowDistribution.defaultRecordingFeatureTier == .vip)
    #expect(!WonderShowDistribution.showsFeatureTierUI)
    #expect(WonderShowDistribution.visibleSourceSlots(for: .vip) == [1, 2, 3, 4, 5, 6])
    #expect(WonderShowDistribution.permitsPresenterColorEffects(for: .free))
    #expect(!WonderShowDistribution.permitsSubjectAwareBeauty(for: .svip))
}

@Test func communityEditionExcludesGestureDemoDeckAndAdvancedPortraitEffects() {
    #expect(!WonderShowDistribution.includesGestureControl)
    #expect(!WonderShowDistribution.includesDemoDeck)
    #expect(!WonderShowDistribution.showsAdvancedPresenterEffectsUI)
}
#else
@Test func studioEditionKeepsFullInternalDistributionDefaults() {
    #expect(WonderShowDistribution.edition == "studio")
    #expect(!WonderShowDistribution.isCommunityEdition)
    #expect(WonderShowDistribution.defaultRecordingFeatureTier == .svip)
    #expect(WonderShowDistribution.showsFeatureTierUI)
    #expect(WonderShowDistribution.includesGestureControl)
    #expect(WonderShowDistribution.includesDemoDeck)
    #expect(WonderShowDistribution.showsAdvancedPresenterEffectsUI)
}
#endif

@Test func communityEditionBuildScriptDocumentsDistributionFlags() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let buildScript = try String(
        contentsOf: packageRoot.appendingPathComponent("scripts/build-app.sh"),
        encoding: .utf8
    )
    let packageScript = try String(
        contentsOf: packageRoot.appendingPathComponent("scripts/package-community-app.sh"),
        encoding: .utf8
    )

    #expect(buildScript.contains("APP_EDITION"))
    #expect(buildScript.contains("WONDERSHOW_COMMUNITY"))
    #expect(buildScript.contains("WonderShowEdition"))
    #expect(packageScript.contains("APP_EDITION=community"))
    #expect(packageScript.contains("wondershow-community-"))
}
