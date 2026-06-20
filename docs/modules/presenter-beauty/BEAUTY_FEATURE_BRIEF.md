# 讲者人像美颜功能简报与新任务提示词

## 背景

灵演 / WonderShow 已在 v0.8 分支加入讲者画面的基础质量控制：镜像、亮度、对比度、轻量柔化。当前实现的柔化偏“全画面滤镜”，不是成熟的人像美化：它没有识别人脸、脖子、皮肤区域，也不能区分讲者主体、背景、衣服、PPT 或桌面内容。

下一阶段要把这条能力升级为“主体/人脸感知的人像美颜 pipeline”：先识别讲者主体和脸部区域，只对脸、脖子等肤区做自然美化；后续再在同一条 portrait pipeline 上扩展 emoji 虚拟头像，并让虚拟头像跟随讲者表情。

## 当前实现状态

- 第一阶段已加入 `PresenterVideoEffects` 智能美颜字段：总强度、磨皮、提亮、净肤、祛瑕、气色和风格；旧 manifest 缺字段时仍默认关闭智能美颜。
- Program 导出已接入 `SubjectAwarePresenterBeautyProcessor`：使用 Apple Vision 检测单张讲者脸，Core Image 只对脸部和估算颈部 mask 做自然美化；无脸、低置信度或多人脸时回退到镜像/亮度/对比等基础效果。
- 2026-06-20 针对“脸部一块、脖子一块”的方块感风险收紧 mask：颈部区域从软矩形改为随下颌向下渐缩的多段椭圆 mask，并补充回归测试，确保颈部中心可以被轻量美化、颈部两侧角落不会被整块刷亮。
- 2026-06-20 下一阶段已开始落地 MediaPipe portrait pipeline：sidecar 同时加载 Face Landmarker 和 selfie multiclass segmenter，`/infer` 除手势外返回 faces、blendshapes 和 gray8 人像 segmentation mask；Swift 端新增 portrait 数据模型、背景虚化/颜色背景替换处理器，以及基于 MediaPipe face bbox 的高级局部美颜处理器。
- 2026-06-20 v1.0.0 之后继续新增 `EmojiFaceOverlayProcessor`：基于 MediaPipe face bbox 在讲者预览画面叠加 emoji 面孔，并通过 `PresenterVideoEffects` 保存开关、emoji 符号和强度；默认关闭，不改变 raw 讲者轨、窗口采集、屏幕合成或高清导出规则。
- 监视器底部与画布/清晰度按钮平齐新增 `智能美颜` 快捷按钮，并保留右侧“讲者画面”详细参数区。
- 实时预览已具备 sample-buffer 渲染路径，可应用 MediaPipe segmentation 的背景替换/虚化和 MediaPipe face bbox 的高级局部美颜；Program 导出仍使用当前 manifest/Core Image 链路，逐帧 MediaPipe 推理导出需要单独做性能预算。
- 第二阶段仍保留：真正的瘦脸/大眼 mesh warp、基于 face parsing 更精细避开眼眉唇、emoji 表情跟随和导出逐帧 MediaPipe 推理。

## 方案结论

当前专项的核心判断：美颜不能基于 `face bounding box -> blur/color filter`，否则一定会出现脸框、颈框、衣服或背景被误处理。可上线的第一阶段必须至少满足：

- 处理区域来自人脸检测、关键点和柔和 mask，而不是矩形 ROI。
- 颈部只能作为弱处理、渐缩处理，不做大面积矩形扩展。
- 无脸、低置信度和多人脸不确定时宁可回退，也不要猜一个大区域。
- 瘦脸、大眼、表情驱动 emoji 属于第二阶段，需要 landmarks/mesh warp 或成熟 AR Effects SDK；本轮已把参数和 MediaPipe landmarks 通路打通，但不把普通 Core Image 调色伪装成真实塑形。

## 当前代码切入点

- `Sources/WonderShow/Recording.swift`
  - `PresenterVideoEffects` 是讲者画面效果的 manifest 数据模型。
  - 旧项目缺字段时必须保持默认无效果，不能破坏历史项目导入。
