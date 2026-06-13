# Presenter Director

Presenter Director is a macOS presentation assistant for DJI Osmo Pocket 3.

It is designed to:

- use Pocket 3 as the tracking speaker camera;
- recognize custom gestures for slide control and annotations;
- record speaker-only or speaker-plus-screen sessions;
- support PowerPoint, WPS, Keynote, PDF viewers, and HTML slide decks.

See [docs/architecture.md](docs/architecture.md) for the product architecture, feasibility notes, and staged development plan.

See [docs/recording-studio-roadmap.md](docs/recording-studio-roadmap.md) for the future recording editor, timeline zoom, picture-in-picture, and export roadmap.

## Current Status

This repository currently contains the tested Swift core logic layer:

- gesture intent to presentation command mapping;
- app compatibility strategy for Office, WPS, generic keyboard control, and HTML decks;
- annotation strategy selection;
- recording pipeline planning;
- Pocket 3 capability modeling as a UVC camera input.

## Development

Run tests:

```bash
swift test
```

Run the current macOS prototype:

```bash
swift run PresenterDirectorApp
```

The next implementation step is to connect the preview panel to AVFoundation camera discovery and default to the `OsmoPocket3` UVC stream when it is present.
