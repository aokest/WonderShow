<div align="center">

# 🎬 灵演 WonderShow

**多机位演示录制助手 — 让演示更专业，让表达更出色**

[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2013+-lightgrey.svg)](https://github.com/aokest/WonderShow)
[![Release](https://img.shields.io/badge/release-v1.0.11-green.svg)](https://github.com/aokest/WonderShow/releases/tag/v1.0.11)
[![Swift](https://img.shields.io/badge/swift-5.9+-orange.svg)](https://swift.org)

[English](README.en.md) | [繁體中文](README.zh-Hant.md) | **简体中文**

</div>

---

灵演（WonderShow）是一款 macOS 原生多机位演示录制工具。它让创作者、讲师和开发者能快速录制带讲者画中画的高清演示视频，支持多摄像头切换、实时布局调整和一键导出。**完全离线运行，不依赖任何网络环境。**

> 💡 灵演最初是一个演讲辅助工具，后来发现培训和知识分享场景中，讲者画面、PPT 和声音的录制与合成需求非常强烈。于是 1.0 版本先做成了一个强大的录屏软件——演讲结束即生成成品，无需大量后期。

[![项目演示视频](https://img.youtube.com/vi/JL7-oVyqE_s/0.jpg)](https://www.youtube.com/watch?v=JL7-oVyqE_s)


## ✨ 核心功能

### 🎥 多机位接入
自动扫描所有可用摄像设备（内置摄像头、DJI Osmo Pocket 3、Insta360、UVC 采集卡、网络摄像头），自动选取最佳设备。录制过程中可像导播一样无缝切换不同机位，无需中断。

### 🖥️ 录制中多源切换
提前给不同活动窗口编号（`⌘1`-`⌘6`），录制过程中一键切换演示窗口。从 PPT 切到浏览器、从文档切到代码编辑器——全程不中断录制，后期零负担。

### 👤 灵活布局切换
支持多种布局随时切换（录制中也可切换）：
- 屏幕主画面 + 讲者画中画
- 讲者主画面 + 屏幕画中画
- 纯屏幕录制 / 纯讲者录制

画中画支持调整大小、对调位置、切换裁切形状（长方形/圆形/方形），窗格可拖拽到屏幕任意位置。

### 📐 多画布比例
快速切换横屏、竖屏、方屏等不同画面比例，适配 B 站、YouTube、视频号等不同平台的播放需求。录制过程中也可随时切换。

### 🎙️ 高保真音频
采样级麦克风录制（AVCaptureAudioDataOutput + AVAssetWriter），支持 AAC 编码，独立音频轨，跳过启动瞬态噪音。

### 📦 项目化保存与导出
录制结束一键合成终版视频（高质量初稿，无需大量后期）。同时保存三个独立轨道：
- 📹 摄像头原始轨
- 🖥️ 录屏原始轨
- 🎙️ 音频原始轨

三个轨道按时间轴同步，可直接拖入剪辑软件继续编辑。支持原始视频格式和 **4K 导出**。

### 🌐 三语界面
内置简体中文、繁体中文、英文，运行时一键切换。

## 📸 使用场景

- 🎓 录制课程、微课、知识分享、产品演示和线上讲座
- 📊 给 Keynote、PowerPoint、WPS、PDF 或网页演示录制讲解视频
- 🎬 为 B 站、YouTube、视频号等平台准备带讲者画中画的素材
- ✅ 在正式录课前验证摄像头、麦克风、屏幕录制权限和画面布局
- 🔧 开发者读取 `.wondershow` 项目格式，构建检查、转换、归档工具

## 🚀 快速开始

### 下载

从 [Releases](https://github.com/aokest/WonderShow/releases/tag/v1.0.11) 页面下载：

| 文件 | 说明 |
|------|------|
| `wondershow-community-1.0.11-*-macos.zip` | 社区版 macOS App（5.6MB） |
| `wondershow-core-1.0.11-*.zip` | 开源 Core 包（Swift Package） |

### 使用步骤

1. 解压并打开 `灵演社区版.app`
2. 在 macOS 系统设置中允许 **摄像头**、**麦克风** 和 **屏幕录制** 权限
3. 在右侧面板选择输入设备和音频输入
4. 选择录制源：演示窗口、整个屏幕或手动选择窗口
5. 选择录制模式和布局（如「摄像头 + 屏幕」「屏幕主画面 + 讲者画中画」）
6. 点击「开始录制」，结束后等待合成输出
7. 使用「预览合成」检查结果，再导出视频或保留项目文件

### 快捷键

| 快捷键 | 功能 |
|--------|------|
| `⌥⌘R` | 开始/停止录制 |
| `⌘1` - `⌘6` | 快速切换录制源 |

## 🏗️ 技术架构

```
┌─────────────────────────────────────────────┐
│              DashboardView                   │
│  ┌──────────┐  ┌──────────┐  ┌───────────┐  │
│  │ Camera   │  │ Screen   │  │ Timeline  │  │
│  │ Preview  │  │ Capture  │  │ Track     │  │
│  └────┬─────┘  └────┬─────┘  └─────┬─────┘  │
│       │              │              │         │
│  ┌────▼──────────────▼──────────────▼─────┐  │
│  │       RecordingSessionService          │  │
│  │   (Project · Manifest · Keyframes)     │  │
│  └────────────────┬───────────────────────┘  │
│                   │                          │
│  ┌────────────────▼───────────────────────┐  │
│  │        ProgramVideoRenderer            │  │
│  │   (Compose · Scale · Export MP4)       │  │
│  └────────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

- **WonderShow Core**（开源 Swift Package）：`.wondershow` 项目格式定义、MediaPipe 侧车协议、插件 API
- **WonderShow App**（社区版）：完整录制工作流、UI、视频合成引擎

## 📂 项目结构

```
WonderShow/
├── Sources/
│   ├── WonderShow/              # 核心库（录制模型、项目格式）
│   └── WonderShowApp/           # macOS App（Dashboard、录制、合成）
├── Tests/                       # 单元测试（244+ 项）
├── open-source/
│   └── wondershow-core/         # 开源 Core Swift Package
├── scripts/                     # 构建和打包脚本
├── docs/                        # 架构文档和路线图
└── releases/                    # 发布文件和校验值
```

## 🧪 测试

```bash
# 运行全部测试
rtk swift test --disable-sandbox

# 运行 Core 包测试
rtk swift test --package-path open-source/wondershow-core

# 构建 App
rtk bash scripts/build-app.sh

# 打包社区版
rtk bash scripts/package-community-app.sh
```

## 📖 开源项目适合谁

- 想了解 `.wondershow` 项目格式的开发者
- 想构建项目检查器、转换器、批处理工具的自动化开发者
- 想基于公开格式做内容归档和工作流集成的团队
- 想学习 macOS 录制产品如何拆分应用体验与开放数据格式的独立开发者


## 💡 支持作者

这个项目由 AI 辅助从零手搓，耗时 80+ 小时。如果灵演社区版对你有帮助，可以在 App 的「关于」页面扫码支持我一瓶可乐或一些 token ☕

也欢迎点赞、转发给需要的朋友！

## 📄 License

[Apache License 2.0](LICENSE)
