import base64
import importlib.util
import sys
import unittest
from pathlib import Path

import numpy as np


MODULE_PATH = Path(__file__).resolve().parents[2] / "sidecar" / "server.py"


def load_module():
    sidecar_dir = str(MODULE_PATH.parent)
    if sidecar_dir not in sys.path:
        sys.path.insert(0, sidecar_dir)
    spec = importlib.util.spec_from_file_location("sidecar_server", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class PortraitEnhancementSidecarTests(unittest.TestCase):
    def test_gray8_mask_payload_encodes_person_probability(self):
        module = load_module()
        mask = np.asarray(
            [
                [0.0, 0.5, 1.0],
                [0.25, 0.75, 0.1],
            ],
            dtype=np.float32,
        )

        payload = module.segmentation_payload(mask)

        self.assertEqual(payload["width"], 3)
        self.assertEqual(payload["height"], 2)
        self.assertEqual(payload["format"], "gray8")
        self.assertEqual(base64.b64decode(payload["mask_base64"]), bytes([0, 128, 255, 64, 191, 26]))

    def test_face_payload_uses_normalized_bounding_box_and_blendshapes(self):
        module = load_module()
        landmarks = [
            {"x": 0.20, "y": 0.25, "z": -0.01},
            {"x": 0.80, "y": 0.75, "z": -0.02},
            {"x": 0.50, "y": 0.50, "z": -0.03},
        ]
        blendshapes = [{"name": "jawOpen", "score": 0.4}]

        payload = module.face_payload(landmarks, blendshapes=blendshapes, confidence=0.87)

        self.assertEqual(payload["confidence"], 0.87)
        self.assertEqual(payload["bounding_box"]["x"], 0.20)
        self.assertEqual(payload["bounding_box"]["y"], 0.25)
        self.assertAlmostEqual(payload["bounding_box"]["width"], 0.60)
        self.assertAlmostEqual(payload["bounding_box"]["height"], 0.50)
        self.assertEqual(payload["landmarks"], landmarks)
        self.assertEqual(payload["blendshapes"], blendshapes)

    def test_background_replacement_preserves_foreground_with_soft_mask(self):
        module = load_module()
        frame = np.zeros((2, 2, 3), dtype=np.uint8)
        frame[:, :] = [10, 20, 30]
        background = np.zeros_like(frame)
        background[:, :] = [100, 120, 140]
        mask = np.asarray([[1.0, 0.0], [0.5, 0.25]], dtype=np.float32)

        composited = module.composite_background(frame, background, mask)

        self.assertEqual(composited[0, 0].tolist(), [10, 20, 30])
        self.assertEqual(composited[0, 1].tolist(), [100, 120, 140])
        self.assertEqual(composited[1, 0].tolist(), [55, 70, 85])
        self.assertEqual(composited[1, 1].tolist(), [78, 95, 112])


if __name__ == "__main__":
    unittest.main()
