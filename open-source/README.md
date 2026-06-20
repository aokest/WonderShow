# WonderShow Open Source

This directory contains the source packages that can be published publicly without exposing the full WonderShow commercial macOS app.

## Packages

- `wondershow-core`: public project schema, MediaPipe sidecar protocol, and plugin-facing Swift APIs.

## Publishing Intent

WonderShow can be developed as an open ecosystem while keeping the official signed macOS app commercial:

- open the data formats and extension points so developers can build plugins, tools, and sidecars;
- keep capture, composition, export acceleration, licensing, polished UI, and distribution inside the paid app;
- use the open package as the stable contract between community contributions and the product.

The release archive is generated with:

```bash
./scripts/package-open-source-kit.sh
```

