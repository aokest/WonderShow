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
SUPPORTED_LANGUAGES = ("zh-Hans", "zh-Hant", "en")
LABEL_OPTIONS = [
    ("剑指", "sword"),
    ("枪指", "finger_gun"),
    ("八字", "l_shape"),
    ("揪取", "pinch"),
    ("抓握", "grab"),
    ("开掌", "open_palm"),
    ("未知", "unknown"),
]
LANGUAGE_LABELS = {
    "zh-Hans": "简体中文",
    "zh-Hant": "繁體中文",
    "en": "English",
}
LANGUAGE_SHORT_LABELS = {
    "zh-Hans": "简",
    "zh-Hant": "繁",
    "en": "EN",
}
UI_TEXTS = {
    "zh-Hans": {
        "app_title": "灵演手势训练助手",
        "app_subtitle": "采样、训练、导出手势包",
        "language": "语言",
        "sampling_settings": "采样设置",
        "subject_id": "采样人 ID",
        "subject_hint": "姓名或编号",
        "gesture": "手势",
        "light": "光线",
        "distance": "距离",
        "camera": "摄像头",
        "timed_capture": "定时拍摄",
        "interval": "间隔",
        "seconds": "秒",
        "burst_count": "连拍张数",
        "burst_hint": "每次按 B 保存",
        "actions": "操作",
        "open_sampler": "打开采样窗口",
        "refresh_counts": "刷新样本数",
        "train_model": "开始训练",
        "export_package": "导出手势包",
        "open_workspace": "打开工作目录",
        "open_document": "打开说明文档",
        "training_settings": "训练参数",
        "min_samples": "每类最少样本",
        "guide": "使用说明",
        "report": "状态与报告",
        "status_ready": "准备采样",
        "status_sampler_opened": "采样窗口已打开",
        "status_training": "训练中...",
        "status_train_complete": "训练完成",
        "status_train_failed": "训练失败，请查看报告",
        "status_export_failed": "导出失败",
        "status_exported": "已导出",
        "counts": "样本数",
        "timed_suffix": "定时 {seconds:.1f} 秒/张",
        "labels": ["剑指", "枪指", "八字", "揪取", "抓握", "开掌", "未知"],
    },
    "zh-Hant": {
        "app_title": "靈演手勢訓練助手",
        "app_subtitle": "採樣、訓練、匯出手勢包",
        "language": "語言",
        "sampling_settings": "採樣設定",
        "subject_id": "採樣人 ID",
        "subject_hint": "姓名或編號",
        "gesture": "手勢",
        "light": "光線",
        "distance": "距離",
        "camera": "攝影機",
        "timed_capture": "定時拍攝",
        "interval": "間隔",
        "seconds": "秒",
        "burst_count": "連拍張數",
        "burst_hint": "每次按 B 儲存",
        "actions": "操作",
        "open_sampler": "開啟採樣視窗",
        "refresh_counts": "重新整理樣本數",
        "train_model": "開始訓練",
        "export_package": "匯出手勢包",
        "open_workspace": "開啟工作目錄",
        "open_document": "開啟說明文件",
        "training_settings": "訓練參數",
        "min_samples": "每類最少樣本",
        "guide": "使用說明",
        "report": "狀態與報告",
        "status_ready": "準備採樣",
        "status_sampler_opened": "採樣視窗已開啟",
        "status_training": "訓練中...",
        "status_train_complete": "訓練完成",
        "status_train_failed": "訓練失敗，請查看報告",
        "status_export_failed": "匯出失敗",
        "status_exported": "已匯出",
        "counts": "樣本數",
        "timed_suffix": "定時 {seconds:.1f} 秒/張",
        "labels": ["劍指", "槍指", "八字", "揪取", "抓握", "開掌", "未知"],
    },
    "en": {
        "app_title": "WonderShow Gesture Lab",
        "app_subtitle": "Collect, train, and export gesture packages",
        "language": "Language",
        "sampling_settings": "Sampling",
        "subject_id": "Collector ID",
        "subject_hint": "Name or ID",
        "gesture": "Gesture",
        "light": "Lighting",
        "distance": "Distance",
        "camera": "Camera",
        "timed_capture": "Timed Capture",
        "interval": "Interval",
        "seconds": "sec",
        "burst_count": "Burst Count",
        "burst_hint": "Saved when pressing B",
        "actions": "Actions",
        "open_sampler": "Open Sampler",
        "refresh_counts": "Refresh Counts",
        "train_model": "Train Model",
        "export_package": "Export Package",
        "open_workspace": "Open Workspace",
        "open_document": "Open Docs",
        "training_settings": "Training",
        "min_samples": "Min Samples",
        "guide": "Guide",
        "report": "Status And Report",
        "status_ready": "Ready to collect",
        "status_sampler_opened": "Sampler opened",
        "status_training": "Training...",
        "status_train_complete": "Training complete",
        "status_train_failed": "Training failed. Check the report.",
        "status_export_failed": "Export failed",
        "status_exported": "Exported",
        "counts": "Counts",
        "timed_suffix": "timed {seconds:.1f}s/photo",
        "labels": ["Sword", "Finger Gun", "L-shape", "Pinch", "Grab", "Open Palm", "Unknown"],
    },
}
GUIDE_TEXTS = {
    "zh-Hans": """使用说明

1. 先采集静态图片，不需要采集挥手或缩放的动态过程。
2. 每个手势建议先采 40-80 张：剑指、枪指、八字、揪取、抓握、开掌、未知。
3. 同一个手势尽量覆盖 normal、low_light、backlight，以及 near、mid、far。
4. 如果未来会混用内置摄像头和外接摄像头，训练样本也要混用这些设备。
5. “未知”用于自然手、半握拳、空手或容易误触发的姿势，它能降低演讲误触发。
6. 需要批量静态样本时可开启定时拍摄，例如每 1 秒保存一张。
7. 点击“打开采样窗口”采集，回到本窗口点“刷新样本数”检查数量。
8. 样本够了以后点“开始训练”，再看训练报告和混淆矩阵摘要。
9. 点击“导出手势包”生成 .wsgesture。主灵演 App 后续只导入这个包，不需要训练依赖。

采样窗口快捷键：Enter/Space 保存单张，B 连拍，T 开关定时拍摄，1-7 切换类别，C 切换摄像头，Q/Esc 退出。
""",
    "zh-Hant": """使用說明

1. 先採集靜態圖片，不需要採集揮手或縮放的動態過程。
2. 每個手勢建議先採 40-80 張：劍指、槍指、八字、揪取、抓握、開掌、未知。
3. 同一個手勢盡量覆蓋 normal、low_light、backlight，以及 near、mid、far。
4. 如果未來會混用內建攝影機和外接攝影機，訓練樣本也要混用這些設備。
5. 「未知」用於自然手、半握拳、空手或容易誤觸發的姿勢，它能降低演講誤觸發。
6. 需要批量靜態樣本時可開啟定時拍攝，例如每 1 秒儲存一張。
7. 點擊「開啟採樣視窗」採集，回到本視窗點「重新整理樣本數」檢查數量。
8. 樣本夠了以後點「開始訓練」，再看訓練報告和混淆矩陣摘要。
9. 點擊「匯出手勢包」生成 .wsgesture。主靈演 App 後續只匯入這個包，不需要訓練依賴。

採樣視窗快捷鍵：Enter/Space 儲存單張，B 連拍，T 開關定時拍攝，1-7 切換類別，C 切換攝影機，Q/Esc 離開。
""",
    "en": """User Guide

1. Start with static photos. You do not need to record swipe or zoom motion yet.
2. Aim for 40-80 photos per gesture: Sword, Finger Gun, L-shape, Pinch, Grab, Open Palm, and Unknown.
3. For the same gesture, cover normal, low_light, backlight, plus near, mid, and far distances.
4. If you may use both the built-in camera and external cameras later, include both device types in the samples.
5. Unknown is for natural hands, half-fists, no clear gesture, or poses that might cause false triggers.
6. Enable timed capture when you need many static samples, for example one photo every 1 second.
7. Click "Open Sampler" to collect samples, then return here and click "Refresh Counts".
8. When there are enough samples, click "Train Model" and review the training report summary.
9. Click "Export Package" to create a .wsgesture file. The main WonderShow app should import this package later without training dependencies.

Sampler shortcuts: Enter/Space saves one photo, B captures a burst, T toggles timed capture, 1-7 switches labels, C switches camera, Q/Esc exits.
""",
}


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


