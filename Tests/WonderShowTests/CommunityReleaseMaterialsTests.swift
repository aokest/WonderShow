import Foundation
import Testing

@Test func communityReleaseMaterialsCoverThreeLanguagesAndOpenSourceAudience() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let docsRoot = packageRoot
        .appendingPathComponent("open-source")
        .appendingPathComponent("wondershow-core")
        .appendingPathComponent("docs")

    let expectedDocuments: [(name: String, requiredPhrases: [String])] = [
        (
            "COMMUNITY_EDITION.zh-Hans.md",
            ["功能介绍", "应用场景", "使用说明", "特点说明", "开源项目适合谁", "录制演示窗口"]
        ),
        (
            "COMMUNITY_EDITION.zh-Hant.md",
            ["功能介紹", "應用場景", "使用說明", "特點說明", "開源專案適合誰", "錄製簡報視窗"]
        ),
        (
            "COMMUNITY_EDITION.en.md",
            ["Feature Overview", "Use Cases", "How To Use", "Highlights", "Who The Open-Source Project Is For", "record a presentation window"]
        )
    ]

    for document in expectedDocuments {
        let text = try String(
            contentsOf: docsRoot.appendingPathComponent(document.name),
            encoding: .utf8
        )
        for phrase in document.requiredPhrases {
            #expect(text.contains(phrase))
        }
        for forbiddenPhrase in forbiddenCommunityReleasePhrases {
            #expect(!text.localizedCaseInsensitiveContains(forbiddenPhrase))
        }
    }
}

private let forbiddenCommunityReleasePhrases = [
    "VIP", "SVIP",
    "实验", "實驗", "experimental", "laboratory",
    "专业版", "專業版", "Pro edition", "Pro features",
    "美颜", "美顏", "beauty",
    "手势", "手勢", "gesture",
    "训练", "訓練", "training",
    "Emoji",
    "背景替换", "背景替換", "background replacement"
]
