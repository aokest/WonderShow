public enum AppLanguage: Hashable, Sendable {
    case zhHans
    case zhHant
    case en
}

public struct AppCopy: Hashable, Sendable {
    public let productName: String
    public let tagline: String
    public let rehearsalButton: String
    public let recordButton: String
    public let programPreview: String
    public let cameraNotConnected: String

    public init(
        productName: String,
        tagline: String,
        rehearsalButton: String,
        recordButton: String,
        programPreview: String,
        cameraNotConnected: String
    ) {
        self.productName = productName
        self.tagline = tagline
        self.rehearsalButton = rehearsalButton
        self.recordButton = recordButton
        self.programPreview = programPreview
        self.cameraNotConnected = cameraNotConnected
    }
}

public struct AppLocalization: Sendable {
    public let defaultLanguage: AppLanguage

    public init(defaultLanguage: AppLanguage = .zhHans) {
        self.defaultLanguage = defaultLanguage
    }

    public func copy(for language: AppLanguage? = nil) -> AppCopy {
        switch language ?? defaultLanguage {
        case .zhHans:
            return AppCopy(
                productName: "灵演",
                tagline: "让摄像头成为你的智能演讲导演",
                rehearsalButton: "开始彩排",
                recordButton: "开始录制",
                programPreview: "导播预览",
                cameraNotConnected: "等待连接摄像头画面"
            )
        case .zhHant:
            return AppCopy(
                productName: "靈演",
                tagline: "讓攝影機成為你的智能演講導播",
                rehearsalButton: "開始彩排",
                recordButton: "開始錄製",
                programPreview: "導播預覽",
                cameraNotConnected: "等待連接攝影機畫面"
            )
        case .en:
            return AppCopy(
                productName: "WonderShow",
                tagline: "Turn any camera into your intelligent presentation director",
                rehearsalButton: "Rehearsal",
                recordButton: "Record",
                programPreview: "Program Preview",
                cameraNotConnected: "Waiting for camera video"
            )
        }
    }
}
