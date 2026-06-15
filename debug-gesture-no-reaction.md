# Debug Session: gesture-no-reaction [OPEN]

## 症状

- 用户反馈：`没有反应。`
- 期望结果：手势进入识别链路后，应用能稳定触发翻页或缩放，HTML 测试页或目标演示也能收到命令。

## 当前上下文

- 已存在旧调试会话：`debug-gesture-no-response.md`
- 上一轮刚改过左右翻页映射，但用户当前反馈是“完全没有反应”，优先级高于方向正确性。
- 本会话先收集运行时证据，不在证据前修改业务逻辑。

## 可证伪假设

1. App 当前没有真正运行，或启动后未进入摄像头采集/手势识别状态。
2. Python sidecar 没有在 `127.0.0.1:18777` 正常提供 `/health` 和 `/infer`。
3. Swift 端已识别到手势，但命令没有成功送到本地 demo bridge。
4. Swift 端根本没有识别到有效手势帧，导致控制器从未收到手势事件。
5. 最新改动引入了构建错误、运行警告升级或状态机回退，导致手势链路被短路。

## 计划

1. 核对 app、sidecar、bridge 的运行态。
2. 读取现有调试日志与最新代码状态。
3. 如证据不足，只追加最小日志插桩。
4. 基于证据实施最小修复。
5. 用测试、运行和手工复现闭环验证。

## 证据记录

- E1: `lsof -nP -iTCP:18777 -sTCP:LISTEN` 显示 `python3.1` 正在监听 `127.0.0.1:18777`。
- E2: `curl -s http://127.0.0.1:18777/health` 返回 `{"ok": true, "engine": "MediaPipe Gesture Recognizer", ...}`，说明 sidecar 在线。
- E3: `ps aux | grep PresenterDirectorApp | grep -v grep` 初次检查为空，说明用户反馈“没有反应”时应用进程并未运行。
- E4: `swift test --disable-sandbox` 构建通过，41 个测试通过，当前仓库不存在会阻止启动的编译错误。
- E5: `bash scripts/build-app.sh` 失败，报 `sandbox-exec: sandbox_apply: Operation not permitted`，说明现有打包脚本会误导用户进入“以为启动了，实际没有可用 app”的状态。
- E6: `open "dist/灵演.app"` 后，`ps aux` 可见 `dist/灵演.app/Contents/MacOS/PresenterDirectorApp` 常驻运行，说明现有 app bundle 可正常拉起。
- E7: `strings dist/灵演.app/Contents/MacOS/PresenterDirectorApp | grep v0.5.0` 命中，说明 bundle 内可执行文件已是当前 `v0.5.0` 代码；用户看到的 `0.4.9` 来自 `Info.plist` 元数据未同步。

## 结论

- H1 已确认：用户当前“没有反应”的直接原因是应用进程未运行。
- H2 已否定：sidecar 当前健康，非本轮主因。
- H5 已部分确认：启动/打包路径存在缺陷，`build-app.sh` 需要改为 `swift build --disable-sandbox`。
- H3/H4 暂未进入本轮主因，因为在 app 不运行时无法继续观察实时手势链路。
