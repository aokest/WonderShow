# 后续智能体接力提示词

请先阅读并遵守本仓库根目录 `AGENTS.md` 和 `/Users/aoke/.codex/RTK.md`，所有 shell 命令前加 `rtk`。如果仓库有未提交改动，不要回滚用户或其他智能体的改动。

你正在接手 macOS SwiftUI 项目“灵演 / WonderShow”，路径通常是 `/Users/aoke/code test/视频直播设备`。它不是单纯翻页工具，而是“演讲导演台 + 录制工作室”：核心目标是同时支持手势演示控制、讲者/屏幕/音频录制、项目保存、预览合成、视频导出和未来时间轴编辑。

请按顺序阅读：

1. `docs/HANDOFF-2026-06-18.md`
2. `docs/INDEX.md`
3. `docs/PRD.md`
4. `docs/ARCH.md`
5. `docs/RISK_MODEL.md`
6. `docs/recording-studio-roadmap.md`
7. `docs/modules/mediapipe-sidecar/*`
8. `docs/modules/gesture-control/*`
9. `docs/DOCLOG.md`

当前稳定基线是 `v0.7.20260619 (202606190305)`，已经过用户复测并确认“真正稳定”。稳定能力包括：录制源选择、摄像头/屏幕/麦克风 raw 录制、项目保存/打开/导入/导出、监视器画中画拖拽/缩放/形状、预览合成、视频导出、录制状态开始/暂停/继续/终止、音频输入选择、录制中切换源、录制中切换布局并进入预览/导出。除非任务明确要求，不要大拆这些主链路；若必须改，先补测试，小步替换。

最近安全修复已经落地：

- `DemoControlServer` 显式绑定 `127.0.0.1:17635`，测试页桥接 API 需要本地一次性 token。
- MediaPipe sidecar 的 `/health` 和 `/infer` 需要 `X-WonderShow-Local-Token`，默认拒绝无 token 启动，去掉通配 CORS，并限制请求体大小。
- `127.0.0.1:7777/event` 调试 telemetry 只允许 DEBUG 编译存在；`scripts/build-app.sh` 默认 Release 构建。
- 项目导入增加 manifest 大小限制和 `schemaVersion` 白名单。
- 不要把 token、密码、Gitea 凭证、私钥、授权盐或支付凭证写入仓库、文档、manifest 或日志。

最近 Swift 6 并发修复也已经落地：

- `CameraPreviewService.captureOutput` 不再把 `CMSampleBuffer` 捕获进 `Task { @MainActor ... }`。
- 摄像头回调队列只在本线程内读取 sample buffer：MediaPipe 路径先转 JPEG `Data`，Vision 兜底先提取 `[HandPoint]`，再把可发送数据交给 MainActor。
- 后续不要重新跨 actor 传递 `CMSampleBuffer`、`CVPixelBuffer`、`VNRecognizedPoint` 等框架对象；要先转成 `Data` 或项目自有的 Sendable 值对象。

最近录制中切源修复也已经落地：

- `ScreenArchiveRecorder.updateSource` 切换窗口/屏幕源时会同时更新 `SCStreamConfiguration` 和 `SCContentFilter`。
- 切源过渡期间临时 sampleBuffer 不写盘、不发布预览；Dashboard 用 `screenPreviewGeneration` 防止旧源 preview 迟到覆盖监视器。
- 屏幕 raw 轨保持录制开始时的固定视频尺寸；切源后若新源尺寸不同，先按 aspect-fit 渲染到固定 pixel buffer 再 append。
- 2026-06-19 追加修复了“监视器里源正常变大，但预览合成里屏幕源变小”：`ScreenArchiveRecorder` 读取 `SCStreamFrameInfo.contentRect` / `scaleFactor`，先裁掉 ScreenCaptureKit sampleBuffer 的实际内容外黑边，再归一化写入固定 raw 屏幕轨；recorder preview 也走同一裁切路径。
- 这轮主要修的是“录制中切源后窗口变小/画面轻微跳动”以及“合成预览小画面”的高概率原因。用户已经确认当前版本稳定；若未来再次复现，再补真实窗口日志定位，不要先重写录制主链路。
- 重要边界：旧项目如果已经把小窗口和黑边写进 `Raw/slides-screen.mov`，新代码不能无损恢复；验证这项修复要用新构建重新录一段。