- `Sources/WonderShowApp/DashboardView.swift`
  - `presenterMirrorEnabled`、`presenterBrightness`、`presenterContrast`、`presenterBeauty` 是当前 UI 状态。
  - `currentPresenterVideoEffects` 把 UI 状态写成 `PresenterVideoEffects`。
  - `PresenterVideoPreviewEffectModifier` 负责实时预览里的基础效果。
- `Sources/WonderShowApp/ProgramVideoRenderer.swift`
  - `ProgramVideoCompositor.applyPresenterEffects(...)` 负责导出 program 视频时应用讲者画面效果。
  - 这里必须和预览共享同一套效果语义，避免“预览好看、导出不一致”。
- 现有测试可参考：
  - `Tests/WonderShowAppTests/ProgramVideoRendererTests.swift`
  - `Tests/WonderShowTests/RecordingStudioTests.swift`

## 第一阶段目标

做一个可稳定上线的“自然人像美颜”基础版本，优先保证自然、稳定、可关闭、预览导出一致。

必须包含：

- 主体/人脸识别：识别讲者脸部，必要时估算脖子和可安全处理的皮肤区域。
- 局部美化：只处理讲者脸、脖子等肤区，不处理背景、PPT、屏幕内容、衣服和画中画外区域。
- 磨皮：降低皮肤噪点和小瑕疵，但保留五官、发际线、眉眼边缘和皮肤纹理。
- 美白/提亮：轻量提高肤色亮度，不能把整张脸刷白。
- 祛瑕：先做弱瑕疵抑制，不要追求“一键磨没所有痘印”，避免脸部闪烁和假面感。
- 气色：轻量提升面部红润度，可作为单独滑杆或模式参数。
- 失败回退：识别不到脸、置信度低、多人脸不确定时，不做局部美颜，只保留现有亮度/对比度/镜像效果。

暂不在第一阶段强做：

- 强烈唇色、牙齿美白、瘦脸、大眼。
- 多人同时精细美颜。
- emoji 虚拟头像替换。
- 独立 Python/HTTP sidecar。除非本机 Vision/Core Image 方案明显无法满足，否则先不引入新服务。

## 推荐技术路线

第一阶段优先用 Apple 原生能力，降低包体、鉴权、离线和发布风险：

- 用 Vision 做检测：
  - `VNDetectFaceRectanglesRequest` 定位人脸。
  - `VNDetectFaceLandmarksRequest` 获取眼、眉、鼻、嘴、脸轮廓等关键点。
  - 可评估 `VNGeneratePersonSegmentationRequest` 辅助主体/头肩范围，但第一版不要强依赖它。
- 用 Core Image 做处理：
  - 根据 landmarks 生成柔和 feather mask。
  - mask 覆盖脸部和估算脖子区域，避开眼睛、眉毛、嘴唇、头发边缘。
  - 使用 `CINoiseReduction`、`CIColorControls`、`CIHighlightShadowAdjust`、`CIColorMatrix` 等稳定滤镜组合。
  - 可用轻量 bilateral/surface blur 思路做磨皮，但必须通过 mask 和边缘保护限制影响范围。
- 性能策略：
  - 预览中检测可以降频，例如 8-12 fps 检测，逐帧复用并平滑 landmarks。
  - 导出时可以逐帧高质量处理，但要设置合理超时和回退。
  - 不要跨 actor 传 `CMSampleBuffer` / `CVPixelBuffer`。如涉及并发，先转成 `Data` 或项目自有 `Sendable` 值对象。

## 数据模型建议

建议扩展 `PresenterVideoEffects`，保持旧字段兼容：

- `beauty`: 继续作为总强度或旧项目兼容字段。
- `isSubjectAwareBeautyEnabled`: 是否启用智能局部美颜。
- `skinSmoothing`: 磨皮强度，范围 0...1。
- `skinBrightening`: 肤色提亮，范围 0...1。
- `skinWhitening`: 美白/净肤，范围 0...1。
- `blemishReduction`: 瑕疵抑制，范围 0...1。
- `complexion`: 气色，范围 0...1。
- `beautyStyle`: 可选，先支持 `natural` / `clean` / `bright` / `cameraReady`。

所有新增字段必须有默认值，旧 manifest 解码后等价于“不开启智能美颜”。

## UI 建议

在右侧“设备与输出 > 讲者画面”附近扩展，不要做单独大页面：

