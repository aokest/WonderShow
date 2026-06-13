import Testing
@testable import PresenterDirector

@Test func defaultsToSimplifiedChineseProductCopy() {
    let copy = AppLocalization().copy()

    #expect(copy.productName == "灵演")
    #expect(copy.tagline == "让 Pocket 3 成为你的智能演讲导演")
    #expect(copy.rehearsalButton == "开始彩排")
    #expect(copy.recordButton == "开始录制")
}

@Test func keepsEnglishCopyAvailableForFutureLanguageSwitching() {
    let copy = AppLocalization().copy(for: .en)

    #expect(copy.productName == "LingYan")
    #expect(copy.programPreview == "Program Preview")
}
