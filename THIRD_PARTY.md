# Third-party projects and licenses

Winglight original code: Copyright © 2026 Andy Wang and contributors,
**GNU GPL version 2 only** (`GPL-2.0-only`), full text in [LICENSE](LICENSE).
Upstream authors retain their copyrights and original grants, including
permission to use later GPL versions where stated upstream.

[Package.swift](Package.swift) declares no external Swift packages.
FlightGear's engine is not linked; its community projects provide model and artwork data.

## Bundled resources

Links identify the exact upstream revisions. Copied licenses and author/README
evidence are in [ThirdParty/Licenses](ThirdParty/Licenses). Their URLs and hashes
are recorded in [inventory.json](ThirdParty/Licenses/inventory.json).
"GPL v2" below records the supplied license version; upstream source notices
govern whether a particular component also permits later versions.

| Project / fixed revision | Use and attribution | License | Original sources / notices |
|---|---|---|---|
| [legoboyvdlp/A320-family](https://github.com/legoboyvdlp/A320-family/tree/fec1ecba767c8fffd145337b27012e89c01e3ade) | A320 exterior, CFM56, textures and normal maps. Josh Davidson, Jonathan Redpath, merspieler, Matthew Maring, Thorsten Herrmann, Semir Gebran. | GPL v2; copyright notice specifies v2 only | `ThirdParty/A320/` |
| [legoboyvdlp/A320-family-liveries](https://github.com/legoboyvdlp/A320-family-liveries/tree/6673dc43d191163c1a4456b3bd7b00ace35f47f6) | A320 liveries, including Air China editable XCF in the asset pack. Individual artist metadata retained. | GPL v2; README contribution terms item 10 | `ThirdParty/AirChina-A320/`, `ThirdParty/Liveries/` |
| [soitanen/737-800](https://github.com/soitanen/737-800/tree/5faef486500aba227804b59b014faf9619e3a18d) | 737 exterior. David Culp, Syd Adams, Innis Cunningham, Michael Soitanen; original metadata retained. | GPL v2 | `ThirdParty/737/` |
| [YV3399/737-800YV](https://github.com/YV3399/737-800YV/tree/9d967d89dd2ee0ae1bf01d00c49839a574aa9da5) | 737 engines, glazing and liveries. Original authors in README/XML; Air China atlas credits FGPRC 0762. | GPL v2 | `ThirdParty/737YV/`, `ThirdParty/AirChina/`, `ThirdParty/Liveries/` |
| [IskenderWang/787-family](https://github.com/IskenderWang/787-family/tree/02626b5b659d89b9399943ee167bbb0b46f0c871) | 787-8/-9/-10, engines and artwork. IskenderWang, Marsdolphin, Pilot2938, Nicolás Castellán, Naviat and original contributors in Authors.md. | GPL v2 | `ThirdParty/Widebody/b787/` |
| [JMaverick16/Airbus_A330](https://github.com/JMaverick16/Airbus_A330/tree/f016c7c0ad8c6c48b7d9eed7ed7dde49dc69059d) | A330-200/-300, engines and artwork. Source XML includes Josh Davidson/Octal450; full README retained. | GPL v2 | `ThirdParty/Widebody/a330/` |
| [FGMEMBERS/A350XWB](https://github.com/FGMEMBERS/A350XWB/tree/04da937ab1ba0b07dabfd71d91aa33eb38316b90) | A350-900 and artwork. Sbyx, Jormappapa and other contributors. | GPL v2 or later, explicitly stated in README | `ThirdParty/Widebody/a350/` |
| [franck-vmd/Boeing-777-Flightgear](https://github.com/franck-vmd/Boeing-777-Flightgear/tree/821f2d9cf77cf3953c1b28df46a32740c77c73d4) | 777-300ER, cockpit glazing and artwork. franck-vmd and FlightGear 777 contributors; README retained. | GPL v2 | `ThirdParty/Widebody/b777/` |
| [sriemmanuel787/FG-Liveries](https://github.com/sriemmanuel787/FG-Liveries/tree/eae9eaf1d079afd4a558ad115209d25cf9346205) | Additional widebody liveries. sriemmanuel787 / Naviat; individual metadata retained. | GPL v2 | `ThirdParty/WidebodyLiveries/` |
| [kolos26/GEOFS-LiverySelector](https://github.com/kolos26/GEOFS-LiverySelector/tree/bd05e90779060883a28b467a577077628c8b355c) | Two XiamenAir 787-9 artworks credited to B-20AJ / TCA Design. Repository copyright © 2022 kolos26. | MIT | `ThirdParty/GeoFS/` |

Per-file original texture URLs, commits and SHA-256 hashes are in
`ThirdParty/Liveries/manifest.json`, `ThirdParty/WidebodyLiveries/catalog.json`,
`ThirdParty/A320/normal-maps.json`, and the runtime catalog. Widebody source model
paths/hashes are in `ThirdParty/Widebody/manifest.json`. Livery XML author credits
are preserved. The source records and notices remain authoritative alongside this summary.

## Modifications

Original AC3D files are retained. `scripts/` selects exterior objects, stows
doors, assembles engines, calibrates dimensions, preserves UVs, triangulates
and subdivides surfaces, separates crease normals, restores glazing and
generates BVHs/Metal buffers. Original images retain native resolution;
`convert_xiamen.py` implements the XiamenAir projection adaptation. Runtime
shaders add materials, lighting, weather, occlusion and window illumination.
Historical changes are recorded in `ThirdParty/NOTICE.txt`.

## Optional development tools

These tools are used for asset conversion and geometry tests. No Python
runtime is shipped in the app. Requirements: `scripts/requirements-assets.txt`.
Exact installed versions and distribution license texts used during validation
are included in `ThirdParty/Licenses/` and its inventory, including bundled-library notices.

| Project | Purpose | License |
|---|---|---|
| [NumPy](https://github.com/numpy/numpy) | Geometry/array operations | BSD-3-Clause; wheel includes additional component notices |
| [Pillow](https://github.com/python-pillow/Pillow) | Image validation/masks | MIT-CMU; wheel includes additional component notices |
| [mapbox-earcut bindings](https://github.com/skogler/mapbox_earcut_python/tree/v2.1.0) | Polygon triangulation | ISC, © Samuel Kogler |
| [Mapbox earcut](https://github.com/mapbox/earcut.hpp) | Algorithm used by the bindings | ISC, © Mapbox; vendored notice retained from the bindings' v2.1.0 source |

Swift/SwiftPM, Python and Xcode/Metal tools are installed separately. SwiftUI,
AppKit, Metal, MetalKit, CoreLocation, Combine, QuartzCore, simd and the optional
ScreenCaptureKit diagnostic are Apple platform APIs. Their implementations are
not copied into this repository or classified as bundled open-source packages.

## Excluded during publication

The previous catalog incorrectly grouped all 737 paints under GPL v2.
At commit `9cc91b7acdb0d688c13c687c5367dded370f54f0`,
[YV3399/B737800-Liveries](https://github.com/YV3399/B737800-Liveries/tree/9cc91b7acdb0d688c13c687c5367dded370f54f0)
contains no LICENSE, COPYING, README license grant or permission notice in
the two selected XMLs. Its `UAL-2019.png`, `TRA-new.png` and selected XMLs are
**excluded from this public source/asset release**; Winglight does not relicense
them. Fetch recipes no longer request these files. The public catalog contains
309 combinations, including 58 for the 737.

Manufacturer documents cited in `MODEL_ACCURACY.md` and `LIGHTING_REFERENCE.md`
are references; their diagrams are not bundled. Airline/manufacturer names and
marks retain their owners' rights and imply no affiliation or endorsement.
