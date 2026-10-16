# Validation

Public-source packaging does not constitute a new complete visual audit.
No renderer or light-timing algorithm changed. Two entries without a verified
license grant were removed; the public catalog has 309 combinations.

The release-preparation checks below are run on the consolidated checkout.
Machine-specific raw logs, older screenshots and previous version directories
remain in the local archive, outside the public repository.

Checks on 2026-10-16, Apple Silicon, Swift 6.4:

- Release build completed; Metal shader compilation and deep/strict bundle
  signature verification passed (ad hoc signing).
- `swift test`: 38 tests passed (23 core, 15 application), including GPU texture
  loading, image dimensions/mipmaps, lighting, occlusion, solar time and weather.
- Python geometry suite: 5 tests passed with NumPy 2.5.4, Pillow 12.3.0 and
  mapbox-earcut 2.1.0.
- All 504 resource files verified against the resource manifest. 1,309 upstream
  texture/model hash references matched local files; catalog has 309 unique entries.
- The built app launched and produced real Metal drawable/depth diagnostics for
  an A320 night scene. This is a runtime smoke check, not a full visual review.
- Public file scan found no machine home paths or private-key/token patterns;
  no tracked file exceeds 50 MiB. Upstream source bytes are preserved by Git attributes.

CoreLocation previously returned `locationUnknown` on the development Mac.
Permission/timeout unit tests cannot prove live coordinate retrieval. Manual
city fallback remains available. HDR luminance, sustained frame rate, energy use
and full scene visual quality require target-device testing.
