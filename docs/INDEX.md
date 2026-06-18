# 文档索引

本文件是项目文档的权威入口。

## 必读顺序

1. `docs/HANDOFF-2026-06-18.md`
2. `docs/PRD.md`
3. `docs/ARCH.md`
4. `docs/RISK_MODEL.md`
5. `docs/TEST_STRATEGY.md`
6. 本次改动关联模块文档
   - `docs/modules/dashboard/DESIGN.md`
   - `docs/modules/dashboard/SPEC.md`
   - `docs/modules/dashboard/TEST.md`
   - `docs/modules/gesture-control/DESIGN.md`
   - `docs/modules/gesture-control/SPEC.md`
   - `docs/modules/gesture-control/TEST.md`
   - `docs/modules/mediapipe-sidecar/DESIGN.md`
   - `docs/modules/mediapipe-sidecar/SPEC.md`
   - `docs/modules/mediapipe-sidecar/TEST.md`
7. 历史补充资料
   - `docs/architecture.md`
   - `docs/recording-studio-roadmap.md`

## 当前阶段

- 阶段：`v0.7.20260618 录制工作室阶段基线`
- 当前包：`dist/灵演.app`，版本 `0.7.20260618 (202606181959)`。
- 目标：冻结当前已通过用户复测的录制源选择、讲者/屏幕/麦克风录制、画中画监视器、预览合成、视频导出、项目管理和录制状态控制能力，作为下一轮时间轴、画质增强、菜单栏常驻/桌面 mini toolbar、授权商业化、多端点、多主题和手势准确度提升的起点。
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
- 未来产品计划：桌面可拖拽 mini toolbar、可选时间片段/多段时间轴导出、授权验证与付费激活、多端点支持、多主题皮肤。

## 约束

- 不引入密钥到仓库
- 首版继续使用本地推理/本地识别链路
- 保持现有 Swift Package 结构，避免破坏后续 MediaPipe sidecar 接入
