import importlib.util
import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[2] / "scripts" / "gesture_training_assistant.py"


def load_module():
    spec = importlib.util.spec_from_file_location("gesture_training_assistant", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class GestureTrainingAssistantTests(unittest.TestCase):
    def test_default_paths_stay_outside_main_app_sources(self):
        module = load_module()

        paths = module.default_paths()

        self.assertEqual(paths.samples_root.name, "Samples")
        self.assertEqual(paths.model_path.name, "wondershow_gesture_model.json")
        self.assertIn("Application Support", str(paths.workspace_root))
        self.assertNotIn("Sources", str(paths.workspace_root))

    def test_build_train_command_uses_explicit_output_and_epoch_settings(self):
        module = load_module()

        paths = module.AssistantPaths(
            project_root=Path("/repo"),
            workspace_root=Path("/workspace"),
            samples_root=Path("/workspace/Samples"),
            model_path=Path("/workspace/model.json"),
            package_path=Path("/workspace/profile.wsgesture"),
        )

        command = module.build_train_command(paths, epochs=120, min_samples_per_label=4)

        self.assertEqual(command[0], str(module.python_executable(Path("/repo"))))
        self.assertIn("/repo/scripts/train_wondershow_gesture_model.py", command)
        self.assertIn("--output", command)
        self.assertIn("/workspace/model.json", command)
        self.assertIn("--epochs", command)
        self.assertIn("120", command)
        self.assertEqual(command[-1], "/workspace/Samples")

    def test_build_sampler_command_includes_timed_capture_interval(self):
        module = load_module()

        paths = module.AssistantPaths(
            project_root=Path("/repo"),
            workspace_root=Path("/workspace"),
            samples_root=Path("/workspace/Samples"),
            model_path=Path("/workspace/model.json"),
            package_path=Path("/workspace/profile.wsgesture"),
        )

        command = module.build_sampler_command(
            paths,
            label="剑指",
            timed_interval_seconds=1.0,
            timed_start=True,
            subject_id="alice-01",
        )

        self.assertIn("--timed-interval-seconds", command)
        self.assertIn("1.0", command)
        self.assertIn("--timed-start", command)
        self.assertIn("--subject-id", command)
        self.assertIn("alice-01", command)

    def test_ui_texts_localize_all_visible_controls(self):
        module = load_module()

        simplified = module.ui_texts("zh-Hans")
        traditional = module.ui_texts("zh-Hant")
        english = module.ui_texts("en")

        self.assertEqual(simplified["open_sampler"], "打开采样窗口")
        self.assertEqual(traditional["open_sampler"], "開啟採樣視窗")
        self.assertEqual(english["open_sampler"], "Open Sampler")
        self.assertEqual(english["subject_id"], "Collector ID")
        self.assertEqual(traditional["timed_capture"], "定時拍攝")
        self.assertEqual(simplified["status_ready"], "准备采样")

    def test_language_button_labels_are_human_readable(self):
        module = load_module()

        labels = module.language_button_labels()

        self.assertEqual(labels, [("zh-Hans", "简"), ("zh-Hant", "繁"), ("en", "EN")])

    def test_summarize_training_report_highlights_accuracy_and_skips(self):
        module = load_module()

        report = {
            "ok": True,
            "samples": 42,
            "labels": ["sword", "grab"],
            "validation_accuracy": 0.8123,
            "train_accuracy": 0.9,
            "skipped_summary": {"no_hand": 3},
        }

        summary = module.summarize_training_report(report)

        self.assertIn("samples=42", summary)
        self.assertIn("validation=81.2%", summary)
        self.assertIn("no_hand:3", summary)

    def test_localized_guides_cover_all_supported_languages(self):
        module = load_module()

        self.assertEqual(set(module.SUPPORTED_LANGUAGES), {"zh-Hans", "zh-Hant", "en"})
        self.assertIn("静态图片", module.localized_guide("zh-Hans"))
        self.assertIn("定时拍摄", module.localized_guide("zh-Hans"))
        self.assertIn("靜態圖片", module.localized_guide("zh-Hant"))
        self.assertIn("定時拍攝", module.localized_guide("zh-Hant"))
        self.assertIn("static photos", module.localized_guide("en"))
        self.assertIn("timed capture", module.localized_guide("en"))

    def test_localized_guide_falls_back_to_simplified_chinese(self):
        module = load_module()

        self.assertEqual(module.localized_guide("missing"), module.localized_guide("zh-Hans"))

    def test_document_paths_exist_for_each_language(self):
        module = load_module()

        docs = module.localized_document_paths(module.PROJECT_ROOT)

        self.assertEqual(set(docs), {"zh-Hans", "zh-Hant", "en"})
        for path in docs.values():
            self.assertTrue(path.exists(), path)

    def test_export_wsgesture_package_contains_model_and_manifest(self):
        module = load_module()

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            model_path = root / "model.json"
            package_path = root / "profile.wsgesture"
            model_payload = {"version": 2, "feature_schema": "landmark_v2", "labels": ["sword"]}
            model_path.write_text(json.dumps(model_payload), encoding="utf-8")
            report = {"ok": True, "samples": 1}

            module.export_wsgesture_package(
                model_path=model_path,
                package_path=package_path,
                report=report,
                profile_name="Default",
            )

            with zipfile.ZipFile(package_path) as archive:
                names = set(archive.namelist())
                manifest = json.loads(archive.read("manifest.json").decode("utf-8"))
                packaged_model = json.loads(archive.read("model/wondershow_gesture_model.json").decode("utf-8"))

        self.assertIn("manifest.json", names)
        self.assertIn("model/wondershow_gesture_model.json", names)
        self.assertEqual(manifest["profile_name"], "Default")
        self.assertEqual(manifest["model"]["feature_schema"], "landmark_v2")
        self.assertEqual(packaged_model["labels"], ["sword"])


if __name__ == "__main__":
    unittest.main()