- 一个总开关：`智能美颜`。
- 一个总强度滑杆：`自然美颜`。
- 高级折叠项：
  - `磨皮`
  - `提亮`
  - `净肤`
  - `气色`
  - `祛瑕`
- 风格菜单：`自然`、`清透`、`明亮`、`上镜`。

默认保持关闭或极低强度，避免用户一打开就觉得“假”。

## 预览与导出一致性

这是本功能最重要的产品要求之一：

- 监视器预览、合成预览、导出 program 视频必须使用同一套参数语义。
- 允许预览为了性能使用降频检测，但最终视觉结果不能明显不同。
- raw 摄像头轨可以保持原始记录，不强制写入美颜；program 合成输出应按 manifest 应用美颜。
- 如果未来提供“导出时烘焙到讲者 raw 轨”的选项，必须另做开关，不能改变当前 raw 录制语义。

## 测试与验收

开发前先写回归测试，再改实现。

建议测试：

- `PresenterVideoEffects` 新字段 Codable round-trip，旧 JSON 缺字段解码为默认值。
- 美颜关闭时，导出输出和当前路径保持一致，不应改变背景和屏幕层。
- 美颜开启时，测试图中脸部区域像素发生合理变化，背景区域变化低于阈值。
- 无脸画面不应产生大面积柔化、闪烁或崩溃。
- 预览参数写入 manifest 后，导出能读取同一组参数。
- 现有 `ProgramVideoRendererTests`、`RecordingStudioTests` 继续通过。

人工验收：

- 摄像头讲者脸部自然变亮、肤色更干净，但眼睛、眉毛、嘴唇边缘不糊。
- PPT/屏幕内容、背景文字、桌面窗口不被磨皮。
- 录制 2-3 分钟后预览不卡顿，导出 1080p/4K 不崩溃。
- 切换录制源、暂停/继续、导出、项目导入导出不受影响。

至少运行：

```bash
rtk swift test --disable-sandbox
```

如改动 App 打包或资源，还需要重新构建并验证 `dist/灵演.app`。

## 风险边界

- 不要破坏稳定录制主链路：录制源选择、录制中切源、raw 屏幕/摄像头/麦克风轨、画中画、布局 keyframe、预览合成、视频导出、项目导入导出、音频连续性、录制状态控制。
- 不要把 token、密码、私钥、授权盐、支付凭证写入仓库或文档。
- 如果引入本地 HTTP / sidecar，必须保留 token 鉴权、禁止通配 CORS、Release 包不能带 DEBUG telemetry。
- 不要为了美颜把所有视频帧都跨 actor 乱传；媒体帧并发必须使用安全的 Sendable 数据边界。
- 不要默认启用过重美颜。产品定位是演讲/录屏增强，不是娱乐相机。

## 第二阶段：emoji 虚拟头像

等第一阶段稳定后，再做 emoji 虚拟头像：

- 用户可以选择 emoji 面孔作为虚拟形象。
- 系统检测讲者脸部姿态、嘴部开合、眨眼、眉眼表情。
- 在讲者脸部区域叠加或替换 emoji 头像，跟随位置、旋转、缩放和基础表情。
- 必须保留一键关闭和低置信度回退。
- 这部分可以复用第一阶段的 face landmarks 和 temporal smoothing，不要另起一套完全独立的人脸检测链路。

## 可复制的新任务提示词

下面这段可以直接复制到新 Codex 任务里：

