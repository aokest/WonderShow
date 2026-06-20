# WonderShow Core

WonderShow Core is the open package for WonderShow's ecosystem layer. It contains public Swift models for `.wondershow` project manifests, the local MediaPipe sidecar protocol, and a lightweight plugin API for integrations.

The official commercial macOS app is not included in this repository.

## What Is Open

- `.wondershow` project manifest data models.
- Recording source, timeline, layout, export, and presenter-effect configuration schemas.
- Local MediaPipe sidecar request and response contracts.
- Plugin-facing Swift protocols for effect catalogs, input sources, and export integrations.
- Examples that show how third-party tools can read project files or prepare plugin metadata.

## What Is Not Included

- ScreenCaptureKit capture implementation.
- Real-time monitor preview and compositor.
- Program video renderer and export acceleration.
- Paid feature gates, licensing, update channels, and code signing.
- The WonderShow desktop interface and commercial design system.

## License

WonderShow Core is released under Apache-2.0. See `LICENSE` and `NOTICE`.

## Build And Test

```bash
swift test
```

## Package Layout

```text
Sources/WonderShowCore/
  RecordingModel.swift      Public project and export schemas
  MediaPipeProtocol.swift   Local sidecar wire protocol
  PluginAPI.swift           Plugin extension contracts
examples/
  sample-project/           Minimal `.wondershow` manifest
  sidecar-response.json     Example MediaPipe response
  PluginSkeleton.swift      Minimal plugin shape
```

## Commercial Boundary

The open package is intentionally useful on its own: it lets developers inspect project files, generate manifests, validate integrations, build local sidecars, and prototype plugins.

The paid WonderShow app remains the recommended path for creators who need a signed macOS app, stable recording, complete preview/export behavior, polished controls, advanced rendering, and support. See `COMMERCIAL.md` and `PACKAGE_BOUNDARY.md` for the full boundary.

