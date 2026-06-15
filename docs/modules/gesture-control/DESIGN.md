# 手势控制设计说明

## 设计目标

- 降低误触
- 增强用户对“当前是否可触发”的感知
- 为后续更换底层识别引擎保留接口稳定性

## 交互模型

采用两阶段交互：

1. 用户先把手放入中央热区
2. 用户做开掌停留以进入可触发状态
3. 在短时间窗口内执行翻页或缩放动作
4. 触发后进入冷却期，避免重复发送

## 视觉反馈

- 热区边框
- 当前会话状态
- 最近识别动作
- 引导文案

## 引擎策略

- 当前主引擎：Vision 增强版
- 后续扩展：MediaPipe sidecar

## v0.7 结构性重构

- 交互从“同一窗口里同时猜翻页和缩放”改为“`GestureModeCoordinator` 互斥仲裁”
- `Swipe` 与 `Zoom` 分别走独立状态机，统一具备：
  - `enter threshold`
  - `exit threshold`
  - `dwell`
  - `grace period`
  - `cooldown`
  - `hysteresis`
- 双手缩放进入后，当前帧与 grace 窗口内都不再进入翻页链路
- MediaPipe 侧新增 `MediaPipeHandGeometry`：
  - 用 `palmSize = dist(wrist, middleMCP)` 归一化
  - 用 21 点几何推导 `sword`、`fingerGun`、`lShape`
  - 用 palm center + palm size 归一化距离驱动连续缩放
- 单手翻页改为只接受明确的 `剑指` 或 `指枪`
- Dashboard 视觉层同步向 Figma 的暖金深色舞台风格靠拢，但不改变现有功能结构
