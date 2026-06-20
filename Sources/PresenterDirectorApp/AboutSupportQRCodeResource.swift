import AppKit
import Foundation

enum AboutSupportQRCodeResource: String, CaseIterable {
    case alipay = "SupportAlipayQRCode"
    case wechat = "SupportWechatQRCode"

    var label: String {
        switch self {
        case .alipay:
            return "Alipay"
        case .wechat:
            return "WeChat"
        }
    }

    var image: NSImage? {
        guard let url = Bundle.module.url(forResource: rawValue, withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
