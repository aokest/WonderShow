# Package Boundary

WonderShow Core is a public compatibility package. It is designed to be useful without revealing the private implementation of the commercial app.

## Included

- Swift package manifest.
- Public `.wondershow` project schema.
- Export setting and timeline schema.
- Presenter visual-effect configuration schema.
- Local MediaPipe sidecar wire format.
- Plugin metadata and extension protocols.
- Tests and examples.

## Not Included

- ScreenCaptureKit capture services.
- Camera preview services.
- ProgramVideoRenderer and compositor internals.
- RecordingSessionService orchestration.
- DashboardView or the commercial UI.
- Licensing, activation, payment, telemetry, code-signing, notarization, or update infrastructure.
- Private assets, credentials, keys, or paid templates.

## Compatibility Rule

The commercial WonderShow app should treat this package as a public contract. Breaking schema changes should be versioned and documented before release.

