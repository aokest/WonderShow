# WonderShow Community Edition

WonderShow Community Edition is the free, practical build for creators, teachers, and developers. It focuses on a clear recording workflow: record a presentation window, presenter camera, and microphone on macOS, then produce a previewable and exportable project.

## Feature Overview

- Camera input: supports the built-in Mac camera, common UVC cameras, and external capture devices.
- Screen and window recording: record a presentation window, the full display, or manually selected windows.
- Presenter picture-in-picture: supports screen main view with presenter PiP, presenter main view, side-by-side, screen-only, and speaker-only layouts.
- Audio recording: follows the current macOS microphone input and writes a separate raw audio track.
- Project-based workflow: creates a `.wondershow` project with raw tracks, program track, timeline, and export metadata.
- Program preview and export: preview the composed result after recording, then export the final MP4.
- Multilingual UI: Simplified Chinese, Traditional Chinese, and English are built in.

## Use Cases

- Record courses, short lessons, knowledge sharing, product demos, and online talks.
- Capture narrated Keynote, PowerPoint, WPS, PDF, or browser-based slide presentations.
- Prepare presenter PiP material for video platforms, YouTube, and internal learning systems.
- Check camera, microphone, screen-recording permissions, and layouts before a real lesson recording.
- Let developers read the `.wondershow` project format and build project inspection, conversion, archive, or media-management tools.

## How To Use

1. Open `灵演社区版.app`.
2. Allow Camera, Microphone, and Screen Recording permissions in macOS System Settings. Camera permission appears only after the app requests it.
3. Choose the input device and audio input from the right-side panel.
4. Choose the recording source: presentation window, full display, or manually selected windows.
5. Choose the recording mode and layout, such as “Camera + Screen” and “Screen Main + Speaker PiP”.
6. Click “Start Recording”, then wait for program composition after stopping.
7. Use “Preview Program” to check the result, then export the video or keep the project for later processing.

## Highlights

- Community Edition focuses on stable, usable, transparent recording, with only the controls needed for the core workflow.
- Community Edition uses the independent bundle id `com.wondershow.community`, so macOS can manage its permissions separately.
- The app package includes signed permission entitlements so macOS can request Camera, Microphone, and Screen Recording access correctly.
- The recording path inherits the protected v1.0.0 baseline: direct active-window capture, source switching, complete-window display, preview/export parity, and HD export.

## Who The Open-Source Project Is For

- Developers who want to understand the WonderShow project format, recording manifest, timeline, and export configuration.
- Automation developers who want to build `.wondershow` inspectors, converters, batch processors, or media-management tools.
- Teams that want to use the public project format for content archiving, course-material organization, or internal workflow integration.
- Independent developers who want to study how a macOS recording product separates the app experience from an open data format.

The open-source package does not include the full desktop app source, ScreenCaptureKit implementation, live monitor, video compositor, commercial UI, licensing system, or update system. Its purpose is to let the community build tools and integrations on the public project format while keeping a clear boundary around the desktop app itself.

## Support The Author

If WonderShow Community helps you, the About panel includes small QR codes for supporting me with a cola or a few tokens. Thank you for trying it and sending feedback.
