# WonderShow Community App 1.0.11 (20260623010720)

## 发布文件

- `releases/wondershow-community-1.0.11-20260623010720-macos.zip`
- `releases/wondershow-community-1.0.11-20260623010720-macos.zip.sha256`
- `releases/wondershow-core-1.0.11-20260623010720.zip`
- `releases/wondershow-core-1.0.11-20260623010720.zip.sha256`

社区版 zip 内只包含 `灵演社区版.app` 和三语社区版说明文档，不包含主 App `灵演.app`。

## 本版修复

- 预览合成和停止录制后的自动 `Exports/program.mp4` 默认使用 1080p 包络内的轻量渲染，降低默认流程的 CPU、内存和导出等待压力。
- 手动“导出视频”仍保留 4K 选择，不影响用户主动导出高清成片。
- 修复摄像头 raw 归档在切换设备或帧泵延迟时可能只写入极短视频的问题，按活跃录制时长补足讲者轨帧，避免后续合成时长异常。

## 验证

- `rtk swift test --disable-sandbox`：244 项测试通过。
- `rtk swift test --package-path open-source/wondershow-core`：21 项测试通过。
- `rtk bash scripts/build-app.sh`：主 App Release 构建通过，`dist/灵演.app` 为 `1.0.11 (20260623010720)`。
- `rtk bash scripts/package-community-app.sh`：社区版发布包生成成功，`dist/灵演社区版.app` 为 `1.0.11 (20260623010720)`。
- `rtk bash scripts/package-open-source-kit.sh`：开源 core 包生成成功。
- 两个发布 zip 的 `.sha256` 校验均通过。
