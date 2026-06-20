# 文档变更记录

## 2026-06-20

- 固化 `v1.0.0` 核心录制基线：活动窗口直接采集、切换录制源、监视器完整显示、预览合成和高清导出作为受保护主链路，后续功能不得轻易破坏这些行为。
- 新增 `VERSION`、`BUILD_VERSION`、`scripts/stamp-version.sh`、`githooks/pre-commit` 与 `scripts/install-git-hooks.sh`：打包脚本从仓库版本文件读取版本号，提交前自动刷新 build 号并纳入提交。
- 新增 `docs/CORE_RECORDING_CONTRACT.md`：记录录制/切源/导出的不可回退约束，明确后续涉及采集源、时间轴、合成渲染的改动必须保留完整窗口与切源回归测试。
- 讲者智能美颜专项调研与实现收口：确认“方块脸/脖子块”的根因是矩形 ROI 或过宽颈部 mask，而不是单纯磨皮参数问题；第一阶段继续采用 Apple Vision + Core Image 的本地局部美颜链路，后续瘦脸、大眼、表情头像再升级到 landmarks/mesh warp 或成熟 Effects SDK。
- 收紧 `SubjectAwarePresenterBeautyProcessor` 的颈部 mask：由软矩形改为随下颌向下渐缩的多段椭圆 mask，只保留颈部中心弱美化，避免颈部两侧角落被整块刷亮；新增 `subjectAwareBeautyUsesTaperedNeckMaskWithoutRectangularCorners` 回归测试。
- 更新 `docs/modules/presenter-beauty/BEAUTY_FEATURE_BRIEF.md`，补充第一阶段方案边界、失败回退和第二阶段能力边界。
- 启动 MediaPipe portrait pipeline：sidecar 下载并加载 `face_landmarker.task` 与 `selfie_multiclass_256x256.tflite`，`/infer` 返回 face landmarks/blendshapes 与 gray8 人像 mask；Swift 新增 portrait Codable 模型、背景虚化/颜色背景替换处理器、高级局部美颜处理器，并在摄像头预览链路缓存 MediaPipe portrait frame。当前完成预览/算法管线，导出逐帧 MediaPipe 推理和真实 mesh warp 仍为下一步。
- 在 v1.0.0 受保护录制合同之上新增 emoji 替脸预览能力：`EmojiFaceOverlayProcessor` 基于 MediaPipe face bbox 叠加 emoji 面孔，`PresenterVideoEffects` 增加 emoji 开关/符号/强度字段，Dashboard 美颜面板提供最小开关入口；该能力仅走讲者增强层，不改活动窗口直接采集、切源、完整窗口显示、预览/导出一致和高清导出主链路。
- 复测确认高级美颜、背景虚化/分割、Emoji 替脸尚不具备可交付质量：实时预览与导出一致性不足，人像贴合与跟随不稳定。新增 `PresenterExperimentalEffectsGate` 将三类入口置灰，并在参数层清零，保留亮度/对比度/镜像等基础稳定调整。
- 关于面板新增“感谢作者 / Buy me a coffee”区域，打包资源内置支付宝与微信小尺寸收款码；新增 `releases/README-1.0.0-20260620181913.md` 记录当前版本状态、实验功能困境和重新开放门槛。

## 2026-06-19

