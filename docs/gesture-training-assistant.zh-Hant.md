# 靈演手勢訓練助手

## 適用場景

這個工具用於採集、標記、訓練個人靜態手型模型，並匯出 `.wsgesture` 手勢包。它獨立於靈演主 App，不會修改主 App 的簡報、錄影或 UI 功能。

目前訓練的是靜態手型，不是動態動作：

- 劍指
- 槍指
- 八字
- 揪取
- 抓握
- 開掌
- 未知

動態動作，例如左揮、右揮、雙手縮放和平移，會在靜態手型穩定後再採集。

## 啟動

命令列啟動：

```bash
cd "/Users/aoke/code test/視頻直播設備"
.venv-mediapipe/bin/python scripts/gesture_training_assistant.py
```

建置並開啟獨立 macOS App：

```bash
scripts/build-gesture-training-assistant-app.sh
open "dist/灵演手势训练助手.app"
```

## 採樣流程

1. 在頂欄點擊 `簡`、`繁` 或 `EN` 切換介面語言。
2. 填寫採樣人 ID 或姓名，例如 `alice-01`。這個值會進入圖片檔名，方便多人採集後區分來源。
3. 選擇手勢類別。
4. 選擇光線標籤：`normal`、`low_light`、`backlight`。
5. 選擇距離標籤：`near`、`mid`、`far`。
6. 如果要指定攝影機，在攝影機輸入框填寫 OpenCV 攝影機編號；預設 `auto`。
7. 如果想自動採集，勾選「定時拍攝」，例如間隔填 `1.0` 表示每 1 秒儲存一張。
8. 點擊「開啟採樣視窗」。
9. 在採樣視窗裡儲存圖片；定時拍攝開啟後，保持手勢並緩慢變換角度即可。
10. 回到訓練助手，點擊「重新整理樣本數」。

採樣視窗快捷鍵：

- `Enter` 或 `Space`：儲存單張圖片
- `B`：連拍
- `T`：開關定時拍攝
- `1-7`：切換手勢類別
- `C`：切換攝影機
- `Q` 或 `Esc`：退出採樣視窗

## 採樣建議

每個手勢先採 `40-80` 張。不要只拍一個標準姿勢，同一類手勢要覆蓋：

- 左手和右手
- 掌心朝鏡頭和輕微側轉
- 正常光線、弱光、背光
- 近距離、中距離、遠距離
- 內建攝影機和未來實際使用的外接攝影機

遠距離樣本尤其依賴攝影機。如果採樣視窗提示 `hand_too_small`、`blurry` 或 `low_light`，代表這個設備和距離組合本身風險較高。

定時拍攝適合快速補充同一類靜態手型。建議每次只採一個手勢類別，開啟 1 秒一張後，在 20-60 秒內慢慢改變左右手、手腕角度、距離和光線，而不是完全不動。

填寫採樣人 ID 後，圖片會採用類似 `alice-01_sword_low_light_far_0001.jpg` 的命名方式。不要在 ID 中放身分證號、手機號等敏感資訊。

## 未知類別

`未知` 是負樣本類別，很重要。建議採：

- 自然手
- 半握拳
- 沒有明確手勢的手
- 空手或背景干擾
- 容易被誤判成劍指、槍指、八字的姿勢

未知樣本可以降低演講過程中的誤觸發。

## 訓練和匯出

樣本採集完成後：

1. 點擊「開始訓練」。
2. 查看狀態和報告摘要。
3. 如果某些類別混淆嚴重，補採對應類別後重新訓練。
4. 點擊「匯出手勢包」，生成 `.wsgesture`。

預設工作目錄：

```text
~/Library/Application Support/WonderShow/GestureTrainingAssistant/<profile>/
```

目錄內容：

```text
Samples/   採樣圖片
Models/    訓練後的 wondershow_gesture_model.json
Exports/   匯出的 .wsgesture 手勢包
```

## 主靈演 App 後續匯入設計

主靈演 App 後續只需要匯入 `.wsgesture`，不需要攜帶訓練腳本、PyTorch、YOLO 或採樣工具。建議匯入時校驗：

- `format == "wondershow.gesture-package"`
- `format_version == 1`
- `model.feature_schema == "landmark_v2"`
- 模型檔存在且可載入

匯入失敗不能影響簡報、錄影、Dashboard 等主功能。
