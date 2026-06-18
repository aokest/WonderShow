import Foundation

public enum AppLanguage: Hashable, Sendable, CaseIterable {
    case zhHans
    case zhHant
    case en

    public var label: String {
        switch self {
        case .zhHans: return "简"
        case .zhHant: return "繁"
        case .en: return "EN"
        }
    }
}

public struct AppCopy: Hashable, Sendable {
    public let language: AppLanguage
    public let productName: String
    public let tagline: String
    public let rehearsalButton: String
    public let recordButton: String
    public let programPreview: String
    public let cameraNotConnected: String
    /// 顶部品牌区第一行文字（如 WONDERSHOW / 灵演）
    public let brandLine1: String
    /// 顶部品牌区第二行文字（如 STUDIO / 工作室）
    public let brandLine2: String
    public let strings: [String: String]

    public init(
        language: AppLanguage = .zhHans,
        productName: String,
        tagline: String,
        rehearsalButton: String,
        recordButton: String,
        programPreview: String,
        cameraNotConnected: String,
        brandLine1: String,
        brandLine2: String,
        strings: [String: String] = [:]
    ) {
        self.language = language
        self.productName = productName
        self.tagline = tagline
        self.rehearsalButton = rehearsalButton
        self.recordButton = recordButton
        self.programPreview = programPreview
        self.cameraNotConnected = cameraNotConnected
        self.brandLine1 = brandLine1
        self.brandLine2 = brandLine2
        self.strings = strings
    }

    public func text(_ key: String) -> String {
        strings[key] ?? key
    }

    public func runtimeText(_ text: String) -> String {
        guard language != .zhHans, !text.isEmpty else {
            return text
        }

        if let translated = runtimeExactTranslations[text] {
            return translated
        }

        var translated = text
        let phraseTranslations = runtimePhraseTranslations.merging(runtimeExactTranslations) { current, _ in
            current
        }
        for (source, replacement) in phraseTranslations.sorted(by: { $0.key.count > $1.key.count }) {
            translated = translated.replacingOccurrences(of: source, with: replacement)
        }
        translated = translated.replacingOccurrences(of: "、", with: language == .en ? ", " : "、")
        translated = translated.replacingOccurrences(of: "；", with: language == .en ? "; " : "；")
        return translated
    }

    public func calibrationSampleProgress(current: Int, total: Int) -> String {
        switch language {
        case .zhHans:
            return "第 \(current) / \(total) 次。\(calibrationHint)"
        case .zhHant:
            return "第 \(current) / \(total) 次。\(calibrationHint)"
        case .en:
            return "Sample \(current) of \(total). \(calibrationHint)"
        }
    }
}