- 从稳定基线 `v0.7.20260619-stable` 开出后续开发分支 `codex/source-slots-hotkeys-v0.8`，用户确认下一阶段按 1-5 顺序推进：`Command+1` 到 `Command+6` 录制中快捷切源、源选择器 1-6 源位绑定、讲者画面镜像/调亮/轻美颜、真实时间轴、菜单栏常驻与桌面 mini toolbar。动态手势增强、授权付费、多端点和多主题先进入后置待办，不混入当前分支。
- 落地 v0.8 第一组功能：新增 `RecordingSourceSlots` 源位模型和测试；“录制源”弹窗的缩略图/列表项支持绑定 1-6 源位；录制中按 `Command+1` 到 `Command+6` 会重新扫描当前可用源并复用现有 `screenSourcePreference` / `ScreenArchiveRecorder.updateSource` 切源链路。源位只持久化 source id、显示名、类型和尺寸等元数据，不保存缩略图或窗口内容。
- 落地 v0.8 后续 3-5 项基础能力：讲者画面新增镜像/亮度/对比度/轻量柔化并写入 manifest 与 program 导出；底部时间轴改为真实轨道/片段显示，支持折叠、片段选区、播放头定位和单段选区导出；新增 macOS 状态栏菜单和桌面 mini toolbar，复用现有录制状态机控制开始/暂停/继续/终止、打开源选择器和切换源位。
- 根据安全审计更新本地安全边界：DemoControlServer 显式绑定 `127.0.0.1` 并引入本地一次性 token，MediaPipe sidecar `/health` 与 `/infer` 需要 `X-WonderShow-Local-Token`，去除通配 CORS 并限制请求体大小。
- 更新打包语义：`scripts/build-app.sh` 默认 Release 构建，确保 `#if DEBUG` 调试遥测不进入可分发包。
- 更新项目导入风险说明：`RecordingProjectStore` 增加 manifest 大小和 `schemaVersion` 校验。
- 更新 `docs/HANDOFF-2026-06-18.md`、`docs/INDEX.md`、`docs/RISK_MODEL.md` 和 MediaPipe sidecar 模块文档，记录审计接受结论、落地修复和剩余发布安全事项。
- 新增 `docs/NEXT_AGENT_PROMPT.md`，作为后续智能体接力提示词。
- 修复既有 Swift 6 `CMSampleBuffer` 并发 warning：`CameraPreviewService` 不再跨 actor 传递 sample buffer，改为在 capture queue 上转 JPEG 或提取 `HandPoint` 后再回 MainActor；同步更新 handoff 和接力提示词。
- 修复录制中切换屏幕/窗口源后监视器小画面或抖动的高概率根因：`ScreenArchiveRecorder.updateSource` 同步更新 `SCStreamConfiguration` 与 `SCContentFilter`，切源过渡期间不发布临时预览帧、写盘沿用上一帧直到新源稳定帧到来，写盘时将不同尺寸的新源按 aspect-fit 归一到固定 raw 轨尺寸；Dashboard 增加 preview generation，防止旧源迟到帧覆盖当前监视器。
- 继续修复“监视器里录制源正常，但预览合成里屏幕源变小”：`ScreenArchiveRecorder` 读取 ScreenCaptureKit sampleBuffer 的 `contentRect` / `scaleFactor`，写入 raw 屏幕轨前先裁掉真实内容外黑边，再归一到固定录制画布；实时 recorder preview 同步使用该裁切路径。新增 contentRect/Retina/clamp 回归测试，全量 `rtk swift test --disable-sandbox` 118/118 通过，Release 构建版本 `0.7.20260619 (202606190229)`。
- 修复麦克风开头爆音/随后断音的高风险链路：`MicrophoneArchiveRecorder` 从 `AVCaptureAudioFileOutput` 改为 `AVCaptureAudioDataOutput + AVAssetWriter` 样本级写入，跳过开录约 120ms 瞬态，停止时等待 writer 完成，暂停/继续时 retime 音频样本。导出测试新增音轨时长断言。
- 修复录制中切换“布局”没有进入预览/导出：新增 `RecordingLayoutKeyframe`，Dashboard 在录制中切布局时记录 keyframe，停止保存时拆分 program timeline；新增 manifest 和真实渲染测试覆盖。全量 `rtk swift test --disable-sandbox` 120/120 通过，Release 构建版本 `0.7.20260619 (202606190305)`。
- 用户复测确认 `v0.7.20260619 (202606190305)` 为真正稳定基线；同步更新 README、文档索引、PRD、架构、风险模型、测试策略、录制工作室路线图、Dashboard 模块文档、handoff 和接力提示词。新增未来规划：录制中通过 `Command+1` 到 `Command+6` 快速切换监控台录制源，并允许用户在活跃窗格选择器中自定义 1-6 源位。

## 2026-06-18

