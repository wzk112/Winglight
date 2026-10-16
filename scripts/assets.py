#!/usr/bin/env python3
"""Fetch, verify, or package the versioned binary resources (Python stdlib only)."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'assets-manifest.json'


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def verify(manifest, root=ROOT):
    failures = []
    for entry in manifest['files']:
        path = root / entry['path']
        if not path.is_file() or path.stat().st_size != entry['bytes'] or digest(path) != entry['sha256']:
            failures.append(entry['path'])
    if failures:
        raise SystemExit('Missing or modified resources:\n' + '\n'.join(failures[:20]) +
                         '\nRun: python3 scripts/assets.py fetch')
    print(f"Verified {len(manifest['files'])} resources.")


def pack(output):
    patterns = [
        'Sources/Winglight/Resources/Models/*.mesh',
        'Sources/Winglight/Resources/Models/*.bvh',
        'Sources/Winglight/Resources/Models/*.png',
        'Sources/Winglight/Resources/Textures/*.png',
        'Sources/Winglight/Resources/Liveries/*.png',
        'ThirdParty/**/*.xcf', 'ThirdParty/GeoFS/*.webp',
    ]
    paths = sorted({p for pattern in patterns for p in ROOT.glob(pattern)})
    entries = [dict(path=p.relative_to(ROOT).as_posix(), bytes=p.stat().st_size,
                    sha256=digest(p)) for p in paths]
    output.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(output, 'w:gz', compresslevel=6) as archive:
        for path in paths:
            info = archive.gettarinfo(str(path), arcname=path.relative_to(ROOT).as_posix())
            info.uid = info.gid = info.mtime = 0
            info.uname = info.gname = ''
            info.mode = 0o644
            with path.open('rb') as stream:
                archive.addfile(info, stream)
    manifest = dict(schema=1, version='1.5.0',
                    url='https://github.com/wzk112/Winglight/releases/download/v1.5.0/' + output.name,
                    archive=dict(name=output.name, bytes=output.stat().st_size, sha256=digest(output)),
                    files=entries)
    MANIFEST.write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Packed {len(entries)} resources: {output.stat().st_size:,} bytes; SHA-256 {digest(output)}')


def fetch(manifest, source=None):
    cache = ROOT / '.build/downloads'
    cache.mkdir(parents=True, exist_ok=True)
    archive_path = Path(source).resolve() if source else cache / manifest['archive']['name']
    if source is None and (not archive_path.exists() or digest(archive_path) != manifest['archive']['sha256']):
        partial = archive_path.with_suffix('.partial')
        print('Downloading ' + manifest['url'], flush=True)
        with urllib.request.urlopen(manifest['url'], timeout=90) as response, partial.open('wb') as stream:
            shutil.copyfileobj(response, stream)
        if digest(partial) != manifest['archive']['sha256']:
            partial.unlink()
            raise SystemExit('Archive checksum mismatch; download discarded.')
        partial.replace(archive_path)
    if archive_path.stat().st_size != manifest['archive']['bytes'] or digest(archive_path) != manifest['archive']['sha256']:
        raise SystemExit('Archive size or checksum mismatch.')
    expected = {entry['path']: entry for entry in manifest['files']}
    seen = set()
    with tarfile.open(archive_path, 'r:gz') as archive:
        for member in archive:
            name = member.name
            path = PurePosixPath(name)
            if name not in expected or name in seen or path.is_absolute() or '..' in path.parts or not member.isfile():
                raise SystemExit('Unexpected archive member: ' + name)
            if member.size != expected[name]['bytes']:
                raise SystemExit('Unexpected resource size: ' + name)
            destination = ROOT / name
            if any(p.is_symlink() for p in [destination, *destination.parents]):
                raise SystemExit('Refusing symlink destination: ' + name)
            destination.parent.mkdir(parents=True, exist_ok=True)
            temporary = destination.with_suffix(destination.suffix + '.partial')
            with archive.extractfile(member) as src, temporary.open('wb') as dst:
                shutil.copyfileobj(src, dst)
            if digest(temporary) != expected[name]['sha256']:
                temporary.unlink()
                raise SystemExit('Resource checksum mismatch: ' + name)
            temporary.replace(destination)
            seen.add(name)
    if seen != set(expected):
        raise SystemExit('Incomplete archive.')
    verify(manifest)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['verify', 'fetch', 'pack'])
    parser.add_argument('--archive', type=Path, help='Existing archive for offline fetch, or output path for pack')
    args = parser.parse_args()
    if args.command == 'pack':
        pack(args.archive or ROOT / 'dist/Winglight-1.5.0-assets.tar.gz')
    else:
        if not MANIFEST.exists():
            raise SystemExit('assets-manifest.json is missing.')
        manifest = json.loads(MANIFEST.read_text())
        if args.command == 'fetch':
            fetch(manifest, args.archive)
        else:
            verify(manifest)
