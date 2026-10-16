# Changelog

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
