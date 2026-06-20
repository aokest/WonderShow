import Testing
@testable import WonderShow

@Test func defaultsToSimplifiedChineseProductCopy() {
    let copy = AppLocalization().copy()

    #expect(copy.productName == "灵演")
    #expect(copy.tagline == "让摄像头成为你的智能演讲导演")
    #expect(copy.rehearsalButton == "开始彩排")
    #expect(copy.recordButton == "开始录制")
}

@Test func keepsEnglishCopyAvailableForFutureLanguageSwitching() {
    let copy = AppLocalization().copy(for: .en)

    #expect(copy.productName == "WonderShow")
    #expect(copy.programPreview == "Program Preview")
    #expect(copy.quickStart == "Quick Start")
    #expect(copy.gestureWorkspace == "Gestures")
    #expect(copy.devicesTitle == "Devices")
    #expect(copy.projectTitle == "Project")
    #expect(copy.openProject == "Open Project")
    #expect(copy.rehearsalPurpose == "Tests playback, slide control, and gestures only. No recording or project is saved.")
    #expect(copy.autoDirector == "Auto Director")
    #expect(copy.text("screenCaptureSource") == "Capture Source")
    #expect(copy.text("speakerMainPipLayout") == "Speaker Main + PPT PiP")
    #expect(copy.text("chooseWindows") == "Choose Windows...")
    #expect(copy.text("selectedDisplay") == "Selected Display")
    #expect(copy.text("pipShapeCircle") == "Circle")
    #expect(copy.text("audioInput") == "Audio Input")
    #expect(copy.text("audioDetails") == "Audio Details")
    #expect(copy.text("systemDefaultMicrophoneDetail") == "Follow macOS sound input")
    #expect(copy.projectPending == "No project")
    #expect(copy.previewUnavailable == "Not ready")
    #expect(copy.text("timelineFullProgram") == "Full")
    #expect(copy.text("timelineExportRange") == "Export Range")
    #expect(copy.connected == "Connected")
    #expect(copy.openTestDeck == "Open Test Deck")
    #expect(copy.runtimeText("热区已进入") == "Inside zone")
    #expect(copy.runtimeText("剑指、握拳") == "Sword, Fist")
    #expect(copy.calibrationSampleProgress(current: 2, total: 3).hasPrefix("Sample 2 of 3."))
}

@Test func keepsTraditionalChineseDashboardCopyAvailable() {
    let copy = AppLocalization().copy(for: .zhHant)

    #expect(copy.productName == "靈演")
    #expect(copy.quickStart == "快速啟動")
    #expect(copy.gestureWorkspace == "手勢工作區")
    #expect(copy.devicesTitle == "設備與輸出")
    #expect(copy.projectTitle == "專案")
    #expect(copy.openProject == "開啟專案")
    #expect(copy.rehearsalPurpose == "只測試播放/翻頁/手勢，不錄屏、不收音、不保存專案")
    #expect(copy.autoDirector == "自動導播")
    #expect(copy.text("screenCaptureSource") == "錄製源")
    #expect(copy.text("speakerMainPipLayout") == "講者主畫面 + PPT子母畫面")
    #expect(copy.text("chooseWindows") == "選擇視窗…")
    #expect(copy.text("selectedDisplay") == "已選螢幕")
    #expect(copy.text("pipShapeCircle") == "圓形")
    #expect(copy.openTestDeck == "開啟測試簡報")
    #expect(copy.runtimeText("热区已进入") == "已進入熱區")
    #expect(copy.runtimeText("剑指、握拳") == "劍指、握拳")
}
