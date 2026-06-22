<div align="center">

# 🎬 靈演 WonderShow

**多機位簡報錄製助手 — 讓簡報更專業，讓表達更出色**

[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2013+-lightgrey.svg)](https://github.com/aokest/WonderShow)
[![Release](https://img.shields.io/badge/release-v1.0.11-green.svg)](https://github.com/aokest/WonderShow/releases/tag/v1.0.11)
[![Swift](https://img.shields.io/badge/swift-5.9+-orange.svg)](https://swift.org)

[简体中文](README_zh.md) | [English](README.en.md) | **繁體中文**

</div>

---

靈演（WonderShow）是一款 macOS 原生多機位簡報錄製工具。它讓創作者、講師和開發者能快速錄製帶講者子母畫面的高清簡報影片，支援多攝影機切換、即時版面調整和一鍵匯出。**完全離線運作，不依賴任何網路環境。**

> 💡 靈演最初是一個簡報輔助工具，後來發現培訓和知識分享場景中，講者畫面、PPT 和聲音的錄製與合成需求非常強烈。於是 1.0 版本先做成了一個強大的螢幕錄製軟體——簡報結束即生成成品，無需大量後製。

## ✨ 核心功能

### 🎥 多機位接入
自動掃描所有可用攝影設備（內建攝影機、DJI Osmo Pocket 3、Insta360、UVC 擷取卡、網路攝影機），自動選取最佳設備。錄製過程中可像導播一樣無縫切換不同機位，無需中斷。

### 🖥️ 錄製中多源切換
提前給不同活動視窗編號（`⌘1`-`⌘6`），錄製過程中一鍵切換演示視窗。從 PPT 切到瀏覽器、從文件切到程式碼編輯器——全程不中斷錄製，後製零負擔。

### 👤 靈活版面切換
支援多種版面隨時切換（錄製中也可切換）：
- 螢幕主畫面 + 講者子母畫面
- 講者主畫面 + 螢幕子母畫面
- 左右分屏
- 純螢幕錄製 / 純講者錄製

子母畫面支援調整大小、對調位置、切換裁切形狀（長方形/圓形/方形），窗格可拖拽到螢幕任意位置。

### 📐 多畫布比例
快速切換橫屏、直屏、方屏等不同畫面比例，適配不同平台的播放需求。錄製過程中也可隨時切換。

### 🎙️ 高保真音訊
取樣級麥克風錄製（AVCaptureAudioDataOutput + AVAssetWriter），支援 AAC 編碼，獨立音訊軌，跳過啟動瞬態噪音。

### 📦 專案化儲存與匯出
錄製結束一鍵合成終版影片（高品質初稿，無需大量後製）。同時保存三個獨立軌道：
- 📹 攝影機原始軌
- 🖥️ 螢幕錄製原始軌
- 🎙️ 音訊原始軌

三個軌道按時間軸同步，可直接拖入剪輯軟體繼續編輯。支援原始影片格式和 **4K 匯出**。

### 🌐 多語言介面
內建簡體中文、繁體中文、英文，運行時一鍵切換。

## 📸 應用場景

- 🎓 錄製課程、微課、知識分享、產品演示和線上講座
- 📊 給 Keynote、PowerPoint、WPS、PDF 或網頁簡報錄製講解影片
- 🎬 為影片平台、YouTube、內部學習平台準備帶講者子母畫面的素材
- ✅ 在正式錄課前驗證攝影機、麥克風、螢幕錄製權限和畫面版面
- 🔧 開發者讀取 `.wondershow` 專案格式，構建檢查、轉換、歸檔工具

## 🚀 快速開始

### 下載

從 [Releases](https://github.com/aokest/WonderShow/releases/tag/v1.0.11) 頁面下載：

| 檔案 | 說明 |
|------|------|
| `wondershow-community-1.0.11-*-macos.zip` | 社群版 macOS App（5.6MB） |
| `wondershow-core-1.0.11-*.zip` | 開源 Core 包（Swift Package） |

### 使用步驟

1. 解壓並開啟 `靈演社群版.app`
2. 在 macOS 系統設定中允許**攝影機**、**麥克風**和**螢幕錄製**權限
3. 在右側面板選擇輸入設備和音訊輸入
4. 選擇錄製源：簡報視窗、整個螢幕或手動選擇視窗
5. 選擇錄製模式和版面（如「攝影機 + 螢幕」「螢幕主畫面 + 講者子母畫面」）
6. 點擊「開始錄製」，結束後等待合成輸出
7. 使用「預覽合成」檢查結果，再匯出影片或保留專案檔

### 快捷鍵

| 快捷鍵 | 功能 |
|--------|------|
| `⌥⌘R` | 開始/停止錄製 |
| `⌘1` - `⌘6` | 快速切換錄製源 |

## 📦 開源 Core 包

[WonderShow Core](open-source/wondershow-core/) 是一個開源 Swift Package，提供：

- **`.wondershow` 專案格式**：完整的錄製專案 schema 定義，支援 JSON 序列化
- **MediaPipe 側車協議**：攝影機手勢識別的通訊協議
- **插件 API**：用於構建自訂專案檢查器、轉換器和工具

```swift
import WonderShowCore

let project = try RecordingProject.load(from: projectURL)
print(project.manifest.layout)
print(project.rawTracks.count)
```

詳細文件見 [open-source/wondershow-core/README.md](open-source/wondershow-core/README.md)。

## 📂 倉庫結構

```
WonderShow/
├── open-source/
│   └── wondershow-core/         # 開源 Core Swift Package
│       ├── Sources/WonderShowCore/
│       │   ├── RecordingModel.swift      # 專案格式定義
│       │   ├── MediaPipeProtocol.swift   # 側車協議
│       │   └── PluginAPI.swift           # 插件介面
│       ├── Tests/                         # Core 包測試
│       ├── examples/                      # 範例程式碼
│       └── docs/                          # Core 文件
├── docs/                        # 架構文件和路線圖
├── releases/                    # 發布文件和校驗值
├── README.md                    # 简体中文
├── README.en.md                 # English
└── README.zh-Hant.md            # 繁體中文
```

## 🧪 測試 Core 包

```bash
git clone https://github.com/aokest/WonderShow.git
cd WonderShow
swift test --package-path open-source/wondershow-core
```

## 💡 支持作者

這個專案由 AI 輔助從零手搓，耗時 80+ 小時。如果覺得靈演社群版對你有幫助，可以在 App 的「關於」頁面掃碼支持我一瓶可樂或一些 token ☕

## 📄 License

[Apache License 2.0](LICENSE)
