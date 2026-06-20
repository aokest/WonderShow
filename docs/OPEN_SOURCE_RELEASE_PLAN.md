# WonderShow Open Source Release Plan

Date: 2026-06-21

## Recommendation

Release `WonderShow Core` as the public open-source package, not the full commercial macOS app.

This gives users and developers something real to use:

- `.wondershow` project schemas;
- local MediaPipe sidecar protocol;
- plugin-facing Swift APIs;
- examples and tests.

At the same time, the paid WonderShow app keeps the parts that create commercial value:

- signed macOS app distribution;
- stable real-time capture and monitor preview;
- program compositor and export renderer;
- paid workflow, templates, support, licensing, and updates.

## Created Package

Source directory:

```text
open-source/wondershow-core
```

Release archive:

```text
releases/wondershow-core-1.0.0-<BUILD_VERSION>.zip
```

Regenerate it with:

```bash
./scripts/package-open-source-kit.sh
```

## Publishing Boundary

Open-source repository should include:

- `open-source/wondershow-core/Package.swift`
- `open-source/wondershow-core/Sources/WonderShowCore`
- `open-source/wondershow-core/Tests/WonderShowCoreTests`
- `open-source/wondershow-core/examples`
- `README.md`, `LICENSE`, `NOTICE`, `CONTRIBUTING.md`, `SECURITY.md`, `ROADMAP.md`
- `COMMERCIAL.md` and `PACKAGE_BOUNDARY.md`

Do not publish:

- `Sources/PresenterDirectorApp`
- capture/preview/export implementation;
- app assets that are part of the paid product identity;
- signing, notarization, update, payment, licensing, or telemetry files;
- NAS/Gitea configuration or credentials.

## Suggested GitHub Positioning

Repository name:

```text
wondershow-core
```

Short description:

```text
Open project schema, sidecar protocol, and plugin API for WonderShow.
```

Initial README message:

```text
WonderShow Core is the open ecosystem layer for WonderShow. The commercial macOS app is separate and remains the recommended product for creators who need reliable recording, live preview, export, updates, and support.
```

## Commercial Model

Use open core:

- Free/community: WonderShow Core, docs, examples, community plugins.
- Pro: signed app, recording, preview/export parity, updates, polished workflow.
- Studio/team: priority support, templates, batch/export automation, team workflows, commercial deployment help.

This makes the open-source package useful without making the paid app replaceable.

## Current Product Caveat

Experimental portrait effects are intentionally parked in the commercial app for now because the previous implementation had unacceptable preview/reliability/performance issues. Do not market advanced beautification, emoji face replacement, or background replacement as production-ready until live monitor preview and export behavior are stable.

## GitHub CLI Status

This machine currently cannot use GitHub CLI because `gh` is not installed:

```text
gh: command not found
```

This is not a repository or authentication problem. Install GitHub CLI and authenticate before using `gh repo create`, `gh release create`, or `gh auth status`.

## Verification Commands

```bash
swift test --package-path open-source/wondershow-core
swift test --disable-sandbox --filter OpenSourceReleaseKitTests
./scripts/package-open-source-kit.sh
```
