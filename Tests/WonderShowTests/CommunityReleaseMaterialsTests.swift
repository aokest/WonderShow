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
            ["功能介绍", "应用场景", "使用说明", "特点说明", "开源项目适合谁", "专业版仍在开发测试中"]
        ),
        (
            "COMMUNITY_EDITION.zh-Hant.md",
            ["功能介紹", "應用場景", "使用說明", "特點說明", "開源專案適合誰", "專業版仍在開發測試中"]
        ),
        (
            "COMMUNITY_EDITION.en.md",
            ["Feature Overview", "Use Cases", "How To Use", "Highlights", "Who The Open-Source Project Is For", "Pro edition is still in development and testing"]
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
    }
}
