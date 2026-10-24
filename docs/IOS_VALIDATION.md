# iOS / iPadOS 1.6.0 validation

Release date: 2026-10-25 (Australia/Melbourne).
Toolchain: Xcode 27.1 / Swift 6 toolchain, Swift 5 language mode; minimum iOS 18.

## Resource and rendering checks

- All 501 bundled binary runtime resources are streamed out of the public IPA
  and checked against the immutable 1.5.2 manifest plus derived geometry hashes.
- The bundled catalog contains all 309 model/livery combinations. Existing
  catalog tests load each livery on the GPU and check dimensions and mipmaps.
- Mobile renderer tests load all 17 model/engine assemblies and render each
  against all four backgrounds, including storm weather, on the iOS Simulator.
  They check command completion and inactive geometry/flow cache eviction.
- Portrait projection tests cover all 9 aircraft and 7 camera presets, and a
  detached scene is checked to pause its Metal display link.
- Solar permission tests include iOS `authorizedWhenInUse`, valid/stale fixes,
  cancellation, deadlines, denied/network errors and manual-location persistence.
- macOS regression: 23 core tests and 20 app tests passed. A macOS Release build
  with the shared shader and source changes also passed.

## Interface checks

The iPhone 17 Pro Simulator passed the full UI flow: landscape aircraft search,
livery search and neutral paint selection, each settings category, manual city,
portrait controls, immersion, and background/foreground return. The 11-inch
iPad Pro Simulator also passed the full UI flow, selecting the sidebar or
compact controls according to the actual window width. The iPad mini
Simulator was also inspected in a fresh portrait window and displayed the
compact scene and controls. Wide iPad windows use the sidebar; window geometry,
rather than a presumed orientation, determines the layout.

## Builds and packaging

- ARM64 iOS Release build and Apple Development signed archive succeeded.
- Universal iPad/iPhone device family is `[1, 2]`; deployment target is 18.0.
- The unsigned distribution IPA contains its own platform-specific metallib,
  aircraft catalog, models, BVHs, window masks, all liveries and legal notices.
  It contains no personal provisioning profile or account credentials.
- The development IPA is kept local. Its initial provisioning profile expires
  on 2026-11-01 at 02:31 AEDT and is limited to its registered devices. Re-signing
  creates a new profile; the embedded profile is authoritative.

## Hardware boundaries

Installation was attempted on the connected 11-inch iPad Pro (M4) and iPhone
17 Pro. Both devices rejected the installation because all three free-developer
app slots were occupied. No installed applications were removed or replaced.
Consequently, physical-device launch, sustained frame rate, power/thermal
behavior, actual HDR/EDR peak, live location fixes, external keyboard and
multiwindow/external-display behavior remain unverified for this release.
The Simulator's screen headroom is 1.0 and its captures do not establish HDR
performance. Higher frame-rate settings are requests capped by the display.
