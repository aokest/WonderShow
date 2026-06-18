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

下一轮优先级大致是：

1. P1 增加录制中快捷切源：用户希望按 `Command+1` 到 `Command+6` 分别快速切换不同录制源到监控台；点击“录制源”刷新出的活跃窗格底部，需要允许用户自定义哪个源是 1、2、3、4、5、6。实现时复用现有 ScreenCaptureKit 源选择/缩略图/updateSource 链路，并把源位状态和切源事件设计成未来时间轴可读的数据。
2. P1 增加讲者画面质量能力：摄像头镜像翻转、调亮/对比度、轻量美颜，要求 preview、raw/export、manifest 一致。
3. P1 把底部时间轴从占位变成真实轨道编辑器：展示音频/视频轨道，支持折叠、删除、拖拽定位、多选导出，支持单段或多段时间范围导出。
4. P1 增加 macOS 菜单栏常驻和桌面可拖拽 mini toolbar：显示录制时间，提供暂停、继续、结束录制和切换活动窗格/录制源按钮；mini toolbar 也应能触发源位切换或打开源选择器。
5. P1 提高手势识别准确度：继续视觉识别主线，建立真实采样/回放测试集，引入基于 landmarks 的动态时序模型；强化学习先用于策略层阈值和触发策略，不要直接替代底层视觉检测。
6. 观察项：如果用户再次反馈监视器窗口抖动或尺寸变化，优先加真实窗口日志 source id、frame、contentRect、scaleFactor、pixelSize、preview image size、raw track natural size，再查 `ScreenPreviewService`、`ScreenArchiveRecorder`、窗口 source rect、Retina scale 和 aspect-fit 布局。
7. P2 设计授权验证/付费激活、正式签名公证、多端点支持和多主题皮肤。

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