public extension AppCopy {
    var camera: String { text("camera") }
    var gesture: String { text("gesture") }
    var target: String { text("target") }
    var rec: String { text("rec") }
    var connected: String { text("connected") }
    var disconnected: String { text("disconnected") }
    var recognizing: String { text("recognizing") }
    var standby: String { text("standby") }
    var recording: String { text("recording") }
    var ready: String { text("ready") }
    var rehearse: String { text("rehearse") }
    var stopRehearse: String { text("stopRehearse") }
    var startRec: String { text("startRec") }
    var stopRec: String { text("stopRec") }
    var reconnect: String { text("reconnect") }
    var live: String { text("live") }
    var quickStart: String { text("quickStart") }
    var realtime: String { text("realtime") }
    var rehearseState: String { text("rehearseState") }
    var recState: String { text("recState") }
    var activeDevice: String { text("activeDevice") }
    var currentGesture: String { text("currentGesture") }
    var refreshDevices: String { text("refreshDevices") }
    var testSlide: String { text("testSlide") }
    var presentSettings: String { text("presentSettings") }
    var auto: String { text("auto") }
    var targetApp: String { text("targetApp") }
    var recMode: String { text("recMode") }
    var layout: String { text("layout") }
    var appPPT: String { text("appPPT") }
    var appWPS: String { text("appWPS") }
    var appKeynote: String { text("appKeynote") }
    var appWord: String { text("appWord") }
    var appExcel: String { text("appExcel") }
    var appPDF: String { text("appPDF") }
    var appHTML: String { text("appHTML") }
    var modeCam: String { text("modeCam") }
    var modeCamScreen: String { text("modeCamScreen") }
    var layoutCloseup: String { text("layoutCloseup") }
    var layoutPiP: String { text("layoutPiP") }
    var layoutSide: String { text("layoutSide") }
    var openTestDeck: String { text("openTestDeck") }
    var gestureWorkspace: String { text("gestureWorkspace") }
    var last5min: String { text("last5min") }
    var enableGesture: String { text("enableGesture") }
    var recogState: String { text("recogState") }
    var session: String { text("session") }
    var engine: String { text("engine") }
    var zone: String { text("zone") }
    var calibrate: String { text("calibrate") }
    var cheatsheet: String { text("cheatsheet") }
    var g1name: String { text("g1name") }
    var g1result: String { text("g1result") }
    var g2name: String { text("g2name") }
    var g2result: String { text("g2result") }
    var g3name: String { text("g3name") }
    var g3result: String { text("g3result") }
    var g4name: String { text("g4name") }
    var g4result: String { text("g4result") }
    var devicesTitle: String { text("devicesTitle") }
    var autoScan: String { text("autoScan") }
    var inputDevice: String { text("inputDevice") }
    var rescan: String { text("rescan") }
    var statusLabel: String { text("statusLabel") }
    var deviceDetail: String { text("deviceDetail") }
    var inputsFound: String { text("inputsFound") }
    var transport: String { text("transport") }
    var recModeLabel: String { text("recModeLabel") }
    var layoutLabel: String { text("layoutLabel") }
    var outputTracks: String { text("outputTracks") }
    var trackUnit: String { text("trackUnit") }
    var elapsed: String { text("elapsed") }
    var directorMode: String { text("directorMode") }
    var about: String { text("about") }
    var advDiag: String { text("advDiag") }
    var waitingConnection: String { text("waitingConnection") }
    var accessPerm: String { text("accessPerm") }
    var chromeAuto: String { text("chromeAuto") }
    var scanSummary: String { text("scanSummary") }
    var examples: String { text("examples") }
    var permBtn: String { text("permBtn") }
    var requestBtn: String { text("requestBtn") }
    var chromeBtn: String { text("chromeBtn") }
    var refreshBtn: String { text("refreshBtn") }
    var aboutTitle: String { text("aboutTitle") }
    var authorLabel: String { text("authorLabel") }
    var authorVal: String { text("authorVal") }
    var genericKeyboard: String { text("genericKeyboard") }
    var selectInputDevice: String { text("selectInputDevice") }
    var deviceListPending: String { text("deviceListPending") }
    var noInputsFound: String { text("noInputsFound") }
    var inputCountSuffix: String { text("inputCountSuffix") }
    var supportedDevices: String { text("supportedDevices") }
    var calibrationTitle: String { text("calibrationTitle") }
    var calibrationHint: String { text("calibrationHint") }
    var startAutoSample: String { text("startAutoSample") }
    var finish: String { text("finish") }
    var currentHandShape: String { text("currentHandShape") }
    var projectTitle: String { text("projectTitle") }
    var projectLocation: String { text("projectLocation") }
    var projectPending: String { text("projectPending") }
    var openProject: String { text("openProject") }
    var revealProject: String { text("revealProject") }
    var previewProgram: String { text("previewProgram") }
    var previewUnavailable: String { text("previewUnavailable") }
    var rehearsalPurpose: String { text("rehearsalPurpose") }
    var autoDirector: String { text("autoDirector") }
    var autoDirectorStage: String { text("autoDirectorStage") }
    var autoDirectorTraining: String { text("autoDirectorTraining") }
    var programExport: String { text("programExport") }
    var rawTracks: String { text("rawTracks") }
    var exportSettings: String { text("exportSettings") }
    var resolution: String { text("resolution") }
    var frameRate: String { text("frameRate") }
    var quality: String { text("quality") }
    var codec: String { text("codec") }
    var export: String { text("export") }
    var cancel: String { text("cancel") }
    var openFile: String { text("openFile") }
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
                language: .zhHans,
                productName: "灵演",
                tagline: "让摄像头成为你的智能演讲导演",
                rehearsalButton: "开始彩排",
                recordButton: "开始录制",
                programPreview: "导播预览",
                cameraNotConnected: "等待连接摄像头画面",
                brandLine1: "WONDERSHOW",
                brandLine2: "STUDIO",
                strings: [
                    "camera": "摄像头", "gesture": "手势", "target": "目标", "rec": "录制",
                    "connected": "已连接", "disconnected": "未连接", "recognizing": "识别中", "standby": "待命",
                    "recording": "进行中", "ready": "就绪", "rehearse": "开始彩排", "stopRehearse": "结束彩排",
                    "startRec": "开始录制", "stopRec": "停止录制", "reconnect": "重新连接", "live": "直播",
                    "quickStart": "快速启动", "realtime": "实时", "rehearseState": "演练状态", "recState": "录制状态",
                    "activeDevice": "活跃设备", "currentGesture": "当前手势", "refreshDevices": "刷新设备", "testSlide": "测试投影片",
                    "presentSettings": "演示设定", "auto": "自动", "targetApp": "目标应用", "recMode": "录制模式", "layout": "布局",
                    "appPPT": "PowerPoint", "appWPS": "WPS", "appKeynote": "Keynote", "appWord": "Word", "appExcel": "Excel",
                    "appPDF": "PDF", "appHTML": "HTML", "modeCam": "摄像头", "modeCamScreen": "摄像头 + 屏幕",
                    "layoutCloseup": "人物特写", "layoutPiP": "子母画面 · 右下角", "layoutPiPBase": "子母画面",
                    "layoutSide": "左右分屏", "topLeft": "左上角", "topRight": "右上角", "bottomLeft": "左下角", "bottomRight": "右下角",
                    "openTestDeck": "打开测试演示文稿", "gestureWorkspace": "手势工作区", "last5min": "最近 5 分钟",
                    "enableGesture": "启用手势识别", "recogState": "识别状态", "session": "本次会话", "engine": "识别引擎",
                    "zone": "手势区域", "calibrate": "校准我的手势", "cheatsheet": "手势速查",
                    "g1name": "剑指右挥", "g1result": "下一张", "g2name": "剑指左挥", "g2result": "上一张",
                    "g3name": "张开手掌", "g3result": "暂停", "g4name": "双手分开", "g4result": "放大",
                    "devicesTitle": "设备与输出", "autoScan": "自动扫描", "inputDevice": "输入设备", "rescan": "扫描",
                    "statusLabel": "状态", "deviceDetail": "设备详情", "inputsFound": "检测输入", "transport": "输出协议",
                    "recModeLabel": "录制模式", "layoutLabel": "布局", "outputTracks": "输出轨道", "trackUnit": "轨道",
                    "elapsed": "已用时长", "directorMode": "导演模式", "about": "关于", "advDiag": "高级诊断",
                    "waitingConnection": "等待连接", "accessPerm": "辅助功能", "chromeAuto": "Chrome 自动化",
                    "scanSummary": "扫描摘要", "examples": "兼容示例", "permBtn": "权限设置", "requestBtn": "请求权限",
                    "chromeBtn": "Chrome 授权", "refreshBtn": "刷新状态", "aboutTitle": "关于灵演",
                    "authorLabel": "作者", "authorVal": "傲客", "genericKeyboard": "通用",
                    "selectInputDevice": "选择输入设备", "deviceListPending": "设备列表待刷新",
                    "noInputsFound": "未发现可采集摄像头", "inputCountSuffix": "路输入",
                    "supportedDevices": "内置 / DJI / Insta360 / 采集卡 / 网络摄像头",
                    "calibrationTitle": "个人手势校准", "calibrationHint": "点击开始后看着摄像头完成动作，系统会自动判断成功并进入下一次。",
                    "startAutoSample": "开始自动采样", "finish": "结束", "currentHandShape": "当前手型",
                    "projectTitle": "项目", "projectLocation": "保存位置", "projectPending": "尚未创建录制项目",
                    "openProject": "打开项目", "revealProject": "在 Finder 中显示", "previewProgram": "预览合成",
                    "previewUnavailable": "合成视频尚未生成", "rehearsalPurpose": "只测试播放/翻页/手势，不录屏、不收音、不保存项目",
                    "autoDirector": "自动导播", "autoDirectorStage": "演讲模板：全身 / 特写 / PPT 画中画 / PPT 全屏",
                    "autoDirectorTraining": "录课模板：特写画中画 / PPT 全屏 / 人物特写",
                    "programExport": "合成输出", "rawTracks": "原始轨道",
                    "stagePresentation": "正式演讲", "trainingCourse": "培训录屏",
                    "importProject": "导入项目", "exportProject": "导出项目", "exportVideo": "导出视频",
                    "exportSettings": "导出设置", "resolution": "分辨率", "frameRate": "帧率",
                    "quality": "清晰度", "codec": "编码", "export": "导出", "cancel": "取消",
                    "openFile": "打开文件", "screenPermBtn": "屏幕录制",
                    "screenCaptureSource": "录制源", "sourcePresentationWindow": "演示窗口（自动）",
                    "sourceEntireDisplay": "整个屏幕", "chooseWindows": "选择窗口…",
                    "chooseWindowsHint": "可勾选一个或多个活跃窗口", "useSelectedWindows": "使用所选窗口",
                    "useSelectedSource": "使用所选源",
                    "selectedDisplay": "已选屏幕", "selectedOneWindow": "已选 1 个窗口", "selectedWindowsPrefix": "已选窗口",
                    "screenSourcePending": "点击扫描读取可录制屏幕和窗口",
                    "noScreenSources": "没有读取到可录制源",
                    "noScreenSourcesHint": "当前构建的屏幕录制权限未生效。先请求权限；若仍为空，打开系统设置重新允许灵演。",
                    "requestScreenCaptureAccess": "请求权限", "openScreenCaptureSettings": "系统设置",
                    "thumbnailView": "缩略图", "listView": "列表", "thumbnailLoading": "预览加载中",
                    "pipControls": "画中画", "pipSize": "尺寸",
                    "pipShapeRounded": "长方形", "pipShapeSquare": "正方形", "pipShapeCircle": "圆形",
                    "modeScreenOnly": "只录屏",
                    "modeSpeakerOnly": "只录讲者", "screenMainPipLayout": "PPT主画面 + 讲者画中画",
                    "speakerMainPipLayout": "讲者主画面 + PPT画中画", "screenOnlyLayout": "PPT/屏幕全屏",
                    "speakerOnlyLayout": "讲者全屏", "layoutSpeakerFullBody": "人物全身",
                    "layoutMeaning": "合成方式", "compositionScreenOnly": "只录制并导出 PPT/屏幕画面",
                    "compositionSpeakerOnly": "只录制并导出讲者画面",
                    "compositionScreenMain": "PPT/屏幕为主画面，讲者作为右下角画中画",
                    "compositionSpeakerMain": "讲者为主画面，PPT/屏幕作为画中画",
                    "compositionSideBySide": "PPT/屏幕与讲者左右分屏对齐",
                    "timelineTitle": "录制时间轴", "timelinePending": "按开始录制后生成项目轨道",
                    "timelineRecording": "正在写入原始轨", "trackSlides": "PPT/屏幕",
                    "trackSpeaker": "讲者", "trackMic": "声音", "trackProgram": "合成",
                    "trackWriting": "写入中", "trackStarting": "启动中"
                ]
            )
        case .zhHant:
            return AppCopy(
                language: .zhHant,
                productName: "靈演",
                tagline: "讓攝影機成為你的智能演講導播",
                rehearsalButton: "開始彩排",
                recordButton: "開始錄製",
                programPreview: "導播預覽",
                cameraNotConnected: "等待連接攝影機畫面",
                brandLine1: "WONDERSHOW",
                brandLine2: "STUDIO",
                strings: [
                    "camera": "攝像頭", "gesture": "手勢", "target": "目標", "rec": "錄製",
                    "connected": "已連接", "disconnected": "未連接", "recognizing": "識別中", "standby": "待命",
                    "recording": "進行中", "ready": "就緒", "rehearse": "開始彩排", "stopRehearse": "結束彩排",
                    "startRec": "開始錄製", "stopRec": "停止錄製", "reconnect": "重新連接", "live": "直播",
                    "quickStart": "快速啟動", "realtime": "即時", "rehearseState": "演練狀態", "recState": "錄製狀態",
                    "activeDevice": "活躍設備", "currentGesture": "當前手勢", "refreshDevices": "刷新設備", "testSlide": "測試投影片",
                    "presentSettings": "演示設定", "auto": "自動", "targetApp": "目標應用", "recMode": "錄製模式", "layout": "版面",
                    "appPPT": "PowerPoint", "appWPS": "WPS", "appKeynote": "Keynote", "appWord": "Word", "appExcel": "Excel",
                    "appPDF": "PDF", "appHTML": "HTML", "modeCam": "攝像頭", "modeCamScreen": "攝像頭 + 螢幕",
                    "layoutCloseup": "人物特寫", "layoutPiP": "子母畫面 · 右下角", "layoutPiPBase": "子母畫面",
                    "layoutSide": "左右分屏", "topLeft": "左上角", "topRight": "右上角", "bottomLeft": "左下角", "bottomRight": "右下角",
                    "openTestDeck": "開啟測試簡報", "gestureWorkspace": "手勢工作區", "last5min": "最近 5 分鐘",
                    "enableGesture": "啟用手勢識別", "recogState": "識別狀態", "session": "本次工作階段", "engine": "識別引擎",
                    "zone": "手勢區域", "calibrate": "校準我的手勢", "cheatsheet": "手勢速查",
                    "g1name": "劍指右揮", "g1result": "下一張", "g2name": "劍指左揮", "g2result": "上一張",
                    "g3name": "張開手掌", "g3result": "暫停", "g4name": "雙手分開", "g4result": "放大",
                    "devicesTitle": "設備與輸出", "autoScan": "自動掃描", "inputDevice": "輸入設備", "rescan": "掃描",
                    "statusLabel": "狀態", "deviceDetail": "設備詳情", "inputsFound": "偵測輸入", "transport": "輸出協議",
                    "recModeLabel": "錄製模式", "layoutLabel": "版面", "outputTracks": "輸出軌道", "trackUnit": "軌道",
                    "elapsed": "已用時長", "directorMode": "導演模式", "about": "關於", "advDiag": "進階診斷",
                    "waitingConnection": "等待連接", "accessPerm": "輔助使用", "chromeAuto": "Chrome 自動化",
                    "scanSummary": "掃描摘要", "examples": "兼容範例", "permBtn": "權限設定", "requestBtn": "請求權限",
                    "chromeBtn": "Chrome 授權", "refreshBtn": "刷新狀態", "aboutTitle": "關於靈演",
                    "authorLabel": "作者", "authorVal": "傲客", "genericKeyboard": "通用",
                    "selectInputDevice": "選擇輸入設備", "deviceListPending": "設備列表待刷新",
                    "noInputsFound": "未發現可採集攝像頭", "inputCountSuffix": "路輸入",
                    "supportedDevices": "內建 / DJI / Insta360 / 採集卡 / 網路攝像頭",
                    "calibrationTitle": "個人手勢校準", "calibrationHint": "點擊開始後看著攝像頭完成動作，系統會自動判斷成功並進入下一次。",
                    "startAutoSample": "開始自動採樣", "finish": "結束", "currentHandShape": "當前手型",
                    "projectTitle": "專案", "projectLocation": "保存位置", "projectPending": "尚未建立錄製專案",
                    "openProject": "開啟專案", "revealProject": "在 Finder 中顯示", "previewProgram": "預覽合成",
                    "previewUnavailable": "合成影片尚未產生", "rehearsalPurpose": "只測試播放/翻頁/手勢，不錄屏、不收音、不保存專案",
                    "autoDirector": "自動導播", "autoDirectorStage": "演講模板：全身 / 特寫 / PPT 子母畫面 / PPT 全螢幕",
                    "autoDirectorTraining": "錄課模板：特寫子母畫面 / PPT 全螢幕 / 人物特寫",
                    "programExport": "合成輸出", "rawTracks": "原始軌道",
                    "stagePresentation": "正式演講", "trainingCourse": "培訓錄屏",
                    "importProject": "導入專案", "exportProject": "匯出專案", "exportVideo": "匯出影片",
                    "exportSettings": "匯出設定", "resolution": "解析度", "frameRate": "影格率",
                    "quality": "清晰度", "codec": "編碼", "export": "匯出", "cancel": "取消",
                    "openFile": "開啟檔案", "screenPermBtn": "螢幕錄製",
                    "screenCaptureSource": "錄製源", "sourcePresentationWindow": "簡報視窗（自動）",
                    "sourceEntireDisplay": "整個螢幕", "chooseWindows": "選擇視窗…",
                    "chooseWindowsHint": "可勾選一個或多個活躍視窗", "useSelectedWindows": "使用所選視窗",
                    "useSelectedSource": "使用所選源",
                    "selectedDisplay": "已選螢幕", "selectedOneWindow": "已選 1 個視窗", "selectedWindowsPrefix": "已選視窗",
                    "screenSourcePending": "點擊掃描讀取可錄製螢幕和視窗",
                    "noScreenSources": "沒有讀取到可錄製源",
                    "noScreenSourcesHint": "目前構建的螢幕錄製權限未生效。先請求權限；若仍為空，開啟系統設定重新允許靈演。",
                    "requestScreenCaptureAccess": "請求權限", "openScreenCaptureSettings": "系統設定",
                    "thumbnailView": "縮圖", "listView": "列表", "thumbnailLoading": "預覽載入中",
                    "pipControls": "子母畫面", "pipSize": "尺寸",
                    "pipShapeRounded": "長方形", "pipShapeSquare": "正方形", "pipShapeCircle": "圓形",
                    "modeScreenOnly": "只錄屏",
                    "modeSpeakerOnly": "只錄講者", "screenMainPipLayout": "PPT主畫面 + 講者子母畫面",
                    "speakerMainPipLayout": "講者主畫面 + PPT子母畫面", "screenOnlyLayout": "PPT/螢幕全屏",
                    "speakerOnlyLayout": "講者全屏", "layoutSpeakerFullBody": "人物全身",
                    "layoutMeaning": "合成方式", "compositionScreenOnly": "只錄製並匯出 PPT/螢幕畫面",
                    "compositionSpeakerOnly": "只錄製並匯出講者畫面",
                    "compositionScreenMain": "PPT/螢幕為主畫面，講者作為右下角子母畫面",
                    "compositionSpeakerMain": "講者為主畫面，PPT/螢幕作為子母畫面",
                    "compositionSideBySide": "PPT/螢幕與講者左右分屏對齊",
                    "timelineTitle": "錄製時間軸", "timelinePending": "按開始錄製後生成專案軌道",
                    "timelineRecording": "正在寫入原始軌", "trackSlides": "PPT/螢幕",
                    "trackSpeaker": "講者", "trackMic": "聲音", "trackProgram": "合成",
                    "trackWriting": "寫入中", "trackStarting": "啟動中"
                ]
            )
        case .en:
            return AppCopy(
                language: .en,
                productName: "WonderShow",
                tagline: "Turn any camera into your intelligent presentation director",
                rehearsalButton: "Rehearsal",
                recordButton: "Record",
                programPreview: "Program Preview",
                cameraNotConnected: "Waiting for camera video",
                brandLine1: "WONDERSHOW",
                brandLine2: "STUDIO",
                strings: [
                    "camera": "Camera", "gesture": "Gesture", "target": "Target", "rec": "Record",
                    "connected": "Connected", "disconnected": "Offline", "recognizing": "Active", "standby": "Idle",
                    "recording": "Active", "ready": "Ready", "rehearse": "Rehearse", "stopRehearse": "Stop Rehearsal",
                    "startRec": "Start Rec", "stopRec": "Stop", "reconnect": "Reconnect", "live": "LIVE",
                    "quickStart": "Quick Start", "realtime": "Live", "rehearseState": "Rehearsal", "recState": "Record",
                    "activeDevice": "Device", "currentGesture": "Gesture", "refreshDevices": "Refresh", "testSlide": "Test Slide",
                    "presentSettings": "Presentation", "auto": "Auto", "targetApp": "Target App", "recMode": "Rec Mode", "layout": "Layout",
                    "appPPT": "PowerPoint", "appWPS": "WPS", "appKeynote": "Keynote", "appWord": "Word", "appExcel": "Excel",
                    "appPDF": "PDF", "appHTML": "HTML", "modeCam": "Camera", "modeCamScreen": "Camera + Screen",
                    "layoutCloseup": "Close-up", "layoutPiP": "PiP · Bottom Right", "layoutPiPBase": "PiP",
                    "layoutSide": "Side by Side", "topLeft": "Top Left", "topRight": "Top Right", "bottomLeft": "Bottom Left", "bottomRight": "Bottom Right",
                    "openTestDeck": "Open Test Deck", "gestureWorkspace": "Gestures", "last5min": "Last 5 min",
                    "enableGesture": "Enable gesture recognition", "recogState": "State", "session": "Session", "engine": "Engine",
                    "zone": "Zone", "calibrate": "Calibrate gestures", "cheatsheet": "Cheatsheet",
                    "g1name": "Sword swipe right", "g1result": "Next", "g2name": "Sword swipe left", "g2result": "Previous",
                    "g3name": "Open palm", "g3result": "Pause", "g4name": "Hands apart", "g4result": "Zoom in",
                    "devicesTitle": "Devices", "autoScan": "Auto scan", "inputDevice": "Input Device", "rescan": "Scan",
                    "statusLabel": "Status", "deviceDetail": "Details", "inputsFound": "Inputs", "transport": "Transport",
                    "recModeLabel": "Rec Mode", "layoutLabel": "Layout", "outputTracks": "Tracks", "trackUnit": "tracks",
                    "elapsed": "Elapsed", "directorMode": "Director", "about": "About", "advDiag": "Diagnostics",
                    "waitingConnection": "Waiting", "accessPerm": "Accessibility", "chromeAuto": "Chrome Automation",
                    "scanSummary": "Scan Summary", "examples": "Supported", "permBtn": "Permissions", "requestBtn": "Request Access",
                    "chromeBtn": "Chrome Auth", "refreshBtn": "Refresh", "aboutTitle": "About WonderShow",
                    "authorLabel": "Author", "authorVal": "Aokest", "genericKeyboard": "Generic",
                    "selectInputDevice": "Select input", "deviceListPending": "Device list pending",
                    "noInputsFound": "No camera inputs found", "inputCountSuffix": "inputs",
                    "supportedDevices": "Built-in / DJI / Insta360 / capture cards / network cameras",
                    "calibrationTitle": "Personal Gesture Calibration", "calibrationHint": "After starting, face the camera and perform the action. The system advances after a good sample.",
                    "startAutoSample": "Start Auto Sample", "finish": "Finish", "currentHandShape": "Current hand",
                    "projectTitle": "Project", "projectLocation": "Save Location", "projectPending": "No recording project yet",
                    "openProject": "Open Project", "revealProject": "Show in Finder", "previewProgram": "Preview Program",
                    "previewUnavailable": "Program export not ready", "rehearsalPurpose": "Tests playback, slide control, and gestures only. No recording or project is saved.",
                    "autoDirector": "Auto Director", "autoDirectorStage": "Talk template: full body / close-up / PPT PiP / PPT full screen",
                    "autoDirectorTraining": "Course template: close-up PiP / PPT full screen / speaker close-up",
                    "programExport": "Program Export", "rawTracks": "Raw Tracks",
                    "stagePresentation": "Formal Talk", "trainingCourse": "Training Course",
                    "importProject": "Import Project", "exportProject": "Export Project", "exportVideo": "Export Video",
                    "exportSettings": "Export Settings", "resolution": "Resolution", "frameRate": "Frame Rate",
                    "quality": "Quality", "codec": "Codec", "export": "Export", "cancel": "Cancel",
                    "openFile": "Open File", "screenPermBtn": "Screen Recording",
                    "screenCaptureSource": "Capture Source", "sourcePresentationWindow": "Presentation Window (Auto)",
                    "sourceEntireDisplay": "Entire Display", "chooseWindows": "Choose Windows...",
                    "chooseWindowsHint": "Select one or more active windows", "useSelectedWindows": "Use Selected Windows",
                    "useSelectedSource": "Use Selected Source",
                    "selectedDisplay": "Selected Display", "selectedOneWindow": "1 window selected", "selectedWindowsPrefix": "Selected windows",
                    "screenSourcePending": "Scan to read recordable displays and windows",
                    "noScreenSources": "No capture sources found",
                    "noScreenSourcesHint": "Screen Recording permission is not active for this build. Request access first; if it remains empty, reopen System Settings.",
                    "requestScreenCaptureAccess": "Request Access", "openScreenCaptureSettings": "System Settings",
                    "thumbnailView": "Thumbnails", "listView": "List", "thumbnailLoading": "Loading preview",
                    "pipControls": "PiP", "pipSize": "Size",
                    "pipShapeRounded": "Rectangle", "pipShapeSquare": "Square", "pipShapeCircle": "Circle",
                    "modeScreenOnly": "Screen Only",
                    "modeSpeakerOnly": "Speaker Only", "screenMainPipLayout": "PPT Main + Speaker PiP",
                    "speakerMainPipLayout": "Speaker Main + PPT PiP", "screenOnlyLayout": "PPT/Screen Full",
                    "speakerOnlyLayout": "Speaker Full", "layoutSpeakerFullBody": "Full Body",
                    "layoutMeaning": "Composition", "compositionScreenOnly": "Record and export only the PPT/screen feed",
                    "compositionSpeakerOnly": "Record and export only the speaker feed",
                    "compositionScreenMain": "Use PPT/screen as main view with speaker PiP",
                    "compositionSpeakerMain": "Use speaker as main view with PPT/screen PiP",
                    "compositionSideBySide": "Align PPT/screen and speaker side by side",
                    "timelineTitle": "Recording Timeline", "timelinePending": "Tracks appear after recording starts",
                    "timelineRecording": "Writing raw tracks", "trackSlides": "PPT/Screen",
                    "trackSpeaker": "Speaker", "trackMic": "Audio", "trackProgram": "Program",
                    "trackWriting": "Writing", "trackStarting": "Starting"
                ]
            )
        }
    }
}

