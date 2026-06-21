#!/usr/bin/env python3
"""Capture labeled WonderShow gesture samples from a local camera."""

from __future__ import annotations

import argparse
import re
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

import cv2
import numpy as np


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT_ROOT = PROJECT_ROOT / "训练样本"
IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp"}
MIN_TIMED_INTERVAL_SECONDS = 0.2


@dataclass(frozen=True)
class GestureLabel:
    """A label supported by the WonderShow training pipeline."""

    key: str
    folder: str
    canonical: str
    display: str


@dataclass(frozen=True)
class CaptureTags:
    """Optional environment tags encoded into sample filenames."""

    light: str = "normal"
    distance: str = "near"

    def filename_token(self) -> str:
        """Returns a compact token for filenames."""

        if self.light == "normal" and self.distance == "near":
            return ""
        return f"{self.light}_{self.distance}"


@dataclass(frozen=True)
class FrameQuality:
    """Lightweight quality metrics shown during sample capture."""

    brightness: float
    contrast: float
    blur: float
    overexposed_ratio: float
    underexposed_ratio: float
    hand_box_ratio: float | None
    flags: tuple[str, ...]


LABELS = [
    GestureLabel("1", "剑指", "sword", "Sword"),
    GestureLabel("2", "枪指", "finger_gun", "Gun"),
    GestureLabel("3", "八字", "l_shape", "L-shape"),
    GestureLabel("4", "揪取", "pinch", "Pinch"),
    GestureLabel("5", "抓握", "grab", "Grab"),
    GestureLabel("6", "开掌", "open_palm", "Open"),
    GestureLabel("7", "未知", "unknown", "Unknown"),
]

ALIASES = {
    "1": "sword",
    "剑指": "sword",
    "sword": "sword",
    "2": "finger_gun",
    "枪指": "finger_gun",
    "指枪": "finger_gun",
    "finger_gun": "finger_gun",
    "gun": "finger_gun",
    "3": "l_shape",
    "八字": "l_shape",
    "l": "l_shape",
    "l_shape": "l_shape",
    "4": "pinch",
    "揪取": "pinch",
    "pinch": "pinch",
    "5": "grab",
    "抓握": "grab",
    "握拳": "grab",
    "grab": "grab",
    "fist": "grab",
    "6": "open_palm",
    "开掌": "open_palm",
    "open": "open_palm",
    "open_palm": "open_palm",
    "7": "unknown",
    "未知": "unknown",
    "负样本": "unknown",
    "unknown": "unknown",
    "other": "unknown",
    "negative": "unknown",
    "none": "unknown",
}

LABEL_BY_CANONICAL = {label.canonical: label for label in LABELS}
LIGHT_TAGS = {"normal", "low_light", "backlight"}
DISTANCE_TAGS = {"near", "mid", "far"}


def resolve_label(value: str) -> GestureLabel:
    """Converts user input into a supported gesture label."""

    normalized = value.strip().lower().replace("-", "_")
    canonical = ALIASES.get(normalized) or ALIASES.get(value.strip())
    if not canonical:
        raise ValueError(f"Unknown gesture label: {value}")
    return LABEL_BY_CANONICAL[canonical]


def ensure_sample_directories(root: Path) -> None:
    """Creates one sample directory for each supported hand shape."""

    for label in LABELS:
        (root / label.folder).mkdir(parents=True, exist_ok=True)


def counts_by_label(root: Path) -> dict[str, int]:
    """Counts image files in each gesture sample directory."""

    counts: dict[str, int] = {}
    for label in LABELS:
        directory = root / label.folder
        counts[label.folder] = sum(
            1
            for path in directory.rglob("*")
            if path.is_file() and path.suffix.lower() in IMAGE_SUFFIXES
        ) if directory.exists() else 0
    return counts


def parse_capture_tags(value: str | None) -> CaptureTags:
    """Parses comma-separated light/distance tags."""

    if not value:
        return CaptureTags()
    light = "normal"
    distance = "near"
    for raw_part in value.split(","):
        part = raw_part.strip().lower().replace("-", "_")
        if not part:
            continue
        if part in LIGHT_TAGS:
            light = part
        elif part in DISTANCE_TAGS:
            distance = part
        else:
            raise ValueError(f"Unknown capture tag: {raw_part.strip()}")
    return CaptureTags(light=light, distance=distance)


