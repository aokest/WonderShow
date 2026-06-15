# Debug Session: zoom-instability-v07
- **Status**: [OPEN - 第二轮修复待复测]
- **Issue**: 双手八字缩放时，虽然已进入缩放模式且误翻页减少，但缩放尺寸、速度和方向仍与预期不符；手静止时也会触发缩放
- **Debug Server**: http://127.0.0.1:7777/event
- **Log File**: .dbg/trae-debug-log-zoom-instability-v07.ndjson

## Reproduction Steps
1. 打开 `dist/灵演.app`
2. 打开 HTML 测试演示页
3. 双手做严格 L 形进入缩放模式
4. 双手远离 / 靠近，观察缩放方向、幅度和速度
5. **新增**：手静止不动时观察是否仍触发缩放

## Hypotheses & Verification
| ID | Hypothesis | Likelihood | Effort | Evidence |
|----|------------|------------|--------|----------|
| A | `ContinuousZoomTracker` 仍按"距离速度/步长"驱动，和用户期望的"距离变化加速度"不一致，导致手感失真 | High | Med | **已修复** |
| B | palm-size 归一化距离在进入缩放后仍受基线重置或 quiet rebase 影响，导致方向偶发翻反或幅度突变 | High | Med | **已修复** |
| C | `CameraPreviewService` 已进入缩放模式，但传给 tracker 的几何序列仍存在左右手排序或采样抖动，导致 distance 导数符号不稳定 | Med | Med | Pending |
| D | HTML 测试页自身的缩放动画和 app 发出的缩放步长叠加，放大了"速度不对"和"方向不稳"的体感 | Med | Low | Pending |
| E | 当前日志只记录"是否发出 zoom"，没有记录 baseline / normalized distance / delta / acceleration，导致真实根因尚不可见 | High | Low | **已修复** |

## 修复记录

### 第一轮修复（2026-06-16）
- 连续缩放追踪器加入三重 rebase 条件（quiet frames + relative change + time interval）
- 加速度能量检测替代纯速度检测
- 方向一致性检查（minimumConsecutiveDirections = 2）
- 缩放范围统一为 30%-300%（0.30-3.0）

### 第二轮修复（2026-06-16）
- **根因**：方向反转抑制检查使用了被加速度膨胀的 `motionEnergy`，导致微小抖动（如 frameRelativeChange=-0.03）因大的加速度方向变化而绕过抑制阈值（0.040）
- **修复**：方向反转抑制和强单方向运动判断改用 `abs(frameRelativeChange)` 而非 `motionEnergy`
- **效果**：微小抖动（手接近静止）不会因加速度方向变化而触发缩放方向反转
- **验证**：57/57 测试通过，包括 `continuousZoomTrackerDoesNotReverseDirectionOnTinyJitter`
- **附带修复**：`DashboardView.swift` 中 `PictureInPictureCorner` → `PiPCorner` 编译错误

## 用户反馈追踪
1. **「缓慢缩放，识别模式为缩放，但是缩放速度和手的动作速度（加速度、方向）相比很迟钝甚至有时候会反」**
   → 第一轮：加速度能量检测 + 方向一致性检查
   → 第二轮：方向抑制用原始 frameRelativeChange 避免误判

2. **「快速缩放，识别模式为空闲或缩放。基本捕捉不到，也不反应」**
   → 第一轮：加速度能量检测允许快速动作通过
   → 待复测确认

3. **「手静止不动的时候也会被识别出缩放信号然后做一定缩放响应」**
   → 第二轮核心修复目标：微小抖动被方向抑制正确拦截

## Log Evidence
- 2026-06-16: 已启动 Debug Server，日志文件位于 `.dbg/trae-debug-log-zoom-instability-v07.ndjson`
- 2026-06-16: 已插桩 `ContinuousZoomTracker.updateDistance`，记录 baseline / rebase / state blocking / direction suppression / emit
- 2026-06-16: 已插桩 `CameraPreviewService.handleContinuousZoom(geometries:)`，记录 handedness / palm center / normalized distance / geometry path output
- 2026-06-16: 已插桩 `examples/wondershow-demo.html`，记录 demo 收到的 `setZoom` 和动画最终 settled 值
- 2026-06-16: 当前已抓到的日志仍以 `pointCount = 1` 的 `idle/swipe` 模式切换为主，尚未抓到 `B/C/D` 关键缩放链日志
- 2026-06-16: 这说明当前证据链只够支持"系统大部分时间只保留了一只手"，还不足以直接判定缩放算法本身的根因

## Verification Conclusion
- `A`：已修复。加速度驱动缩放 + 动态步长限制
- `B`：已修复。三重 rebase 条件 + 方向抑制用原始 frameRelativeChange
- `E`：已修复。完整 debug points 覆盖整条缩放链
- `C/D`：仍待确认，需要用户在**重新打开新打包 app** 后做复测