private extension AppCopy {
    var runtimeExactTranslations: [String: String] {
        switch language {
        case .zhHans:
            return [:]
        case .zhHant:
            return [
                "未连接": "未連接",
                "自动选择最佳输入": "自動選擇最佳輸入",
                "优先外接跟踪相机，其次内置摄像头": "優先外接追蹤攝像頭，其次內建攝像頭",
                "外接/UVC 输入": "外接/UVC 輸入",
                "Mac 内置摄像头": "Mac 內建攝像頭",
                "连续互通摄像头": "接續互通攝像頭",
                "桌面视角摄像头": "桌面視角攝像頭",
                "系统视频输入": "系統視訊輸入",
                "尚未扫描": "尚未掃描",
                "未检测": "未偵測",
                "未校准": "未校準",
                "先把手放到中央热区": "先把手放到中央熱區",
                "待命中": "待命中",
                "Vision 增强版": "Vision 增強版",
                "热区待进入": "熱區待進入",
                "空闲": "空閒",
                "未开启": "未開啟",
                "寻找手势": "尋找手勢",
                "正在跟踪": "正在追蹤",
                "识别异常": "識別異常",
                "未知": "未知",
                "自然手": "自然手",
                "开掌": "開掌",
                "揪取": "揪取",
                "握拳": "握拳",
                "指枪": "指槍",
                "剑指": "劍指",
                "八字": "八字",
                "未启动": "未啟動",
                "正在连接": "正在連接",
                "画面已接入": "畫面已接入",
                "缺少摄像头权限": "缺少攝像頭權限",
                "未发现摄像头": "未發現攝像頭",
                "连接失败": "連接失敗",
                "系统未返回任何视频输入": "系統未返回任何視訊輸入",
                "未找到摄像头": "未找到攝像頭",
                "需要摄像头权限": "需要攝像頭權限",
                "需要屏幕录制权限": "需要螢幕錄製權限",
                "未开始采样": "尚未開始採樣",
                "热区外": "熱區外",
                "请把手移动到画面中央的激活框内": "請把手移動到畫面中央的啟用框內",
                "校准中，请按提示稳定完成动作": "校準中，請按提示穩定完成動作",
                "校准采集中": "校準採集中",
                "热区已进入": "已進入熱區",
                "先张开手掌停留，再执行动作": "先張開手掌停留，再執行動作",
                "翻页模式": "翻頁模式",
                "缩放模式": "縮放模式",
                "双手枪指或八字缩放中，翻页识别已锁定": "雙手指槍或八字縮放中，翻頁識別已鎖定",
                "已进入双手缩放模式，保持枪指或八字再继续放缩": "已進入雙手縮放模式，保持指槍或八字再繼續縮放",
                "单手揪取缩小，伸展开来放大；抓握移动可拖拽": "單手揪取縮小，伸展開來放大；抓握移動可拖拽",
                "检测到双手缩放，已优先处理缩放": "偵測到雙手縮放，已優先處理縮放",
                "检测到单手动作：先张开手掌停留解锁后再用单手缩放/拖拽": "偵測到單手動作：先張開手掌停留解鎖後再用單手縮放/拖拽",
                "单手翻页只在明确剑指时生效": "單手翻頁只在明確劍指時生效",
                "动作已触发，请等待冷却结束": "動作已觸發，請等待冷卻結束",
                "缩放中": "縮放中",
                "单手开合缩放：握拳放大，张开缩小": "單手開合縮放：握拳放大，張開縮小",
                "已固定缩放位置": "已固定縮放位置",
                "握拳抓取移动：移动手来调整缩放中心": "握拳抓取移動：移動手來調整縮放中心",
                "已解锁，请快速完成翻页或缩放动作": "已解鎖，請快速完成翻頁或縮放動作",
                "未检测到手，请将手抬到镜头前": "未偵測到手，請將手抬到鏡頭前",
                "MediaPipe 当前未稳定检出手，已临时切换到 Vision 兜底": "MediaPipe 目前未穩定偵測到手，已臨時切換到 Vision 備援",
                "个人手势样本已停用，当前只使用实时识别": "個人手勢樣本已停用，目前只使用即時識別",
                "已停用旧个人手势样本，当前只使用实时识别": "已停用舊個人手勢樣本，目前只使用即時識別",
                "左挥下一页": "左揮下一頁",
                "右挥上一页": "右揮上一頁",
                "双手分开放大": "雙手分開放大",
                "双手合拢缩小": "雙手合攏縮小",
                "开始播放": "開始播放",
                "退出播放": "退出播放",
                "开始/停止录制": "開始/停止錄製",
                "开关标注": "開關標註",
                "绘制标注": "繪製標註",
                "清除标注": "清除標註",
                "先在中央热区张开手掌停留": "先在中央熱區張開手掌停留",
                "手势已解锁，请在短时间内执行动作": "手勢已解鎖，請在短時間內執行動作",
                "冷却中，忽略动作": "冷卻中，忽略動作",
                "未解锁，忽略动作": "未解鎖，忽略動作",
                "动作已接收，进入冷却期": "動作已接收，進入冷卻期",
                "尚未触发": "尚未觸發",
                "未发送": "未傳送",
                "等待命令": "等待命令",
                "测试演示页已打开": "測試簡報頁已開啟",
                "本地测试页桥接": "本地測試頁橋接",
                "测试演示页打开失败": "測試簡報頁開啟失敗",
                "快速校准已启用": "快速校準已啟用",
                "手势识别": "手勢識別",
                "缩放已尝试发送": "已嘗試傳送縮放",
                "移动视图": "移動畫面",
                "移动已尝试发送": "已嘗試傳送移動",
                "3 秒后测试下一页：已开始倒计时": "3 秒後測試下一頁：已開始倒數",
                "倒计时": "倒數",
                "等待 3 秒后发送下一页命令": "等待 3 秒後傳送下一頁命令",
                "彩排已开始": "彩排已開始",
                "彩排已结束": "彩排已結束",
                "内部状态": "內部狀態",
                "未实现": "未實作",
                "HTML 直连": "HTML 直連",
                "Chrome HTML 直连": "Chrome HTML 直連",
                "Chrome 自动化权限": "Chrome 自動化權限",
                "通用键盘": "通用鍵盤",
                "目标进程键盘": "目標行程鍵盤",
                "系统键盘兜底": "系統鍵盤備援",
                "Chrome 自动化已授权": "Chrome 自動化已授權",
                "Chrome 已授权，但没有打开窗口": "Chrome 已授權，但沒有開啟視窗",
                "已发送": "已傳送",
                "下一页": "下一頁",
                "上一页": "上一頁",
                "放大演示": "放大演示",
                "缩小演示": "縮小演示",
                "切换录制": "切換錄製",
                "无动作": "無動作",
                "键盘事件": "鍵盤事件",
                "辅助控制": "輔助控制",
                "HTML 桥接": "HTML 橋接",
                "应用浮层": "應用浮層",
                "采样不足，请保持手在画面中并重做这次动作": "採樣不足，請保持手在畫面中並重做這次動作",
                "个人手势校准完成，后续识别会优先使用你的动作模板": "個人手勢校準完成，後續識別會優先使用你的動作模板",
                "做你的‘下一页’左挥手势": "做你的「下一頁」左揮手勢",
                "做你的‘上一页’右挥手势": "做你的「上一頁」右揮手勢",
                "双手八字分开，作为放大": "雙手八字分開，作為放大",
                "双手八字合拢，作为缩小": "雙手八字合攏，作為縮小"
            ]
        case .en:
            return [
                "未连接": "Offline",
                "自动选择最佳输入": "Auto-select best input",
                "优先外接跟踪相机，其次内置摄像头": "Prefer external tracking camera, then built-in camera",
                "外接/UVC 输入": "External/UVC input",
                "Mac 内置摄像头": "Mac built-in camera",
                "连续互通摄像头": "Continuity camera",
                "桌面视角摄像头": "Desk View camera",
                "系统视频输入": "System video input",
                "尚未扫描": "Not scanned",
                "未检测": "Not detected",
                "未校准": "Not calibrated",
                "先把手放到中央热区": "Move your hand into the center zone",
                "待命中": "Standing by",
                "Vision 增强版": "Vision Enhanced",
                "热区待进入": "Waiting for zone",
                "空闲": "Idle",
                "未开启": "Off",
                "寻找手势": "Finding hand",
                "正在跟踪": "Tracking",
                "识别异常": "Recognition error",
                "未知": "Unknown",
                "自然手": "Natural",
                "开掌": "Open palm",
                "揪取": "Pinch",
                "握拳": "Fist",
                "指枪": "Finger gun",
                "剑指": "Sword",
                "八字": "L shape",
                "未启动": "Not started",
                "正在连接": "Connecting",
                "画面已接入": "Video connected",
                "缺少摄像头权限": "Camera permission needed",
                "未发现摄像头": "No camera found",
                "连接失败": "Connection failed",
                "系统未返回任何视频输入": "No video inputs returned by system",
                "未找到摄像头": "No camera found",
                "需要摄像头权限": "Camera permission needed",
                "需要屏幕录制权限": "Screen recording permission needed",
                "未开始采样": "Sampling has not started",
                "热区外": "Outside zone",
                "请把手移动到画面中央的激活框内": "Move your hand into the center activation frame",
                "校准中，请按提示稳定完成动作": "Calibrating. Hold the prompted motion steadily.",
                "校准采集中": "Capturing calibration",
                "热区已进入": "Inside zone",
                "先张开手掌停留，再执行动作": "Open your palm briefly, then perform an action",
                "翻页模式": "Page mode",
                "缩放模式": "Zoom mode",
                "双手枪指或八字缩放中，翻页识别已锁定": "Two-hand finger-gun or L-shape zoom active. Page swipes are locked.",
                "已进入双手缩放模式，保持枪指或八字再继续放缩": "Two-hand zoom mode. Keep finger-gun or L-shape poses to continue.",
                "单手揪取缩小，伸展开来放大；抓握移动可拖拽": "One-hand pinch closes to zoom out, opens to zoom in; grab and move to pan",
                "检测到双手缩放，已优先处理缩放": "Two-hand zoom detected and prioritized",
                "检测到单手动作：先张开手掌停留解锁后再用单手缩放/拖拽": "One-hand motion detected. Open palm to unlock before zoom/pan.",
                "单手翻页只在明确剑指时生效": "One-hand page turns need a clear sword pose",
                "动作已触发，请等待冷却结束": "Action triggered. Wait for cooldown.",
                "缩放中": "Zooming",
                "单手开合缩放：握拳放大，张开缩小": "One-hand zoom: fist in, open out",
                "已固定缩放位置": "Zoom position locked",
                "握拳抓取移动：移动手来调整缩放中心": "Hold fist and move your hand to pan",
                "已解锁，请快速完成翻页或缩放动作": "Unlocked. Complete a page or zoom action quickly.",
                "未检测到手，请将手抬到镜头前": "No hand detected. Raise your hand into the camera.",
                "MediaPipe 当前未稳定检出手，已临时切换到 Vision 兜底": "MediaPipe is missing hands; temporarily falling back to Vision",
                "个人手势样本已停用，当前只使用实时识别": "Personal gesture samples are disabled; using live recognition only",
                "已停用旧个人手势样本，当前只使用实时识别": "Old personal gesture samples disabled; using live recognition only",
                "左挥下一页": "Swipe left for next",
                "右挥上一页": "Swipe right for previous",
                "双手分开放大": "Hands apart to zoom in",
                "双手合拢缩小": "Hands together to zoom out",
                "开始播放": "Start presentation",
                "退出播放": "Exit presentation",
                "开始/停止录制": "Start/stop recording",
                "开关标注": "Toggle annotation",
                "绘制标注": "Draw annotation",
                "清除标注": "Clear annotations",
                "先在中央热区张开手掌停留": "Open palm in the center zone to unlock",
                "手势已解锁，请在短时间内执行动作": "Gesture unlocked. Perform an action soon.",
                "冷却中，忽略动作": "Cooling down. Action ignored.",
                "未解锁，忽略动作": "Not unlocked. Action ignored.",
                "动作已接收，进入冷却期": "Action accepted. Cooling down.",
                "尚未触发": "No action yet",
                "未发送": "Not sent",
                "等待命令": "Waiting for command",
                "测试演示页已打开": "Test deck opened",
                "本地测试页桥接": "Local test bridge",
                "测试演示页打开失败": "Failed to open test deck",
                "快速校准已启用": "Quick calibration enabled",
                "手势识别": "Gesture recognition",
                "缩放已尝试发送": "Zoom send attempted",
                "移动视图": "Pan view",
                "移动已尝试发送": "Pan send attempted",
                "3 秒后测试下一页：已开始倒计时": "Testing next slide in 3 seconds",
                "倒计时": "Countdown",
                "等待 3 秒后发送下一页命令": "Waiting 3 seconds before sending next",
                "彩排已开始": "Rehearsal started",
                "彩排已结束": "Rehearsal ended",
                "内部状态": "Internal state",
                "未实现": "Not implemented",
                "HTML 直连": "HTML direct",
                "Chrome HTML 直连": "Chrome HTML direct",
                "Chrome 自动化权限": "Chrome automation permission",
                "通用键盘": "Generic keyboard",
                "目标进程键盘": "Target-process keyboard",
                "系统键盘兜底": "System keyboard fallback",
                "Chrome 自动化已授权": "Chrome automation granted",
                "Chrome 已授权，但没有打开窗口": "Chrome is authorized, but no window is open",
                "已发送": "Sent",
                "下一页": "Next slide",
                "上一页": "Previous slide",
                "放大演示": "Zoom in",
                "缩小演示": "Zoom out",
                "切换录制": "Toggle recording",
                "无动作": "No action",
                "键盘事件": "Keyboard event",
                "辅助控制": "Accessibility control",
                "HTML 桥接": "HTML bridge",
                "应用浮层": "App overlay",
                "采样不足，请保持手在画面中并重做这次动作": "Not enough samples. Keep your hand in frame and redo this action.",
                "个人手势校准完成，后续识别会优先使用你的动作模板": "Personal gesture calibration complete. Your motion templates now have priority.",
                "做你的‘下一页’左挥手势": "Perform your next-slide left swipe",
                "做你的‘上一页’右挥手势": "Perform your previous-slide right swipe",
                "双手八字分开，作为放大": "Spread both L-shape hands to zoom in",
                "双手八字合拢，作为缩小": "Bring both L-shape hands together to zoom out"
            ]
        }
    }