def sanitize_subject_id(value: str | None) -> str:
    """Returns a filename-safe collector identifier."""

    if not value:
        return ""
    normalized = value.strip()
    if not normalized:
        return ""
    normalized = re.sub(r"[^\w.-]+", "_", normalized, flags=re.UNICODE)
    normalized = normalized.strip("._-")
    return normalized[:48]


def sample_prefix(label: GestureLabel, *, tags: CaptureTags | None = None, subject_id: str | None = None) -> str:
    """Builds the filename prefix used for captured samples."""

    parts = [label.canonical]
    token = tags.filename_token() if tags else ""
    if token:
        parts.append(token)
    safe_subject = sanitize_subject_id(subject_id)
    if safe_subject:
        parts.insert(0, safe_subject)
    return "_".join(parts)


def next_sample_path(
    root: Path,
    label: GestureLabel,
    extension: str,
    *,
    tags: CaptureTags | None = None,
    subject_id: str | None = None,
) -> Path:
    """Returns the next non-conflicting sample path for a label."""

    directory = root / label.folder
    prefix = sample_prefix(label, tags=tags, subject_id=subject_id)
    pattern = re.compile(rf"^{re.escape(prefix)}_(\d+){re.escape(extension)}$")
    max_index = 0
    for path in directory.iterdir() if directory.exists() else []:
        match = pattern.match(path.name)
        if match:
            max_index = max(max_index, int(match.group(1)))
    return directory / f"{prefix}_{max_index + 1:04d}{extension}"


def label_menu() -> str:
    """Builds the label picker text shown in the terminal."""

    return "  ".join(f"{label.key}:{label.folder}" for label in LABELS)


def overlay_label_menu() -> str:
    """Builds an ASCII-only label picker for OpenCV text rendering."""

    return "  ".join(f"{label.key}:{label.display}" for label in LABELS)


def print_counts(root: Path) -> None:
    """Prints a compact count summary."""

    counts = counts_by_label(root)
    summary = "  ".join(f"{folder}:{count}" for folder, count in counts.items())
    print(f"[WonderShow] 当前样本数量: {summary}")


def quality_summary(metrics: FrameQuality | None) -> str:
    """Builds an ASCII quality summary for OpenCV overlay."""

    if metrics is None:
        return "Quality: measuring"
    flags = ",".join(metrics.flags) if metrics.flags else "ok"
    hand = "n/a" if metrics.hand_box_ratio is None else f"{metrics.hand_box_ratio:.3f}"
    return (
        f"Quality: light={metrics.brightness:.0f} contrast={metrics.contrast:.0f} "
        f"blur={metrics.blur:.0f} hand={hand} flags={flags}"
    )


def overlay_lines(
    label: GestureLabel,
    counts: dict[str, int],
    *,
    tags: CaptureTags | None = None,
    quality: FrameQuality | None = None,
    burst_count: int = 1,
    timed_capture_enabled: bool = False,
    timed_interval_seconds: float = 1.0,
    subject_id: str | None = None,
) -> list[str]:
    """Builds ASCII-only overlay lines for OpenCV's limited text renderer."""

    tags = tags or CaptureTags()
    timed_state = "on" if timed_capture_enabled else "off"
    subject_label = sanitize_subject_id(subject_id) or "none"
    return [
        f"Gesture Sampler | Current: {label.display} ({label.canonical})",
        "Click this window, then use keyboard shortcuts:",
        "Enter/Space=SAVE   B=burst   T=timed   1-7=switch gesture   C=camera   Q/Esc=quit",
        overlay_label_menu(),
        f"Subject: {subject_label}   Tags: light={tags.light} distance={tags.distance} burst={burst_count}",
        f"Timed: {timed_state} every {timed_interval_seconds:.1f}s",
        quality_summary(quality),
        "Counts: " + " ".join(f"{item.display}:{counts[item.folder]}" for item in LABELS),
        "Tip: save one clear single-hand photo each time.",
    ]


def list_cameras(max_index: int) -> int:
    """Probes camera indices and prints the indices that can produce a frame."""

    found = 0
    for index in range(max_index + 1):
        capture = cv2.VideoCapture(index)
        ok, frame = capture.read()
        capture.release()
        if ok and frame is not None:
            height, width = frame.shape[:2]
            print(f"{index}: 可用 ({width}x{height})")
            found += 1
        else:
            print(f"{index}: 不可用")
    return 0 if found else 1


