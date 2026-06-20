@testable import PresenterDirectorApp
import Testing

@Test func aboutSupportQRCodesAreBundledWithAppResources() {
    for code in AboutSupportQRCodeResource.allCases {
        #expect(code.image != nil)
    }
}
