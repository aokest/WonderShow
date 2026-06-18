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


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT_ROOT = PROJECT_ROOT / "训练样本"
IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp"}


@dataclass(frozen=True)
class GestureLabel:
    """A label supported by the WonderShow training pipeline."""

    key: str
    folder: str
    canonical: str
    display: str


LABELS = [
    GestureLabel("1", "剑指", "sword", "Sword"),
    GestureLabel("2", "枪指", "finger_gun", "Gun"),
    GestureLabel("3", "八字", "l_shape", "L-shape"),
    GestureLabel("4", "揪取", "pinch", "Pinch"),
    GestureLabel("5", "抓握", "grab", "Grab"),
    GestureLabel("6", "开掌", "open_palm", "Open"),
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
}

LABEL_BY_CANONICAL = {label.canonical: label for label in LABELS}


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


def next_sample_path(root: Path, label: GestureLabel, extension: str) -> Path:
    """Returns the next non-conflicting sample path for a label."""

    directory = root / label.folder
    pattern = re.compile(rf"^{re.escape(label.canonical)}_(\d+){re.escape(extension)}$")
    max_index = 0
    for path in directory.iterdir() if directory.exists() else []:
        match = pattern.match(path.name)
        if match:
            max_index = max(max_index, int(match.group(1)))
    return directory / f"{label.canonical}_{max_index + 1:04d}{extension}"


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


def overlay_lines(label: GestureLabel, counts: dict[str, int]) -> list[str]:
    """Builds ASCII-only overlay lines for OpenCV's limited text renderer."""

    return [
        f"Gesture Sampler | Current: {label.display} ({label.canonical})",
        "Click this window, then use keyboard shortcuts:",
        "Enter/Space=SAVE   1-6=switch gesture   C=camera   Q/Esc=quit",
        overlay_label_menu(),
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


def draw_overlay(frame, label: GestureLabel, root: Path) -> None:
    """Draws capture instructions on the preview frame."""

    counts = counts_by_label(root)
    lines = overlay_lines(label, counts)
    for offset, line in enumerate(lines):
        y = 28 + offset * 26
        cv2.putText(frame, line, (14, y), cv2.FONT_HERSHEY_SIMPLEX, 0.62, (0, 0, 0), 4, cv2.LINE_AA)
        cv2.putText(frame, line, (14, y), cv2.FONT_HERSHEY_SIMPLEX, 0.62, (255, 255, 255), 1, cv2.LINE_AA)


def save_frame(root: Path, label: GestureLabel, frame, extension: str) -> Path:
    """Writes the current camera frame to the label folder."""

    path = next_sample_path(root, label, extension)
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

    if args.list_cameras:
        return list_cameras(args.max_camera_index)

    current_label = select_initial_label(args.label)
    print_counts(output_root)
    print("[WonderShow] 采集窗口打开后，摆好动作，按 Enter 或空格保存当前帧。")
    print("[WonderShow] 可在预览窗口按 1-6 切换类别，按 c 切换摄像头，按 q 或 Esc 退出。")

    if args.dry_run:
        print(f"[WonderShow] dry-run: camera={args.camera} label={current_label.folder} output={output_root}")
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

    try:
        while True:
            ok, frame = capture.read()
            if not ok or frame is None:
                print("[WonderShow] 无法读取摄像头画面。", file=sys.stderr)
                return 1

            preview = frame.copy()
            draw_overlay(preview, current_label, output_root)
            if last_saved_path and time.monotonic() - last_saved_at < 1.2:
                text = f"Saved: {last_saved_path.name}"
                cv2.putText(preview, text, (14, preview.shape[0] - 24), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 0), 4, cv2.LINE_AA)
                cv2.putText(preview, text, (14, preview.shape[0] - 24), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (90, 255, 120), 2, cv2.LINE_AA)

            cv2.imshow(window_name, preview)
            key = cv2.waitKey(1) & 0xFF
            if key in (27, ord("q")):
                break
            if key in (13, 10, 32):
                last_saved_path = save_frame(output_root, current_label, frame, args.extension)
                last_saved_at = time.monotonic()
                print(f"[WonderShow] 已保存 {current_label.folder}: {last_saved_path}")
            elif ord("1") <= key <= ord("6"):
                current_label = resolve_label(chr(key))
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
    parser.add_argument("--label", help="Initial gesture label: 1-6, 剑指, 枪指, 八字, 揪取, 抓握, 开掌, or aliases.")
    parser.add_argument("--output-root", default=str(DEFAULT_OUTPUT_ROOT), help="Root folder containing per-label sample directories.")
    parser.add_argument("--extension", default=".jpg", choices=sorted(IMAGE_SUFFIXES), help="Saved image extension.")
    parser.add_argument("--width", type=int, help="Optional camera capture width.")
    parser.add_argument("--height", type=int, help="Optional camera capture height.")
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
