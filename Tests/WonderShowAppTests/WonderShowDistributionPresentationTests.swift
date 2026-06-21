@testable import WonderShow
@testable import WonderShowApp
import Testing

@Test func communityEditionPresentationLabelsCommunityBuildClearly() {
    let copy = AppLocalization().copy(for: .zhHans)
    let presentation = WonderShowEditionPresentation(isCommunityEdition: true)

    #expect(presentation.windowTitle == "灵演社区版")
    #expect(presentation.productName(for: copy) == "灵演社区版")
    #expect(presentation.brandLine2(for: copy) == "COMMUNITY")
    #expect(presentation.aboutTitle(for: copy) == "关于灵演社区版")
    #expect(presentation.aboutEditionNote(for: copy)?.contains("专业版") == true)
    #expect(presentation.supportBody(for: copy).contains("一瓶可乐"))
    #expect(presentation.supportBody(for: copy).contains("token"))
}

@Test func studioPresentationKeepsMainProductIdentity() {
    let copy = AppLocalization().copy(for: .zhHans)
    let presentation = WonderShowEditionPresentation(isCommunityEdition: false)

    #expect(presentation.windowTitle == "灵演")
    #expect(presentation.productName(for: copy) == "灵演")
    #expect(presentation.brandLine2(for: copy) == "STUDIO")
    #expect(presentation.aboutTitle(for: copy) == "关于灵演")
    #expect(presentation.aboutEditionNote(for: copy) == nil)
}
