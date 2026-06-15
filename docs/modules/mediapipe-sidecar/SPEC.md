# MediaPipe Sidecar 规格

## 服务端口

- 默认地址：`http://127.0.0.1:18777`

## 接口

### `GET /health`

- 用途：检查 sidecar 是否已启动
- 返回：
  - `ok`
  - `engine`
  - `model_path`

### `POST /infer`

- 输入：
  - `timestamp_ms`
  - `image_base64`
- 输出：
  - `ok`
  - `timestamp_ms`
  - `hands[]`
    - `handedness`
    - `handedness_score`
    - `landmarks[21]`
    - `gesture_categories[]`

## 模型文件

- 当前使用：`sidecar/models/gesture_recognizer.task`
- 后续可扩展：
  - 自定义 gesture classifier
  - 仅 landmarks 模式
  - 自训练时序分类器

## 回退

- sidecar 不可用时，Swift 继续使用旧 Vision 路线

## v0.7 消费约束

- `hands[].landmarks[21]` 必须完整，否则该手不会进入 `MediaPipeHandGeometry`
- `gesture_categories[]` 仍保留给兼容映射，但 v0.7 的缩放主链路不再把它作为唯一真相
- Swift 侧会同时读取：
  - `gesture_categories[]` 生成兼容 `HandShape`
  - `landmarks[21]` 生成 `palmSize`、`palmCenter`、`primaryShape`
- 双手缩放要求两只手的 21 点都完整，且必须都能推导出严格 `L` 形
