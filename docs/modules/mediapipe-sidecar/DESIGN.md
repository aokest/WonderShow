# MediaPipe Sidecar 设计说明

## 目标

- 用官方 MediaPipe Hand Landmarker + Gesture Recognizer 替换当前原型级 Vision 规则链
- 保持 SwiftUI 主程序职责清晰，不把复杂推理依赖混进 Swift Package
- 本地完成推理，不把摄像头图像发到外网

## 设计原则

- Swift 负责采集、UI、命令路由
- Python sidecar 负责手部检测、21 点 landmarks、手势分类、后续时序模型
- 双方通过本机 HTTP/JSON 通信
- 旧 Vision 路径暂时保留为回退方案

## 当前阶段

- 已定义统一数据结构
- 已创建 sidecar 服务骨架
- 已准备安装脚本和模型目录
- 已把 `CameraPreviewService` 接到 sidecar 实时推理链路
- sidecar 在线时优先走 MediaPipe，离线时回退到 Vision
- sidecar 现在以 `HandLandmarker` 作为双手与 21 点的权威来源，以 `GestureRecognizer` 作为分类标签来源

## 下一步

- Swift 采样帧发送到 `/infer`
- 使用 MediaPipe 返回的 21 点 landmarks 驱动现有识别窗口
- 再逐步把时序识别从锚点轨迹升级为 21 点时序特征

## 当前折中实现

- sidecar 已返回完整 `21` 点 landmarks
- Swift 侧会将 MediaPipe 顶左原点坐标转换到应用内底左原点坐标，保证热区、叠加层和识别状态机使用同一坐标系
- Swift 主链路目前仍使用“每只手一个代表锚点”的轻量识别模型，以便兼容既有状态机与测试
- 但代表锚点已不再是固定单点：
  - `Pointing_Up` 使用指尖与食指根部的加权锚点
  - `Victory` 使用拇指/食指尖中点再融合食指根部
  - 其他手型使用掌心多点质心
- 这样可以在不重写整套识别器的前提下，先降低单点抖动导致的翻页迟滞与缩放发飘

## v0.7 衔接方式

- Swift 侧新增 `MediaPipeHandGeometry`，直接消费 sidecar 返回的 21 点 landmarks
- `handPoints()` 继续保留给兼容层和旧测试使用，避免破坏 v0.6.0 基线
- 真正的新链路只在两处直接依赖 21 点几何：
  - 双手缩放姿态判定
  - 连续缩放的 palm-size 归一化距离
- 因此 sidecar 现在同时服务两条链路：
  - 兼容链：`landmarks -> HandPoint`
  - v0.7 链：`landmarks -> MediaPipeHandGeometry -> GestureModeCoordinator`
