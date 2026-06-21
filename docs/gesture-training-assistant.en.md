# WonderShow Gesture Training Assistant

## Purpose

This tool collects, labels, and trains a personal static hand-shape model, then exports a `.wsgesture` package. It is independent from the main WonderShow app and does not change presentation, recording, or main-app UI behavior.

The current training target is static hand shape, not motion:

- Sword
- Finger Gun
- L-shape
- Pinch
- Grab
- Open Palm
- Unknown

Motion samples, such as swipe left, swipe right, two-hand zoom, and pan, should be collected later after static hand-shape recognition is stable.

## Launch

Launch from the terminal:

```bash
cd "/Users/aoke/code test/视频直播设备"
.venv-mediapipe/bin/python scripts/gesture_training_assistant.py
```

Build and open the standalone macOS app:

```bash
scripts/build-gesture-training-assistant-app.sh
open "dist/灵演手势训练助手.app"
```

## Sampling Workflow

1. Use the `简`, `繁`, or `EN` buttons in the header to switch the interface language.
2. Enter a Collector ID or name, such as `alice-01`. This value is included in image filenames so samples from different people remain traceable.
3. Choose the gesture label.
4. Choose a lighting tag: `normal`, `low_light`, or `backlight`.
5. Choose a distance tag: `near`, `mid`, or `far`.
6. If needed, enter an OpenCV camera index in the camera field; the default is `auto`.
7. For automatic collection, enable timed capture. For example, enter `1.0` to save one photo every 1 second.
8. Click "Open Sampler".
9. Save photos in the sampler window. When timed capture is enabled, hold the gesture and slowly vary the angle.
10. Return to the assistant and click "Refresh Counts".

Sampler shortcuts:

- `Enter` or `Space`: save one photo
- `B`: capture a burst
- `T`: toggle timed capture
- `1-7`: switch gesture label
- `C`: switch camera
- `Q` or `Esc`: exit the sampler

## Sampling Guidance

Start with `40-80` photos per gesture. Do not capture only one perfect pose. For each gesture, try to cover:

- Left and right hands
- Palm-facing and slightly rotated hands
- Normal light, low light, and backlight
- Near, mid, and far distance
- Built-in camera and the external cameras you may use in real talks

Far-distance samples depend heavily on the camera. If the sampler shows `hand_too_small`, `blurry`, or `low_light`, that device and distance combination is risky.

Timed capture is useful for quickly adding many static samples of the same hand shape. Capture one gesture label at a time. With a 1-second interval, spend 20-60 seconds slowly changing hand side, wrist angle, distance, and lighting instead of staying perfectly still.

When a Collector ID is set, filenames look like `alice-01_sword_low_light_far_0001.jpg`. Do not use sensitive personal data such as government IDs or phone numbers.

## Unknown Class

`Unknown` is the negative-sample class. It is important. Capture:

- Natural hands
- Half-fists
- Hands without a clear gesture
- Empty frames or background interference
- Poses that may be mistaken for Sword, Finger Gun, or L-shape

Unknown samples reduce false triggers during presentations.

## Training And Export

After collecting samples:

1. Click "Train Model".
2. Review the status and report summary.
3. If some classes are confused, collect more samples for those classes and train again.
4. Click "Export Package" to create a `.wsgesture` package.

Default workspace:

```text
~/Library/Application Support/WonderShow/GestureTrainingAssistant/<profile>/
```

Folder layout:

```text
Samples/   captured images
Models/    trained wondershow_gesture_model.json
Exports/   exported .wsgesture packages
```

## Future Main-App Import Design

The main WonderShow app should import only the `.wsgesture` package. It should not include training scripts, PyTorch, YOLO, or the sampler. During import, validate:

- `format == "wondershow.gesture-package"`
- `format_version == 1`
- `model.feature_schema == "landmark_v2"`
- the model file exists and can be loaded

Import failure must not affect presentation, recording, Dashboard, or other main app functionality.
