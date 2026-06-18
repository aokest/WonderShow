# 架构总览

## 总体分层

```text
SwiftUI Dashboard
  -> CameraPreviewService
     -> AVFoundation 采集
     -> Vision 手部检测 / MediaPipe sidecar
     -> Gesture Gate / Session
     -> CameraArchiveRecorder
  -> ScreenPreviewService
     -> ScreenCaptureKit 监视器预览
  -> ScreenArchiveRecorder
     -> ScreenCaptureKit 屏幕/窗口录制
     -> AVAssetWriter 屏幕原始轨
  -> MicrophoneArchiveRecorder
     -> AVFoundation 麦克风采集
  -> PresentationCommandController
     -> 键盘事件 / HTML Bridge / 内部状态
     -> 预览合成 / 导出调度
  -> RecordingSessionService
     -> .wondershow 项目目录
     -> project.json manifest
  -> ProgramVideoRenderer
     -> AVFoundation 合成 / 编码 / 进度
  -> PresenterDirector 核心策略
     -> RecordingPipeline / RecordingProject / Timeline 模型
```

## 当前实现原则

- UI 层只负责展示状态和触发动作
- 手势识别拆成“检测”“识别”“稳态控制”三段
- 演示命令投递与手势识别解耦
- 录制工程模型保持在 `PresenterDirector` 纯策略层，真实采集和渲染放在 `PresenterDirectorApp` 层
- 录制主链路以非破坏式项目为方向，原始轨道、时间轴 metadata 和 program 输出分离
- 底层识别引擎要可替换，便于后续接入 MediaPipe sidecar

## MediaPipe sidecar 新增分层

```text
Swift CameraPreviewService
  -> JPEG 帧编码
  -> http://127.0.0.1:18777/infer
Python MediaPipe Sidecar
  -> Gesture Recognizer
  -> 21 点 landmarks
  -> gesture categories
Swift Adapter
  -> HandPoint / GestureFrameSnapshot
  -> PresenterDirector 命令映射
```

## 本轮架构调整

- 增加手势稳态控制：
  - 中央激活热区
  - 开掌停留解锁
  - 解锁后短窗口执行手势
  - 冷却期避免连续误触
- Dashboard 改为导演台布局：
  - 大预览
  - 快速开始
  - 演示控制
  - 手势工作区
  - 高级诊断抽屉
- v0.7 手势结构重构：
  - `MediaPipeHandGeometry` 负责 21 点几何和 palm-size 归一化
  - `GestureModeCoordinator` 负责 `swipe` / `zoom` 互斥仲裁
  - `GestureRecognitionStateMachine` 统一处理 enter / exit / dwell / grace / cooldown
  - `CameraPreviewService` 先走模式仲裁，再决定进入缩放链或离散翻页链
  - `MediaPipeGestureAdapter.handPoints()` 保持兼容层语义，避免破坏 v0.6.0 基线测试
- 录制工程模型：
  - `RecordingProjectFactory` 将正式演讲和培训录屏对齐为同一个双源录制能力
  - 原始素材轨固定表达讲者摄像头与 PPT/屏幕采集，program timeline 再表达讲者全身、讲者特写、讲者画中画、PPT 全屏等视角
  - `CameraArchiveRecorder`、`ScreenArchiveRecorder`、`MicrophoneArchiveRecorder` 已接入真实摄像头、屏幕/窗口和麦克风写盘
  - `ProgramVideoRenderer` 已接入真实预览合成和导出，支持画中画 geometry/keyframes、音频合并、导出进度和输出校验
  - `ScreenPreviewService` 与 `ScreenArchiveRecorder` 使用同一组选源语义，支持录制中切换屏幕/窗口源

## 录制与合成链路

```text
User selects sources
  -> camera device / screen or window / microphone
  -> RecordingSessionService creates .wondershow project
  -> Raw tracks
       Raw/presenter-camera.mov
       Raw/slides-screen.mov
       Raw/microphone.m4a
  -> project.json
       selected sources
       duration
       layout
       PiP geometry and keyframes
  -> ProgramVideoRenderer
       preview composition
       Exports/program.mp4
       user selected export file
```

当前录制目录默认位于 `~/Movies/灵演/`。每个项目是一个 `.wondershow` 文件夹，未来时间轴编辑应继续围绕 manifest 和 raw tracks 做非破坏式操作。

## 后续规划

- 保持 `PresenterDirector` 作为纯策略层
- 把 MediaPipe sidecar 作为下一阶段的可插拔输入源
- 建立真实录像回放测试集，作为识别回归基线
- 修复监视器活动窗口抖动
- 增加讲者画面美颜、调亮和镜像翻转
- 把底部录制时间轴升级为真实轨道展示和编辑器
- 增加 macOS 菜单栏常驻入口和录制迷你工具条
- 将手势识别从静态手型升级为远距离动态动作识别

## 参考

- `docs/architecture.md`
- `docs/recording-studio-roadmap.md`