def localized_guide(language: str) -> str:
    """Returns the in-app guide text for a supported language."""

    return GUIDE_TEXTS.get(language, GUIDE_TEXTS["zh-Hans"])


def ui_texts(language: str) -> dict[str, Any]:
    """Returns localized UI copy for the assistant."""

    return UI_TEXTS.get(language, UI_TEXTS["zh-Hans"])


def language_button_labels() -> list[tuple[str, str]]:
    """Returns compact labels for the language segmented control."""

    return [(language, LANGUAGE_SHORT_LABELS[language]) for language in SUPPORTED_LANGUAGES]


def localized_label_options(language: str) -> list[str]:
    """Returns localized gesture labels in stable canonical order."""

    return list(ui_texts(language)["labels"])


def canonical_label_from_display(display: str, language: str) -> str:
    """Maps a localized gesture display value back to the sampler label."""

    labels = localized_label_options(language)
    if display in labels:
        index = labels.index(display)
        return LABEL_OPTIONS[index][0]
    for raw_label, _canonical in LABEL_OPTIONS:
        if display == raw_label:
            return raw_label
    return LABEL_OPTIONS[0][0]


def localized_document_paths(project_root: Path = PROJECT_ROOT) -> dict[str, Path]:
    """Returns the user-facing documentation files for all supported languages."""

    docs_root = project_root / "docs"
    return {
        "zh-Hans": docs_root / "gesture-training-assistant.zh-Hans.md",
        "zh-Hant": docs_root / "gesture-training-assistant.zh-Hant.md",
        "en": docs_root / "gesture-training-assistant.en.md",
    }


