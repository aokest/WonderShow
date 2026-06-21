# WonderShow Community Edition

WonderShow Community Edition is the free, practical build for creators, teachers, and developers. It keeps the core recording workflow: capture a presentation window, presenter camera, and microphone on macOS, then produce a previewable and exportable video project.

The Pro edition is still in development and testing. I hope the Pro edition and companion tools can meet everyone in the near future.

## Feature Overview

- Camera input: supports the built-in Mac camera, common UVC cameras, and external capture devices.
- Screen and window recording: choose a presentation window, the full display, or manually selected recordable windows.
- Presenter picture-in-picture: supports PPT/screen main view with presenter PiP, presenter main view, side-by-side, screen-only, and speaker-only layouts.
- Audio recording: follows the current macOS microphone input and writes a separate raw audio track.
- Project-based workflow: creates a `.wondershow` project with raw tracks, program track, timeline, and export metadata.
- Program preview and export: preview the composed result after recording, then export the final MP4.
- Basic presenter image controls: mirror, brightness, contrast, and softening remain available in the Community Edition.
- Multilingual UI: Simplified Chinese, Traditional Chinese, and English are built in.

## Use Cases

- Record courses, mini lessons, knowledge sharing, product demos, and online talks.
- Capture narrated Keynote, PowerPoint, WPS, PDF, or browser-based slide presentations.
- Prepare presenter PiP material for video platforms, YouTube, and internal training systems.
- Check camera, microphone, screen-recording permissions, and layouts before a real stream or lesson recording.
- Let developers validate the `.wondershow` project format and build readers, validators, converters, or plugin prototypes.

## How To Use

1. Open `灵演社区版.app`.
2. Allow Camera, Microphone, and Screen Recording permissions in macOS System Settings. Camera permission appears only after the app requests it.
3. Choose the input device and audio input from the right-side panel.
4. Choose the recording source: presentation window, full display, or manually selected windows.
5. Choose the recording mode and layout, such as “Camera + Screen” and “PPT Main + Speaker PiP”.
6. Click “Start Recording”, then wait for program composition after stopping.
7. Use “Preview Program” to check the result, then export the video or keep the project for later processing.

## Highlights

- Community Edition focuses on stable, usable, transparent recording. It does not show VIP, SVIP, or gesture-control entry points.
- Community Edition does not include experimental Pro features such as advanced beauty filters, background replacement, Emoji face replacement, or live gesture directing.
- Community Edition uses the independent bundle id `com.wondershow.community`, keeping macOS permissions separate from the main app.
- The app package includes signed permission entitlements so macOS can request Camera, Microphone, and Screen Recording access correctly.
- The recording path inherits the protected v1.0.0 baseline: direct active-window capture, source switching, complete-window display, preview/export parity, and HD export.

## Who The Open-Source Project Is For

- Developers who want to understand the WonderShow project format, recording manifest, timeline, and export configuration.
- Automation developers who want to build `.wondershow` inspectors, converters, batch processors, or media-management tools.
- Researchers who want to integrate local MediaPipe sidecars or experiment with portrait and gesture-recognition protocols.
- Plugin authors who want to prototype third-party effects, input sources, export integrations, or workflow extensions.
- Independent developers who want to study how a macOS recording product separates a commercial app from open protocol boundaries.

The open-source package does not include the complete commercial app source, ScreenCaptureKit implementation, live monitor, video compositor, commercial UI, licensing system, update system, or Pro features. Its purpose is to let the community build tools and integrations on public contracts while preserving a clear path for future paid development.

## Support The Author

If WonderShow Community helps you, the About panel includes small QR codes for supporting me with a cola or a few tokens. Thank you for trying it and sending feedback.