def parse_camera_value(value: str) -> int | Literal["auto"]:
    """Parses a camera argument into an OpenCV index or auto-detection mode."""

    normalized = value.strip().lower()
    if normalized == "auto":
        return "auto"
    try:
        camera_index = int(normalized)
    except ValueError as exc:
        raise ValueError(f"Camera must be an index or 'auto': {value}") from exc
    if camera_index < 0:
        raise ValueError(f"Camera index must be non-negative: {value}")
    return camera_index


def first_available_camera(max_index: int) -> int | None:
    """Returns the first camera index that can produce a frame."""

    for index in range(max_index + 1):
        capture = cv2.VideoCapture(index)
        ok, frame = capture.read()
        capture.release()
        if ok and frame is not None:
            return index
    return None


def next_available_camera(current_index: int, max_index: int) -> int | None:
    """Returns the next available camera after the current index, wrapping around."""

    for offset in range(1, max_index + 2):
        index = (current_index + offset) % (max_index + 1)
        capture = cv2.VideoCapture(index)
        ok, frame = capture.read()
        capture.release()
        if ok and frame is not None:
            return index
    return None


def open_camera(index: int, width: int | None, height: int | None) -> cv2.VideoCapture:
    """Opens a camera and applies optional dimensions."""

    capture = cv2.VideoCapture(index)
    if width:
        capture.set(cv2.CAP_PROP_FRAME_WIDTH, width)
    if height:
        capture.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
    return capture


def estimate_frame_quality(frame, hand_box: tuple[int, int, int, int] | None = None) -> FrameQuality:
    """Estimates capture quality without running a hand detector."""

    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    brightness = float(np.mean(gray))
    contrast = float(np.std(gray))
    blur = float(cv2.Laplacian(gray, cv2.CV_64F).var())
    overexposed_ratio = float(np.mean(gray >= 245))
    underexposed_ratio = float(np.mean(gray <= 25))
    hand_box_ratio: float | None = None
    if hand_box:
        _, _, width, height = hand_box
        frame_area = max(1, frame.shape[0] * frame.shape[1])
        hand_box_ratio = float((width * height) / frame_area)

    flags: list[str] = []
    if brightness < 45 or underexposed_ratio > 0.35:
        flags.append("low_light")
    if brightness > 215 or overexposed_ratio > 0.18:
        flags.append("overexposed")
    if contrast < 18:
        flags.append("low_contrast")
    if blur < 40:
        flags.append("blurry")
    if hand_box_ratio is not None and hand_box_ratio < 0.018:
        flags.append("hand_too_small")

    return FrameQuality(
        brightness=brightness,
        contrast=contrast,
        blur=blur,
        overexposed_ratio=overexposed_ratio,
        underexposed_ratio=underexposed_ratio,
        hand_box_ratio=hand_box_ratio,
        flags=tuple(flags),
    )