    var runtimePhraseTranslations: [String: String] {
        switch language {
        case .zhHans:
            return [:]
        case .zhHant:
            return [
                "已解锁，可在": "已解鎖，可在",
                "冷却中，": "冷卻中，",
                "后可再次触发": "後可再次觸發",
                "第 ": "第 ",
                " 次：请做动作": " 次：請做動作",
                " 次采样不足": " 次採樣不足",
                " 次已保存": " 次已儲存",
                " 次：采集中 ": " 次：採集中 ",
                " 帧": " 幀",
                "保存个人手势失败：": "儲存個人手勢失敗：",
                "已加载 ": "已載入 ",
                " 个个人手势样本": " 個個人手勢樣本",
                "录制状态：开启；当前版本只标记录制流程，尚未写出视频文件": "錄製狀態：開啟；目前版本只標記錄製流程，尚未寫出影片檔",
                "录制状态：关闭；当前版本未生成视频文件": "錄製狀態：關閉；目前版本未產生影片檔",
                "测试页地址：": "測試頁地址：",
                "缩放到 ": "縮放到 ",
                " 已发送到 ": " 已傳送到 ",
                "视图移动已发送到 ": "畫面移動已傳送到 ",
                "无法启动本地测试页桥接：": "無法啟動本地測試頁橋接：",
                " 暂无测试页命令": " 暫無測試頁命令",
                " 暂无 HTML 测试页命令": " 暫無 HTML 測試頁命令",
                " 暂未接入当前目标": " 暫未接入目前目標",
                "无法创建 AppleScript": "無法建立 AppleScript",
                "需要允许“灵演”控制 Google Chrome；请在弹窗点允许，或到 系统设置 > 隐私与安全性 > 自动化 中打开。原始错误：": "需要允許「靈演」控制 Google Chrome；請在彈窗點允許，或到 系統設定 > 隱私權與安全性 > 自動化 中開啟。原始錯誤：",
                " 已发送：": " 已傳送：",
                "无法创建键盘事件": "無法建立鍵盤事件",
                "已发送到 ": "已傳送到 ",
                "已发送到系统事件队列": "已傳送到系統事件佇列",
                "（HTML 失败后兜底）": "（HTML 失敗後備援）",
                "；HTML 直连未生效：": "；HTML 直連未生效：",
                "已尝试发送": "已嘗試傳送"
            ]
        case .en:
            return [
                "已解锁，可在": "Unlocked. Act within",
                "冷却中，": "Cooling down, ",
                "后可再次触发": "before next action",
                "第 ": "Sample ",
                " 次：请做动作": ": perform the action",
                " 次采样不足": ": not enough samples",
                " 次已保存": ": saved",
                " 次：采集中 ": ": capturing ",
                " 帧": " frames",
                "保存个人手势失败：": "Failed to save personal gestures: ",
                "已加载 ": "Loaded ",
                " 个个人手势样本": " personal gesture samples",
                "录制状态：开启；当前版本只标记录制流程，尚未写出视频文件": "Recording state: on. This version marks the flow but does not write a video file.",
                "录制状态：关闭；当前版本未生成视频文件": "Recording state: off. This version has not generated a video file.",
                "测试页地址：": "Test page: ",
                "缩放到 ": "Zoom to ",
                " 已发送到 ": " sent to ",
                "视图移动已发送到 ": "Pan sent to ",
                "无法启动本地测试页桥接：": "Could not start local test bridge: ",
                " 暂无测试页命令": " has no test-page command",
                " 暂无 HTML 测试页命令": " has no HTML test-page command",
                " 暂未接入当前目标": " is not wired for the current target",
                "无法创建 AppleScript": "Could not create AppleScript",
                "需要允许“灵演”控制 Google Chrome；请在弹窗点允许，或到 系统设置 > 隐私与安全性 > 自动化 中打开。原始错误：": "Allow WonderShow to control Google Chrome. Click Allow in the prompt, or enable it in System Settings > Privacy & Security > Automation. Original error: ",
                " 已发送：": " sent: ",
                "无法创建键盘事件": "Could not create keyboard event",
                "已发送到 ": "Sent to ",
                "已发送到系统事件队列": "Sent to the system event queue",
                "（HTML 失败后兜底）": " (HTML fallback)",
                "；HTML 直连未生效：": "; HTML direct failed: ",
                "已尝试发送": " send attempted"
            ]
        }
    }
}