- 新增 `docs/HANDOFF-2026-06-18.md`：固化当前阶段交接文档，包含项目立项背景、开发意图、版本迭代过程、当前已实现功能、技术预研结论、Debug 记录、已踩坑和后续计划。
- 更新 `docs/INDEX.md`：将 handoff 加为当前文档入口，并把当前阶段更新为 `v0.7.20260618 录制工作室阶段基线`。
- 更新 `docs/PRD.md`：从早期导演台/手势基线状态，更新为当前录制工作室可用基线和下一轮问题清单。
- 更新 `docs/ARCH.md`：补充真实录制链路，包括 `CameraArchiveRecorder`、`ScreenArchiveRecorder`、`MicrophoneArchiveRecorder`、`ScreenPreviewService`、`RecordingSessionService` 和 `ProgramVideoRenderer`。
- 更新 `docs/recording-studio-roadmap.md`：把已经实现的窗口/屏幕选源、音频采集、画中画一致性、预览合成、真实导出和录制状态控制从“未实现”移到当前能力，并登记下一轮优先事项。
- 验证记录：`rtk swift test --disable-sandbox` 通过 109 个测试；当前已打包 app 为 `dist/灵演.app`，版本 `0.7.20260618 (202606181959)`。
- 更新未来计划：补充桌面可拖拽 mini toolbar 且可切换活动窗格、时间轴单段/多段选择导出、授权验证与付费激活、多端点支持、多皮肤/主题系统。

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
- 更新 `docs/INDEX.md` 与 `README.md`：固化仓库远程约定，明确本项目 Git 远程默认是 NAS 上的 Gitea（`nas` / `ssh://gitea-nas/agent/lingyan.git`），不是 GitHub

## 2026-06-16

- 新增 `docs/modules/gesture-control/v0.7-overhaul-design.md`：v0.7 手势控制结构性重构设计提案
  - 目标：结束“按参数缝补”的循环，改用 21 点几何 + 双轨独立模式 + 六态状态机
  - 模式：Swipe（指剑/指枪单手）与 Zoom（双手八字）由 `GestureModeCoordinator` 互斥仲裁
  - 几何：新增 `MediaPipeHandGeometry`，用 `palmSize = dist(0, 9)` 做归一化单位；用 tip/MCP 距离比判定手指伸出
  - 状态机：六态 `idle/candidate/dwell/active/grace/cooldown` + enter/exit hysteresis + dwell/grace 时长
  - 验证：必补 14 条单元测试覆盖 4 个真实问题（上一页不敏感、缩放反向、快速缩放不识别、缩放时翻页比缩放快）
  - 回滚：保留 `gesture.engine.version = "v0.6" | "v0.7"` 开关，v0.6.0 路径不动
  - 状态：待用户对决策点（§12）的 5 个问题回复后再进入代码实现阶段
- 更新 `Sources/PresenterDirector/MediaPipeHandGeometry.swift`、`GestureStateMachine.swift`、`Gesture.swift`、`MediaPipeGesture.swift`、`CameraPreviewService.swift` 与 `DashboardView.swift`：开始落地 v0.7 结构性重构实现
  - 新增 `MediaPipeHandGeometry`：用 21 点 landmarks 推导 `palmSize`、`palmCenter`、`剑指`、`指枪`、严格 `L` 形
  - 新增 `GestureRecognitionStateMachine` 与 `GestureModeCoordinator`：为翻页/缩放提供 enter/exit/dwell/grace/cooldown 状态机与模式互斥
  - 重写 `ContinuousZoomTracker`：改为 dwell + hysteresis + grace，并增加反向抖动保护，解决“放大时偶发缩小”
  - 重写 `StreamingGestureRecognizer`：按单手窗口对称评估左右挥，解决“上一页不敏感”
  - `CameraPreviewService` 先仲裁模式再进入手势链路，确保双手缩放进入后绝对禁止翻页识别
  - `DashboardView` 吸收 Figma 暖金深色舞台风格，收窄右侧控制列并更新剑指提示
- 更新 `Tests/PresenterDirectorTests/MediaPipeHandGeometryTests.swift` 与 `GestureRecognitionTests.swift`
  - 新增 v0.7 核心测试：缩放模式优先、缩放方向不反、快速缩放可识别、左右挥对称
  - 同步修正旧断言：不再允许 `unknown` 手型直接触发翻页
- 更新 `docs/modules/gesture-control/*`、`docs/modules/mediapipe-sidecar/*`、`docs/ARCH.md`、`docs/TEST_STRATEGY.md`
  - 记录 v0.7 的 21 点几何、模式互斥、状态机参数、测试覆盖和兼容层边界
