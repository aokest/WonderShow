# 灵演 WonderShow

灵演 WonderShow is a macOS presentation and recording assistant for multiple camera inputs.

It is designed to:

- use a built-in Mac camera, DJI Osmo Pocket 3, Insta360 camera, UVC capture device, or network camera as the speaker camera;
- recognize custom gestures for slide control and annotations;
- record speaker-only or speaker-plus-screen sessions;
- support PowerPoint, WPS, Keynote, PDF viewers, and HTML slide decks.

See [docs/architecture.md](docs/architecture.md) for the product architecture, feasibility notes, and staged development plan.

See [docs/recording-studio-roadmap.md](docs/recording-studio-roadmap.md) for the future recording editor, timeline zoom, picture-in-picture, and export roadmap.

## Repository Remote

- This project uses a NAS-hosted Gitea remote by default, not GitHub.
- Default remote: `nas`
- Remote URL: `ssh://gitea-nas/agent/lingyan.git`

## Current Status

This repository currently contains the tested Swift core logic layer:

- gesture intent to presentation command mapping;
- app compatibility strategy for Office, WPS, generic keyboard control, and HTML decks;
- annotation strategy selection;
- recording pipeline planning;
- multi-camera capability modeling, with Pocket 3 as one verified UVC input.

## Development

Run tests:

```bash
swift test
```

Run the current macOS prototype from Terminal:

```bash
swift run --disable-sandbox PresenterDirectorApp
```

The macOS prototype uses AVFoundation camera discovery and prefers a recognizable tracking camera such as `OsmoPocket3` when it is present, while still falling back to other available camera inputs.

## Easiest Launch For Non-Developers

Build a clickable macOS app bundle:

```bash
bash scripts/build-app.sh
```

Then open the app bundle:

```bash
open "dist/灵演.app"
```

If `dist/灵演.app` already exists, you can also open it directly from Finder by double-clicking it.
