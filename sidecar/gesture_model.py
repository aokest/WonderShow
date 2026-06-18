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
]


def _landmark_xyz(landmark: Any) -> tuple[float, float, float]:
    """Reads a landmark from MediaPipe objects or JSON dictionaries."""

    if isinstance(landmark, dict):
        return (
            float(landmark.get("x", 0.0)),
            float(landmark.get("y", 0.0)),
            float(landmark.get("z", 0.0)),
        )
    return (float(landmark.x), float(landmark.y), float(getattr(landmark, "z", 0.0)))


def landmark_feature_vector(landmarks: Iterable[Any]) -> np.ndarray:
    """Converts 21 hand landmarks into a scale-normalized feature vector.

    The feature is intentionally small and dependency-free:
    - 21 relative xyz points normalized by palm size
    - fingertip distances to palm center
    - selected fingertip pair distances
    """

    points = np.asarray([_landmark_xyz(landmark) for landmark in landmarks], dtype=np.float32)
    if points.shape[0] < 21:
        raise ValueError(f"Expected 21 landmarks, got {points.shape[0]}.")
    points = points[:21]

    anchor_indices = np.asarray([0, 5, 9, 13, 17])
    palm_center = points[anchor_indices].mean(axis=0)
    palm_size = float(np.linalg.norm(points[9, :2] - points[0, :2]))
    palm_size = max(palm_size, 1e-4)

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

    @property
    def input_size(self) -> int:
        return int(self.mean.shape[0])

    def predict_proba(self, feature: np.ndarray) -> np.ndarray:
        """Runs one forward pass and returns class probabilities."""

        x = (feature.astype(np.float32) - self.mean) / np.maximum(self.std, 1e-6)
        hidden = np.tanh(x @ self.weights1 + self.bias1)
        logits = hidden @ self.weights2 + self.bias2
        return softmax(logits)

    def predict(self, landmarks: Iterable[Any]) -> dict[str, Any]:
        """Predicts a custom gesture label from 21 landmarks."""

        feature = landmark_feature_vector(landmarks)
        probabilities = self.predict_proba(feature)
        index = int(np.argmax(probabilities))
        return {
            "name": self.labels[index],
            "score": float(probabilities[index]),
            "scores": {
                label: float(probabilities[label_index])
                for label_index, label in enumerate(self.labels)
            },
        }

    def save(self, path: Path) -> None:
        """Saves the model as a compact JSON file."""

        payload = {
            "version": 1,
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
        return GestureMLP(
            labels=list(payload["labels"]),
            weights1=np.asarray(payload["weights1"], dtype=np.float32),
            bias1=np.asarray(payload["bias1"], dtype=np.float32),
            weights2=np.asarray(payload["weights2"], dtype=np.float32),
            bias2=np.asarray(payload["bias2"], dtype=np.float32),
            mean=np.asarray(payload["mean"], dtype=np.float32),
            std=np.asarray(payload["std"], dtype=np.float32),
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
    )

