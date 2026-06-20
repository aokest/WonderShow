import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np


MODULE_PATH = Path(__file__).resolve().parents[2] / "sidecar" / "gesture_model.py"


def load_module():
    spec = importlib.util.spec_from_file_location("gesture_model", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def sample_landmarks(*, mirrored: bool = False):
    points = [
        (0.50, 0.80, 0.00),
        (0.46, 0.74, -0.01),
        (0.43, 0.68, -0.01),
        (0.40, 0.62, -0.02),
        (0.37, 0.58, -0.02),
        (0.47, 0.62, -0.01),
        (0.47, 0.50, -0.02),
        (0.47, 0.38, -0.03),
        (0.47, 0.26, -0.04),
        (0.52, 0.62, -0.01),
        (0.53, 0.50, -0.02),
        (0.53, 0.38, -0.03),
        (0.53, 0.27, -0.04),
        (0.57, 0.64, -0.01),
        (0.58, 0.59, -0.01),
        (0.58, 0.55, -0.02),
        (0.57, 0.52, -0.02),
        (0.61, 0.66, -0.01),
        (0.62, 0.62, -0.01),
        (0.62, 0.58, -0.02),
        (0.61, 0.55, -0.02),
    ]
    if mirrored:
        points = [(1.0 - x, y, z) for x, y, z in points]
    return [{"x": x, "y": y, "z": z} for x, y, z in points]


class GestureModelTests(unittest.TestCase):
    def test_v2_feature_vector_has_stable_schema_and_expected_size(self):
        module = load_module()

        feature = module.landmark_feature_vector(sample_landmarks())

        self.assertEqual(feature.shape, (module.FEATURE_VECTOR_SIZE,))
        self.assertEqual(module.FEATURE_SCHEMA_VERSION, 2)
        self.assertGreater(module.FEATURE_VECTOR_SIZE, 120)
        self.assertTrue(np.all(np.isfinite(feature)))

    def test_v2_feature_vector_is_mirror_normalized(self):
        module = load_module()

        original = module.landmark_feature_vector(sample_landmarks())
        mirrored = module.landmark_feature_vector(sample_landmarks(mirrored=True))

        self.assertLess(float(np.linalg.norm(original - mirrored)), 1e-4)

    def test_v1_model_payload_loads_with_legacy_schema(self):
        module = load_module()

        payload = {
            "version": 1,
            "labels": ["pinch", "grab"],
            "weights1": [[0.01] * 2 for _ in range(97)],
            "bias1": [0.0, 0.0],
            "weights2": [[0.02, -0.01], [0.01, 0.02]],
            "bias2": [0.0, 0.0],
            "mean": [0.0] * 97,
            "std": [1.0] * 97,
        }

        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "legacy.json"
            path.write_text(json.dumps(payload), encoding="utf-8")

            model = module.GestureMLP.load(path)

        self.assertEqual(model.version, 1)
        self.assertEqual(model.feature_schema, "landmark_v1")
        self.assertEqual(model.input_size, 97)

    def test_v1_short_legacy_model_can_still_predict_from_landmarks(self):
        module = load_module()

        model = module.GestureMLP(
            labels=["pinch", "grab"],
            weights1=np.zeros((97, 2), dtype=np.float32),
            bias1=np.zeros(2, dtype=np.float32),
            weights2=np.asarray([[0.2, -0.1], [0.0, 0.1]], dtype=np.float32),
            bias2=np.zeros(2, dtype=np.float32),
            mean=np.zeros(97, dtype=np.float32),
            std=np.ones(97, dtype=np.float32),
            version=1,
            feature_schema=module.LEGACY_FEATURE_SCHEMA_NAME,
        )

        prediction = model.predict(sample_landmarks())

        self.assertIn(prediction["name"], {"pinch", "grab"})
        self.assertEqual(prediction["feature_schema"], module.LEGACY_FEATURE_SCHEMA_NAME)

    def test_v2_model_save_includes_metadata_and_recommended_threshold(self):
        module = load_module()

        rng = np.random.default_rng(17)
        features = np.vstack(
            [
                rng.normal(-0.8, 0.05, size=(10, module.FEATURE_VECTOR_SIZE)),
                rng.normal(0.8, 0.05, size=(10, module.FEATURE_VECTOR_SIZE)),
            ]
        ).astype(np.float32)
        label_indices = np.asarray([0] * 10 + [1] * 10, dtype=np.int64)
        model = module.train_mlp(features, label_indices, ["pinch", "grab"], epochs=160, learning_rate=0.045)

        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "model.json"
            model.save(path)
            payload = json.loads(path.read_text(encoding="utf-8"))
            loaded = module.GestureMLP.load(path)

        self.assertEqual(payload["version"], 2)
        self.assertEqual(payload["feature_schema"], module.FEATURE_SCHEMA_NAME)
        self.assertIn("recommended_threshold", payload)
        self.assertEqual(loaded.input_size, module.FEATURE_VECTOR_SIZE)


if __name__ == "__main__":
    unittest.main()
