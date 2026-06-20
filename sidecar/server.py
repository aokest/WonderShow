#!/usr/bin/env python3
"""MediaPipe gesture sidecar for WonderShow.

This service receives JPEG frames over local HTTP, runs MediaPipe Gesture Recognizer,
and returns normalized hand landmarks plus gesture categories as JSON.
"""

from __future__ import annotations

import argparse
import base64
import hmac
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
from gesture_model import GestureMLP


BaseOptions = mp.tasks.BaseOptions
FaceLandmarker = mp.tasks.vision.FaceLandmarker
FaceLandmarkerOptions = mp.tasks.vision.FaceLandmarkerOptions
GestureRecognizer = mp.tasks.vision.GestureRecognizer
GestureRecognizerOptions = mp.tasks.vision.GestureRecognizerOptions
HandLandmarker = mp.tasks.vision.HandLandmarker
HandLandmarkerOptions = mp.tasks.vision.HandLandmarkerOptions
ImageSegmenter = mp.tasks.vision.ImageSegmenter
ImageSegmenterOptions = mp.tasks.vision.ImageSegmenterOptions
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
    hand_model_path: Path
    face_model_path: Path
    segmenter_model_path: Path
    custom_model_path: Path | None
    local_token: str | None


def segmentation_payload(mask: np.ndarray) -> dict[str, Any]:
    """Encodes a foreground probability mask as a compact gray8 payload."""

    clipped = np.clip(mask, 0.0, 1.0)
    gray8 = np.rint(clipped * 255).astype(np.uint8)
    return {
        "width": int(gray8.shape[1]),
        "height": int(gray8.shape[0]),
        "format": "gray8",
        "mask_base64": base64.b64encode(gray8.tobytes()).decode("ascii"),
    }


def face_payload(
    landmarks: list[dict[str, float]],
    *,
    blendshapes: list[dict[str, float]] | None = None,
    confidence: float = 1.0,
) -> dict[str, Any]:
    """Builds a normalized face payload from MediaPipe landmarks."""

    xs = [float(point["x"]) for point in landmarks]
    ys = [float(point["y"]) for point in landmarks]
    min_x = min(xs) if xs else 0.0
    max_x = max(xs) if xs else 0.0
    min_y = min(ys) if ys else 0.0
    max_y = max(ys) if ys else 0.0
    return {
        "confidence": float(confidence),
        "bounding_box": {
            "x": min_x,
            "y": min_y,
            "width": max(0.0, max_x - min_x),
            "height": max(0.0, max_y - min_y),
        },
        "landmarks": landmarks,
        "blendshapes": blendshapes or [],
    }


