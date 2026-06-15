# MediaPipe Sidecar

本目录是 `灵演 WonderShow` 的本地手势推理服务。

## 目标

- 用 MediaPipe Gesture Recognizer 替换当前 Swift 侧的原型级 Vision 手势识别
- 保持主应用仍然是 SwiftUI/macOS 应用
- 把重模型和推理依赖放到本地 Python sidecar，降低 Swift 主程序复杂度

## 当前阶段

- 已提供本地 HTTP 推理服务骨架
- 已定义统一 JSON 协议
- 下一步会把 Swift 采集帧发送到 `/infer` 并消费返回结果

## 目录说明

- `server.py`：本地 HTTP 推理服务
- `requirements.txt`：Python 依赖
- `models/`：MediaPipe `.task` 模型文件存放目录

## 必需模型

`scripts/setup-mediapipe-sidecar.sh` 现在会自动下载官方 `gesture_recognizer.task` 到：

```text
sidecar/models/gesture_recognizer.task
```

## 本地安装

```bash
cd "/Users/aoke/code test/视频直播设备"
python3 -m venv .venv-mediapipe
source .venv-mediapipe/bin/activate
python -m pip install --upgrade pip
python -m pip install -r sidecar/requirements.txt
```

更简单的方式：

```bash
cd "/Users/aoke/code test/视频直播设备"
./scripts/setup-mediapipe-sidecar.sh
```

## 启动

```bash
cd "/Users/aoke/code test/视频直播设备"
source .venv-mediapipe/bin/activate
python sidecar/server.py
```

## 健康检查

```bash
curl http://127.0.0.1:18777/health
```

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
      ]
    }
  ]
}
```

## 注意

- 该服务默认只监听本机 `127.0.0.1`
- 当前使用单帧 `IMAGE` 模式，后续会升级为更适合实时流的长期会话模式
- 本阶段不上传任何图像到外网，推理全部在本机完成
