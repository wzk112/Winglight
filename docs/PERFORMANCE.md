# Performance and lightning update — 2026-10-16

Local application: **1.5.1, build 10**. Original Apple Development identity and
bundle identifier retained. The previous installed application is backed up
outside the source tree.

## Changes

- Skip sun shadow sampling/BRDF evaluation only when that contribution is zero.
  Skip studio lighting/reflections only at zero studio weight; fractional
  transitions retain the original calculations.
- Render the opaque aircraft before a far-depth background, then render blended
  flow and rain in the original order. Covered MSAA samples avoid background
  shading. Geometry, textures, shadow sizes/filtering, particle/flow counts,
  resolution, MSAA, HDR limits and frame-rate options are unchanged.
- Stop reading the previous scene after a crossfade reaches its endpoint.
- Build diagnostic dictionaries only for explicit QA readback. Ordinary windows
  use framebuffer-only drawables, as recommended by the MetalKit SDK; QA retains
  drawable readback. Timing diagnostics exclude hidden-window pause intervals.

## Controlled measurements

Apple M5 Pro / 48 GB, release builds, 4720 × 3280 RGBA16F, 4× MSAA, fixed
6× SDR headroom, 12 warm-up frames and 300 measured frames per scene. The
production renderer runs offscreen with identical camera, livery and time inputs.
GPU command-buffer timestamps measure GPU duration; these are not FPS or battery
measurements. Results can vary with device, clocks, temperature and other GPU work.

| Scene | Before (ms) | After (ms) | GPU time saved |
|---|---:|---:|---:|
| A320, daytime clouds | 4.878 | 4.519 | 7.4% |
| A320, night clouds | 4.914 | 4.401 | 10.4% |
| A320, daytime flow | 3.817 | 3.553 | 6.9% |
| A320, studio | 2.383 | 2.289 | 4.0% |
| A320, stars | 3.061 | 2.762 | 9.8% |
| 777, night flow/rain | 3.458 | 3.196 | 7.6% |

Wireframe and 2× MSAA were also checked. Exact measurements, source hashes and
image comparison statistics are in [performance-results.json](performance-results.json).
The 2× check deliberately keeps the same full resolution to isolate sample-count
coverage; it does not represent the ordinary lower-resolution efficient preset.

Eight unchanged scenes were compared over every full-resolution RGBA16F channel.
Night, stars and 777 night captures are bit-identical. Other scenes have at most
0.00048828125 absolute difference (one half-float rounding step below SDR white),
with unchanged HDR maxima and above-SDR channel counts. No nonfinite pixels were
introduced. Both screenshot review and the numerical checks passed.

Native-window tests confirmed playback, scene switching and rendering. Window
occlusion deliberately pauses rendering; trials containing those pauses are
not used to claim an FPS improvement. The original refresh-rate limits remain.

## Lightning redesign

Lightning is an intentional visual change, assessed separately from the eight
unchanged scenes. The previous oversized smooth ribbon is replaced by thin
angular channels, four irregular branches, partial cloud veiling, localized cloud
illumination and material-based aircraft reflections. Subsequent short return
strokes reuse the same channel with fainter branches; event timing varies between
cycles. HDR/SDR limits and reduced-motion behavior are preserved.

The behavior follows the qualitative distinction between an initial branched
discharge and subsequent strokes reusing its channel, described by the
[US National Weather Service](https://www.weather.gov/safety/lightning-science-dart-leaders).
This remains a visual approximation, not an electrical/meteorological simulation.
The final storm scenario averaged 4.510 ms versus the former 4.937 ms, but its
different visuals mean that number is not a like-for-like quality comparison.

40 Swift tests passed, including channel stability, fainter return-stroke branches,
quiet intervals, varying event timing, HDR/SDR limits and reduced motion.

## Reproduce

```sh
./scripts/build.sh
dist/Winglight.app/Contents/MacOS/Winglight --audit-performance /tmp/winglight-after --audit-frames 300
# Run a baseline build with the same audit harness, then:
.venv/bin/python scripts/compare_render_audits.py /tmp/winglight-before /tmp/winglight-after \
  --exclude a320-storm-night --output /tmp/winglight-comparison.json
swift test
```

Raw floating-point captures, PNGs, test/build logs and the installed-binary hash
record are retained in the local performance archive, outside Git. No model or
texture asset was changed; the existing resource-pack manifest still verifies.