def build_sampler_command(
    paths: AssistantPaths,
    *,
    camera: str = "auto",
    label: str = "剑指",
    tags: str = "normal,near",
    burst_count: int = 5,
    timed_interval_seconds: float = 1.0,
    timed_start: bool = False,
    subject_id: str = "",
) -> list[str]:
    """Builds the command used to launch the sample collection window."""

    command = [
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
        "--subject-id",
        subject_id.strip(),
        "--timed-interval-seconds",
        f"{max(0.2, float(timed_interval_seconds)):.1f}",
    ]
    if timed_start:
        command.append("--timed-start")
    return command


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
        self.root.title(ui_texts("zh-Hans")["app_title"])
        self.root.geometry("1040x740")
        self.root.minsize(940, 680)
        self.root.configure(background="#f6f8fb")

        self.language_var = tk.StringVar(value="zh-Hans")
        self.subject_id_var = tk.StringVar(value="" if profile_name == "default" else profile_name)
        self.label_var = tk.StringVar(value="剑指")
        self.light_var = tk.StringVar(value="normal")
        self.distance_var = tk.StringVar(value="near")
        self.camera_var = tk.StringVar(value="auto")
        self.burst_var = tk.IntVar(value=5)
        self.timed_enabled_var = tk.BooleanVar(value=False)
        self.timed_interval_var = tk.DoubleVar(value=1.0)
        self.epochs_var = tk.IntVar(value=900)
        self.min_samples_var = tk.IntVar(value=3)
        self.status_var = tk.StringVar(value=ui_texts("zh-Hans")["status_ready"])
        self._status_key = "status_ready"
        self._localized_widgets: dict[str, list[Any]] = {}
        self._language_buttons: dict[str, Any] = {}

        self._configure_style()
        self._build_ui()
        self.update_language()
        self.refresh_counts()

    def _configure_style(self) -> None:
        """Applies a compact desktop style to the assistant."""

        ttk = self.ttk
        style = ttk.Style(self.root)
        try:
            style.theme_use("clam")
        except self.tk.TclError:
            pass

        style.configure(".", font=("Helvetica", 12))
        style.configure("TLabel", background="#ffffff", foreground="#27323f")
        style.configure("App.TFrame", background="#f6f8fb")
        style.configure("Panel.TFrame", background="#ffffff", relief="flat")
        style.configure("Header.TFrame", background="#f6f8fb")
        style.configure("Title.TLabel", background="#f6f8fb", foreground="#12202b", font=("Helvetica", 28, "bold"))
        style.configure("Subtitle.TLabel", background="#f6f8fb", foreground="#6b7788", font=("Helvetica", 12))
        style.configure("Section.TLabel", background="#ffffff", foreground="#12202b", font=("Helvetica", 14, "bold"))
        style.configure("Muted.TLabel", background="#ffffff", foreground="#7b8794", font=("Helvetica", 11))
        style.configure("Status.TLabel", background="#ffffff", foreground="#0d9488", font=("Helvetica", 12, "bold"))
        style.configure("Card.TLabelframe", background="#ffffff", bordercolor="#dce5ea", borderwidth=1, relief="solid")
        style.configure("Card.TLabelframe.Label", background="#ffffff", foreground="#12202b", font=("Helvetica", 13, "bold"))
        style.configure("Primary.TButton", background="#0d9488", foreground="#ffffff", font=("Helvetica", 12, "bold"), padding=(15, 10))
        style.map(
            "Primary.TButton",
            background=[("active", "#0f766e"), ("pressed", "#115e59")],
            foreground=[("active", "#ffffff"), ("pressed", "#ffffff")],
        )
        style.configure("Tool.TButton", background="#eef4f6", foreground="#263340", padding=(12, 9))
        style.map("Tool.TButton", background=[("active", "#e1ecef"), ("pressed", "#d3e2e6")])
        style.configure("Language.TButton", background="#ffffff", foreground="#536170", padding=(10, 6), font=("Helvetica", 12, "bold"))
        style.configure("Selected.Language.TButton", background="#ccfbf1", foreground="#0f766e", padding=(10, 6), font=("Helvetica", 12, "bold"))
        style.map(
            "Language.TButton",
            background=[("active", "#eef4f6"), ("pressed", "#dce9ec")],
            foreground=[("active", "#263340")],
        )
        style.map(
            "Selected.Language.TButton",
            background=[("active", "#99f6e4"), ("pressed", "#5eead4")],
            foreground=[("active", "#0f766e")],
        )
        style.configure("TCheckbutton", background="#ffffff", foreground="#27323f")
        style.configure("TCombobox", padding=(6, 5))
        style.configure("TEntry", padding=(6, 5))

    def _build_ui(self) -> None:
        tk = self.tk
        ttk = self.ttk

        root_frame = ttk.Frame(self.root, padding=18, style="App.TFrame")
        root_frame.pack(fill=tk.BOTH, expand=True)
        root_frame.columnconfigure(0, weight=0, minsize=360)
        root_frame.columnconfigure(1, weight=1)
        root_frame.rowconfigure(1, weight=1)

        header = ttk.Frame(root_frame, style="Header.TFrame")
        header.grid(row=0, column=0, columnspan=2, sticky="ew", pady=(0, 14))
        header.columnconfigure(0, weight=1)
        self.title_label = self._localized_label(header, "app_title", style="Title.TLabel")
        self.title_label.grid(row=0, column=0, sticky="w")
        self.subtitle_label = self._localized_label(header, "app_subtitle", style="Subtitle.TLabel")
        self.subtitle_label.grid(row=1, column=0, sticky="w", pady=(2, 0))

        language_frame = ttk.Frame(header, style="App.TFrame")
        language_frame.grid(row=0, column=1, rowspan=2, sticky="ne")
        self._localized_label(language_frame, "language", style="Subtitle.TLabel").pack(side=tk.LEFT, padx=(0, 8))
        for language, short_label in language_button_labels():
            button = ttk.Button(
                language_frame,
                text=short_label,
                command=lambda value=language: self.set_language(value),
                style="Language.TButton",
                width=4,
            )
            button.pack(side=tk.LEFT, padx=(0, 6))
            self._language_buttons[language] = button

        left = ttk.Frame(root_frame, style="App.TFrame")
        left.grid(row=1, column=0, sticky="nsew", padx=(0, 14))
        left.columnconfigure(0, weight=1)

        right = ttk.Frame(root_frame, style="App.TFrame")
        right.grid(row=1, column=1, sticky="nsew")
        right.columnconfigure(0, weight=1)
        right.rowconfigure(1, weight=1)

        settings = self._localized_labelframe(left, "sampling_settings", padding=14)
        settings.grid(row=0, column=0, sticky="ew")
        for column in range(2):
            settings.columnconfigure(column, weight=1)

        self._localized_label(settings, "subject_id").grid(row=0, column=0, columnspan=2, sticky="w")
        ttk.Entry(settings, textvariable=self.subject_id_var).grid(row=1, column=0, columnspan=2, sticky="ew", pady=(4, 12))
        self.subject_hint_label = self._localized_label(settings, "subject_hint", style="Muted.TLabel")
        self.subject_hint_label.grid(row=2, column=0, columnspan=2, sticky="w", pady=(0, 12))

        self._localized_label(settings, "gesture").grid(row=3, column=0, sticky="w")
        self.gesture_picker = ttk.Combobox(
            settings,
            textvariable=self.label_var,
            values=localized_label_options(self.language_var.get()),
            state="readonly",
        )
        self.gesture_picker.grid(row=4, column=0, sticky="ew", pady=(4, 12), padx=(0, 8))

        self._localized_label(settings, "light").grid(row=3, column=1, sticky="w")
        ttk.Combobox(
            settings,
            textvariable=self.light_var,
            values=["normal", "low_light", "backlight"],
            state="readonly",
        ).grid(row=4, column=1, sticky="ew", pady=(4, 12))

        self._localized_label(settings, "distance").grid(row=5, column=0, sticky="w")
        ttk.Combobox(
            settings,
            textvariable=self.distance_var,
            values=["near", "mid", "far"],
            state="readonly",
        ).grid(row=6, column=0, sticky="ew", pady=(4, 12), padx=(0, 8))

        self._localized_label(settings, "camera").grid(row=5, column=1, sticky="w")
        ttk.Entry(settings, textvariable=self.camera_var).grid(row=6, column=1, sticky="ew", pady=(4, 12))

        timed_row = ttk.Frame(settings, style="Panel.TFrame")
        timed_row.grid(row=7, column=0, columnspan=2, sticky="ew", pady=(0, 12))
        timed_row.columnconfigure(2, weight=1)
        self.timed_checkbutton = self._localized_checkbutton(timed_row, "timed_capture", variable=self.timed_enabled_var)
        self.timed_checkbutton.grid(row=0, column=0, sticky="w")
        self._localized_label(timed_row, "interval").grid(row=0, column=1, sticky="e", padx=(12, 4))
        ttk.Spinbox(
            timed_row,
            from_=0.2,
            to=10.0,
            increment=0.1,
            textvariable=self.timed_interval_var,
            width=6,
            format="%.1f",
        ).grid(row=0, column=2, sticky="w")
        self._localized_label(timed_row, "seconds").grid(row=0, column=3, sticky="w", padx=(4, 0))

        self._localized_label(settings, "burst_count").grid(row=8, column=0, sticky="w")
        ttk.Spinbox(settings, from_=1, to=30, textvariable=self.burst_var, width=8).grid(row=9, column=0, sticky="ew", pady=(4, 0), padx=(0, 8))
        self._localized_label(settings, "burst_hint", style="Muted.TLabel").grid(row=9, column=1, sticky="w", pady=(4, 0))

        actions = self._localized_labelframe(left, "actions", padding=14)
        actions.grid(row=1, column=0, sticky="ew", pady=(12, 0))
        actions.columnconfigure(0, weight=1)
        actions.columnconfigure(1, weight=1)

        self._localized_button(actions, "open_sampler", command=self.open_sampler, style="Primary.TButton").grid(row=0, column=0, columnspan=2, sticky="ew")
        self._localized_button(actions, "refresh_counts", command=self.refresh_counts, style="Tool.TButton").grid(row=1, column=0, sticky="ew", pady=(10, 0), padx=(0, 6))
        self._localized_button(actions, "train_model", command=self.train_model, style="Tool.TButton").grid(row=1, column=1, sticky="ew", pady=(10, 0))
        self._localized_button(actions, "export_package", command=self.export_package, style="Tool.TButton").grid(row=2, column=0, sticky="ew", pady=(8, 0), padx=(0, 6))
        self._localized_button(actions, "open_workspace", command=self.open_workspace, style="Tool.TButton").grid(row=2, column=1, sticky="ew", pady=(8, 0))
        self._localized_button(actions, "open_document", command=self.open_document, style="Tool.TButton").grid(row=3, column=0, columnspan=2, sticky="ew", pady=(8, 0))

        train_settings = self._localized_labelframe(left, "training_settings", padding=14)
        train_settings.grid(row=2, column=0, sticky="ew", pady=(12, 0))
        train_settings.columnconfigure(0, weight=1)
        train_settings.columnconfigure(1, weight=1)
        ttk.Label(train_settings, text="epochs").grid(row=0, column=0, sticky="w")
        self._localized_label(train_settings, "min_samples").grid(row=0, column=1, sticky="w")
        ttk.Spinbox(train_settings, from_=50, to=3000, increment=50, textvariable=self.epochs_var, width=7).grid(row=1, column=0, sticky="ew", pady=(4, 10), padx=(0, 8))
        ttk.Spinbox(train_settings, from_=1, to=30, textvariable=self.min_samples_var, width=5).grid(row=1, column=1, sticky="ew", pady=(4, 10))
        ttk.Label(train_settings, text=str(self.paths.workspace_root), style="Muted.TLabel", wraplength=280).grid(row=2, column=0, columnspan=2, sticky="w")

        guide_frame = self._localized_labelframe(right, "guide", padding=14)
        guide_frame.grid(row=0, column=0, sticky="ew", pady=(0, 12))
        guide_frame.columnconfigure(0, weight=1)
        guide_frame.rowconfigure(0, weight=1)
        self.guide_text = tk.Text(
            guide_frame,
            height=10,
            wrap="word",
            bg="#fbfdfe",
            fg="#27323f",
            insertbackground="#0d9488",
            relief="flat",
            padx=10,
            pady=8,
            font=("Helvetica", 12),
        )
        guide_scroll = ttk.Scrollbar(guide_frame, orient=tk.VERTICAL, command=self.guide_text.yview)
        self.guide_text.configure(yscrollcommand=guide_scroll.set)
        self.guide_text.grid(row=0, column=0, sticky="ew")
        guide_scroll.grid(row=0, column=1, sticky="ns")

        report_frame = self._localized_labelframe(right, "report", padding=14)
        report_frame.grid(row=1, column=0, sticky="nsew")
        report_frame.rowconfigure(1, weight=1)
        report_frame.columnconfigure(0, weight=1)
        ttk.Label(report_frame, textvariable=self.status_var, style="Status.TLabel").grid(row=0, column=0, sticky="w")
        self.report_text = tk.Text(
            report_frame,
            height=18,
            wrap="word",
            bg="#fbfdfe",
            fg="#27323f",
            insertbackground="#0d9488",
            relief="flat",
            padx=10,
            pady=8,
            font=("Menlo", 11),
        )
        report_scroll = ttk.Scrollbar(report_frame, orient=tk.VERTICAL, command=self.report_text.yview)
        self.report_text.configure(yscrollcommand=report_scroll.set)
        self.report_text.grid(row=1, column=0, sticky="nsew", pady=(8, 0))
        report_scroll.grid(row=1, column=1, sticky="ns", pady=(8, 0))

    def _register_localized_widget(self, widget: Any, key: str) -> Any:
        self._localized_widgets.setdefault(key, []).append(widget)
        return widget

    def _localized_label(self, parent: Any, key: str, **kwargs: Any) -> Any:
        widget = self.ttk.Label(parent, text="", **kwargs)
        return self._register_localized_widget(widget, key)

    def _localized_button(self, parent: Any, key: str, **kwargs: Any) -> Any:
        widget = self.ttk.Button(parent, text="", **kwargs)
        return self._register_localized_widget(widget, key)

    def _localized_checkbutton(self, parent: Any, key: str, **kwargs: Any) -> Any:
        widget = self.ttk.Checkbutton(parent, text="", **kwargs)
        return self._register_localized_widget(widget, key)

    def _localized_labelframe(self, parent: Any, key: str, **kwargs: Any) -> Any:
        widget = self.ttk.LabelFrame(parent, text="", style="Card.TLabelframe", **kwargs)
        return self._register_localized_widget(widget, key)

    def _append_report(self, text: str) -> None:
        self.report_text.insert(self.tk.END, text.rstrip() + "\n")
        self.report_text.see(self.tk.END)

    def _set_busy(self, text: str) -> None:
        self.status_var.set(text)
        self.root.update_idletasks()

    def set_language(self, language: str) -> None:
        """Switches the assistant language from the segmented control."""

        if language not in SUPPORTED_LANGUAGES:
            return
        self.language_var.set(language)
        self.update_language()

    def update_language(self) -> None:
        """Refreshes all localized UI copy."""

        language = self.language_var.get()
        texts = ui_texts(language)
        self.root.title(texts["app_title"])
        for key, widgets in self._localized_widgets.items():
            for widget in widgets:
                widget.configure(text=texts[key])

        previous_language = getattr(self, "_current_language", language)
        current_canonical_label = canonical_label_from_display(self.label_var.get(), previous_language)
        localized_labels = localized_label_options(language)
        self.gesture_picker.configure(values=localized_labels)
        canonical_index = next(
            (index for index, (raw_label, _canonical) in enumerate(LABEL_OPTIONS) if raw_label == current_canonical_label),
            0,
        )
        self.label_var.set(localized_labels[canonical_index])

        for button_language, button in self._language_buttons.items():
            selected = button_language == language
            button.configure(style="Selected.Language.TButton" if selected else "Language.TButton")

        self.update_guide()
        self.status_var.set(texts.get(self._status_key, texts["status_ready"]))
        self._current_language = language

    def update_guide(self) -> None:
        """Refreshes the in-app guide when the user changes language."""

        self.guide_text.configure(state="normal")
        self.guide_text.delete("1.0", self.tk.END)
        self.guide_text.insert("1.0", localized_guide(self.language_var.get()))
        self.guide_text.configure(state="disabled")

    def open_sampler(self) -> None:
        texts = ui_texts(self.language_var.get())
        command = build_sampler_command(
            self.paths,
            camera=self.camera_var.get(),
            label=canonical_label_from_display(self.label_var.get(), self.language_var.get()),
            tags=f"{self.light_var.get()},{self.distance_var.get()}",
            burst_count=int(self.burst_var.get()),
            timed_interval_seconds=float(self.timed_interval_var.get()),
            timed_start=bool(self.timed_enabled_var.get()),
            subject_id=self.subject_id_var.get(),
        )
        self._append_report("$ " + " ".join(command))
        subprocess.Popen(command)
        timed_text = ""
        if self.timed_enabled_var.get():
            timed_text = " / " + texts["timed_suffix"].format(seconds=float(self.timed_interval_var.get()))
        self._status_key = "status_sampler_opened"
        self.status_var.set(f"{texts['status_sampler_opened']}{timed_text}")

    def refresh_counts(self) -> None:
        counts = {}
        for folder in ["剑指", "枪指", "八字", "揪取", "抓握", "开掌", "未知"]:
            directory = self.paths.samples_root / folder
            counts[folder] = len([path for path in directory.rglob("*") if path.suffix.lower() in {".jpg", ".jpeg", ".png", ".webp"}]) if directory.exists() else 0
        self._append_report(ui_texts(self.language_var.get())["counts"] + ": " + "  ".join(f"{key}:{value}" for key, value in counts.items()))

    def train_model(self) -> None:
        command = build_train_command(
            self.paths,
            epochs=int(self.epochs_var.get()),
            min_samples_per_label=int(self.min_samples_var.get()),
        )
        self._append_report("$ " + " ".join(command))
        self._status_key = "status_training"
        self._set_busy(ui_texts(self.language_var.get())["status_training"])
        threading.Thread(target=self._train_worker, args=(command,), daemon=True).start()

    def _train_worker(self, command: list[str]) -> None:
        returncode, report, output = run_json_command(command)
        def finish() -> None:
            self._append_report(output)
            if returncode == 0 and report:
                self.last_report = report
                self._status_key = "status_train_complete"
                self.status_var.set(ui_texts(self.language_var.get())["status_train_complete"] + ": " + summarize_training_report(report))
            else:
                self._status_key = "status_train_failed"
                self.status_var.set(ui_texts(self.language_var.get())["status_train_failed"])
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
            self._status_key = "status_export_failed"
            self.status_var.set(f"{ui_texts(self.language_var.get())['status_export_failed']}: {exc}")
            return
        self._status_key = "status_exported"
        self.status_var.set(f"{ui_texts(self.language_var.get())['status_exported']}: {package_path}")
        self._append_report(f"{ui_texts(self.language_var.get())['status_exported']}: {package_path}")

    def open_workspace(self) -> None:
        ensure_workspace(self.paths)
        subprocess.run(["open", str(self.paths.workspace_root)], check=False)

    def open_document(self) -> None:
        docs = localized_document_paths(self.paths.project_root)
        path = docs.get(self.language_var.get(), docs["zh-Hans"])
        subprocess.run(["open", str(path)], check=False)

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
