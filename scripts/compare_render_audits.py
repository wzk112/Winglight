"""Compare complete RGBA16F captures and timings from --audit-performance."""
import argparse
import json
from pathlib import Path
import numpy as np


def compare(before, after, exclude=None):
    baseline = {r['scene']: r for r in json.loads((before / 'results.json').read_text())}
    candidate = {r['scene']: r for r in json.loads((after / 'results.json').read_text())}
    if not baseline or baseline.keys() != candidate.keys():
        raise ValueError('Scene sets differ')
    results = []
    for name, reference in baseline.items():
        if name in (exclude or []):
            continue
        current = candidate[name]
        for key in ['width', 'height', 'samples', 'headroom']:
            if reference[key] != current[key]:
                raise ValueError(f'{name}: {key} differs')
        a = np.memmap(before / (name + '.rgba16f'), dtype='<f2', mode='r')
        b = np.memmap(after / (name + '.rgba16f'), dtype='<f2', mode='r')
        expected = reference['width'] * reference['height'] * 4
        if a.size != expected or b.size != expected:
            raise ValueError(f'{name}: incomplete capture')
        maximum = squares = 0.0
        changed = nonfinite = 0
        peaks = [0.0, 0.0]
        above_sdr = [0, 0]
        for start in range(0, expected, 1_000_000):
            aa = a[start:start + 1_000_000].astype('float32')
            bb = b[start:start + 1_000_000].astype('float32')
            delta = np.abs(aa - bb)
            maximum = max(maximum, float(delta.max()))
            squares += float(np.square(delta, dtype='float64').sum())
            changed += int(np.count_nonzero(delta))
            nonfinite += int(np.count_nonzero(~np.isfinite(bb)))
            for i, values in enumerate([aa, bb]):
                peaks[i] = max(peaks[i], float(values.max()))
                above_sdr[i] += int(np.count_nonzero(values > 1.001))
        # One half-float rounding step below 1 SDR white, with identical HDR
        # peaks/coverage. This checks complete images, not thumbnail similarity.
        passed = maximum <= 1 / 2048 and nonfinite == 0 and peaks[0] == peaks[1] and above_sdr[0] == above_sdr[1]
        row = dict(scene=name, gpuBeforeMS=reference['gpuMeanMS'],
                   gpuAfterMS=current['gpuMeanMS'],
                   gpuPercentSaved=100 * (1 - current['gpuMeanMS'] / reference['gpuMeanMS']),
                   cpuBeforeMS=reference['cpuMeanMS'], cpuAfterMS=current['cpuMeanMS'],
                   maxAbsoluteDifference=maximum, changedChannels=changed,
                   rmse=(squares / expected) ** .5, nonfiniteChannels=nonfinite,
                   peaks=peaks, aboveSDRChannels=above_sdr, passed=passed)
        results.append(row)
        print(f"{name}: GPU {row['gpuBeforeMS']:.3f} -> {row['gpuAfterMS']:.3f} ms; "
              f"delta {maximum:.8f}; {'PASS' if passed else 'FAIL'}")
    if not results:
        raise ValueError('No scenes left to compare')
    return results


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('before', type=Path)
    parser.add_argument('after', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--exclude', action='append', default=[], help='An intentionally redesigned scene to assess separately')
    args = parser.parse_args()
    results = compare(args.before, args.after, args.exclude)
    args.output.write_text(json.dumps(results, indent=2) + '\n')
    raise SystemExit(0 if all(row['passed'] for row in results) else 1)
