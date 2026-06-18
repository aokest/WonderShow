# MediaPipe Sidecar

本目录是 `灵演 WonderShow` 的本地手势推理服务。

## 目标

- 用 MediaPipe Hand Landmarker + Gesture Recognizer 替换当前 Swift 侧的原型级 Vision 手势识别
- 保持主应用仍然是 SwiftUI/macOS 应用
- 把重模型和推理依赖放到本地 Python sidecar，降低 Swift 主程序复杂度

## 当前阶段

- 已提供本地 HTTP 推理服务骨架
- 已定义统一 JSON 协议
- Swift 已把采集帧发送到 `/infer` 并消费返回结果
- `HandLandmarker` 负责双手检测与每手 21 点 landmarks，`GestureRecognizer` 仅补充分类标签
- 可选加载 `sidecar/models/wondershow_gesture_model.json`，用你自己的手势样本覆盖官方分类

## 目录说明

- `server.py`：本地 HTTP 推理服务
- `gesture_model.py`：WonderShow 自训练手型分类器（纯 NumPy MLP）
- `requirements.txt`：Python 依赖
- `models/`：MediaPipe `.task` 模型文件存放目录

## 必需模型

`scripts/setup-mediapipe-sidecar.sh` 现在会自动下载官方 `gesture_recognizer.task` 与 `hand_landmarker.task` 到：

```text
sidecar/models/gesture_recognizer.task
sidecar/models/hand_landmarker.task
```

## 训练自定义手势模型

先把图片按文件名或目录标注，例如：

```text
手势图片示意/
  剑指-正.png
  枪指-正.png
  八字-正.png
  揪取-正.png
  抓握-背.png
```

然后运行：

```bash
cd "<repo-root>"
source .venv-mediapipe/bin/activate
python scripts/train_wondershow_gesture_model.py 手势图片示意
```

输出模型默认保存到：

```text
sidecar/models/wondershow_gesture_model.json
```

sidecar 启动时会自动加载它，并在 `/infer` 的每只手上返回 `custom_gesture`。

## 本地安装

```bash
cd "<repo-root>"
python3 -m venv .venv-mediapipe
source .venv-mediapipe/bin/activate
python -m pip install --upgrade pip
python -m pip install -r sidecar/requirements.txt
```

更简单的方式：

```bash
cd "<repo-root>"
./scripts/setup-mediapipe-sidecar.sh
```

## 启动

```bash
cd "<repo-root>"
source .venv-mediapipe/bin/activate
WONDERSHOW_LOCAL_TOKEN=dev-local-token-please-change python sidecar/server.py
```

## 健康检查

```bash
curl -H "X-WonderShow-Local-Token: dev-local-token-please-change" \
  http://127.0.0.1:18777/health
```

App 自动启动 sidecar 时会生成一次性本地 token 并通过环境变量传入；不要把真实 token 写进仓库、文档或日志。
如果要手动启动 sidecar 并让 App 复用它，需要用同一个 `WONDERSHOW_LOCAL_TOKEN` 启动 App 和 sidecar；否则 App 会把该 sidecar 视为不可信并回退到 Vision 或尝试启动自己的 sidecar。
如果只是短时本地调试，也可以显式传 `--allow-unauthenticated-local-dev`，但不要把这种模式用于分发或长期运行。

## 推理接口

### 请求

```json
{
  "timestamp_ms": 1781460000000,
  "image_base64": "<base64-jpeg>"
}
```

### 响应

```json
{
  "ok": true,
  "timestamp_ms": 1781460000000,
  "hands": [
    {
      "handedness": "Right",
      "handedness_score": 0.99,
      "landmarks": [
        { "x": 0.5, "y": 0.4, "z": -0.02 }
      ],
      "gesture_categories": [
        { "name": "Pointing_Up", "score": 0.93 }
      ],
      "custom_gesture": { "name": "pinch", "score": 0.88 }
    }
  ]
}
```

## 注意

- 该服务默认只监听本机 `127.0.0.1`
- `/health` 的 `engine` 应显示 `MediaPipe Hand Landmarker + Gesture Recognizer`
- 当前使用单帧 `IMAGE` 模式，后续会升级为更适合实时流的长期会话模式
- 本阶段不上传任何图像到外网，推理全部在本机完成
