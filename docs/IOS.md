# Winglight for iPad and iPhone

Winglight 1.6.0 adds a native iOS/iPadOS application, with iPad as the primary
layout. Requires iOS/iPadOS 18 or newer and a Metal-capable device. The code and
artwork use the same licenses as the Mac application; see `LICENSE`, `NOTICE`
and `THIRD_PARTY.md`. All runtime resources are bundled; there is no account,
telemetry or runtime asset download.

## Features

The iOS target compiles the same app state, aircraft and livery catalogs, solar
controller, occlusion, airflow, weather, Metal renderer and shaders as the Mac
application. It includes all 9 aircraft, model/engine assemblies and 309
model/livery combinations at their original resolution.

| Feature | iPad / iPhone |
| --- | --- |
| Aircraft, engine variants, Chinese/English livery search, regions, special liveries, favorites | Included |
| Strobes, beacons, navigation, landing, logo and cabin lights; one-cycle test flash | Included |
| Clouds, airflow, stars, studio; clear/cloudy/rain/fog/storm | Included |
| Solar direction, sunrise/sunset, system location, manual cities/coordinates, local time zones, time scrubbing and return to now | Included |
| Orbit, zoom, reset, seven camera presets, orthographic views | Included |
| HDR/EDR, intensity, core size, glow, timing, MSAA | Included |
| Flight and background motion, motion intensity, wireframe, dimensions and studio grid | Included |
| Playback/pause, stop/reset, immersive view, adaptive light/dark glass | Included |
| 30 / 60 / up to 120 fps, high precision rendering | Included; actual rate depends on display and GPU |
| Keyboard playback, settings, immersion and Escape | Included with an external keyboard |

A wide iPad window displays the controls beside the scene. Portrait, compact
windows, Split View and iPhone use a large control sheet. The layout follows
available window size rather than assuming the device model. Each window owns
its scene state. Drag to orbit, pinch to zoom and double-tap to reset. The view
menu contains stop/reset. All panels and settings remain available on iPhone.
Mac menu-bar actions and OS window fullscreen are represented by mobile controls
and immersive mode; Mac-only command-line demo exporters are developer tooling.

The mobile default is native display resolution, 60 fps and 4× MSAA. The 2×
width/height high-precision setting remains available, with render targets capped
at 16,777,216 pixels / 8192 pixels per side to bound allocation. No aircraft,
livery textures, weather particles or catalog entries are removed. Inactive
scenes stop their display links; memory warnings discard reusable inactive
resources while keeping the selected scene. Higher resolutions and frame rates
can substantially increase power consumption.

EDR uses the current scene screen's `currentEDRHeadroom` and
`potentialEDRHeadroom`, with an extended-linear-sRGB, 16-bit floating-point Metal
layer. Actual headroom depends on the screen and system; SDR remains supported.
See [Apple's EDR headroom documentation](https://developer.apple.com/documentation/uikit/uiscreen/currentedrheadroom).
The Simulator does not support the framebuffer fetch used on Apple devices; it
uses a separate positive-light accumulation pass with the same final peak bound.

## Build from source

```sh
git clone https://github.com/wzk112/Winglight.git
cd Winglight
git checkout ios-v1.6.0
python3 scripts/assets.py fetch
open Apps/iOS/Winglight.xcodeproj
```

The resource fetch verifies the immutable 1.5.2 archive, which already includes
the corrected engine geometry. Python third-party dependencies are only needed
when rebuilding models from upstream source. See
`docs/DEVELOPMENT.md`. Choose the Winglight scheme and your device/simulator.
Choose your own Apple development team under Signing & Capabilities for device
builds. No team identifier, private key or provisioning profile is committed.
Xcode builds Metal for the selected platform; it never reuses the Mac metallib.

The checked-in Xcode project needs no project generator or third-party Xcode
plugins. If source membership changes, `python3 scripts/generate-ios-project.py`
regenerates it deterministically. WinglightCore is a local Swift package.

```sh
# An IPA for signing with your own credentials:
./scripts/build-ios.sh unsigned
# A local development-signed IPA (using your own configured Xcode account):
DEVELOPMENT_TEAM=YOUR_TEAM_ID ./scripts/build-ios.sh signed
# Simulator build:
./scripts/build-ios.sh simulator
# Tests:
xcodebuild -project Apps/iOS/Winglight.xcodeproj -scheme Winglight \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' test
swift test
```

Build outputs go under ignored `.build/ios-release` and `dist/iOS`. Override
`IOS_BUILD_DIR` and `IOS_OUTPUT_DIR` with absolute paths when needed.

## Installing the IPA

The public `Winglight-1.6.0-iOS-unsigned.ipa` includes every runtime resource and
must be signed with your own credentials using your preferred sideloading tool.
It cannot be installed as-is. It is not an App Store or TestFlight package.
Personal-team signing has the validity and device limits imposed by Apple.

A development-signed IPA built locally is restricted to its provisioning profile's
registered devices and expiration date. It is retained locally for the developer's
devices; the public release uses the unsigned package to avoid publishing device
identifiers from a personal provisioning profile. Keep the app together with its
corresponding tagged source, resource pack and upstream notices.

## Verification

See `docs/IOS_VALIDATION.md` for the release's actual test results and remaining
hardware checks. Compilation, successful launch and simulator screenshots do
not establish a hardware HDR peak or sustained 120 fps.
