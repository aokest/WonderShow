import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np


SCRIPT_PATH = Path(__file__).resolve().parents[2] / "scripts" / "train_wondershow_gesture_model.py"


def load_module():
    spec = importlib.util.spec_from_file_location("train_wondershow_gesture_model", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class TrainWonderShowGestureModelTests(unittest.TestCase):
    def test_parse_label_accepts_natural_and_unknown_negative_samples(self):
        module = load_module()

        self.assertEqual(module.parse_label(Path("自然/natural_0001.jpg")), "natural")
        self.assertEqual(module.parse_label(Path("unknown/other_0001.jpg")), "unknown")
        self.assertEqual(module.parse_label(Path("负样本/sample.jpg")), "unknown")

    def test_default_output_path_is_user_application_support(self):
        module = load_module()

        output = module.default_user_model_path()

        self.assertIn("Application Support", str(output))
        self.assertEqual(output.name, "wondershow_gesture_model.json")

    def test_self_test_does_not_write_default_user_model_without_output(self):
        module = load_module()

        args = module.parse_args(["--self-test"])

        self.assertIsNone(args.output)

    def test_validate_training_labels_reports_small_classes(self):
        module = load_module()

        labels = ["sword", "sword", "finger_gun", "natural"]
        errors = module.validate_training_labels(labels, minimum_samples_per_label=2)

        self.assertTrue(any("finger_gun" in error for error in errors))
        self.assertTrue(any("natural" in error for error in errors))

    def test_build_training_report_includes_validation_metrics_and_confusion_matrix(self):
        module = load_module()

        labels = ["sword", "finger_gun"]
        sample_labels = ["sword", "sword", "finger_gun", "finger_gun"]
        predictions = ["sword", "finger_gun", "finger_gun", "finger_gun"]
        skipped = [{"path": "bad.jpg", "reason": "no_hand"}]

        report = module.build_training_report(
            output_path=Path("/tmp/model.json"),
            labels=labels,
            sample_labels=sample_labels,
            train_predictions=predictions,
            validation_labels=sample_labels,
            validation_predictions=predictions,
            skipped=skipped,
            feature_schema="landmark_v2",
        )

        self.assertTrue(report["ok"])
        self.assertEqual(report["samples"], 4)
        self.assertAlmostEqual(report["train_accuracy"], 0.75)
        self.assertAlmostEqual(report["validation_accuracy"], 0.75)
        self.assertEqual(report["confusion_matrix"]["sword"]["finger_gun"], 1)
        self.assertEqual(report["skipped_summary"]["no_hand"], 1)

    def test_split_validation_indices_keeps_tiny_classes_in_training(self):
        module = load_module()

        label_indices = np.asarray([0, 0, 0, 1], dtype=np.int64)
        train_indices, validation_indices = module.split_validation_indices(label_indices, validation_ratio=0.34, seed=3)

        self.assertEqual(set(train_indices.tolist()), {0, 1, 2, 3})
        self.assertEqual(validation_indices.tolist(), [])


if __name__ == "__main__":
    unittest.main()
