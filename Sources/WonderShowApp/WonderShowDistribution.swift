import WonderShow

enum WonderShowDistribution {
    #if WONDERSHOW_COMMUNITY
    static let edition = "community"
    static let isCommunityEdition = true
    #else
    static let edition = "studio"
    static let isCommunityEdition = false
    #endif

    static var presentation: WonderShowEditionPresentation {
        WonderShowEditionPresentation(isCommunityEdition: isCommunityEdition)
    }

    static var windowTitle: String {
        presentation.windowTitle
    }

    static var defaultRecordingFeatureTier: RecordingFeatureTier {
        isCommunityEdition ? .vip : .svip
    }

    static var showsFeatureTierUI: Bool {
        !isCommunityEdition
    }

    static var includesGestureControl: Bool {
        !isCommunityEdition
    }

    static var includesDemoDeck: Bool {
        includesGestureControl
    }

    static var showsAdvancedPresenterEffectsUI: Bool {
        !isCommunityEdition
    }

    static func permitsPresenterColorEffects(for tier: RecordingFeatureTier) -> Bool {
        isCommunityEdition ? true : tier.permitsPresenterColorEffects
    }

    static func permitsSubjectAwareBeauty(for tier: RecordingFeatureTier) -> Bool {
        !isCommunityEdition && tier.permitsSubjectAwareBeauty
    }

    static func visibleSourceSlots(for tier: RecordingFeatureTier) -> [Int] {
        if isCommunityEdition {
            return Array(tier.sourceSlotRange)
        }
        return Array(RecordingSourceSlots.validSlots)
    }

    static func unavailableSourceSlotMessage(slot: Int, copy: AppCopy, tier: RecordingFeatureTier) -> String {
        if isCommunityEdition {
            let range = tier.sourceSlotRange
            return copy.runtimeText("社区版可使用源位 \(range.lowerBound)-\(range.upperBound)，当前源位 \(slot) 不可用")
        }
        return "\(tier.localizedLabel(copy)) \(copy.text("sourceSlotLocked")) \(slot)"
    }
}
