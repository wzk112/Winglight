# Validation

## 1.5.0 public-source packaging

Public-source packaging did not constitute a new complete visual audit.
No renderer or light-timing algorithm changed in 1.5.0. Two entries without a verified
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
- Cloned the public repository from GitHub, retrieved the complete resource pack
  through the anonymous public download URL, and verified archive SHA-256
  `e16818c130ab0397e8f6d2a213be3c1827fa9464b1c5bb16f85c6b0357680748`.
  All 504 resources and 45 accompanying license/attribution files were restored.
  A subsequent build and deep/strict signature check passed, with no changes to
  tracked files. This validates the published source/resource retrieval route.
- Removed build caches and the temporary validation clone, then launched the
  retained application again. Metal drawable/depth output and bundle signature
  verification passed, confirming runtime resources load from the app bundle.

## 1.5.1 release preparation — 2026-10-16

- Rebuilt the release executable and Metal library from the release checkout.
  The Apple Silicon app reports 1.5.1 / build 10, macOS 15 minimum. Deep/strict
  signature verification passed using the existing Apple Development identity;
  this is not a Developer ID notarization.
- Re-ran all 40 Swift tests (23 core, 17 application) and 5 Python geometry tests:
  zero failures. All 504 source resources still match the immutable 1.5.0 manifest.
- Verified all 501 bundled runtime resources against that manifest, and all 40
  upstream license/attribution evidence files against their inventory. Current
  project license/notices and the shader source/library match the checkout.
- Ran the rebuilt standalone bundle through the production Metal storm renderer
  at 4720 × 3280, 4× MSAA and fixed 6× SDR headroom. Its floating-point lightning
  capture is bit-identical to the final audited 1.5.1 capture. The shader and
  renderer hashes match the controlled performance evidence in
  [PERFORMANCE.md](PERFORMANCE.md). This release smoke check is not a new benchmark.
- The ZIP carries the complete app, license notices, release notes and a
  `SOURCE.txt` with its exact Git commit and corresponding-source downloads.
  The compatible 1.5.0 resource archive remains unchanged.

CoreLocation previously returned `locationUnknown` on the development Mac.
Permission/timeout unit tests cannot prove live coordinate retrieval. Manual
city fallback remains available. HDR luminance, sustained frame rate, energy use
and full scene visual quality require target-device testing.
