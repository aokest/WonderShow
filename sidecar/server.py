#!/usr/bin/env python3
"""MediaPipe gesture sidecar for WonderShow.

This service receives JPEG frames over local HTTP, runs MediaPipe Gesture Recognizer,
and returns normalized hand landmarks plus gesture categories as JSON.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
from dataclasses import dataclass
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

import cv2
import mediapipe as mp
import numpy as np


BaseOptions = mp.tasks.BaseOptions
GestureRecognizer = mp.tasks.vision.GestureRecognizer
GestureRecognizerOptions = mp.tasks.vision.GestureRecognizerOptions
VisionRunningMode = mp.tasks.vision.RunningMode


@dataclass(slots=True)
class SidecarConfig:
    """Holds runtime configuration for the local sidecar service.

    Attributes:
        host: Host address to bind.
        port: TCP port to listen on.
        model_path: Path to the MediaPipe gesture recognizer task bundle.
    """

    host: str
    port: int
    model_path: Path


class GestureSidecar:
    """Wraps MediaPipe Gesture Recognizer and exposes frame inference methods.

    Args:
        config: Runtime configuration including model file location.
    Raises:
        FileNotFoundError: If the required model file does not exist.
        RuntimeError: If the recognizer cannot be created.
    """

    def __init__(self, config: SidecarConfig) -> None:
        self._config = config
        if not config.model_path.exists():
            raise FileNotFoundError(
                f"MediaPipe task model not found: {config.model_path}. "
                "Please download gesture_recognizer.task into sidecar/models/."
            )
        options = GestureRecognizerOptions(
            base_options=BaseOptions(model_asset_path=str(config.model_path)),
            running_mode=VisionRunningMode.IMAGE,
            num_hands=2,
            min_hand_detection_confidence=0.35,
            min_hand_presence_confidence=0.35,
            min_tracking_confidence=0.35,
        )
        try:
            self._recognizer = GestureRecognizer.create_from_options(options)
        except Exception as exc:  # pragma: no cover - direct wrapper for native init
            raise RuntimeError(f"Failed to initialize MediaPipe recognizer: {exc}") from exc

    def health_payload(self) -> dict[str, Any]:
        """Builds a health response for liveness checks.

        Returns:
            A JSON-serializable health payload.
        """

        return {
            "ok": True,
            "engine": "MediaPipe Gesture Recognizer",
            "model_path": str(self._config.model_path),
        }

    def infer(self, image_bytes: bytes, timestamp_ms: int) -> dict[str, Any]:
        """Runs MediaPipe inference on a JPEG frame.

        Args:
            image_bytes: Encoded JPEG frame bytes.
            timestamp_ms: Timestamp provided by the caller.
        Returns:
            A JSON-serializable inference payload.
        Raises:
            ValueError: If the image cannot be decoded.
        """

        np_buffer = np.frombuffer(image_bytes, dtype=np.uint8)
        bgr = cv2.imdecode(np_buffer, cv2.IMREAD_COLOR)
        if bgr is None:
            raise ValueError("Failed to decode JPEG image bytes.")

        rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        result = self._recognizer.recognize(mp_image)

        hands: list[dict[str, Any]] = []
        handedness_list = result.handedness or []
        gesture_list = result.gestures or []
        landmark_list = result.hand_landmarks or []

        for index, landmarks in enumerate(landmark_list):
            handedness = handedness_list[index][0] if index < len(handedness_list) and handedness_list[index] else None
            gestures = gesture_list[index] if index < len(gesture_list) else []
            hands.append(
                {
                    "handedness": handedness.category_name if handedness else "Unknown",
                    "handedness_score": handedness.score if handedness else 0.0,
                    "landmarks": [
                        {"x": point.x, "y": point.y, "z": point.z}
                        for point in landmarks
                    ],
                    "gesture_categories": [
                        {"name": category.category_name, "score": category.score}
                        for category in gestures
                    ],
                }
            )

        return {
            "ok": True,
            "timestamp_ms": timestamp_ms,
            "hands": hands,
        }


class SidecarRequestHandler(BaseHTTPRequestHandler):
    """Handles local HTTP requests for health and inference endpoints."""

    sidecar: GestureSidecar | None = None

    def do_GET(self) -> None:  # noqa: N802
        """Handles GET requests for health checks."""

        if self.path == "/health":
            self._send_json(HTTPStatus.OK, self.sidecar.health_payload() if self.sidecar else {"ok": False})
            return

        self._send_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "Not found"})

    def do_POST(self) -> None:  # noqa: N802
        """Handles POST requests for frame inference."""

        if self.path != "/infer":
            self._send_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "Not found"})
            return

        if not self.sidecar:
            self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"ok": False, "error": "Sidecar unavailable"})
            return

        try:
            payload = self._read_json_body()
            image_base64 = payload["image_base64"]
            timestamp_ms = int(payload["timestamp_ms"])
            image_bytes = base64.b64decode(image_base64)
            response = self.sidecar.infer(image_bytes=image_bytes, timestamp_ms=timestamp_ms)
            self._send_json(HTTPStatus.OK, response)
        except KeyError as exc:
            self._send_json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": f"Missing field: {exc}"})
        except ValueError as exc:
            self._send_json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
        except Exception as exc:  # pragma: no cover - runtime guard for native tasks
            self._send_json(HTTPStatus.INTERNAL_SERVER_ERROR, {"ok": False, "error": str(exc)})

    def log_message(self, format: str, *args: Any) -> None:
        """Suppresses default noisy HTTP request logging."""

        return

    def _read_json_body(self) -> dict[str, Any]:
        """Reads and parses the JSON request body.

        Returns:
            Parsed JSON object.
        Raises:
            ValueError: If the body is empty or not valid JSON.
        """

        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        if not body:
            raise ValueError("Request body is empty.")
        return json.loads(body.decode("utf-8"))

    def _send_json(self, status: HTTPStatus, payload: dict[str, Any]) -> None:
        """Sends a JSON response with permissive local CORS headers.

        Args:
            status: HTTP status code.
            payload: JSON payload to send.
        """

        body = json.dumps(payload, ensure_ascii=True).encode("utf-8")
        self.send_response(status.value)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)


def default_model_path(project_root: Path) -> Path:
    """Builds the default model location within the repository.

    Args:
        project_root: Root path of the repository.
    Returns:
        Expected local gesture recognizer task bundle path.
    """

    return project_root / "sidecar" / "models" / "gesture_recognizer.task"


def parse_args(argv: list[str]) -> SidecarConfig:
    """Parses CLI arguments into a typed sidecar configuration.

    Args:
        argv: Raw command line arguments excluding the executable name.
    Returns:
        Sidecar configuration derived from CLI flags.
    """

    project_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description="WonderShow MediaPipe gesture sidecar")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=18777)
    parser.add_argument("--model-path", default=str(default_model_path(project_root)))
    args = parser.parse_args(argv)
    return SidecarConfig(host=args.host, port=args.port, model_path=Path(args.model_path))


def main(argv: list[str]) -> int:
    """Starts the local HTTP sidecar server.

    Args:
        argv: Raw command line arguments excluding the executable name.
    Returns:
        Process exit code.
    """

    config = parse_args(argv)
    try:
        sidecar = GestureSidecar(config)
    except Exception as exc:
        print(f"[MediaPipe Sidecar] {exc}", file=sys.stderr)
        return 1

    SidecarRequestHandler.sidecar = sidecar
    server = ThreadingHTTPServer((config.host, config.port), SidecarRequestHandler)
    print(
        json.dumps(
            {
                "ok": True,
                "service": "WonderShow MediaPipe Sidecar",
                "host": config.host,
                "port": config.port,
                "health_url": f"http://{config.host}:{config.port}/health",
                "infer_url": f"http://{config.host}:{config.port}/infer",
                "model_path": str(config.model_path),
            },
            ensure_ascii=True,
        )
    )
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
