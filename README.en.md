<div align="center">

# 🎬 WonderShow

**Multi-Camera Presentation Recorder — Make Presentations Professional, Make Expressions Outstanding**

[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2013+-lightgrey.svg)](https://github.com/aokest/WonderShow)
[![Release](https://img.shields.io/badge/release-v1.0.11-green.svg)](https://github.com/aokest/WonderShow/releases/tag/v1.0.11)
[![Swift](https://img.shields.io/badge/swift-5.9+-orange.svg)](https://swift.org)

[简体中文](README_zh.md) | **English** | [繁體中文](README.zh-Hant.md)

</div>

---

WonderShow (灵演) is a native macOS multi-camera presentation recording tool. It enables creators, educators, and developers to quickly record HD presentation videos with presenter picture-in-picture, supporting multi-camera switching, real-time layout adjustment, and one-click export. **Runs completely offline — no network required.**

> 💡 WonderShow started as a live presentation assistant. During development, we discovered a strong need in training and knowledge-sharing scenarios: recording the presenter's camera, screen content, and audio together — then composing them into a polished video. So v1.0 became a powerful screen recorder that produces finished videos the moment you stop recording.

## ✨ Key Features

### 🎥 Multi-Camera Input
Automatically scans all available camera devices (built-in Mac camera, DJI Osmo Pocket 3, Insta360, UVC capture cards, network cameras) and selects the best one by default. Switch between cameras like a live director — no interruption needed.

### 🖥️ Live Source Switching
Pre-assign window slots (`⌘1`-`⌘6`), then switch between any active window during recording. From PPT to browser, from documents to code editor — seamless switching with zero post-production burden.

### 👤 Flexible Layouts
Switch layouts anytime (even during recording):
- Screen main + Presenter PiP
- Presenter main + Screen PiP
- Side-by-side
- Screen-only / Speaker-only

PiP supports adjustable size, position swap, crop shape (rectangle/circle/square), and free drag anywhere on screen.

### 📐 Multiple Canvas Ratios
Quickly switch between landscape, portrait, and square aspect ratios to match different platforms (Bilibili, YouTube, WeChat Channels). Switchable during recording.

### 🎙️ High-Fidelity Audio
Sample-level microphone recording (AVCaptureAudioDataOutput + AVAssetWriter), AAC encoding, independent audio track, startup transient noise filtering.

### 📦 Project-Based Workflow
One-click synthesis produces a polished final video. Simultaneously preserves three independent tracks:
- 📹 Camera raw track
- 🖥️ Screen raw track
- 🎙️ Audio raw track

All tracks are timeline-synchronized — drag directly into your favorite editor. Supports original format and **4K export**.

### 🌐 Trilingual UI
Built-in Simplified Chinese, Traditional Chinese, and English. Switch at runtime.

## 📸 Use Cases

- 🎓 Record courses, tutorials, knowledge sharing, product demos, and online lectures
- 📊 Capture narrated Keynote, PowerPoint, WPS, PDF, or browser-based presentations
- 🎬 Prepare presenter PiP content for Bilibili, YouTube, WeChat Channels
- ✅ Verify camera, microphone, screen-recording permissions before real recording
- 🔧 Build project inspectors, converters, and archiving tools using the `.wondershow` format

## 🚀 Quick Start

### Download

Get the latest version from [Releases](https://github.com/aokest/WonderShow/releases/tag/v1.0.11):

| File | Description |
|------|-------------|
| `wondershow-community-1.0.11-*-macos.zip` | Community Edition macOS App (5.6MB) |
| `wondershow-core-1.0.11-*.zip` | Open-source Core Package (Swift Package) |

### Steps

1. Unzip and open `灵演社区版.app` (WonderShow Community)
2. Allow **Camera**, **Microphone**, and **Screen Recording** permissions in macOS System Settings
3. Select input device and audio input from the right panel
4. Choose recording source: presentation window, full display, or manually selected windows
5. Select recording mode and layout (e.g., "Camera + Screen", "Screen Main + Speaker PiP")
6. Click "Start Recording" — wait for program composition after stopping
7. Use "Preview Program" to check the result, then export or keep the project

### Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌥⌘R` | Start/Stop recording |
| `⌘1` - `⌘6` | Switch recording source |

## 🏗️ Architecture

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

- **WonderShow Core** (open-source Swift Package): `.wondershow` project format, MediaPipe sidecar protocol, plugin APIs
- **WonderShow App** (Community Edition): Full recording workflow, UI, video composition engine

## 📂 Project Structure

```
WonderShow/
├── Sources/
│   ├── WonderShow/              # Core library (recording models, project format)
│   └── WonderShowApp/           # macOS App (Dashboard, recording, composition)
├── Tests/                       # Unit tests (244+ passing)
├── open-source/
│   └── wondershow-core/         # Open-source Core Swift Package
├── scripts/                     # Build and packaging scripts
├── docs/                        # Architecture docs and roadmap
└── releases/                    # Release files and checksums
```

## 🧪 Testing

```bash
rtk swift test --disable-sandbox
rtk swift test --package-path open-source/wondershow-core
rtk bash scripts/build-app.sh
rtk bash scripts/package-community-app.sh
```

## 🤝 Community vs Pro

| Feature | Community (this repo) | Pro (in development) |
|---------|:---:|:---:|
| Multi-camera input & switching | ✅ | ✅ |
| Live source switching | ✅ | ✅ |
| Flexible layouts & PiP | ✅ | ✅ |
| Multiple canvas ratios | ✅ | ✅ |
| Preview & export (incl. 4K) | ✅ | ✅ |
| Trilingual UI | ✅ | ✅ |
| .wondershow project format | ✅ | ✅ |

| Presenter video effects | — | ✅ |
| Live director monitor | — | ✅ |

## 💡 Support the Author

This project was built from scratch with AI assistance, taking 80+ hours. If WonderShow Community helps you, scan the QR code in the About panel to buy me a coffee ☕

## 📄 License

[Apache License 2.0](LICENSE)
