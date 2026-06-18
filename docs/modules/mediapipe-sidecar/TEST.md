# MediaPipe Sidecar 测试要点

## 安装验证

1. 运行 `scripts/setup-mediapipe-sidecar.sh`
2. 确认脚本自动下载 `gesture_recognizer.task` 和 `hand_landmarker.task`
3. 运行 `scripts/run-mediapipe-sidecar.sh`
4. 访问 `http://127.0.0.1:18777/health`
5. 确认 `engine` 为 `MediaPipe Hand Landmarker + Gesture Recognizer`

## 接口验证

1. 使用任意 JPEG 进行 `POST /infer`
2. 确认返回 `hands`、`gesture_categories` 和每只手完整 `landmarks[21]`
3. 确认未检测到手时返回空数组而不是崩溃

## 应用集成验证

1. Swift 能检测到 sidecar 存活
2. Swift 能把摄像头帧编码为 JPEG
3. Swift 能解析 sidecar 返回的 JSON
4. MediaPipe 输出能映射到现有 `HandPoint` 和 `GestureFrameSnapshot`
5. `Pointing_Up` 与 `Victory` 手型的 Swift 锚点映射应来自多个 landmarks 的加权结果，而不是单一指尖点
6. v0.7 `MediaPipeHandGeometry` 应能从 `landmarks[21]` 正确推导 `剑指` 与严格 `L` 形
7. 双手 `L` 形进入后，Swift 侧应直接进入缩放模式，而不是继续等待翻页链路先判定
8. MediaPipe 顶左原点坐标进入 Swift 后必须转换为底左原点，否则叠加点会远离真实手部

## 未来回归

- 外接相机与内置相机都要测
- 不同光照下的连续翻页要测
- 校准前后都要测
