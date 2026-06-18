#!/usr/bin/env python3
"""Train WonderShow's custom hand-shape classifier from labeled images."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

import cv2
import mediapipe as mp
import numpy as np

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT / "sidecar") not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT / "sidecar"))

from gesture_model import DEFAULT_LABELS, GestureMLP, landmark_feature_vector, train_mlp


BaseOptions = mp.tasks.BaseOptions
HandLandmarker = mp.tasks.vision.HandLandmarker
HandLandmarkerOptions = mp.tasks.vision.HandLandmarkerOptions
VisionRunningMode = mp.tasks.vision.RunningMode


LABEL_ALIASES = {
    "开掌": "open_palm",
    "open": "open_palm",
    "open_palm": "open_palm",
    "剑指": "sword",
    "sword": "sword",
    "枪指": "finger_gun",
    "指枪": "finger_gun",
    "finger_gun": "finger_gun",
    "gun": "finger_gun",
    "八字": "l_shape",
    "l": "l_shape",
    "l_shape": "l_shape",
    "揪取": "pinch",
    "pinch": "pinch",
    "抓握": "grab",
    "grab": "grab",
    "握拳": "grab",
    "fist": "grab",
    "自然": "natural",
    "natural": "natural",
}


def parse_label(path: Path) -> str | None:
    """Infers a label from parent directory or filename prefix."""

    candidates = [
        path.parent.name,
        path.stem.split("-")[0],
        path.stem.split("_")[0],
    ]
    for candidate in candidates:
        normalized = LABEL_ALIASES.get(candidate.lower()) or LABEL_ALIASES.get(candidate)
        if normalized:
            return normalized
    return None


def iter_images(input_paths: list[Path]) -> list[Path]:
    """Collects supported image files from files or directories."""

    image_paths: list[Path] = []
    suffixes = {".jpg", ".jpeg", ".png", ".webp"}
    for input_path in input_paths:
        if input_path.is_dir():
            image_paths.extend(
                path
                for path in input_path.rglob("*")
                if path.is_file() and path.suffix.lower() in suffixes
            )
        elif input_path.is_file() and input_path.suffix.lower() in suffixes:
            image_paths.append(input_path)
    return sorted(set(image_paths))


def extract_hand_features(
    image_paths: list[Path],
    hand_model_path: Path,
) -> tuple[np.ndarray, list[str], list[dict[str, Any]]]:
    """Runs MediaPipe Hand Landmarker and returns feature rows plus labels."""

    options = HandLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=str(hand_model_path)),
        running_mode=VisionRunningMode.IMAGE,
        num_hands=1,
        min_hand_detection_confidence=0.20,
        min_hand_presence_confidence=0.20,
        min_tracking_confidence=0.20,
    )
    landmarker = HandLandmarker.create_from_options(options)
    features: list[np.ndarray] = []
    labels: list[str] = []
    skipped: list[dict[str, Any]] = []

    for image_path in image_paths:
        label = parse_label(image_path)
        if not label:
            skipped.append({"path": str(image_path), "reason": "unknown_label"})
            continue

        bgr = cv2.imread(str(image_path), cv2.IMREAD_COLOR)
        if bgr is None:
            skipped.append({"path": str(image_path), "reason": "read_failed"})
            continue

        rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        result = landmarker.detect(mp_image)
        landmarks = result.hand_landmarks or []
        if not landmarks:
            skipped.append({"path": str(image_path), "reason": "no_hand"})
            continue

        features.append(landmark_feature_vector(landmarks[0]))
        labels.append(label)

    if not features:
        return np.empty((0, 0), dtype=np.float32), [], skipped
    return np.stack(features).astype(np.float32), labels, skipped


def train_from_images(args: argparse.Namespace) -> int:
    """Trains a gesture model from labeled image paths."""

    image_paths = iter_images([Path(path) for path in args.input])
    if not image_paths:
        print(json.dumps({"ok": False, "error": "no_images"}, ensure_ascii=False), file=sys.stderr)
        return 1

    features, sample_labels, skipped = extract_hand_features(
        image_paths=image_paths,
        hand_model_path=Path(args.hand_model_path),
    )
    labels = [label for label in DEFAULT_LABELS if label in set(sample_labels)]
    if len(labels) < 2:
        print(
            json.dumps(
                {
                    "ok": False,
                    "error": "need_at_least_two_labels",
                    "sample_labels": sample_labels,
                    "skipped": skipped,
                },
                ensure_ascii=False,
            ),
            file=sys.stderr,
        )
        return 1

    label_to_index = {label: index for index, label in enumerate(labels)}
    label_indices = np.asarray([label_to_index[label] for label in sample_labels], dtype=np.int64)
    model = train_mlp(
        features,
        label_indices,
        labels,
        hidden_size=args.hidden_size,
        epochs=args.epochs,
        learning_rate=args.learning_rate,
        seed=args.seed,
    )
    output_path = Path(args.output)
    model.save(output_path)

    predictions = [model.labels[int(np.argmax(model.predict_proba(feature)))] for feature in features]
    accuracy = sum(pred == label for pred, label in zip(predictions, sample_labels)) / len(sample_labels)
    print(
        json.dumps(
            {
                "ok": True,
                "output": str(output_path),
                "samples": len(sample_labels),
                "labels": labels,
                "train_accuracy": accuracy,
                "skipped": skipped,
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


def self_test(output_path: Path | None = None) -> int:
    """Runs a dependency-light train/save/load smoke test."""

    rng = np.random.default_rng(11)
    features = np.vstack(
        [
            rng.normal(-0.8, 0.08, size=(8, 97)),
            rng.normal(0.8, 0.08, size=(8, 97)),
        ]
    ).astype(np.float32)
    labels = ["pinch", "grab"]
    label_indices = np.asarray([0] * 8 + [1] * 8, dtype=np.int64)
    model = train_mlp(features, label_indices, labels, epochs=220, learning_rate=0.05)
    predictions = [labels[int(np.argmax(model.predict_proba(feature)))] for feature in features]
    ok = all(pred == expected for pred, expected in zip(predictions, ["pinch"] * 8 + ["grab"] * 8))

    if output_path:
        model.save(output_path)
        loaded = GestureMLP.load(output_path)
        ok = ok and loaded.labels == labels and loaded.input_size == features.shape[1]

    print(json.dumps({"ok": ok, "labels": labels}, ensure_ascii=False))
    return 0 if ok else 1


def parse_args(argv: list[str]) -> argparse.Namespace:
    """Parses command-line arguments."""

    parser = argparse.ArgumentParser(description="Train WonderShow custom gesture classifier")
    parser.add_argument("input", nargs="*", help="Image files or directories. Labels come from filename or folder.")
    parser.add_argument("--hand-model-path", default=str(PROJECT_ROOT / "sidecar/models/hand_landmarker.task"))
    parser.add_argument("--output", default=str(PROJECT_ROOT / "sidecar/models/wondershow_gesture_model.json"))
    parser.add_argument("--epochs", type=int, default=900)
    parser.add_argument("--hidden-size", type=int, default=32)
    parser.add_argument("--learning-rate", type=float, default=0.035)
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--self-test", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    """Entrypoint."""

    args = parse_args(argv)
    if args.self_test:
        return self_test(Path(args.output))
    return train_from_images(args)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

