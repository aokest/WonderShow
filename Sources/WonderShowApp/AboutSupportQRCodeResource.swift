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
        #if WONDERSHOW_COMMUNITY
        for bundle in Self.communityResourceBundles {
            if let url = bundle.url(forResource: rawValue, withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return nil
        #else
        guard let url = Bundle.module.url(forResource: rawValue, withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
        #endif
    }

    private static var communityResourceBundles: [Bundle] {
        var bundles = [Bundle.main]
        if let bundleURL = Bundle.main.url(forResource: "WonderShow_WonderShowApp", withExtension: "bundle"),
           let bundle = Bundle(url: bundleURL) {
            bundles.append(bundle)
        }
        if let resourceURL = Bundle.main.resourceURL?
            .appendingPathComponent("WonderShow_WonderShowApp.bundle", isDirectory: true),
           let bundle = Bundle(url: resourceURL) {
            bundles.append(bundle)
        }
        return bundles
    }
}
