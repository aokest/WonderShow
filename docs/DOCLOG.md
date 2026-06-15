# 文档变更记录

## 2026-06-15

- 新增 `docs/INDEX.md` 作为权威入口
- 新增 `docs/PRD.md`、`docs/ARCH.md`、`docs/RISK_MODEL.md`、`docs/TEST_STRATEGY.md`
- 新增 `docs/modules/dashboard/*` 模块文档
- 新增 `docs/modules/gesture-control/*` 模块文档
- 目的：支撑导演台 UI 重构与手势稳态控制改造
- 新增 `docs/modules/mediapipe-sidecar/*` 模块文档
- 新增 `sidecar/` 本地 MediaPipe 推理服务骨架与安装脚本
- 新增 `Sources/PresenterDirector/MediaPipeGesture.swift` 作为 MediaPipe 数据结构与适配层
- 更新 `scripts/setup-mediapipe-sidecar.sh`，自动下载官方 `gesture_recognizer.task`
- 更新 `CameraPreviewService`，sidecar 在线时优先使用 MediaPipe 实时推理
- 更新 `CameraPreviewService`，个人校准模板未命中时自动回退到实时识别，并支持清空旧校准
- 更新 `DashboardView`，修复深色界面中菜单/切换/次级按钮的低对比度显示问题
- 更新 `CameraPreviewService`，清空旧校准改为停用旧样本标记，不再依赖删除系统目录中的文件
- 更新 `DashboardView`，优化导演台卡片、下拉框和次级按钮的视觉层次，减少“工程感”
- 更新 `MediaPipeSidecarClient` 与 `sidecar/server.py`，提高传输图像质量并下调检手阈值，缓解 MediaPipe 空帧导致的无响应
- 更新 `CameraPreviewService`，连续空帧时自动临时回退到 Vision 兜底，恢复基础手势响应
- 更新 `scripts/build-app.sh` 与 `README.md`，修复 macOS 上因 Swift 沙箱导致的打包失败，并补充“直接打开 dist/灵演.app”的最简启动路径
- 更新 `scripts/build-app.sh`，同步 app bundle 的 `CFBundleVersion` 与 `CFBundleShortVersionString` 到 `0.5.0`，避免 Finder/系统信息仍显示旧版 `0.4.9`
- 更新 `Gesture.swift`、`CameraPreviewService.swift` 与手势测试/文档，修复“双手缩放候选过宽导致吞掉普通翻页识别”的稳定性问题
- 更新 `GestureControl.swift` 与 `CameraPreviewService.swift`，在画面中出现多只手（例如两个人）时选择热区内更靠近中心的最多两只手作为输入，避免“多人入镜即无法识别”
- 更新 `ContinuousZoomTracker`，降低缩放结束后因点位缓慢回落导致的持续缩放
- 更新 `Gesture.swift` 与 `CameraPreviewService.swift`，修复“缩放候选过严导致双手八字被识别为翻页、握拳误触翻页”的回归问题，并在双手缩放姿态下抑制翻页识别
- 更新 `wondershow-demo.html`，为 HTML 测试页缩放加入阻尼式动画与平移能力（仅测试页）
- 更新 `ContinuousZoomTracker`、`CameraPreviewService` 与测试页动画参数，降低缩放脉冲感并提升指枪翻页响应速度
- 回滚上一轮激进的“手感调优”参数：恢复 `ContinuousZoomTracker`、`StreamingGestureRecognizer` 与点位平滑的稳定参数，撤销导致翻页/缩放主链路退化的实验性阈值调整
- 基于 `gesture-regression-loop` 调试证据更新 `CameraPreviewService`：MediaPipe 连续空帧不再整体切回 Vision，避免双手缩放在短时空帧下退化成单手翻页；同步更新 `gesture-control` 规格与测试说明
- 基于 `gesture-regression-loop` 的 post-fix 日志进一步更新 `CameraPreviewService`：为稳定双手八字窗口增加“直接优先缩放”捷径，修复 `lShape,lShape` 已稳定出现但仍被候选判定挡住的问题
- 基于 `gesture-regression-loop` 的进一步证据更新 `ContinuousZoomTracker`、`CameraPreviewService` 与 `wondershow-demo.html`：为连续缩放增加单次最大步长限制、在缩放姿态期间抑制离散翻页，并将单步缩放从 15% 下调到 8%
- 进一步更新 `ContinuousZoomTracker`、`Gesture.swift`、`CameraPreviewService` 与 `wondershow-demo.html`：将“当前进入的缩放帧”纳入离散翻页抑制判断，为连续缩放增加按动作幅度分级的动态步长，并将 HTML 测试页弹簧动画改为更稳的分段缓动，减少双手八字误翻页与缩放晃动
- 继续更新 `MediaPipeGesture.swift`、`CameraPreviewService`、`Gesture.swift` 与测试页动画：下调 MediaPipe 采样间隔、提升离散翻页与连续缩放响应速度，并将 `Pointing_Up` / `Victory` 的单点锚点升级为多 landmarks 加权锚点，缓解“上一页偏弱”和“缩放不够像触屏一样跟手”的问题
- 新增 `docs/modules/dashboard/DESIGN_TOKENS.md`：固化 v0.5 导演台的视觉令牌（颜色、字体、间距、圆角、阴影、动效、组件契约、反模式清单），用于约束后续 Figma 设计与 SwiftUI 实现
- 更新 `scripts/build-app.sh`、`DashboardView.swift`、`docs/INDEX.md` 与设计文档中的版本标识：将当前稳定包固化为 `v0.6.0` 基线，作为下一轮手势结构改造的新分支起点
