# Gesture Training Handoff - 2026-06-17

## 任务背景

灵演 WonderShow 当前已经从纯规则手势识别转向“MediaPipe 21 点手部 landmarks + 本地可训练分类器”的路线。

用户实测反馈：

- 点位和点位连接线能显示，说明 MediaPipe 手部检测和 21 点定位是通的。
- 但所有手势控制目前无法识别，推测原因是 `sidecar/models/wondershow_gesture_model.json` 只用 9 张示意图训练，严重过拟合，实时手势被错误分类覆盖。
- 用户现在要新开任务，专门做真实样本采集、训练、验证。

核心目标不是继续调阈值，而是采集用户本人、当前摄像头、当前光照和当前手势习惯下的样本，让模型学会：

- 剑指：只用于翻页。
- 枪指：不翻页，可作为双手缩放手势之一。
- 八字：双手缩放手势之一。
- 揪取：单手脉冲缩小，揪取后伸展开来脉冲放大。
- 抓握：以拳头/抓握位置作为接触点拖拽平移。
- 开掌：单手伸展开来、校准/状态过渡。

## 当前代码状态

工作目录：

```bash
/Users/aoke/code test/视频直播设备
```

关键文件：

```text
sidecar/gesture_model.py
scripts/train_wondershow_gesture_model.py
sidecar/server.py
sidecar/models/wondershow_gesture_model.json
Sources/PresenterDirector/MediaPipeGesture.swift
Sources/PresenterDirector/MediaPipeHandGeometry.swift
Sources/PresenterDirector/Gesture.swift
Sources/PresenterDirectorApp/CameraPreviewService.swift
examples/wondershow-demo.html
```

已经创建的样本目录：

```text
训练样本/
  八字/
  剑指/
  开掌/
  抓握/
  揪取/
  枪指/
```

当前 `wondershow_gesture_model.json` 是用 `手势图片示意/` 下 9 张示意图训练出的种子模型。这个模型只能证明训练管线跑通，不能代表可用精度。

如果测试时所有控制都死掉，优先临时停用种子模型：

```bash
cd "/Users/aoke/code test/视频直播设备"
mv sidecar/models/wondershow_gesture_model.json sidecar/models/wondershow_gesture_model.disabled.json
```

训练完成后会重新生成：

```text
sidecar/models/wondershow_gesture_model.json
```

## 理论基础和技术路线

当前不做端到端 RGB 手势检测。原因：

- 端到端检测需要大量标注图像、训练成本高、调试慢。
- MediaPipe Hand Landmarker 已经能稳定输出 21 个手部关键点。
- 本项目的问题主要是“有了 21 点后如何区分用户自定义手型”，适合训练轻量分类头。

采用路线：

```text
摄像头帧
  -> MediaPipe Hand Landmarker
  -> 每只手 21 点 landmarks
  -> 归一化特征
  -> 纯 NumPy MLP 分类器
  -> custom_gesture
  -> Swift 映射为 HandShape
  -> 翻页 / 缩放 / 揪取 / 抓握
```

参考依据：

- MediaPipe Gesture Recognizer 官方文档：
  https://ai.google.dev/edge/mediapipe/solutions/vision/gesture_recognizer
- MediaPipe 自定义手势模型文档：
  https://ai.google.dev/edge/mediapipe/solutions/customization/gesture_recognizer
  注意：官方 Model Maker 已标注不再积极维护，所以本项目先采用自维护的轻量 NumPy MLP。
- HaGRIDv2：
  https://arxiv.org/abs/2412.01508
  提供静态/动态手势数据集思路，说明真实场景、光照、手型变体对识别非常关键。
- SHREC 2017 3D Hand Gesture：
  https://hal.science/hal-01563505/file/17-EG3DOR-SHREC-Hand-Gesture-DeSmedt.pdf
  说明骨架/关键点序列适合动态手势识别。本项目第一阶段先做静态手型分类，动态意图由手型 + 运动轨迹处理。

## 样本采集目的

采样不是为了“拍好看的图”，而是为了覆盖实际使用中的变化：

- 左手 / 右手。
- 手心朝摄像头 / 手背朝摄像头 / 侧面。
- 手在画面中央、偏左、偏右。
- 离摄像头近一点、远一点。
- 真实光照、真实背景、真实摄像头。
- 用户实际做手势的自然姿势，而不是刻意摆拍。

特别重要：

- 剑指和枪指必须分清，因为枪指不应翻页。
- 揪取和抓握必须分清，因为揪取是缩放脉冲，抓握是拖拽平移。
- 八字和枪指可以都属于缩放姿态，但模型仍应能识别出标签，便于调试。

## 样本数量要求

第一轮最低建议：

```text
剑指：40 张
枪指：40 张
八字：40 张
揪取：40 张
抓握：40 张
开掌：40 张
```

更推荐：

```text
每类 80-120 张
```

每类样本分布建议：

```text
右手手心朝摄像头：10-20 张
右手手背朝摄像头：10-20 张
右手侧面/斜向：10-20 张
左手手心朝摄像头：10-20 张
左手手背朝摄像头：10-20 张
左手侧面/斜向：10-20 张
近距离/远距离：穿插采
```

