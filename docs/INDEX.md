# 文档索引

本文件是项目文档的权威入口。

## 必读顺序

1. `docs/PRD.md`
2. `docs/ARCH.md`
3. `docs/RISK_MODEL.md`
4. `docs/TEST_STRATEGY.md`
5. 本次改动关联模块文档
   - `docs/modules/dashboard/DESIGN.md`
   - `docs/modules/dashboard/SPEC.md`
   - `docs/modules/dashboard/TEST.md`
   - `docs/modules/gesture-control/DESIGN.md`
   - `docs/modules/gesture-control/SPEC.md`
   - `docs/modules/gesture-control/TEST.md`
   - `docs/modules/mediapipe-sidecar/DESIGN.md`
   - `docs/modules/mediapipe-sidecar/SPEC.md`
   - `docs/modules/mediapipe-sidecar/TEST.md`
6. 历史补充资料
   - `docs/architecture.md`
   - `docs/recording-studio-roadmap.md`

## 当前阶段

- 阶段：`v0.6 稳定基线`
- 目标：冻结当前可运行的导演台 + MediaPipe 手势版本，作为下一轮结构性手势改造的可回退基线。
- 原则：先固化可启动、可测试、可打包的稳定版本，再在新分支做大刀阔斧的交互与识别重构。

## 本轮改动范围

- Dashboard 主界面信息架构重构
- 手势引擎稳态控制重构
- 文档体系补齐
- MediaPipe sidecar 方案落地

## 约束

- 不引入密钥到仓库
- 首版继续使用本地推理/本地识别链路
- 保持现有 Swift Package 结构，避免破坏后续 MediaPipe sidecar 接入
