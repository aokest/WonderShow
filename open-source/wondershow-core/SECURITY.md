# Security

WonderShow Core is a local package and should not require secrets.

Please report security issues privately to the project maintainer before public disclosure. Do not include exploit details in a public issue until a fix is available.

Security expectations:

- local sidecars must bind to loopback by default;
- local sidecars must require a per-session token with at least 128 bits of entropy;
- local sidecar tokens must not be logged, committed, stored in project manifests, or exposed in public URLs;
- frame payloads should be rejected above `WonderShowMediaPipeProtocol.maximumJPEGBytes`;
- portrait masks and landmark arrays should be bounded before allocation or rendering;
- `.wondershow` media asset paths must stay relative to the project root and must not contain `..`, absolute paths, `~`, empty path components, or backslashes;
- plugins receive an empty environment by default; host apps should pass only explicitly allowlisted keys;
- export plugins should write only to a host-authorized directory, using `WonderShowPluginPathSecurity` or an equivalent containment check;
- tokens, signing keys, payment credentials, and private user data must never be committed;
- example files should use dummy data only;
- plugins should document any network or file-system access they require.

## Security Helpers

WonderShow Core includes defensive helpers for host apps and plugin authors:

- `WonderShowManifestValidator` rejects unsafe media paths and out-of-range presenter-effect values.
- `WonderShowMediaPathSecurity` resolves media paths only inside the selected project root.
- `WonderShowMediaPipeSecurity` validates local token plausibility and MediaPipe request/response bounds.
- `WonderShowPluginContext` filters environment values through an explicit allowlist.
- `WonderShowPluginPathSecurity` rejects export destinations outside the authorized directory.

These helpers are part of the public contract. Commercial or third-party hosts should run them before opening an imported project, invoking a sidecar, or handing work to a plugin.