```text
你正在接手 macOS SwiftUI 项目“灵演 / WonderShow”，仓库路径通常是：
/Users/aoke/code test/视频直播设备

请先阅读并遵守根目录 AGENTS.md 和 /Users/aoke/.codex/RTK.md。所有 shell 命令前加 rtk。仓库有 .codegraph/，理解代码前优先使用 CodeGraph；如需重建索引，运行 rtk codegraph sync .

当前后续开发分支是：
codex/source-slots-hotkeys-v0.8

当前 v0.8 已稳定完成：Command+0...9 源位切换、源位 VIP/SVIP 分级、mini toolbar、菜单栏常驻、监视器布局比例与导出一致、窗口源清晰度修正、暂停/继续录制时间轴修正、App 图标打包修正。不要破坏这些已测功能。

历史稳定基线：
tag: v0.7.20260619-stable
commit: d6f264b8ce14d2ea4587e854a3bc29b7d5acc5db
release zip: releases/lingyan-0.7.20260619-202606190305-macos.zip

请先阅读这些文档：
1. docs/NEXT_AGENT_PROMPT.md
2. docs/HANDOFF-2026-06-18.md
3. docs/INDEX.md
4. docs/PRD.md
5. docs/ARCH.md
6. docs/RISK_MODEL.md
7. docs/TEST_STRATEGY.md
8. docs/recording-studio-roadmap.md
9. docs/modules/dashboard/*
10. docs/modules/mediapipe-sidecar/*
11. docs/modules/gesture-control/*
12. docs/modules/presenter-beauty/BEAUTY_FEATURE_BRIEF.md

本任务目标：实现第一阶段“讲者人像智能美颜”。

产品要求：
- 先识别讲者主体/人脸区域，只美化脸、脖子等肤区。
- 美颜包含自然磨皮、美白/净肤、祛瑕、提亮、气色。
- 不要对 PPT、桌面、背景、衣服、屏幕文字做磨皮。
- 预览、合成预览和 program 导出必须使用同一套参数语义。
- raw 摄像头轨默认继续保留原始素材，不要改变现有 raw 录制语义。
- 低置信度、无脸、多人脸不确定时必须安全回退。
- emoji 虚拟头像只做第二阶段 TODO，不在本任务强做。

推荐技术路线：
- 第一版优先使用 Apple Vision + Core Image，不要一上来引入 HTTP sidecar。
- 用 VNDetectFaceRectanglesRequest / VNDetectFaceLandmarksRequest 定位脸部与 landmarks。
- 可评估 VNGeneratePersonSegmentationRequest 辅助主体范围，但不要让它成为硬依赖。
- 用 Core Image mask + feather + 边缘保护实现局部美颜。
- 预览可降频检测并复用 landmarks，导出走高质量处理。

重点代码切入点：
- Sources/WonderShow/Recording.swift
  - 扩展 PresenterVideoEffects，所有新增字段必须有默认值，旧 manifest 兼容。
- Sources/WonderShowApp/DashboardView.swift
  - 扩展“讲者画面”区域 UI：智能美颜开关、总强度、高级滑杆。
  - PresenterVideoPreviewEffectModifier 或新的共享预览处理器需要体现同一套效果语义。
- Sources/WonderShowApp/ProgramVideoRenderer.swift
  - ProgramVideoCompositor.applyPresenterEffects(...) 是导出 program 视频应用讲者效果的位置。
  - 把当前全画面 beauty 改为主体/脸部感知处理，不能影响屏幕层。
- Tests/WonderShowAppTests/ProgramVideoRendererTests.swift
- Tests/WonderShowTests/RecordingStudioTests.swift

开发原则：
- 已稳定功能先写回归测试再改，小步提交。
- 不要随意重构录制主链路。
- 不要把 token、密码、私钥、授权盐、支付凭证写入仓库或文档。
- 本地 HTTP / sidecar 改动必须保持 token 鉴权、无通配 CORS、Release 包无 DEBUG telemetry。
- 涉及媒体帧并发时，不要跨 actor 传 CMSampleBuffer/CVPixelBuffer，先转 Data 或项目自有 Sendable 值对象。

请按顺序做：
1. 用 CodeGraph 理解 PresenterVideoEffects、DashboardView 讲者画面 UI、ProgramVideoCompositor.applyPresenterEffects、现有测试。
2. 先补测试：manifest 兼容/round-trip、美颜关闭不改变输出、局部美颜只影响脸部区域、无脸安全回退。
3. 实现 Apple Vision + Core Image 的第一版局部美颜 pipeline。
4. 接入实时预览和 program 导出，确保同一套参数语义。
5. 更新必要文档和测试说明。
6. 至少运行 rtk swift test --disable-sandbox。
7. 如改动 App 打包，重建 dist/灵演.app 并验证签名/图标/版本号。

交付时请说明：
- 改了哪些文件。
- 如何测试。
- 哪些能力是第一阶段已完成，哪些作为第二阶段 emoji 虚拟头像 TODO。
```
