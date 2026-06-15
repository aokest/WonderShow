# [OPEN] Debug Session: gesture-no-response

## 症状
- 现在界面可正常打开，MediaPipe 引擎可显示。
- 清空旧校准按钮可用。
- HTML 测试页打开后，手势依然没有反应。

## 预期
- 在 HTML 测试页中，左右翻页手势至少应触发翻页命令。

## 假设
- H1: MediaPipe 已识别到手，但结果在热区、解锁或冷却状态中被拦截。
- H2: 手势已从识别链输出，但命令未正确投递到 HTML 目标。
- H3: HTML 页面桥接在线，但接收命令的名称或通道不匹配。
- H4: 旧校准停用后，仍有其他个性化样本/状态缓存影响识别。

## 当前状态
- 已创建调试会话，下一步只添加运行时插桩并收集证据。

## 已收集证据
- H1 已确认：`gesture-no-response` 日志中大量出现 `no hands detected`，且仅偶尔出现 `no discrete gesture recognized`，说明问题主要卡在识别前半段。
- H2 已否定：本地测试按钮仍可触发 `command delivery finished`，命令能进入桥接。
- H3 已否定：HTML 页持续轮询 `/api/command`，并能成功应用测试按钮发出的 `next` 命令。
- H4 暂不支持：停用旧校准后，仍未出现任何 `controller received gesture`，说明主问题不是旧模板残留，而是当前 MediaPipe 实时检手不稳定。

## 修复计划
- 提高发送给 sidecar 的 JPEG 质量，减少手部细节损失。
- 下调 MediaPipe 检手阈值，减少空帧。
- 连续空帧时自动临时回退到 Vision，先恢复“至少能触发”的能力。