- 继续更新 `CameraPreviewService.swift`、`DashboardView.swift` 与 `docs/modules/gesture-control/TEST.md`
  - 导演台新增“交互模式”可视化字段，实时显示 `空闲 / 翻页模式 / 缩放模式`
  - `CameraPreviewService` 在模式切换时上报一次调试事件，便于真实摄像头复测时判断究竟卡在模式仲裁、翻页链还是缩放链
- 继续修复与调优 v0.7 连续缩放（ContinuousZoomTracker）
  - 修复缩放抖动和方向翻转：方向反转抑制和强单方向运动判断改用 `abs(frameRelativeChange)` 而非加速度膨胀后的 `motionEnergy`
  - 缩放驱动改为加速度敏感模型，保留快速动作并过滤微小抖动
  - 统一全链路缩放边界：将 30%-300% (0.30 - 3.0) 的边界约束同步到 ContinuousZoomTracker 默认值、PresentationCommandController 和 HTML Demo
  - 修复 `DashboardView.swift` 中的 `PictureInPictureCorner` 编译错误

- 更新 `Sources/PresenterDirectorApp/DashboardView.swift`：根据 Figma 设计稿完整重构导演台界面，采用全新“暖黑金”设计系统，移除旧版原生/冷色卡片布局，实现了定制化胶囊状态栏、带有浮层和内发光的预览面板、可折叠的控制卡片列表以及深色金属质感的按钮/Toggle 控件。
- 更新 `docs/modules/dashboard/DESIGN.md`：同步修改视觉方向与布局原则。
\n- 修复左上角 `AppIcon` 无法加载显示的 Bug，统一使用 `NSImage(named:)` 与 `NSApplication.shared.applicationIconImage` 兜底机制读取图标。\n- 修复语言切换功能，在原本仅有简体中文（`zhHans`）的基础上新增支持繁体中文（`zhHant`）和英文（`en`），并接入到右上角的语言切换菜单中。
- [2026-06-16] 修复了 DashboardView 的语言切换 Bug（重构 UI 后枚举未正确映射到 AppLanguage），并更新单元测试通过
- [2026-06-16] 修复了 UI 重构带来的手势迟钝问题。根因是 `CameraPreviewService.processDetectedPoints` 在未检测到目标手（但依然在热区外）时，错误且高频地重置了 `gestureModeCoordinator`、`gestureSessionCoordinator`、`continuousZoomTracker` 以及清空了 `gestureSamples`，导致了手势窗口被彻底打碎无法积累到满足条件的时长。修改为仅更新提示语而不清除状态机。
- [2026-06-16] 修复摄像头预览黑影复测仍存在的问题：运行态摄像头层不再叠加 `previewGlow` 装饰背景，仅在未连接摄像头的占位态显示该装饰；同时将 Dashboard 与打包脚本版本标识更新到 `v0.7.0`，并重新生成 `dist/灵演.app`，避免继续打开旧打包产物。
- [2026-06-16] 修复 MediaPipe v0.7 主链路的热区锚点：运行态改用 21 点几何的 palm center 作为手部输入点，保留旧 `handPoints` 作为兼容层，避免 L 形 / Victory 指尖锚点越界时把真实双手缩放误过滤成单手。
- [2026-06-16] 修复 MediaPipe 坐标系回归：将 sidecar 顶左原点 landmarks 统一转换为应用内底左原点坐标，避免叠加点远离手部、热区判断错位和剑指/缩放控制混乱；新增测试覆盖 `snapshot` 旧入口。
- [2026-06-16] 升级 sidecar 为 `HandLandmarker + GestureRecognizer` 双模型：`HandLandmarker` 负责双手检测与每手 21 点，`GestureRecognizer` 只提供分类标签；安装脚本同步下载 `hand_landmarker.task`，Swift 叠加层新增 21 点小点显示与 palm anchor 金色点显示。
- [2026-06-16] 通读并移植 `figma_design/灵演wondershow/src/app/i18n.ts` 的前端三语结构，将 Dashboard 主 UI、右侧面板、底部诊断、校准弹层与运行态状态文本接入 `AppCopy` / `runtimeText`，不再只切换左上角应用名。
- [2026-06-16] 根据真机复测继续调优 v0.7 手感：剑指判定改为优先识别食指/中指并拢伸出并容忍无名指/小指软收拢；流式翻页识别支持两帧快速划过；双手缩放允许靠近到更小掌距并降低进入 dwell，修复缩小迟钝、缩小被过早重置和小抖动误反向问题。新增回归测试后全量 `swift test --disable-sandbox` 66/66 通过。

