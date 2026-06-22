# 文档索引

本文件是项目文档的权威入口。

## 必读顺序

1. `docs/HANDOFF-2026-06-18.md`
2. `docs/NEXT_AGENT_PROMPT.md`
3. `docs/PRD.md`
4. `docs/ARCH.md`
5. `docs/RISK_MODEL.md`
6. `docs/TEST_STRATEGY.md`
7. 本次改动关联模块文档
   - `docs/modules/dashboard/DESIGN.md`
   - `docs/modules/dashboard/SPEC.md`
   - `docs/modules/dashboard/TEST.md`
   - `docs/modules/gesture-control/DESIGN.md`
   - `docs/modules/gesture-control/SPEC.md`
   - `docs/modules/gesture-control/TEST.md`
   - `docs/modules/mediapipe-sidecar/DESIGN.md`
   - `docs/modules/mediapipe-sidecar/SPEC.md`
   - `docs/modules/mediapipe-sidecar/TEST.md`
8. 历史补充资料
   - `docs/architecture.md`
   - `docs/recording-studio-roadmap.md`

## 当前阶段

- 阶段：`v1.0.11 录制工作室发布候选`
- 当前包：打包后读取 `VERSION` / `BUILD_VERSION`，当前仓库版本为 `1.0.11 (20260623010720)`。
- 目标：冻结当前已通过用户复测并确认稳定的录制源选择、讲者/屏幕/麦克风录制、画中画监视器、录制中画布比例切换、预览合成、视频导出、项目管理和录制状态控制能力，作为社区版发布和后续专业版开发的受保护主链路。
- 原则：已测试通过的录制主链路不要随意重构；后续改动先补回归测试，再小步替换。

## 仓库约定

- 本项目 Git 远程仓库默认指向 NAS 上的 Gitea，不是 GitHub。
- 当前远程名称：`nas`
- 当前远程地址：`ssh://gitea-nas/agent/lingyan.git`
- 后续任务在提到“远程仓库”“push”“分支”“标签”时，默认都以 NAS Gitea 为准，除非用户明确要求改到其他平台。

## 本轮改动范围

- 录制工作室主链路：视频输入、屏幕/窗口输入、音频输入、项目保存、预览、导出。
- 监视器画中画：拖拽、缩放、形状、keyframe 与导出一致性。
- 录制状态控制：开始、暂停、继续、终止保存/放弃、倒计时与时间清零。
- 导出体验：真实进度、文件大小、成功弹窗、Finder 入口。
- 手势主链路继续保留 MediaPipe/Vision 视觉识别方向，后续重点转向动态手势准确度和远距离鲁棒性。
- 安全修复：本地 HTTP 服务 token 鉴权、sidecar 去通配 CORS、Release 包移除 DEBUG-only telemetry、项目导入校验。
- 并发修复：摄像头回调不再跨 actor 传递 `CMSampleBuffer`，Swift 6 sampleBuffer warning 已清理。
- 切源尺寸修复：录制中切换屏幕/窗口源时，写入 raw 屏幕轨前会读取 ScreenCaptureKit `contentRect` / `scaleFactor` 裁掉实际内容外黑边，减少“监视器正常但预览合成小画面”的不一致。
- 音频与布局修复：麦克风 raw 轨改为样本级 writer，降低开头爆音和短音轨风险；录制中布局切换写入 `RecordingLayoutKeyframe`，预览/导出可复现监视器布局变化。
- 画布比例修复：录制中切换画布比例会写入 layout keyframe 的画布像素尺寸，并为屏幕 raw 轨切出新段；预览/导出按每段活动画布矩形合成，停止录制后的画布调整不影响本次录制。
- 资源策略：预览合成和停止录制后的自动 program 文件默认生成 1080p 包络内的轻量视频；手动“导出视频”仍可按用户选择导出 4K。
- 未来产品计划：`Command+1` 到 `Command+6` 录制中快捷切源和用户自定义源位、桌面可拖拽 mini toolbar、可选时间片段/多段时间轴导出、授权验证与付费激活、多端点支持、多主题皮肤。

## 约束

- 不引入密钥到仓库
- 不把本地 token、授权凭证或支付凭证写进项目文件、日志或文档
- 首版继续使用本地推理/本地识别链路
- 保持现有 Swift Package 结构，避免破坏后续 MediaPipe sidecar 接入
