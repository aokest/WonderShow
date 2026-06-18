# MediaPipe Sidecar 规格

## 服务端口

- 默认地址：`http://127.0.0.1:18777`
- 默认只绑定本机 loopback。
- App 自动启动 sidecar 时会注入一次性本地 token：`WONDERSHOW_LOCAL_TOKEN`。
- Swift 请求会携带 `X-WonderShow-Local-Token`，`/health` 和 `/infer` 都必须通过该 token 校验。
- sidecar 默认拒绝无 token 启动；临时本地开发必须显式传 `--allow-unauthenticated-local-dev`。
- 不再向响应添加 `Access-Control-Allow-Origin: *`；Swift 原生客户端不需要 CORS。

## 接口

### `GET /health`

- 用途：检查 sidecar 是否已启动
- 鉴权：需要 `X-WonderShow-Local-Token`
- 返回：
  - `ok`
  - `engine`
  - `model_path`
  - `hand_model_path`
  - `auth_required`

### `POST /infer`

- 鉴权：需要 `X-WonderShow-Local-Token`
- 输入：
  - `timestamp_ms`
  - `image_base64`
- 限制：请求体最大 6 MiB，避免本机恶意页面/进程用超大 body 压垮推理进程
- 输出：
  - `ok`
  - `timestamp_ms`
  - `hands[]`
    - `handedness`
    - `handedness_score`
    - `landmarks[21]`
    - `gesture_categories[]`

## 模型文件

- 当前使用：
  - `sidecar/models/hand_landmarker.task`：双手检测与完整 `landmarks[21]`
  - `sidecar/models/gesture_recognizer.task`：补充 `gesture_categories[]`
- 后续可扩展：
  - 自定义 gesture classifier
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
- Swift 会先把 MediaPipe 顶左原点坐标转换为应用内底左原点坐标，再进入热区、叠加层和手势状态机
