#!/usr/bin/env python3
"""Trainable WonderShow gesture classifier built on MediaPipe hand landmarks."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

import numpy as np


DEFAULT_LABELS = [
    "open_palm",
    "sword",
    "finger_gun",
    "l_shape",
    "pinch",
    "grab",
    "natural",
    "unknown",
]

FEATURE_SCHEMA_VERSION = 2
FEATURE_SCHEMA_NAME = "landmark_v2"
LEGACY_FEATURE_SCHEMA_NAME = "landmark_v1"
LEGACY_FEATURE_VECTOR_SIZE = 103
FEATURE_VECTOR_SIZE = 179

ANCHOR_INDICES = np.asarray([0, 5, 9, 13, 17])
TIP_INDICES = (4, 8, 12, 16, 20)
FINGER_MCP_INDICES = (1, 5, 9, 13, 17)
FINGER_CHAINS = (
    (0, 1, 2, 3, 4),
    (0, 5, 6, 7, 8),
    (0, 9, 10, 11, 12),
    (0, 13, 14, 15, 16),
    (0, 17, 18, 19, 20),
)
PAIR_DISTANCE_INDICES = (
    (4, 8),
    (4, 12),
    (4, 16),
    (4, 20),
    (8, 12),
    (8, 16),
    (8, 20),
    (12, 16),
    (12, 20),
    (16, 20),
    (4, 5),
    (8, 5),
    (12, 9),
    (16, 13),
    (20, 17),
)
PALM_DISTANCE_INDICES = (
    (0, 5),
    (0, 9),
    (0, 13),
    (0, 17),
    (5, 9),
    (9, 13),
    (13, 17),
    (5, 17),
)


def _landmark_xyz(landmark: Any) -> tuple[float, float, float]:
    """Reads a landmark from MediaPipe objects or JSON dictionaries."""

    if isinstance(landmark, dict):
        return (
            float(landmark.get("x", 0.0)),
            float(landmark.get("y", 0.0)),
            float(landmark.get("z", 0.0)),
        )
    return (float(landmark.x), float(landmark.y), float(getattr(landmark, "z", 0.0)))


def _landmark_points(landmarks: Iterable[Any]) -> np.ndarray:
    """Returns the first 21 landmarks as a float32 xyz array."""

    points = np.asarray([_landmark_xyz(landmark) for landmark in landmarks], dtype=np.float32)
    if points.shape[0] < 21:
        raise ValueError(f"Expected 21 landmarks, got {points.shape[0]}.")
    return points[:21]


def _palm_center(points: np.ndarray) -> np.ndarray:
    """Computes the wrist/MCP palm center used as a stable origin."""

    return points[ANCHOR_INDICES].mean(axis=0)


def _palm_size(points: np.ndarray) -> float:
    """Computes a scale unit from wrist to middle MCP."""

    return max(float(np.linalg.norm(points[9, :2] - points[0, :2])), 1e-4)


def _distance_xy(points: np.ndarray, left: int, right: int, palm_size: float) -> float:
    """Computes a 2D point distance normalized by palm size."""

    return float(np.linalg.norm(points[left, :2] - points[right, :2]) / palm_size)


def _angle_degrees(a: np.ndarray, b: np.ndarray, c: np.ndarray) -> float:
    """Computes the invariant angle at point b in degrees."""

    lhs = a[:2] - b[:2]
    rhs = c[:2] - b[:2]
    denominator = float(np.linalg.norm(lhs) * np.linalg.norm(rhs))
    if denominator <= 1e-6:
        return 0.0
    cosine = float(np.dot(lhs, rhs) / denominator)
    cosine = max(-1.0, min(1.0, cosine))
    return float(np.degrees(np.arccos(cosine)) / 180.0)


def legacy_landmark_feature_vector(landmarks: Iterable[Any]) -> np.ndarray:
    """Converts landmarks using the v1 feature schema kept for old model files.

    The legacy feature is intentionally small and dependency-free:
    - 21 relative xyz points normalized by palm size
    - fingertip distances to palm center
    - selected fingertip pair distances
    """

    points = _landmark_points(landmarks)
    palm_center = _palm_center(points)
    palm_size = _palm_size(points)

    relative = (points - palm_center) / palm_size
    wrist_to_tip = [
        np.linalg.norm(points[index, :2] - points[0, :2]) / palm_size
        for index in (4, 8, 12, 16, 20)
    ]
    center_to_tip = [
        np.linalg.norm(points[index, :2] - palm_center[:2]) / palm_size
        for index in (4, 8, 12, 16, 20)
    ]
    pair_distances = [
        np.linalg.norm(points[left, :2] - points[right, :2]) / palm_size
        for left, right in (
            (4, 8),
            (8, 12),
            (12, 16),
            (16, 20),
            (4, 5),
            (8, 5),
            (12, 9),
            (16, 13),
            (20, 17),
        )
    ]
    handedness_invariant_x = np.abs(relative[:, 0])

    return np.concatenate(
        [
            relative.reshape(-1),
            handedness_invariant_x,
            np.asarray(wrist_to_tip, dtype=np.float32),
            np.asarray(center_to_tip, dtype=np.float32),
            np.asarray(pair_distances, dtype=np.float32),
        ]
    ).astype(np.float32)


def landmark_feature_vector(landmarks: Iterable[Any]) -> np.ndarray:
    """Converts 21 hand landmarks into the v2 scale-normalized feature vector.

    The v2 schema stays lightweight but adds the invariants needed for user-trained
    gestures: mirror-normalized coordinates, finger extension ratios, joint angles,
    and stable fingertip/palm distances.
    """

    points = _landmark_points(landmarks)
    palm_center = _palm_center(points)
    palm_size = _palm_size(points)

    palm_relative = (points - palm_center) / palm_size
    wrist_relative = (points - points[0]) / palm_size
    palm_relative[:, 0] = np.abs(palm_relative[:, 0])
    wrist_relative[:, 0] = np.abs(wrist_relative[:, 0])

    extension_ratios = [
        _distance_xy(points, 0, tip, palm_size) / max(_distance_xy(points, 0, mcp, palm_size), 1e-4)
        for tip, mcp in zip(TIP_INDICES, FINGER_MCP_INDICES)
    ]
    joint_angles = [
        _angle_degrees(points[chain[index - 1]], points[chain[index]], points[chain[index + 1]])
        for chain in FINGER_CHAINS
        for index in (1, 2, 3)
    ]
    center_to_tip = [
        float(np.linalg.norm(points[index, :2] - palm_center[:2]) / palm_size)
        for index in TIP_INDICES
    ]
    wrist_to_tip = [
        _distance_xy(points, 0, index, palm_size)
        for index in TIP_INDICES
    ]
    pair_distances = [
        _distance_xy(points, left, right, palm_size)
        for left, right in PAIR_DISTANCE_INDICES
    ]
    palm_distances = [
        _distance_xy(points, left, right, palm_size)
        for left, right in PALM_DISTANCE_INDICES
    ]

    feature = np.concatenate(
        [
            palm_relative.reshape(-1),
            wrist_relative.reshape(-1),
            np.asarray(extension_ratios, dtype=np.float32),
            np.asarray(joint_angles, dtype=np.float32),
            np.asarray(center_to_tip, dtype=np.float32),
            np.asarray(wrist_to_tip, dtype=np.float32),
            np.asarray(pair_distances, dtype=np.float32),
            np.asarray(palm_distances, dtype=np.float32),
        ]
    ).astype(np.float32)
    if feature.shape[0] != FEATURE_VECTOR_SIZE:
        raise RuntimeError(f"Unexpected v2 feature size: {feature.shape[0]}.")
    return feature


def softmax(logits: np.ndarray) -> np.ndarray:
    """Computes stable softmax probabilities for one vector."""

    shifted = logits - np.max(logits)
    exp = np.exp(shifted)
    return exp / np.sum(exp)


@dataclass(slots=True)
class GestureMLP:
    """Tiny NumPy MLP used for local custom gesture inference."""

    labels: list[str]
    weights1: np.ndarray
    bias1: np.ndarray
    weights2: np.ndarray
    bias2: np.ndarray
    mean: np.ndarray
    std: np.ndarray
    version: int = FEATURE_SCHEMA_VERSION
    feature_schema: str = FEATURE_SCHEMA_NAME
    recommended_threshold: float = 0.55

    @property
    def input_size(self) -> int:
        return int(self.mean.shape[0])

    def predict_proba(self, feature: np.ndarray) -> np.ndarray:
        """Runs one forward pass and returns class probabilities."""

        if feature.shape[0] != self.input_size:
            raise ValueError(f"Expected feature size {self.input_size}, got {feature.shape[0]}.")
        x = (feature.astype(np.float32) - self.mean) / np.maximum(self.std, 1e-6)
        hidden = np.tanh(x @ self.weights1 + self.bias1)
        logits = hidden @ self.weights2 + self.bias2
        return softmax(logits)

    def feature_vector(self, landmarks: Iterable[Any]) -> np.ndarray:
        """Converts landmarks using the schema expected by this model."""

        if self.feature_schema == FEATURE_SCHEMA_NAME or self.input_size == FEATURE_VECTOR_SIZE:
            return landmark_feature_vector(landmarks)
        if self.feature_schema == LEGACY_FEATURE_SCHEMA_NAME or self.input_size == LEGACY_FEATURE_VECTOR_SIZE:
            feature = legacy_landmark_feature_vector(landmarks)
            if feature.shape[0] == self.input_size:
                return feature
            if feature.shape[0] > self.input_size:
                return feature[: self.input_size]
            return np.pad(feature, (0, self.input_size - feature.shape[0])).astype(np.float32)
        raise ValueError(f"Unsupported gesture feature schema: {self.feature_schema} ({self.input_size}).")

    def predict(self, landmarks: Iterable[Any]) -> dict[str, Any]:
        """Predicts a custom gesture label from 21 landmarks."""

        feature = self.feature_vector(landmarks)
        probabilities = self.predict_proba(feature)
        index = int(np.argmax(probabilities))
        return {
            "name": self.labels[index],
            "score": float(probabilities[index]),
            "scores": {
                label: float(probabilities[label_index])
                for label_index, label in enumerate(self.labels)
            },
            "model_version": self.version,
            "feature_schema": self.feature_schema,
            "recommended_threshold": self.recommended_threshold,
        }

    def save(self, path: Path) -> None:
        """Saves the model as a compact JSON file."""

        payload = {
            "version": self.version,
            "feature_schema": self.feature_schema,
            "feature_size": self.input_size,
            "recommended_threshold": self.recommended_threshold,
            "labels": self.labels,
            "weights1": self.weights1.tolist(),
            "bias1": self.bias1.tolist(),
            "weights2": self.weights2.tolist(),
            "bias2": self.bias2.tolist(),
            "mean": self.mean.tolist(),
            "std": self.std.tolist(),
        }
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")

    @staticmethod
    def load(path: Path) -> "GestureMLP":
        """Loads a model saved by :meth:`save`."""

        payload = json.loads(path.read_text(encoding="utf-8"))
        version = int(payload.get("version", 1))
        mean = np.asarray(payload["mean"], dtype=np.float32)
        feature_schema = str(
            payload.get(
                "feature_schema",
                FEATURE_SCHEMA_NAME if version >= FEATURE_SCHEMA_VERSION and mean.shape[0] == FEATURE_VECTOR_SIZE else LEGACY_FEATURE_SCHEMA_NAME,
            )
        )
        return GestureMLP(
            labels=list(payload["labels"]),
            weights1=np.asarray(payload["weights1"], dtype=np.float32),
            bias1=np.asarray(payload["bias1"], dtype=np.float32),
            weights2=np.asarray(payload["weights2"], dtype=np.float32),
            bias2=np.asarray(payload["bias2"], dtype=np.float32),
            mean=mean,
            std=np.asarray(payload["std"], dtype=np.float32),
            version=version,
            feature_schema=feature_schema,
            recommended_threshold=float(payload.get("recommended_threshold", 0.55)),
        )


def train_mlp(
    features: np.ndarray,
    label_indices: np.ndarray,
    labels: list[str],
    *,
    hidden_size: int = 32,
    epochs: int = 700,
    learning_rate: float = 0.035,
    seed: int = 7,
    version: int = FEATURE_SCHEMA_VERSION,
    feature_schema: str = FEATURE_SCHEMA_NAME,
    recommended_threshold: float = 0.55,
) -> GestureMLP:
    """Trains a small MLP classifier using full-batch gradient descent."""

    if features.ndim != 2:
        raise ValueError("features must be a 2D array.")
    if features.shape[0] != label_indices.shape[0]:
        raise ValueError("features and labels must have the same row count.")
    if features.shape[0] < len(set(label_indices.tolist())):
        raise ValueError("Need at least one sample per class.")

    x_mean = features.mean(axis=0).astype(np.float32)
    x_std = (features.std(axis=0) + 1e-4).astype(np.float32)
    x = ((features - x_mean) / x_std).astype(np.float32)
    y = np.eye(len(labels), dtype=np.float32)[label_indices]

    rng = np.random.default_rng(seed)
    weights1 = rng.normal(0.0, 0.12, size=(x.shape[1], hidden_size)).astype(np.float32)
    bias1 = np.zeros(hidden_size, dtype=np.float32)
    weights2 = rng.normal(0.0, 0.12, size=(hidden_size, len(labels))).astype(np.float32)
    bias2 = np.zeros(len(labels), dtype=np.float32)

    for _ in range(epochs):
        hidden = np.tanh(x @ weights1 + bias1)
        logits = hidden @ weights2 + bias2
        logits -= logits.max(axis=1, keepdims=True)
        probabilities = np.exp(logits)
        probabilities /= probabilities.sum(axis=1, keepdims=True)

        grad_logits = (probabilities - y) / x.shape[0]
        grad_weights2 = hidden.T @ grad_logits
        grad_bias2 = grad_logits.sum(axis=0)
        grad_hidden = (grad_logits @ weights2.T) * (1 - hidden * hidden)
        grad_weights1 = x.T @ grad_hidden
        grad_bias1 = grad_hidden.sum(axis=0)

        weights1 -= learning_rate * grad_weights1
        bias1 -= learning_rate * grad_bias1
        weights2 -= learning_rate * grad_weights2
        bias2 -= learning_rate * grad_bias2

    return GestureMLP(
        labels=labels,
        weights1=weights1,
        bias1=bias1,
        weights2=weights2,
        bias2=bias2,
        mean=x_mean,
        std=x_std,
        version=version,
        feature_schema=feature_schema,
        recommended_threshold=recommended_threshold,
    )
