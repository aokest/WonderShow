#!/usr/bin/env python3
"""Independent WonderShow gesture training assistant.

This tool deliberately stays outside the main Swift app. It wraps the existing
sampler and trainer scripts with a small desktop UI, then exports a portable
`.wsgesture` package that the main app can import later.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import threading
import time
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[1]
APP_SUPPORT_ROOT = Path.home() / "Library" / "Application Support" / "WonderShow" / "GestureTrainingAssistant"


@dataclass(frozen=True)
class AssistantPaths:
    """Filesystem locations used by the standalone training assistant."""

    project_root: Path
    workspace_root: Path
    samples_root: Path
    model_path: Path
    package_path: Path


def timestamp_token() -> str:
    """Returns a compact local timestamp for package filenames."""

    return time.strftime("%Y%m%d-%H%M%S")


def default_paths(profile_name: str = "default") -> AssistantPaths:
    """Builds default paths outside the main app source tree."""

    safe_profile = "".join(ch if ch.isalnum() or ch in ("-", "_") else "_" for ch in profile_name).strip("_") or "default"
    workspace_root = APP_SUPPORT_ROOT / safe_profile
    samples_root = workspace_root / "Samples"
    model_path = workspace_root / "Models" / "wondershow_gesture_model.json"
    package_path = workspace_root / "Exports" / f"{safe_profile}-{timestamp_token()}.wsgesture"
    return AssistantPaths(
        project_root=PROJECT_ROOT,
        workspace_root=workspace_root,
        samples_root=samples_root,
        model_path=model_path,
        package_path=package_path,
    )


def python_executable(project_root: Path = PROJECT_ROOT) -> Path:
    """Returns the preferred Python runtime for MediaPipe tools."""

    venv_python = project_root / ".venv-mediapipe" / "bin" / "python"
    return venv_python if venv_python.exists() else Path(sys.executable)


def ensure_workspace(paths: AssistantPaths) -> None:
    """Creates workspace folders used by the assistant."""

    paths.samples_root.mkdir(parents=True, exist_ok=True)
    paths.model_path.parent.mkdir(parents=True, exist_ok=True)
    paths.package_path.parent.mkdir(parents=True, exist_ok=True)


def build_sampler_command(
    paths: AssistantPaths,
    *,
    camera: str = "auto",
    label: str = "剑指",
    tags: str = "normal,near",
    burst_count: int = 5,
) -> list[str]:
    """Builds the command used to launch the sample collection window."""

    return [
        str(python_executable(paths.project_root)),
        str(paths.project_root / "scripts" / "capture_gesture_samples.py"),
        "--camera",
        camera,
        "--label",
        label,
        "--tags",
        tags,
        "--burst-count",
        str(burst_count),
        "--output-root",
        str(paths.samples_root),
    ]


def build_train_command(
    paths: AssistantPaths,
    *,
    epochs: int = 900,
    min_samples_per_label: int = 3,
    validation_ratio: float = 0.2,
) -> list[str]:
    """Builds the command used to train a gesture model."""

    return [
        str(python_executable(paths.project_root)),
        str(paths.project_root / "scripts" / "train_wondershow_gesture_model.py"),
        "--output",
        str(paths.model_path),
        "--epochs",
        str(epochs),
        "--min-samples-per-label",
        str(min_samples_per_label),
        "--validation-ratio",
        str(validation_ratio),
        str(paths.samples_root),
    ]


def run_json_command(command: list[str]) -> tuple[int, dict[str, Any] | None, str]:
    """Runs a command and parses the last JSON object printed to stdout."""

    completed = subprocess.run(command, text=True, capture_output=True, check=False)
    output = "\n".join(part for part in (completed.stdout, completed.stderr) if part)
    report = parse_json_report(completed.stdout)
    if report is None:
        report = parse_json_report(completed.stderr)
    return completed.returncode, report, output


def parse_json_report(text: str) -> dict[str, Any] | None:
    """Extracts a JSON object from command output."""

    start = text.find("{")
    end = text.rfind("}")
    if start < 0 or end <= start:
        return None
    try:
        payload = json.loads(text[start : end + 1])
    except json.JSONDecodeError:
        return None
    return payload if isinstance(payload, dict) else None


def _format_percent(value: Any) -> str:
    if value is None:
        return "n/a"
    try:
        return f"{float(value) * 100:.1f}%"
    except (TypeError, ValueError):
        return "n/a"


def summarize_training_report(report: dict[str, Any]) -> str:
    """Builds a short human-readable training summary."""

    skipped = report.get("skipped_summary") or {}
    skipped_text = ",".join(f"{key}:{value}" for key, value in sorted(skipped.items())) or "none"
    return (
        f"samples={report.get('samples', 0)} "
        f"labels={','.join(report.get('labels', []))} "
        f"train={_format_percent(report.get('train_accuracy'))} "
        f"validation={_format_percent(report.get('validation_accuracy'))} "
        f"skipped={skipped_text}"
    )


def export_wsgesture_package(
    *,
    model_path: Path,
    package_path: Path,
    report: dict[str, Any] | None,
    profile_name: str,
) -> Path:
    """Exports a portable gesture package for future main-app import."""

    if not model_path.exists():
        raise FileNotFoundError(f"Model not found: {model_path}")
    model_payload = json.loads(model_path.read_text(encoding="utf-8"))
    manifest = {
        "format": "wondershow.gesture-package",
        "format_version": 1,
        "profile_name": profile_name,
        "created_at_unix": int(time.time()),
        "model": {
            "path": "model/wondershow_gesture_model.json",
            "version": model_payload.get("version"),
            "feature_schema": model_payload.get("feature_schema"),
            "labels": model_payload.get("labels", []),
            "recommended_threshold": model_payload.get("recommended_threshold"),
        },
        "training_report": report or {},
    }
    package_path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(package_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2))
        archive.write(model_path, "model/wondershow_gesture_model.json")
    return package_path


class TrainingAssistantApp:
    """Tkinter desktop shell around the sampler and training scripts."""

    def __init__(self, profile_name: str = "default") -> None:
        import tkinter as tk
        from tkinter import ttk

        self.tk = tk
        self.ttk = ttk
        self.profile_name = profile_name
        self.paths = default_paths(profile_name)
        ensure_workspace(self.paths)
        self.last_report: dict[str, Any] | None = None

        self.root = tk.Tk()
        self.root.title("灵演手势训练助手")
        self.root.geometry("780x560")
        self.root.minsize(720, 500)

        self.label_var = tk.StringVar(value="剑指")
        self.light_var = tk.StringVar(value="normal")
        self.distance_var = tk.StringVar(value="near")
        self.camera_var = tk.StringVar(value="auto")
        self.burst_var = tk.IntVar(value=5)
        self.epochs_var = tk.IntVar(value=900)
        self.min_samples_var = tk.IntVar(value=3)
        self.status_var = tk.StringVar(value="准备采样")

        self._build_ui()
        self.refresh_counts()

    def _build_ui(self) -> None:
        tk = self.tk
        ttk = self.ttk

        root_frame = ttk.Frame(self.root, padding=14)
        root_frame.pack(fill=tk.BOTH, expand=True)
        root_frame.columnconfigure(0, weight=1)
        root_frame.rowconfigure(3, weight=1)

        header = ttk.Label(root_frame, text="灵演手势训练助手", font=("Helvetica", 20, "bold"))
        header.grid(row=0, column=0, sticky="w")

        settings = ttk.LabelFrame(root_frame, text="采样设置", padding=10)
        settings.grid(row=1, column=0, sticky="ew", pady=(12, 8))
        for column in range(8):
            settings.columnconfigure(column, weight=1)

        ttk.Label(settings, text="手势").grid(row=0, column=0, sticky="w")
        ttk.Combobox(
            settings,
            textvariable=self.label_var,
            values=["剑指", "枪指", "八字", "揪取", "抓握", "开掌", "未知"],
            state="readonly",
            width=10,
        ).grid(row=0, column=1, sticky="ew", padx=(4, 12))

        ttk.Label(settings, text="光线").grid(row=0, column=2, sticky="w")
        ttk.Combobox(
            settings,
            textvariable=self.light_var,
            values=["normal", "low_light", "backlight"],
            state="readonly",
            width=12,
        ).grid(row=0, column=3, sticky="ew", padx=(4, 12))

        ttk.Label(settings, text="距离").grid(row=0, column=4, sticky="w")
        ttk.Combobox(
            settings,
            textvariable=self.distance_var,
            values=["near", "mid", "far"],
            state="readonly",
            width=8,
        ).grid(row=0, column=5, sticky="ew", padx=(4, 12))

        ttk.Label(settings, text="摄像头").grid(row=0, column=6, sticky="w")
        ttk.Entry(settings, textvariable=self.camera_var, width=8).grid(row=0, column=7, sticky="ew", padx=(4, 0))

        actions = ttk.Frame(root_frame)
        actions.grid(row=2, column=0, sticky="ew", pady=(0, 8))
        for column in range(7):
            actions.columnconfigure(column, weight=1)

        ttk.Button(actions, text="打开采样窗口", command=self.open_sampler).grid(row=0, column=0, sticky="ew", padx=(0, 8))
        ttk.Button(actions, text="刷新样本数", command=self.refresh_counts).grid(row=0, column=1, sticky="ew", padx=(0, 8))
        ttk.Button(actions, text="开始训练", command=self.train_model).grid(row=0, column=2, sticky="ew", padx=(0, 8))
        ttk.Button(actions, text="导出手势包", command=self.export_package).grid(row=0, column=3, sticky="ew", padx=(0, 8))
        ttk.Button(actions, text="打开工作目录", command=self.open_workspace).grid(row=0, column=4, sticky="ew", padx=(0, 8))
        ttk.Label(actions, text="连拍").grid(row=0, column=5, sticky="e")
        ttk.Spinbox(actions, from_=1, to=30, textvariable=self.burst_var, width=5).grid(row=0, column=6, sticky="w")

        report_frame = ttk.LabelFrame(root_frame, text="状态与报告", padding=10)
        report_frame.grid(row=3, column=0, sticky="nsew")
        report_frame.rowconfigure(1, weight=1)
        report_frame.columnconfigure(0, weight=1)
        ttk.Label(report_frame, textvariable=self.status_var).grid(row=0, column=0, sticky="w")
        self.report_text = tk.Text(report_frame, height=18, wrap="word")
        self.report_text.grid(row=1, column=0, sticky="nsew", pady=(8, 0))

        train_settings = ttk.Frame(root_frame)
        train_settings.grid(row=4, column=0, sticky="ew", pady=(8, 0))
        ttk.Label(train_settings, text="epochs").pack(side=tk.LEFT)
        ttk.Spinbox(train_settings, from_=50, to=3000, increment=50, textvariable=self.epochs_var, width=7).pack(side=tk.LEFT, padx=(4, 16))
        ttk.Label(train_settings, text="每类最少样本").pack(side=tk.LEFT)
        ttk.Spinbox(train_settings, from_=1, to=30, textvariable=self.min_samples_var, width=5).pack(side=tk.LEFT, padx=(4, 16))
        ttk.Label(train_settings, text=str(self.paths.workspace_root)).pack(side=tk.LEFT)

    def _append_report(self, text: str) -> None:
        self.report_text.insert(self.tk.END, text.rstrip() + "\n")
        self.report_text.see(self.tk.END)

    def _set_busy(self, text: str) -> None:
        self.status_var.set(text)
        self.root.update_idletasks()

    def open_sampler(self) -> None:
        command = build_sampler_command(
            self.paths,
            camera=self.camera_var.get(),
            label=self.label_var.get(),
            tags=f"{self.light_var.get()},{self.distance_var.get()}",
            burst_count=int(self.burst_var.get()),
        )
        self._append_report("$ " + " ".join(command))
        subprocess.Popen(command)
        self.status_var.set("采样窗口已打开")

    def refresh_counts(self) -> None:
        counts = {}
        for folder in ["剑指", "枪指", "八字", "揪取", "抓握", "开掌", "未知"]:
            directory = self.paths.samples_root / folder
            counts[folder] = len([path for path in directory.rglob("*") if path.suffix.lower() in {".jpg", ".jpeg", ".png", ".webp"}]) if directory.exists() else 0
        self._append_report("样本数: " + "  ".join(f"{key}:{value}" for key, value in counts.items()))

    def train_model(self) -> None:
        command = build_train_command(
            self.paths,
            epochs=int(self.epochs_var.get()),
            min_samples_per_label=int(self.min_samples_var.get()),
        )
        self._append_report("$ " + " ".join(command))
        self._set_busy("训练中...")
        threading.Thread(target=self._train_worker, args=(command,), daemon=True).start()

    def _train_worker(self, command: list[str]) -> None:
        returncode, report, output = run_json_command(command)
        def finish() -> None:
            self._append_report(output)
            if returncode == 0 and report:
                self.last_report = report
                self.status_var.set("训练完成: " + summarize_training_report(report))
            else:
                self.status_var.set("训练失败，请查看报告")
        self.root.after(0, finish)

    def export_package(self) -> None:
        try:
            package_path = export_wsgesture_package(
                model_path=self.paths.model_path,
                package_path=self.paths.package_path,
                report=self.last_report,
                profile_name=self.profile_name,
            )
        except Exception as exc:
            self.status_var.set(f"导出失败: {exc}")
            return
        self.status_var.set(f"已导出: {package_path}")
        self._append_report(f"已导出手势包: {package_path}")

    def open_workspace(self) -> None:
        ensure_workspace(self.paths)
        subprocess.run(["open", str(self.paths.workspace_root)], check=False)

    def run(self) -> None:
        self.root.mainloop()


def parse_args(argv: list[str]) -> argparse.Namespace:
    """Parses CLI options for the assistant."""

    parser = argparse.ArgumentParser(description="WonderShow standalone gesture training assistant")
    parser.add_argument("--profile", default="default", help="Gesture profile name.")
    parser.add_argument("--print-paths", action="store_true", help="Print workspace paths and exit.")
    parser.add_argument("--export", action="store_true", help="Export the current model package and exit.")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    """Entrypoint."""

    args = parse_args(argv)
    paths = default_paths(args.profile)
    ensure_workspace(paths)
    if args.print_paths:
        print(json.dumps({
            "workspace_root": str(paths.workspace_root),
            "samples_root": str(paths.samples_root),
            "model_path": str(paths.model_path),
            "package_path": str(paths.package_path),
        }, ensure_ascii=False, indent=2))
        return 0
    if args.export:
        package_path = export_wsgesture_package(
            model_path=paths.model_path,
            package_path=paths.package_path,
            report=None,
            profile_name=args.profile,
        )
        print(package_path)
        return 0
    TrainingAssistantApp(profile_name=args.profile).run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
