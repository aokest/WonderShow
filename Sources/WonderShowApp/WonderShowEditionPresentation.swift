import WonderShow

struct WonderShowEditionPresentation: Hashable, Sendable {
    let isCommunityEdition: Bool

    var windowTitle: String {
        isCommunityEdition ? "灵演社区版" : "灵演"
    }

    func productName(for copy: AppCopy) -> String {
        guard isCommunityEdition else {
            return copy.productName
        }

        switch copy.language {
        case .zhHans:
            return "灵演社区版"
        case .zhHant:
            return "靈演社群版"
        case .en:
            return "WonderShow Community"
        }
    }

    func brandLine2(for copy: AppCopy) -> String {
        isCommunityEdition ? "COMMUNITY" : copy.brandLine2
    }

    func aboutTitle(for copy: AppCopy) -> String {
        guard isCommunityEdition else {
            return copy.aboutTitle
        }

        switch copy.language {
        case .zhHans:
            return "关于灵演社区版"
        case .zhHant:
            return "關於靈演社群版"
        case .en:
            return "About WonderShow Community"
        }
    }

    func aboutEditionNote(for copy: AppCopy) -> String? {
        guard isCommunityEdition else {
            return nil
        }

        switch copy.language {
        case .zhHans:
            return "这是社区版。专业版仍在开发测试中，希望在不久的未来，专业版和其他配套工具可以和大家见面。"
        case .zhHant:
            return "這是社群版。專業版仍在開發測試中，希望在不久的未來，專業版和其他配套工具可以和大家見面。"
        case .en:
            return "This is the Community Edition. The Pro edition is still in development and testing, and I hope to share it with companion tools in the near future."
        }
    }

    func supportTitle(for copy: AppCopy) -> String {
        switch copy.language {
        case .zhHans:
            return "感谢作者"
        case .zhHant:
            return "感謝作者"
        case .en:
            return "Support the author"
        }
    }

    func supportBody(for copy: AppCopy) -> String {
        switch copy.language {
        case .zhHans:
            return "如果觉得灵演社区版对你有帮助，可以支持我一瓶可乐，或一些 token。"
        case .zhHant:
            return "如果覺得靈演社群版對你有幫助，可以支持我一瓶可樂，或一些 token。"
        case .en:
            return "If WonderShow Community helps you, you can support me with a cola or a few tokens."
        }
    }
}
