import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[2] / "scripts" / "capture_gesture_samples.py"


def load_module():
    spec = importlib.util.spec_from_file_location("capture_gesture_samples", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class CaptureGestureSamplesTests(unittest.TestCase):
    def test_resolve_label_accepts_numbers_chinese_and_aliases(self):
        module = load_module()

        self.assertEqual(module.resolve_label("1").folder, "剑指")
        self.assertEqual(module.resolve_label("指枪").canonical, "finger_gun")
        self.assertEqual(module.resolve_label("finger_gun").folder, "枪指")
        self.assertEqual(module.resolve_label("grab").folder, "抓握")
        self.assertEqual(module.resolve_label("unknown").folder, "未知")

    def test_resolve_label_rejects_unknown_values(self):
        module = load_module()

        with self.assertRaises(ValueError):
            module.resolve_label("not-a-gesture")

    def test_parse_camera_value_accepts_auto_and_indices(self):
        module = load_module()

        self.assertEqual(module.parse_camera_value("auto"), "auto")
        self.assertEqual(module.parse_camera_value("2"), 2)

        with self.assertRaises(ValueError):
            module.parse_camera_value("built-in")

    def test_ensure_sample_directories_creates_all_expected_folders(self):
        module = load_module()

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            module.ensure_sample_directories(root)

            self.assertTrue((root / "剑指").is_dir())
            self.assertTrue((root / "枪指").is_dir())
            self.assertTrue((root / "八字").is_dir())
            self.assertTrue((root / "揪取").is_dir())
            self.assertTrue((root / "抓握").is_dir())
            self.assertTrue((root / "开掌").is_dir())
            self.assertTrue((root / "未知").is_dir())

    def test_next_sample_path_uses_canonical_numbering_without_overwriting(self):
        module = load_module()

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            label = module.resolve_label("剑指")
            module.ensure_sample_directories(root)
            (root / "剑指" / "sword_0001.jpg").write_bytes(b"first")
            (root / "剑指" / "unrelated.jpg").write_bytes(b"other")

            path = module.next_sample_path(root, label, ".jpg")

            self.assertEqual(path.name, "sword_0002.jpg")

    def test_counts_by_label_ignores_non_images(self):
        module = load_module()

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            module.ensure_sample_directories(root)
            (root / "抓握" / "grab_0001.jpg").write_bytes(b"image")
            (root / "抓握" / "notes.txt").write_text("ignore", encoding="utf-8")

            counts = module.counts_by_label(root)

            self.assertEqual(counts["抓握"], 1)
            self.assertEqual(counts["剑指"], 0)

    def test_overlay_lines_are_ascii_for_opencv_text(self):
        module = load_module()

        label = module.resolve_label("剑指")
        lines = module.overlay_lines(label, {"剑指": 1, "枪指": 2, "八字": 3, "揪取": 4, "抓握": 5, "开掌": 6, "未知": 0})

        self.assertTrue(lines)
        for line in lines:
            line.encode("ascii")

    def test_parse_capture_tags_accepts_known_light_and_distance_values(self):
        module = load_module()

        tags = module.parse_capture_tags("low_light, far")

        self.assertEqual(tags.light, "low_light")
        self.assertEqual(tags.distance, "far")

        with self.assertRaises(ValueError):
            module.parse_capture_tags("moonlight")

    def test_quality_metrics_flags_dark_blurry_and_small_hand_frames(self):
        module = load_module()

        import numpy as np

        frame = np.full((80, 120, 3), 18, dtype=np.uint8)
        metrics = module.estimate_frame_quality(frame, hand_box=(50, 30, 8, 8))

        self.assertLess(metrics.brightness, 30)
        self.assertIn("low_light", metrics.flags)
        self.assertIn("blurry", metrics.flags)
        self.assertIn("hand_too_small", metrics.flags)

    def test_next_sample_path_includes_optional_capture_tags(self):
        module = load_module()

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            label = module.resolve_label("剑指")
            tags = module.CaptureTags(light="low_light", distance="far")
            module.ensure_sample_directories(root)

            path = module.next_sample_path(root, label, ".jpg", tags=tags)

            self.assertEqual(path.name, "sword_low_light_far_0001.jpg")


if __name__ == "__main__":
    unittest.main()