def composite_background(frame: np.ndarray, background: np.ndarray, mask: np.ndarray) -> np.ndarray:
    """Composites BGR/RGB frames with a soft foreground mask."""

    if frame.shape != background.shape:
        background = cv2.resize(background, (frame.shape[1], frame.shape[0]), interpolation=cv2.INTER_LINEAR)
    if mask.shape[:2] != frame.shape[:2]:
        mask = cv2.resize(mask, (frame.shape[1], frame.shape[0]), interpolation=cv2.INTER_LINEAR)
    alpha = np.clip(mask.astype(np.float32), 0.0, 1.0)[..., np.newaxis]
    composited = frame.astype(np.float32) * alpha + background.astype(np.float32) * (1.0 - alpha)
    return np.rint(np.clip(composited, 0, 255)).astype(np.uint8)


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
        if not config.hand_model_path.exists():
            raise FileNotFoundError(
                f"MediaPipe hand landmarker model not found: {config.hand_model_path}. "
                "Please download hand_landmarker.task into sidecar/models/."
            )
        self._custom_model = (
            GestureMLP.load(config.custom_model_path)
            if config.custom_model_path and config.custom_model_path.exists()
            else None
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
            self._hand_landmarker = HandLandmarker.create_from_options(
                HandLandmarkerOptions(
                    base_options=BaseOptions(model_asset_path=str(config.hand_model_path)),
                    running_mode=VisionRunningMode.IMAGE,
                    num_hands=2,
                    min_hand_detection_confidence=0.25,
                    min_hand_presence_confidence=0.25,
                    min_tracking_confidence=0.25,
                )
            )
            self._face_landmarker = (
                FaceLandmarker.create_from_options(
                    FaceLandmarkerOptions(
                        base_options=BaseOptions(model_asset_path=str(config.face_model_path)),
                        running_mode=VisionRunningMode.IMAGE,
                        num_faces=1,
                        min_face_detection_confidence=0.35,
                        min_face_presence_confidence=0.35,
                        min_tracking_confidence=0.35,
                        output_face_blendshapes=True,
                    )
                )
                if config.face_model_path.exists()
                else None
            )
            self._segmenter = (
                ImageSegmenter.create_from_options(
                    ImageSegmenterOptions(
                        base_options=BaseOptions(model_asset_path=str(config.segmenter_model_path)),
                        running_mode=VisionRunningMode.IMAGE,
                        output_confidence_masks=True,
                        output_category_mask=False,
                    )
                )
                if config.segmenter_model_path.exists()
                else None
            )
        except Exception as exc:  # pragma: no cover - direct wrapper for native init
            raise RuntimeError(f"Failed to initialize MediaPipe tasks: {exc}") from exc

    def health_payload(self) -> dict[str, Any]:
        """Builds a health response for liveness checks.

        Returns:
            A JSON-serializable health payload.
        """

        return {
            "ok": True,
            "engine": "MediaPipe Hand Landmarker + Gesture Recognizer",
            "model_path": str(self._config.model_path),
            "hand_model_path": str(self._config.hand_model_path),
            "face_model_path": str(self._config.face_model_path),
            "segmenter_model_path": str(self._config.segmenter_model_path),
            "face_landmarker_loaded": self._face_landmarker is not None,
            "segmenter_loaded": self._segmenter is not None,
            "custom_model_path": str(self._config.custom_model_path) if self._config.custom_model_path else None,
            "custom_model_loaded": self._custom_model is not None,
            "auth_required": self._config.local_token is not None,
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
        image_quality = self._image_quality(bgr)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        gesture_result = self._recognizer.recognize(mp_image)
        hand_result = self._hand_landmarker.detect(mp_image)
        portrait = self._portrait_payload(mp_image)

        hands: list[dict[str, Any]] = []
        handedness_list = hand_result.handedness or []
        landmark_list = hand_result.hand_landmarks or []
        gesture_matches = self._gesture_matches(gesture_result)

        for index, landmarks in enumerate(landmark_list):
            handedness = handedness_list[index][0] if index < len(handedness_list) and handedness_list[index] else None
            gestures = self._nearest_gestures(landmarks=landmarks, gesture_matches=gesture_matches)
            custom_gesture = self._predict_custom_gesture(landmarks)
            if custom_gesture is not None:
                custom_gesture["quality"] = self._hand_quality(landmarks, bgr.shape, image_quality)
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
                    "custom_gesture": custom_gesture,
                }
            )

        return {
            "ok": True,
            "timestamp_ms": timestamp_ms,
            "hands": hands,
            "faces": portrait["faces"],
            "segmentation": portrait["segmentation"],
        }

    def _portrait_payload(self, mp_image: Any) -> dict[str, Any]:
        """Runs optional face and person segmentation models for portrait effects."""

        faces: list[dict[str, Any]] = []
        segmentation: dict[str, Any] | None = None

        if self._face_landmarker is not None:
            face_result = self._face_landmarker.detect(mp_image)
            blendshape_groups = face_result.face_blendshapes or []
            for index, landmarks in enumerate(face_result.face_landmarks or []):
                blendshapes = [
                    {"name": category.category_name, "score": float(category.score)}
                    for category in (blendshape_groups[index] if index < len(blendshape_groups) else [])
                ]
                faces.append(
                    face_payload(
                        [
                            {"x": float(point.x), "y": float(point.y), "z": float(point.z)}
                            for point in landmarks
                        ],
                        blendshapes=blendshapes,
                        confidence=1.0,
                    )
                )

        if self._segmenter is not None:
            segment_result = self._segmenter.segment(mp_image)
            confidence_masks = segment_result.confidence_masks or []
            if len(confidence_masks) >= 2:
                mask = confidence_masks[1].numpy_view()
            elif confidence_masks:
                mask = confidence_masks[0].numpy_view()
            else:
                mask = None
            if mask is not None:
                segmentation = segmentation_payload(mask)

        return {"faces": faces, "segmentation": segmentation}

    def _gesture_matches(self, gesture_result: Any) -> list[dict[str, Any]]:
        """Builds palm-center indexed gesture categories from the classifier output."""

        landmark_list = gesture_result.hand_landmarks or []
        gesture_list = gesture_result.gestures or []
        matches: list[dict[str, Any]] = []
        for index, landmarks in enumerate(landmark_list):
            gestures = gesture_list[index] if index < len(gesture_list) else []
            matches.append(
                {
                    "center": self._palm_center(landmarks),
                    "gestures": gestures,
                }
            )
        return matches

    def _nearest_gestures(self, landmarks: Any, gesture_matches: list[dict[str, Any]]) -> Any:
        """Returns classifier categories for the nearest detected hand when available."""

        if not gesture_matches:
            return []

        center = self._palm_center(landmarks)
        nearest = min(
            gesture_matches,
            key=lambda match: self._distance_squared(center, match["center"]),
        )
        return nearest["gestures"]

    def _palm_center(self, landmarks: Any) -> tuple[float, float]:
        """Computes the same wrist/MCP palm center used by the Swift geometry code."""

        anchor_indices = [0, 5, 9, 13, 17]
        anchors = [landmarks[index] for index in anchor_indices if index < len(landmarks)]
        if not anchors:
            return (0.0, 0.0)
        return (
            sum(point.x for point in anchors) / len(anchors),
            sum(point.y for point in anchors) / len(anchors),
        )

    def _distance_squared(self, lhs: tuple[float, float], rhs: tuple[float, float]) -> float:
        """Computes squared distance between two normalized centers."""

        dx = lhs[0] - rhs[0]
        dy = lhs[1] - rhs[1]
        return dx * dx + dy * dy

    def _predict_custom_gesture(self, landmarks: Any) -> dict[str, Any] | None:
        """Runs the optional WonderShow-specific gesture classifier."""

        if not self._custom_model:
            return None
        prediction = self._custom_model.predict(landmarks)
        sorted_scores = sorted(prediction["scores"].values(), reverse=True)
        margin = (
            float(sorted_scores[0] - sorted_scores[1])
            if len(sorted_scores) >= 2
            else float(sorted_scores[0]) if sorted_scores else 0.0
        )
        return {
            "name": prediction["name"],
            "score": prediction["score"],
            "scores": prediction["scores"],
            "margin": margin,
            "model_version": prediction.get("model_version"),
            "feature_schema": prediction.get("feature_schema"),
            "recommended_threshold": prediction.get("recommended_threshold"),
        }

    def _image_quality(self, bgr: np.ndarray) -> dict[str, Any]:
        """Computes lightweight image quality metrics for downstream diagnostics."""

        gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
        brightness = float(np.mean(gray))
        contrast = float(np.std(gray))
        blur = float(cv2.Laplacian(gray, cv2.CV_64F).var())
        overexposed_ratio = float(np.mean(gray >= 245))
        underexposed_ratio = float(np.mean(gray <= 25))
        flags: list[str] = []
        if brightness < 45 or underexposed_ratio > 0.35:
            flags.append("low_light")
        if brightness > 215 or overexposed_ratio > 0.18:
            flags.append("overexposed")
        if contrast < 18:
            flags.append("low_contrast")
        if blur < 40:
            flags.append("blurry")
        return {
            "brightness": brightness,
            "contrast": contrast,
            "blur": blur,
            "overexposed_ratio": overexposed_ratio,
            "underexposed_ratio": underexposed_ratio,
            "flags": flags,
        }

    def _hand_quality(self, landmarks: Any, image_shape: tuple[int, ...], image_quality: dict[str, Any]) -> dict[str, Any]:
        """Adds hand-size diagnostics without changing required response fields."""

        height, width = image_shape[:2]
        xs = [float(point.x) for point in landmarks]
        ys = [float(point.y) for point in landmarks]
        box_width = max(xs) - min(xs) if xs else 0.0
        box_height = max(ys) - min(ys) if ys else 0.0
        hand_box_ratio = float(max(0.0, box_width) * max(0.0, box_height))
        flags = list(image_quality.get("flags", []))
        palm_size_px = self._distance_squared(
            (float(landmarks[0].x) * width, float(landmarks[0].y) * height),
            (float(landmarks[9].x) * width, float(landmarks[9].y) * height),
        ) ** 0.5 if len(landmarks) > 9 else 0.0
        if hand_box_ratio < 0.018 or palm_size_px < 18:
            flags.append("hand_too_small")
        return {
            "brightness": image_quality["brightness"],
            "contrast": image_quality["contrast"],
            "blur": image_quality["blur"],
            "hand_box_ratio": hand_box_ratio,
            "palm_size_px": palm_size_px,
            "flags": flags,
        }


