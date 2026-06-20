# Core Recording Contract

This document freezes the v1.0.0 recording baseline. Recording, source switching, monitor preview, preview composition, and HD export are core business logic. Future features should build on these contracts instead of weakening them.

## Invariants

- Window recording must capture the active/shareable window directly when a window source is selected. Do not record the whole display and crop it back into a window unless the platform API gives no direct window source.
- Monitor preview and exported program video must show the complete active window. The source may be aspect-fit into the program canvas with letterboxing, but it must not be stretched, center-cropped, square-cropped, or inferred-cropped from image content.
- Switching recording source during recording must keep the exported program canvas stable while fitting each new source completely inside that canvas.
- HD export must use the selected program canvas and resolution, with `4K` and `1080p` export paths both preserving source aspect ratio and timeline duration.
- Preview composition and final export must use the same timeline/range rules, including paused recording intervals.
- Any change that touches capture source selection, archive recording, timeline ranges, or program rendering must keep focused regression tests for complete-window output and source-switch behavior.

## Protected Areas

- `ScreenArchiveRecorder`
- `ScreenPreviewService`
- `ProgramVideoRenderer`
- recording timeline generation in `DashboardView`
- `RecordingProjectManifest` / program timeline models

If a new feature conflicts with these contracts, discuss the tradeoff before changing the baseline.