最近音频与布局时间轴修复也已经落地：

- `MicrophoneArchiveRecorder` 不再使用 `AVCaptureAudioFileOutput` 黑盒写 `.m4a`，改为 `AVCaptureAudioDataOutput + AVAssetWriter` 样本级写入。
- 麦克风录制会跳过开录约 120ms 启动瞬态来降低爆音风险；停止录制会等待 writer `finishWriting` 后再进入合成；暂停/继续会 retime 音频样本，避免时间轴错位。
- 录制中切换“布局”现在会生成 `RecordingLayoutKeyframe`，停止保存时拆分 program timeline；预览合成和导出会复现“屏幕主画面/讲者主画面”等切换。
- 已有测试覆盖：program 音轨时长不是一瞬间、layout keyframes 拆 timeline、真实渲染前后半段主画面变化。用户已确认当前版本稳定；未来改音频/布局时要继续以这些测试作为回归边界。

当前开发分支建议从 `codex/source-slots-hotkeys-v0.8` 继续，基于用户已确认稳定的 `v0.7.20260619-stable`。用户已确认下一阶段按下面 1-5 顺序推进；第 6 组先进入待办，不混入当前快捷切源/录制工作室主线。

1. P1 增加录制中快捷切源：已在 `codex/source-slots-hotkeys-v0.8` 开始落地。`Command+1` 到 `Command+6` 只在录制中且当前 program 使用屏幕源时生效；触发后重新扫描当前可用 ScreenCaptureKit 源，解析源位并复用现有 `screenSourcePreference -> handleScreenCaptureSourceChange() -> ScreenArchiveRecorder.updateSource` 链路。
2. P1 在“录制源”弹窗中增加 1-6 源位绑定：已新增 `RecordingSourceSlots`，源选择器缩略图/列表项都显示 1-6 小按钮。源位状态持久化到 UserDefaults，只保存 slot、source id、显示名、类型、尺寸等元数据，不保存窗口截图或隐私内容。测试覆盖槽位边界、重复绑定替换、窗口关闭后不可切和快捷键解析。
3. P1 增加讲者画面质量能力：已新增镜像、亮度、对比度和轻量柔化控制；预览层即时显示，manifest 记录 `PresenterVideoEffects`，program 导出按 manifest 应用同样效果，旧项目缺字段时默认无效果。
4. P1 把底部时间轴从占位变成真实轨道编辑器基础：已按 manifest/raw 文件状态展示 PPT/屏幕、讲者、声音、合成轨道，支持轨道折叠、点击片段定位播放头、选择单段范围并导出选区。未做破坏性删除 raw、多段非连续拼接和完整波形/缩略图编辑器。
5. P1 增加 macOS 菜单栏常驻和桌面可拖拽 mini toolbar：已新增状态栏菜单和浮动 mini toolbar，显示录制时间，复用现有 Dashboard 录制状态机执行开始/取消倒计时/暂停/继续/终止、打开录制源选择器和源位 1-6 切换。
6. 待办后置：动态手势识别增强、授权验证/付费激活、正式签名公证、多端点支持和多主题皮肤先不进入当前开发分支，等用户重新确认优先级后再单独开分支或专项推进。
7. 观察项：如果用户再次反馈监视器窗口抖动或尺寸变化，优先加真实窗口日志 source id、frame、contentRect、scaleFactor、pixelSize、preview image size、raw track natural size，再查 `ScreenPreviewService`、`ScreenArchiveRecorder`、窗口 source rect、Retina scale 和 aspect-fit 布局。

关键命令：

```bash
rtk swift test --disable-sandbox
rtk bash scripts/build-app.sh
open "dist/灵演.app"
```

仓库远程默认是用户 NAS Gitea，不是 GitHub：

- remote: `nas`
- URL: `ssh://gitea-nas/agent/lingyan.git`

回答用户时请用中文，保持工程判断清晰。改 UI 时维持现有暖黑金设计语言，避免让整个 UI 框架崩掉。改安全/授权/支付相关功能时必须做安全审查。