def center_hand_box(frame) -> tuple[int, int, int, int]:
    """Returns a conservative central hand-size proxy for quality guidance."""

    height, width = frame.shape[:2]
    box_width = max(1, int(width * 0.18))
    box_height = max(1, int(height * 0.24))
    return ((width - box_width) // 2, (height - box_height) // 2, box_width, box_height)


def draw_overlay(
    frame,
    label: GestureLabel,
    root: Path,
    *,
    tags: CaptureTags | None = None,
    quality: FrameQuality | None = None,
    burst_count: int = 1,
    timed_capture_enabled: bool = False,
    timed_interval_seconds: float = 1.0,
    subject_id: str | None = None,
) -> None:
    """Draws capture instructions on the preview frame."""

    counts = counts_by_label(root)
    lines = overlay_lines(
        label,
        counts,
        tags=tags,
        quality=quality,
        burst_count=burst_count,
        timed_capture_enabled=timed_capture_enabled,
        timed_interval_seconds=timed_interval_seconds,
        subject_id=subject_id,
    )
    for offset, line in enumerate(lines):
        y = 28 + offset * 26
        cv2.putText(frame, line, (14, y), cv2.FONT_HERSHEY_SIMPLEX, 0.62, (0, 0, 0), 4, cv2.LINE_AA)
        cv2.putText(frame, line, (14, y), cv2.FONT_HERSHEY_SIMPLEX, 0.62, (255, 255, 255), 1, cv2.LINE_AA)


def save_frame(
    root: Path,
    label: GestureLabel,
    frame,
    extension: str,
    *,
    tags: CaptureTags | None = None,
    subject_id: str | None = None,
) -> Path:
    """Writes the current camera frame to the label folder."""

    path = next_sample_path(root, label, extension, tags=tags, subject_id=subject_id)
    ok = cv2.imwrite(str(path), frame)
    if not ok:
        raise RuntimeError(f"Failed to save image: {path}")
    return path


def select_initial_label(value: str | None) -> GestureLabel:
    """Prompts for a gesture label when one was not supplied on the command line."""

    if value:
        return resolve_label(value)

    while True:
        print(f"请选择当前要采集的手势类别：{label_menu()}")
        choice = input("类别: ").strip()
        try:
            return resolve_label(choice)
        except ValueError as exc:
            print(f"[WonderShow] {exc}")


def run_capture(args: argparse.Namespace) -> int:
    """Runs the interactive camera capture loop."""

    output_root = Path(args.output_root)
    ensure_sample_directories(output_root)
    try:
        tags = parse_capture_tags(args.tags)
    except ValueError as exc:
        print(f"[WonderShow] {exc}", file=sys.stderr)
        return 1

    if args.list_cameras:
        return list_cameras(args.max_camera_index)

    if args.timed_interval_seconds < MIN_TIMED_INTERVAL_SECONDS:
        print(
            f"[WonderShow] 定时拍摄间隔不能小于 {MIN_TIMED_INTERVAL_SECONDS:.1f} 秒。",
            file=sys.stderr,
        )
        return 1

    current_label = select_initial_label(args.label)
    timed_interval_seconds = float(args.timed_interval_seconds)
    timed_capture_enabled = bool(args.timed_start)
    subject_id = sanitize_subject_id(args.subject_id)
    print_counts(output_root)
    print("[WonderShow] 采集窗口打开后，摆好动作，按 Enter 或空格保存当前帧。")
    print("[WonderShow] 可在预览窗口按 1-7 切换类别，按 b 连拍，按 t 开关定时拍摄，按 c 切换摄像头，按 q 或 Esc 退出。")
    print(
        f"[WonderShow] 定时拍摄: {'已开启' if timed_capture_enabled else '未开启'}，"
        f"间隔 {timed_interval_seconds:.1f} 秒。"
    )
    if subject_id:
        print(f"[WonderShow] 采样人 ID: {subject_id}")

    if args.dry_run:
        print(
            f"[WonderShow] dry-run: camera={args.camera} label={current_label.folder} "
            f"tags={tags.light},{tags.distance} burst={args.burst_count} "
            f"subject={subject_id or 'none'} "
            f"timed={'on' if timed_capture_enabled else 'off'} interval={timed_interval_seconds:.1f}s "
            f"output={output_root}"
        )
        return 0

    try:
        camera = parse_camera_value(str(args.camera))
    except ValueError as exc:
        print(f"[WonderShow] {exc}", file=sys.stderr)
        return 1

    if camera == "auto":
        camera_index = first_available_camera(args.max_camera_index)
        if camera_index is None:
            print("[WonderShow] 没有找到可用摄像头。请检查系统相机权限。", file=sys.stderr)
            return 1
    else:
        camera_index = camera

    capture = open_camera(camera_index, args.width, args.height)

    if not capture.isOpened():
        print(f"[WonderShow] 无法打开摄像头 index={camera_index}。可先运行 --list-cameras 查看。", file=sys.stderr)
        return 1

    window_name = "WonderShow gesture sampler"
    print(f"[WonderShow] 当前摄像头 index={camera_index}")
    last_saved_path: Path | None = None
    last_saved_at = 0.0
    last_timed_saved_at = time.monotonic()

    try:
        while True:
            ok, frame = capture.read()
            if not ok or frame is None:
                print("[WonderShow] 无法读取摄像头画面。", file=sys.stderr)
                return 1

            now = time.monotonic()
            if timed_capture_enabled and now - last_timed_saved_at >= timed_interval_seconds:
                last_saved_path = save_frame(output_root, current_label, frame, args.extension, tags=tags, subject_id=subject_id)
                last_saved_at = now
                last_timed_saved_at = now
                print(f"[WonderShow] 定时保存 {current_label.folder}: {last_saved_path}")

            preview = frame.copy()
            quality = estimate_frame_quality(frame, center_hand_box(frame))
            draw_overlay(
                preview,
                current_label,
                output_root,
                tags=tags,
                quality=quality,
                burst_count=args.burst_count,
                timed_capture_enabled=timed_capture_enabled,
                timed_interval_seconds=timed_interval_seconds,
                subject_id=subject_id,
            )
            if last_saved_path and time.monotonic() - last_saved_at < 1.2:
                text = f"Saved: {last_saved_path.name}"
                cv2.putText(preview, text, (14, preview.shape[0] - 24), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 0), 4, cv2.LINE_AA)
                cv2.putText(preview, text, (14, preview.shape[0] - 24), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (90, 255, 120), 2, cv2.LINE_AA)

            cv2.imshow(window_name, preview)
            key = cv2.waitKey(1) & 0xFF
            if key in (27, ord("q")):
                break
            if key in (13, 10, 32):
                last_saved_path = save_frame(output_root, current_label, frame, args.extension, tags=tags, subject_id=subject_id)
                last_saved_at = time.monotonic()
                last_timed_saved_at = last_saved_at
                print(f"[WonderShow] 已保存 {current_label.folder}: {last_saved_path}")
            elif key == ord("b"):
                for _ in range(max(1, args.burst_count)):
                    ok, burst_frame = capture.read()
                    if not ok or burst_frame is None:
                        break
                    last_saved_path = save_frame(output_root, current_label, burst_frame, args.extension, tags=tags, subject_id=subject_id)
                    last_saved_at = time.monotonic()
                    last_timed_saved_at = last_saved_at
                    print(f"[WonderShow] 连拍保存 {current_label.folder}: {last_saved_path}")
                    time.sleep(max(0.0, args.burst_interval_ms / 1_000))
            elif key in (ord("t"), ord("T")):
                timed_capture_enabled = not timed_capture_enabled
                last_timed_saved_at = time.monotonic()
                state = "开启" if timed_capture_enabled else "关闭"
                print(f"[WonderShow] 定时拍摄已{state}，间隔 {timed_interval_seconds:.1f} 秒。")
            elif ord("1") <= key <= ord("7"):
                current_label = resolve_label(chr(key))
                last_timed_saved_at = time.monotonic()
                print(f"[WonderShow] 当前类别切换为: {current_label.folder}")
            elif key == ord("c"):
                next_index = next_available_camera(camera_index, args.max_camera_index)
                if next_index is None or next_index == camera_index:
                    print("[WonderShow] 没有找到其他可用摄像头。")
                    continue
                capture.release()
                capture = open_camera(next_index, args.width, args.height)
                if not capture.isOpened():
                    print(f"[WonderShow] 无法切换到摄像头 index={next_index}。", file=sys.stderr)
                    capture = open_camera(camera_index, args.width, args.height)
                    continue
                camera_index = next_index
                last_timed_saved_at = time.monotonic()
                print(f"[WonderShow] 当前摄像头切换为 index={camera_index}")
    finally:
        capture.release()
        cv2.destroyAllWindows()

    print_counts(output_root)
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    """Parses command-line arguments."""

    parser = argparse.ArgumentParser(description="Capture labeled WonderShow gesture training samples")
    parser.add_argument("--camera", default="0", help="OpenCV camera index, or 'auto' to use the first available camera.")
    parser.add_argument("--label", help="Initial gesture label: 1-7, 剑指, 枪指, 八字, 揪取, 抓握, 开掌, 未知, or aliases.")
    parser.add_argument("--output-root", default=str(DEFAULT_OUTPUT_ROOT), help="Root folder containing per-label sample directories.")
    parser.add_argument("--extension", default=".jpg", choices=sorted(IMAGE_SUFFIXES), help="Saved image extension.")
    parser.add_argument("--width", type=int, help="Optional camera capture width.")
    parser.add_argument("--height", type=int, help="Optional camera capture height.")
    parser.add_argument("--tags", default="normal,near", help="Comma-separated capture tags: normal, low_light, backlight, near, mid, far.")
    parser.add_argument("--subject-id", default="", help="Optional collector ID or name included in sample filenames.")
    parser.add_argument("--burst-count", type=int, default=5, help="Number of frames saved when pressing B.")
    parser.add_argument("--burst-interval-ms", type=int, default=120, help="Delay between burst samples.")
    parser.add_argument(
        "--timed-interval-seconds",
        type=float,
        default=1.0,
        help="Seconds between automatic saves when timed capture is enabled.",
    )
    parser.add_argument("--timed-start", action="store_true", help="Start timed capture when the sampler opens.")
    parser.add_argument("--list-cameras", action="store_true", help="Probe camera indices and exit.")
    parser.add_argument("--max-camera-index", type=int, default=5, help="Highest camera index to probe with --list-cameras.")
    parser.add_argument("--dry-run", action="store_true", help="Create directories and print settings without opening the camera.")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    """Entrypoint."""

    args = parse_args(argv)
    return run_capture(args)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
