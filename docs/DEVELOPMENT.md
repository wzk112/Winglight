# Development

`Sources/Winglight` contains the macOS app and renderer; `Sources/WinglightCore`
contains lighting, solar and occlusion logic. `Tests` covers Swift logic and Python
geometry regressions. `ThirdParty` retains original AC3D files, metadata and licenses.

## Build

```sh
python3 scripts/assets.py fetch
./scripts/build.sh
swift test
```

The script verifies resources, compiles Metal, builds the executable, bundles
resources/licenses and signs/verifies `dist/Winglight.app`. Defaults are relative
to the checkout; `.build` and `dist` are ignored. To use your own signing identity,
set `SIGNING_IDENTITY`. Stable signing helps retain location permission identity.

Offline restoration:

```sh
python3 scripts/assets.py fetch --archive /path/to/Winglight-1.5.0-assets.tar.gz
python3 scripts/assets.py verify
```

Git tracks sources and metadata; the resource archive contains 504 large/binary
files including meshes, BVHs, textures, original Air China XCF and GeoFS WebPs.
It also includes the project and upstream license/attribution texts; fetch keeps
those copies in `.build/downloads/legal` without overwriting tracked documents.
It complements the corresponding repository source; it is not standalone source.

## Asset regeneration

Start with the resource pack, which also supplies base textures and original art:

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r scripts/requirements-assets.txt
.venv/bin/python scripts/convert_models.py
.venv/bin/python scripts/convert_widebody.py
.venv/bin/python scripts/fetch_liveries.py
.venv/bin/python scripts/fetch_widebody_liveries.py
.venv/bin/python scripts/convert_xiamen.py
.venv/bin/python scripts/calibrate_lamps.py
.venv/bin/python scripts/review_catalog.py
.venv/bin/python scripts/window_masks.py
.venv/bin/python -m unittest discover -s Tests/Geometry
```

Fetch scripts require network for missing files and use fixed revisions. Source
AC3D files are committed. Generate masks after catalog/geometry changes.
After intentional changes, update `scripts/assets.py`'s release version/URL and
run `python3 scripts/assets.py pack`. Use a new version for changed pack content;
do not overwrite a published pack while retaining an old integrity manifest.

## Diagnostics

```sh
dist/Winglight.app/Contents/MacOS/Winglight --qa-time 0.015 --qa-output /tmp/winglight-gpu.json
dist/Winglight.app/Contents/MacOS/Winglight --audit-catalog /tmp/winglight-catalog
dist/Winglight.app/Contents/MacOS/Winglight --audit-lights /tmp/winglight-lights
dist/Winglight.app/Contents/MacOS/Winglight --audit-models /tmp/winglight-closeups --audit-filter b77w
dist/Winglight.app/Contents/MacOS/Winglight --audit-flow /tmp/winglight-flow
```

Optional flags: `--aircraft boeing`, `--view left|rear|top`,
`--environment day|dusk|night`, `--background clouds|flow|stars|studio`,
`--weather clear|cloudy|rain|fog|storm`, `--quality efficient|balanced|smooth|ultra`,
`--neutral`, `--sdr`, `--no-motion`, `--autoplay`.
`--perf-output /tmp/perf.json --perf-frames 240 --autoplay` records timing;
`--perf-scrub` exercises time changes. Close diagnostic instances between runs.

`scripts/CaptureWindow.swift` optionally records composited HDR pixels and SDR
screenshots with ScreenCaptureKit. It needs host screen-capture permission;
the main application does not request it.

## Distribution

Keep corresponding source, resource pack and notices together. Built apps include
license texts in `Contents/Resources/Legal`. Preserve GPL corresponding source,
conversion instructions, artist credits and original grants for distributed versions.
See [THIRD_PARTY.md](../THIRD_PARTY.md).