class SidecarRequestHandler(BaseHTTPRequestHandler):
    """Handles local HTTP requests for health and inference endpoints."""

    sidecar: GestureSidecar | None = None
    local_token: str | None = None
    max_body_bytes = 6 * 1024 * 1024

    def do_GET(self) -> None:  # noqa: N802
        """Handles GET requests for health checks."""

        if self.path == "/health":
            if not self._is_authorized():
                self._send_json(HTTPStatus.UNAUTHORIZED, {"ok": False, "error": "Unauthorized"})
                return
            self._send_json(HTTPStatus.OK, self.sidecar.health_payload() if self.sidecar else {"ok": False})
            return

        self._send_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "Not found"})

    def do_POST(self) -> None:  # noqa: N802
        """Handles POST requests for frame inference."""

        if self.path != "/infer":
            self._send_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "Not found"})
            return

        if not self._is_authorized():
            self._send_json(HTTPStatus.UNAUTHORIZED, {"ok": False, "error": "Unauthorized"})
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
        if length > self.max_body_bytes:
            raise ValueError("Request body is too large.")
        body = self.rfile.read(length)
        if not body:
            raise ValueError("Request body is empty.")
        return json.loads(body.decode("utf-8"))

    def _is_authorized(self) -> bool:
        """Validates the per-app local token when one is configured."""

        if not self.local_token:
            return True
        supplied = self.headers.get("X-WonderShow-Local-Token")
        return supplied is not None and hmac.compare_digest(supplied, self.local_token)

    def _send_json(self, status: HTTPStatus, payload: dict[str, Any]) -> None:
        """Sends a JSON response.

        Args:
            status: HTTP status code.
            payload: JSON payload to send.
        """

        body = json.dumps(payload, ensure_ascii=True).encode("utf-8")
        self.send_response(status.value)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
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


