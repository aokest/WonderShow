# WonderShow Community App 1.0.0 (20260621162412)

本说明对应本地发布包：

- `releases/wondershow-community-1.0.0-20260621162412-macos.zip`
- `releases/wondershow-community-1.0.0-20260621162412-macos.zip.sha256`

## 定位

社区版是可双击运行的实用录制器，用于配合开源项目体验 WonderShow 的基础录制工作流。它不是商业版完整 App，也不包含当前尚未稳定的人像增强实验能力。

## 社区版包含

- 摄像头预览与摄像头原始轨录制
- 屏幕/窗口录制源选择
- 麦克风录制
- 录制项目生成、预览合成、视频导出
- 画布比例与导出清晰度选择
- 讲者画面基础调整：镜像、亮度、对比
- 关于页支持作者二维码

## 社区版不包含

- VIP/SVIP 权益 UI 和付费等级选择
- 手势控制、彩排控制、手势校准、手势速查、测试演示页入口
- 高级美颜、背景虚化/替换、Emoji 替脸、瘦脸、大眼等实验人像能力
- MediaPipe sidecar、手势模型、demo HTML 资源
- 商业版授权、付费、更新、专属支持逻辑

## 发布前检查

- `swift test --disable-sandbox`：199 个测试通过
- `swift test --disable-sandbox -Xswiftc -DWONDERSHOW_COMMUNITY --filter 'CommunityEditionTests|AppBundlePackagingTests|RecordingSourceSlotTests'`：17 个社区版边界测试通过
- `codesign --verify --deep --strict --verbose=2 dist/灵演社区版.app`：通过
- `codesign -dvvv`：ad-hoc 签名，Hardened Runtime 已启用
- `unzip -t releases/wondershow-community-1.0.0-20260621162412-macos.zip`：通过
- 包内容检查：未包含 `wondershow-demo.html`、`sidecar/`、`wondershow_gesture_model.json`、`__MACOSX`、`.DS_Store`
- 字符串扫描：未发现常见密钥、固定 token、本机路径或 NAS/Gitea 凭据

## 安全与逆向说明

macOS Swift 应用无法从技术上彻底防止逆向。当前社区版已经移除用户可见入口、运行链路和发布资源，并对 Release 二进制做了 strip 与 Hardened Runtime 签名。

由于当前仍复用主 App target，二进制中可能残留部分共享类型名、历史本地化 key 或未调用实现的符号名。若下一步要进一步降低逆向可见面，需要拆出独立 `WonderShowCommunityApp` target，只编译社区版实际需要的录制、预览、导出和基础 UI 文件。

正式对外分发前，建议使用 Apple Developer ID 证书重新签名并完成 notarization。
