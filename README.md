# WonderShow 灵演

[中文](docs/COMMUNITY_EDITION.zh-Hans.md) | [繁體中文](docs/COMMUNITY_EDITION.zh-Hant.md) | [English](docs/COMMUNITY_EDITION.en.md)

灵演 WonderShow 是一款 macOS 演示录制助手，支持多摄像头输入、讲者画中画和 `.wondershow` 项目格式。

## 社区版 App

灵演社区版是面向创作者、讲师和开发者的**免费可用版本**。它保留了核心录制链路，让你可以在 macOS 上录制演示窗口、摄像头讲者画面和麦克风声音，并生成可预览、可导出的视频项目。

### 功能一览

- **摄像头接入**：支持 Mac 内置摄像头、UVC 摄像头和外接采集设备
- **屏幕和窗口录制**：选择演示窗口、整个屏幕或手动选择窗口
- **讲者画中画**：PPT/屏幕主画面 + 讲者画中画、讲者主画面、左右分屏、只录屏、只录讲者等多种布局
- **音频录制**：跟随 macOS 当前麦克风输入，生成独立原始音频轨
- **项目化保存**：生成 `.wondershow` 项目结构，保留原始轨、合成轨、时间轴和导出信息
- **合成预览与导出**：录制后预览合成视频，导出高清 MP4
- **多语言界面**：内置简体中文、繁体中文和英文

### 下载

前往 [Releases](https://github.com/aokest/WonderShow/releases) 下载最新社区版 App：

| 文件 | 说明 |
|------|------|
| `wondershow-community-1.0.0-macos.zip` | 社区版 macOS App（双击运行） |
| `wondershow-core-1.0.0.zip` | 开源 Core 包（Swift Package） |

### 使用说明

1. 解压并打开 `灵演社区版.app`
2. 在 macOS 系统设置中允许摄像头、麦克风和屏幕录制权限
3. 在右侧选择输入设备和音频输入
4. 选择录制源和布局模式
5. 点击「开始录制」，结束后预览合成并导出视频

> 专业版仍在开发测试中。希望在不久的将来，专业版和配套工具可以和大家见面。

## 开源 Core 包

本仓库同时包含 **WonderShow Core** — 项目的开源生态层，包含公共 Swift 模型、`.wondershow` 项目格式定义、MediaPipe sidecar 协议和插件 API。

### 什么是开放的

- `.wondershow` 项目清单数据模型
- 录制源、时间轴、布局、导出和讲者效果配置 Schema
- 本地 MediaPipe sidecar 请求和响应协议
- 面向插件的 Swift 协议（效果目录、输入源、导出集成）
- 示例项目和插件骨架

### 构建与测试

```bash
swift test
```

## 项目结构

```
Sources/WonderShowCore/
  RecordingModel.swift      项目和导出 Schema
  MediaPipeProtocol.swift   本地 sidecar 通信协议
  PluginAPI.swift           插件扩展合约
examples/
  sample-project/           最小 .wondershow 清单
  sidecar-response.json     MediaPipe 响应示例
  PluginSkeleton.swift      插件骨架示例
docs/
  COMMUNITY_EDITION.*.md    社区版说明（三语）
```

## 许可证

WonderShow Core 使用 [Apache-2.0](LICENSE) 许可证。

## 支持作者

如果灵演社区版对你有帮助，可以在 App 的「关于」里支持我一瓶可乐，或一些 token。谢谢你愿意试用和反馈。
