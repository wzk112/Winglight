# Changelog

## 1.5.1 — local performance update, 2026-10-16

- Skip lighting and shadow calculations only when their contribution is exactly
  zero; preserve active lighting and fractional scene transitions.
- Draw the depth-tested far background after opaque aircraft geometry and before
  translucent flow/rain, retaining the same MSAA sample count and all particles.
- Skip the previous-frame texture read after scene crossfades finish.
- Avoid assembling diagnostic dictionaries during normal rendering.
- Keep ordinary drawables framebuffer-only; enable texture readback only for QA.
- Replace smooth oversized lightning ribbons with finer angular channels,
  irregular branches, partial cloud veiling and localized cloud illumination.
  Return strokes reuse the channel, vary between events, and light aircraft
  through their existing material response. Reduced-motion and SDR/HDR limits remain.
- Add deterministic full-resolution performance/float-image audits and a comparison
  script. Measurements and quality checks are recorded in `docs/PERFORMANCE.md`.

## 1.5.0 — 2026-10-16

First public source release, based on the local Winglight 1.5 project.

- Native SwiftUI/AppKit interface and Metal renderer, nine aircraft variants,
  17 geometry assemblies, exterior lighting, shadows, HDR/EDR, solar time,
  manually selected weather, motion, and multiple backgrounds.
- Publish 309 model/livery combinations with pinned upstream provenance.
  Exclude the previous United Airlines 2019 and Transavia 737 textures from
  YV3399/B737800-Liveries because that pinned repository has no license grant.
- Consolidate the working project into one Git repository. Keep previous
  releases and raw machine-specific QA outside the public source tree.
- Make build paths relative to the checkout; default output is
  `dist/Winglight.app`, with ad hoc signing unless explicitly overridden.
- Publish large binary resources separately with archive and per-file SHA-256
  checks; retain original AC3D sources, conversion scripts, and source records.
- Add a dependency/license inventory and bundle upstream license notices.

Earlier 1.1–1.4 builds were local iterations, not public Git releases.