图片要求：

- 一张图里尽量只出现一只目标手。
- 手要完整入镜，手指不要被画面裁掉。
- 背景可以真实杂乱，不必干净。
- 不要只用截图里的红字示意图，必须用真实摄像头场景。
- 图片可用 `.png`、`.jpg`、`.jpeg`、`.webp`。

## 文件夹和标签规则

训练脚本从“父文件夹名”或“文件名前缀”推断标签。

推荐直接按文件夹放：

```text
训练样本/剑指/001.png
训练样本/剑指/002.png
训练样本/枪指/001.png
训练样本/八字/001.png
训练样本/揪取/001.png
训练样本/抓握/001.png
训练样本/开掌/001.png
```

文件名随便，文件夹名最重要。

标签映射在：

```text
scripts/train_wondershow_gesture_model.py
```

当前支持：

```text
剑指 -> sword
枪指 / 指枪 -> finger_gun
八字 -> l_shape
揪取 -> pinch
抓握 / 握拳 -> grab
开掌 -> open_palm
自然 -> natural
```

## 训练方法

进入项目：

```bash
cd "/Users/aoke/code test/视频直播设备"
```

激活虚拟环境：

```bash
source .venv-mediapipe/bin/activate
```

训练：

```bash
python scripts/train_wondershow_gesture_model.py 训练样本
```

成功后会生成：

```text
sidecar/models/wondershow_gesture_model.json
```

训练成功输出示例：

```json
{
  "ok": true,
  "output": "sidecar/models/wondershow_gesture_model.json",
  "samples": 240,
  "labels": ["open_palm", "sword", "finger_gun", "l_shape", "pinch", "grab"],
  "train_accuracy": 0.98,
  "skipped": []
}
```

注意：

- `train_accuracy` 高不代表真实可用，尤其样本少时会虚高。
- 更重要的是实际打开 app 后，右侧“当前手型”是否显示正确。
- `skipped` 里如果有图片，说明 MediaPipe 没检测到手或标签不明，需要删掉或补拍。

## 训练失败排查

### no_images

没有找到图片。检查图片是否放在：

```text
训练样本/...
```

### need_at_least_two_labels

可用标签少于 2 类。通常是：

- 只有一个文件夹里有图。
- 文件夹名不在标签映射里。
- 大量图片没有检测到手。

### skipped 很多

说明图片质量或手部完整度不够。优先检查：

- 手是否完整入镜。
- 图片是否太暗、太糊。
- 是否一张图里有多只手或手太小。

## 训练后验证方法

训练完后：

1. 退出灵演。
2. 重新启动 sidecar / 重新打开 app。
3. 打开 `/Users/aoke/code test/视频直播设备/dist/灵演.app`。
4. 先不要测试翻页，先只看“当前手型”显示。

逐个摆：

```text
剑指 -> 应显示 剑指
枪指 -> 应显示 指枪
八字 -> 应显示 八字
揪取 -> 应显示 揪取
抓握 -> 应显示 握拳
开掌 -> 应显示 开掌
```

如果“当前手型”错，先不要调动作逻辑，继续补样本。

## 控制逻辑验收

手型显示正确后再测试控制：

```text
剑指左挥 / 右挥 -> 翻页
枪指单手 -> 不翻页
双手枪指或八字拉开 -> 放大
双手枪指或八字合拢 -> 缩小
单手开掌 -> 揪取 -> 脉冲缩小约 20%
单手揪取 -> 开掌 -> 脉冲放大约 20%
抓握移动 -> 平移画面
```

## 重要风险

当前模型是单帧手型分类器，不是完整时序动作模型。

也就是说：

- 它负责识别“这只手是什么形状”。
- 翻页、缩放、平移仍由 Swift 侧根据轨迹和状态判断。

如果静态手型已经稳定，但动态动作仍差，下一阶段应该训练时序模型：

```text
连续 N 帧 landmarks -> swipeLeft / swipeRight / zoomIn / zoomOut / pan
```

但当前第一目标是先把静态手型分类训准。

## 新任务提示词

下面这段可以直接复制到新任务：

```text
请读取并遵循 /Users/aoke/code test/视频直播设备/.trae/gesture-training-handoff-2026-06-17.md。

我要继续做灵演 WonderShow 的手势识别训练任务。当前项目已经有 MediaPipe 21 点 landmarks、Python sidecar、纯 NumPy MLP 分类器和训练脚本。请先理解交接文档里的背景、当前代码状态、训练目标、采样规范、训练命令和验收标准。

你的任务是手把手帮助我完成真实样本采集、训练、验证和下一轮迭代：
1. 检查训练样本目录是否正确。
2. 指导我把每类手势样本放到正确文件夹。
3. 运行训练脚本，读取训练输出。
4. 判断 skipped、samples、labels、train_accuracy 是否合理。
5. 如果模型过拟合或某类识别差，告诉我具体要补拍哪类、哪种角度、多少张。
6. 训练后验证 sidecar 是否加载 custom model。
7. 打开或指导打开 app，先验证“当前手型”显示，再验证翻页、缩放、揪取、抓握。

不要继续盲目调阈值。优先让自训练手型分类器学会用户真实手势。
```