## 2026-06-17

- 新增录制工程核心模型：`RecordingProjectFactory` 将正式演讲录制和培训录屏对齐为同一套“讲者摄像头原始轨 + PPT/屏幕原始轨 + program 时间轴”的能力，默认区分正式演讲的讲者全身/讲者特写/讲者画中画/PPT 全屏，以及培训录屏的特写画中画/纯 PPT 视图。
- 新增 `RecordingProjectManifest` 与 `RecordingMediaAsset`，支持 JSON 往返，并固化首版相对媒体路径：`Raw/presenter-camera.mov`、`Raw/slides-screen.mov`、`Exports/program.mp4`。
- 新增 `Tests/PresenterDirectorTests/RecordingStudioTests.swift`，覆盖录制工程、时间轴视角、纯 PPT 场景不混入讲者图层、manifest 路径和 JSON 序列化。
- 新增 App 层 `RecordingSessionService`，现有录制按钮开始时会在 `~/Movies/灵演/` 创建 `.wondershow` 工程目录、`Raw/`、`Exports/` 和 `project.json`。
- 新增 `CameraArchiveRecorder`、`ScreenArchiveRecorder` 与 `ProgramVideoRenderer`：录制开始后写讲者摄像头 raw track，尝试通过 ScreenCaptureKit 写 PPT/屏幕 raw track，停止后按录制工程时间轴导出首版固定模板 `Exports/program.mp4`；本轮未改 Dashboard UI，屏幕权限或素材缺失时会保留工程并通过现有诊断文案提示。
- 更新 Dashboard 录制相关 UI：在不改变整体框架的前提下新增“项目”卡片，展示保存位置、原始轨道、合成输出和自动导播模板，并提供打开项目、在 Finder 中显示、预览合成视频入口；快速启动区补充彩排“不保存文件”的语义说明。
- 更新录制项目管理链路：新增 `RecordingProjectStore`，将项目卡片中的“导入项目 / 导出项目 / 导出视频 / 预览合成”接入真实文件读写和 App 内 AVKit 预览；导入支持 `.wondershow` 项目文件夹或 `project.json`，导出时保护源路径避免误删原项目。
- 更新录制状态反馈：录制开始明确提示正在写入讲者与屏幕原始轨，program 合成成功改为“录制工程更新”而不是异常提示；重新执行 `swift test --disable-sandbox` 81/81 通过并重建 `dist/灵演.app`。
- 新增麦克风原始轨：录制项目 manifest 固化 `Raw/microphone.m4a`，App 录制生命周期会请求麦克风权限并写入 AAC 音频，`ProgramVideoRenderer` 在素材存在时将麦克风音频并入 `Exports/program.mp4`；打包脚本同步写入 `NSMicrophoneUsageDescription`。
- 修复录制复测问题：新增 `ScreenCapturePlanner`，录屏优先选择包含 PowerPoint/Keynote/HTML 播放窗口的显示器而不是盲录第一块屏幕；预览合成改为自动播放的 App 内视频窗口；导出视频新增分辨率、帧率、清晰度、编码设置弹窗；录制开始增加 3 秒全屏浮层倒计时，并支持 `⌥⌘R` 开始/停止录制快捷键。
- 继续修复录制复测问题：导出设置弹窗改为自绘深色选项按钮，避免 macOS 原生 Picker 在深色面板中黑字不可见；“预览合成”在 program 不存在时会先尝试从 raw 轨重合成并弹出预览，失败时明确报告缺失轨道；ScreenCaptureKit 录制优先改为直接捕获识别到的 PPT/Keynote/HTML 演示窗口，无法识别窗口时再回退到显示器；录制模型补充多摄像头、多麦克风输入能力测试，Dashboard 监视器先显示 PiP 构图雏形。
