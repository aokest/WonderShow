# 灵演手势训练助手

## 适用场景

这个工具用于采集、标记、训练个人静态手型模型，并导出 `.wsgesture` 手势包。它独立于灵演主 App，不会修改主 App 的演示、录屏或 UI 功能。

当前训练的是静态手型，不是动态动作：

- 剑指
- 枪指
- 八字
- 揪取
- 抓握
- 开掌
- 未知

动态动作，例如左挥、右挥、双手缩放和平移，会在静态手型稳定后再采集。

## 启动

命令行启动：

```bash
cd "/Users/aoke/code test/视频直播设备"
.venv-mediapipe/bin/python scripts/gesture_training_assistant.py
```

构建并打开独立 macOS App：

```bash
scripts/build-gesture-training-assistant-app.sh
open "dist/灵演手势训练助手.app"
```

## 采样流程

1. 在顶栏点击 `简`、`繁` 或 `EN` 切换界面语言。
2. 填写采样人 ID 或姓名，例如 `alice-01`。这个值会进入图片文件名，方便多人采集后区分来源。
3. 选择手势类别。
4. 选择光线标签：`normal`、`low_light`、`backlight`。
5. 选择距离标签：`near`、`mid`、`far`。
6. 如果要指定摄像头，在摄像头输入框填写 OpenCV 摄像头编号；默认 `auto`。
7. 如果想自动采集，勾选“定时拍摄”，例如间隔填 `1.0` 表示每 1 秒保存一张。
8. 点击“打开采样窗口”。
9. 在采样窗口里保存图片；定时拍摄开启后，保持手势并缓慢变换角度即可。
10. 回到训练助手，点击“刷新样本数”。

采样窗口快捷键：

- `Enter` 或 `Space`：保存单张图片
- `B`：连拍
- `T`：开关定时拍摄
- `1-7`：切换手势类别
- `C`：切换摄像头
- `Q` 或 `Esc`：退出采样窗口

## 采样建议

每个手势先采 `40-80` 张。不要只拍一个标准姿势，同一类手势要覆盖：

- 左手和右手
- 掌心朝镜头和轻微侧转
- 正常光线、弱光、背光
- 近距离、中距离、远距离
- 内置摄像头和未来实际使用的外接摄像头

远距离样本尤其依赖摄像头。如果采样窗口提示 `hand_too_small`、`blurry` 或 `low_light`，说明这个设备和距离组合本身风险较高。

定时拍摄适合快速补充同一类静态手型。建议每次只采一个手势类别，开启 1 秒一张后，在 20-60 秒内慢慢改变左右手、手腕角度、距离和光照，而不是完全不动。

填写采样人 ID 后，图片会采用类似 `alice-01_sword_low_light_far_0001.jpg` 的命名方式。不要在 ID 中放身份证号、手机号等敏感信息。

## 未知类别

`未知` 是负样本类别，很重要。建议采：

- 自然手
- 半握拳
- 没有明确手势的手
- 空手或背景干扰
- 容易被误判成剑指、枪指、八字的姿势

未知样本可以降低演讲过程中的误触发。

## 训练和导出

样本采集完成后：

1. 点击“开始训练”。
2. 查看状态和报告摘要。
3. 如果某些类别混淆严重，补采对应类别后重新训练。
4. 点击“导出手势包”，生成 `.wsgesture`。

默认工作目录：

```text
~/Library/Application Support/WonderShow/GestureTrainingAssistant/<profile>/
```

目录内容：

```text
Samples/   采样图片
Models/    训练后的 wondershow_gesture_model.json
Exports/   导出的 .wsgesture 手势包
```

## 主灵演 App 后续导入设计

主灵演 App 后续只需要导入 `.wsgesture`，不需要携带训练脚本、PyTorch、YOLO 或采样工具。建议导入时校验：

- `format == "wondershow.gesture-package"`
- `format_version == 1`
- `model.feature_schema == "landmark_v2"`
- 模型文件存在且可加载

导入失败不能影响演示、录屏、Dashboard 等主功能。
