# 架构总览

## 总体分层

```text
SwiftUI Dashboard
  -> CameraPreviewService
     -> AVFoundation 采集
     -> Vision 手部检测 / MediaPipe sidecar
     -> Gesture Gate / Session
  -> PresentationCommandController
     -> 键盘事件 / HTML Bridge / 内部状态
  -> PresenterDirector 核心策略
```

## 当前实现原则

- UI 层只负责展示状态和触发动作
- 手势识别拆成“检测”“识别”“稳态控制”三段
- 演示命令投递与手势识别解耦
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

## 后续规划

- 保持 `PresenterDirector` 作为纯策略层
- 把 MediaPipe sidecar 作为下一阶段的可插拔输入源
- 建立真实录像回放测试集，作为识别回归基线

## 参考

- `docs/architecture.md`
- `docs/recording-studio-roadmap.md`