def default_hand_model_path(project_root: Path) -> Path:
    """Builds the default hand landmarker model location within the repository."""

    return project_root / "sidecar" / "models" / "hand_landmarker.task"


def default_face_model_path(project_root: Path) -> Path:
    """Builds the default face landmarker model location within the repository."""

    return project_root / "sidecar" / "models" / "face_landmarker.task"


def default_segmenter_model_path(project_root: Path) -> Path:
    """Builds the default selfie segmentation model location within the repository."""

    return project_root / "sidecar" / "models" / "selfie_multiclass_256x256.tflite"


def default_custom_model_path(project_root: Path) -> Path:
    """Builds the default WonderShow custom gesture model location."""

    return project_root / "sidecar" / "models" / "wondershow_gesture_model.json"


def resolve_existing_path(preferred: Path, fallbacks: list[Path] | None = None) -> Path:
    """Returns the first existing path while preserving the preferred path for diagnostics."""

    if preferred.exists():
        return preferred
    for fallback in fallbacks or []:
        if fallback.exists():
            return fallback
    return preferred


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
    parser.add_argument("--hand-model-path", default=str(default_hand_model_path(project_root)))
    parser.add_argument("--face-model-path", default=str(default_face_model_path(project_root)))
    parser.add_argument("--segmenter-model-path", default=str(default_segmenter_model_path(project_root)))
    parser.add_argument("--custom-model-path", default=str(default_custom_model_path(project_root)))
    parser.add_argument("--token", default=os.environ.get("WONDERSHOW_LOCAL_TOKEN"))
    parser.add_argument(
        "--allow-unauthenticated-local-dev",
        action="store_true",
        help="Allow unauthenticated localhost requests for short-lived development only.",
    )
    args = parser.parse_args(argv)
    if not args.token and not args.allow_unauthenticated_local_dev:
        parser.error("set WONDERSHOW_LOCAL_TOKEN or pass --token; unauthenticated sidecar is disabled by default")
    return SidecarConfig(
        host=args.host,
        port=args.port,
        model_path=Path(args.model_path),
        hand_model_path=Path(args.hand_model_path),
        face_model_path=resolve_existing_path(
            Path(args.face_model_path),
            [
                Path(sys.executable).resolve().parents[1] / "Resources" / "sidecar" / "models" / "face_landmarker.task",
                Path.cwd() / "sidecar" / "models" / "face_landmarker.task",
            ],
        ),
        segmenter_model_path=resolve_existing_path(
            Path(args.segmenter_model_path),
            [
                Path(sys.executable).resolve().parents[1] / "Resources" / "sidecar" / "models" / "selfie_multiclass_256x256.tflite",
                Path.cwd() / "sidecar" / "models" / "selfie_multiclass_256x256.tflite",
            ],
        ),
        custom_model_path=resolve_existing_path(
            Path(args.custom_model_path),
            [
                Path(sys.executable).resolve().parents[1] / "Resources" / "sidecar" / "models" / "wondershow_gesture_model.json",
                Path.cwd() / "sidecar" / "models" / "wondershow_gesture_model.json",
            ],
        ) if args.custom_model_path else None,
        local_token=args.token,
    )


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
    SidecarRequestHandler.local_token = config.local_token
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
                "hand_model_path": str(config.hand_model_path),
                "face_model_path": str(config.face_model_path),
                "segmenter_model_path": str(config.segmenter_model_path),
                "custom_model_path": str(config.custom_model_path) if config.custom_model_path else None,
            },
            ensure_ascii=True,
        )
    )
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
