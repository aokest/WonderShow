# 灵演手势训练助手

## 当前实现

`scripts/gesture_training_assistant.py` 是独立训练工具，不依赖灵演主 App UI。它负责：

- 打开采样窗口并传入手势、光线、距离和连拍设置。
- 使用 `scripts/train_wondershow_gesture_model.py` 训练 `landmark_v2` 手势模型。
- 展示训练报告摘要，包括样本数、训练/验证准确率和跳过样本原因。
- 导出 `.wsgesture` 手势包，包内包含：
  - `manifest.json`
  - `model/wondershow_gesture_model.json`

默认工作目录在：

```text
~/Library/Application Support/WonderShow/GestureTrainingAssistant/<profile>/
```

启动方式：

```bash
.venv-mediapipe/bin/python scripts/gesture_training_assistant.py
```

构建独立 macOS App：

```bash
scripts/build-gesture-training-assistant-app.sh
```

## 主灵演 App 后续导入/管理接口设计

暂不修改主 App。后续接入时建议只增加一个独立的模型管理服务，不把训练依赖带入主 App。

### 导入流程

1. 用户在训练助手里导出 `.wsgesture`。
2. 主 App 的模型管理入口选择该文件。
3. 主 App 解压读取 `manifest.json`，校验：
   - `format == "wondershow.gesture-package"`
   - `format_version == 1`
   - `model.feature_schema == "landmark_v2"`
   - `model.path` 存在
4. 主 App 将模型复制到：

```text
~/Library/Application Support/WonderShow/GestureProfiles/<profile-id>/
```

5. 主 App 只加载 `wondershow_gesture_model.json`，不加载训练脚本、PyTorch 或 YOLO。

### 管理能力

- 列出已导入的手势模型包。
- 显示模型标签、特征版本、创建时间、训练样本数、验证准确率。
- 启用、停用、删除某个 profile。
- 支持回退到内置/仓库默认模型。
- 模型不可信或 schema 不兼容时拒绝加载，并提示用户重新训练。

### 运行时原则

- 主 App 仍只做推理，不做训练。
- `.wsgesture` 只是 zip 包格式，避免引入额外依赖。
- 导入失败不能影响演示、录屏、Dashboard 等主功能。
