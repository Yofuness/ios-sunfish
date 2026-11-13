#!/usr/bin/env python3
"""sunfish: iOS 27 fixes for UniXNU-zeta's dyld shared cache prover, and the worker that prove-cache.py runs.

zeta's files in zeta/ are vendored unchanged (UniXNU-zeta eb48928, BSD-2-Clause-Patent, zeta/LICENSE). install()
changes three things at run time; each is on by default for iOS 27 and has an off switch in prove-cache.py
(why: research/notes/dyld27-proof-2026-11-13.md):
- tpro: the llvm-mc oracle knows 0xd5940000, 0xd5900040 and 0xd5900020 as straight-line words. They are Apple's TPRO
  set/clear (unallocated in Arm's A64 map, gated by commpage byte 0xc10c == 4) in 27's dyld, libdyld, libobjc and
  libsystem_pthread; without this every function holding one, and every caller of it, stays unproven.
- gaps: bytes of executable mappings that no section of any image owns become stub islands (Coverage + proven from
  the calls that reach them). 27 moved the objc stubs out of the images to after libobjcMsgSendN in each subcache.
- noreturn_end: a strict walk that falls off the decoded sections right after a call treats the call as noreturn,
  like zeta's udf-after-call rule (27's libdyld ends __text with a call to an assert).

  sunfish_pac.py setup --cache MAIN --out DIR [--no-gaps]
  sunfish_pac.py run --cache MAIN --out DIR --kind p1|p2|island --units N,N,... [--no-tpro] [--no-noreturn-end]
  sunfish_pac.py calls --cache MAIN --out DIR

Run it through prove-cache.py (memory cap, resume, summary); the subcommands are its building blocks.
"""
import argparse
import bisect
import importlib.util
import inspect
import json
import os
from pathlib import Path
import sys
import time

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / 'zeta'))

import numpy as np  # noqa: E402

import zeta_dyld_cache as dc  # noqa: E402
import zeta_userland_code as code  # noqa: E402

_spec = importlib.util.spec_from_file_location('zeta_prover', HERE / 'zeta' / 'prove-zeta-dyld-cache.py')
P = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(P)

# sunfish: TPRO words seen in 27.2.1 (128 + 121 + 1 in the whole cache, none in 26.6.2).
TPRO = {0xd5940000: ('tpro', 'set'), 0xd5900040: ('tpro', 'clear'), 0xd5900020: ('tpro', 'clear1')}
GAP_MINIMUM = 0x40
EXIT_RECYCLE = 75          # worker RSS passed the recycle mark: the driver restarts it on the rest of its units

_NORETURN_ANCHOR = "                break  # the trap clang places after a call to a noreturn function\n"
_NORETURN_ADD = ("            # sunfish: noreturn-end. The last function of a section may end in a call to a noreturn\n"
                 "            # function and fall into the next (non-code) section: the same rule as udf after a call.\n"
                 "            if strict and found is None and after_call:\n"
                 "                break\n")


def install(tpro=True, noreturn_end=True):
    if tpro:
        upstream = code.llvm_oracle

        def tpro_oracle(words):
            known = {word: TPRO[word] for word in words if word in TPRO}
            known.update(upstream({word for word in words if word not in TPRO}))
            return known
        code.llvm_oracle = tpro_oracle
    if noreturn_end:
        # One added `if` in zeta's walk(), applied to its source so zeta updates flow in; refuses if walk() changed.
        source = inspect.getsource(code.walk)
        if source.count(_NORETURN_ANCHOR) != 1:
            raise RuntimeError('zeta_userland_code.walk changed: re-check the sunfish noreturn-end patch')
        exec(compile(source.replace(_NORETURN_ANCHOR, _NORETURN_ANCHOR + _NORETURN_ADD), code.__file__, 'exec'),
             code.__dict__)


def unowned_gaps(cache, images):
    """(start, end, file index, file offset) of executable-mapping bytes no image section owns (sunfish: gaps)."""
    owned = sorted((s['addr'], s['addr'] + s['size']) for image in images for s in image.sections if s['size'])
    owned += [(address, address + 0x20) for address, _ in cache.images]
    owned.sort()
    gaps = []
    for index, cache_file in enumerate(cache.files):
        for start, size, fileoff, _, _, flags, maxprot, _ in cache_file.slid:
            if not maxprot & dc.VM_PROT_EXECUTE or flags & 8:
                continue
            cursor = start
            for begin, end in owned:
                if end <= start or begin >= start + size:
                    continue
                if begin > cursor:
                    gaps.append((cursor, begin, index, fileoff + cursor - start))
                cursor = max(cursor, end)
            if cursor < start + size:
                gaps.append((cursor, start + size, index, fileoff + cursor - start))
    return [gap for gap in gaps if gap[1] - gap[0] >= GAP_MINIMUM]


def setup(args):
    """The cache-wide inputs every worker shares, computed once: ranges, islands, slide targets, the image list."""
    started = time.time()
    cache = dc.Cache(args.cache)
    images = [dc.Image(cache, address, path) for address, path in cache.images]
    ranges = [(s['addr'], s['addr'] + s['size']) for image in images for s in image.sections
              if s['flags'] & dc.INSTRUCTIONS and s['size']]
    islands = [(start, start + size, index, fileoff, 0)
               for index, cache_file in enumerate(cache.files)
               for start, size, fileoff, _, _, flags, _, _ in cache_file.slid if flags & 8]
    if not args.no_gaps:
        islands += [gap + (1,) for gap in unowned_gaps(cache, images)]
    ranges += [(start, end) for start, end, _, _, _ in islands]
    targets = cache.slide_targets()
    listed = []
    for index, image in enumerate(images):
        size = sum(s['size'] for s in image.sections if s['flags'] & dc.INSTRUCTIONS and s['size'])
        if size:
            listed.append(dict(index=index, path=image.path, code_bytes=size, name=P.result_name(image.path)))
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    np.savez(out / 'setup.npz', ranges=np.array(sorted(ranges), dtype=np.uint64).reshape(-1, 2),
             islands=np.array(islands, dtype=np.uint64).reshape(-1, 5), targets=targets)
    gaps = [i for i in islands if i[4]]
    info = dict(cache=str(Path(args.cache).resolve()), images=listed, stub_islands=len(islands) - len(gaps),
                gap_islands=len(gaps), gap_bytes=sum(e - s for s, e, _, _, _ in gaps), targets=len(targets),
                seconds=round(time.time() - started, 1), peak_rss_mb=rss_mb('VmHWM'))
    (out / 'setup.json').write_text(json.dumps(info, indent=1) + '\n')
    print(f'setup: {len(listed)} images with code, {len(islands) - len(gaps)} stub islands, {len(gaps)} gap islands '
          f'({info["gap_bytes"]:#x} bytes), {len(targets)} slide targets, {info["seconds"]} s, '
          f'peak {info["peak_rss_mb"]} MB', file=sys.stderr)


def load_setup(out):
    arrays = np.load(out / 'setup.npz')
    return arrays, json.loads((out / 'setup.json').read_text())


def load_calls(out):
    """{image index: sorted called addresses}, inbound addresses (sorted array), from calls.npz."""
    z = np.load(out / 'calls.npz')
    called = {}
    for index, address in zip(z['image'].tolist(), z['address'].tolist()):
        called.setdefault(index, []).append(address)
    return called, z['inbound']


def rss_reset():
    try:
        Path('/proc/self/clear_refs').write_text('5')     # resets VmHWM, so each unit gets its own peak
    except OSError:
        pass


def rss_mb(field):
    for line in Path('/proc/self/status').read_text().splitlines():
        if line.startswith(field + ':'):
            return int(line.split()[1]) // 1024
    return 0


def run(args):
    """Prove the given units (images of pass 1 or 2, or islands), one JSON + one npz each; skips units already done."""
    install(tpro=not args.no_tpro, noreturn_end=not args.no_noreturn_end)
    out = Path(args.out)
    arrays, info = load_setup(out)
    work = out / {'p1': 'pass1', 'p2': 'pass2', 'island': 'islands'}[args.kind]
    work.mkdir(exist_ok=True)
    ranges = [tuple(r) for r in arrays['ranges'].tolist()]
    P.init(args.cache, ranges, arrays['targets'], work)
    cache = P.STATE['cache']
    called, inbound = load_calls(out) if args.kind != 'p1' else ({}, None)
    by_index = {entry['index']: entry for entry in info['images']}
    islands = arrays['islands'].tolist()
    marker = out / 'run' / f'{args.worker}.cur'
    marker.parent.mkdir(exist_ok=True)
    for unit in (int(u) for u in args.units.split(',') if u):
        if args.kind == 'island':
            start, end, file_index, fileoff, gap = islands[unit]
            name = f'island-{start:x}'
            low, high = np.searchsorted(inbound, [start, end])
            roots = set(int(t) for t in inbound[low:high])
            path, used = None, len(roots)
        else:
            name, path = by_index[unit]['name'], by_index[unit]['path']
            used = len(called.get(unit, ()))
        result_json = work / f'{name}.json'
        if result_json.exists():
            done = json.loads(result_json.read_text())
            if args.kind == 'p1' or done.get('calls_used') == used:
                continue
        marker.write_text(f'{args.kind} {unit}\n')
        rss_reset()
        started = time.time()
        try:
            if args.kind == 'island':
                section = dict(name='island', addr=start, size=end - start, offset=fileoff, file=file_index)
                result = P.prove_code(cache, [section], set(), set(), set(), [('call', roots)], f'island {start:#x}')
                result.pop('reached')
                result = P.save(work, name, dict(result, roots={'call': len(roots)}))
                result.update(address=hex(start), size=end - start, kind='gap' if gap else 'stubs')
            else:
                _, result, _ = P.prove_image((unit, called.get(unit, ())))
            result.update(result_file=f'{work.name}/{name}.npz', calls_used=used)
        except Exception as error:   # deterministic failures are recorded and listed, not retried
            result = dict(error=f'{type(error).__name__}: {error}', calls_used=used)
        result.update(path=path, index=unit, wall_seconds=round(time.time() - started, 2), peak_rss_mb=rss_mb('VmHWM'))
        result_json.write_text(json.dumps(result) + '\n')
        marker.unlink()
        if args.recycle_mb and rss_mb('VmRSS') > args.recycle_mb:
            sys.exit(EXIT_RECYCLE)


def calls(args):
    """Calls the pass-1 proofs made into other images' code and into islands (zeta's second-pass input)."""
    out = Path(args.out)
    arrays, info = load_setup(out)
    cache = dc.Cache(args.cache)
    inbound = set()
    owners = []
    for entry in info['images']:
        result_json = out / 'pass1' / f'{entry["name"]}.json'
        if not result_json.exists() or 'error' in json.loads(result_json.read_text()):
            continue
        inbound.update(int(t) for t in np.load(out / 'pass1' / f'{entry["name"]}.npz')['reached'])
        image = dc.Image(cache, *cache.images[entry['index']])
        owners += [(s['addr'], s['addr'] + s['size'], entry['index']) for s in image.instruction_sections()]
    owners.sort()
    begins = [begin for begin, _, _ in owners]
    pairs = []
    for target in sorted(inbound):
        at = bisect.bisect_right(begins, target) - 1
        if at >= 0 and target < owners[at][1]:
            pairs.append((owners[at][2], target))
    np.savez(out / 'calls.npz', image=np.array([p[0] for p in pairs], dtype=np.int64),
             address=np.array([p[1] for p in pairs], dtype=np.uint64),
             inbound=np.array(sorted(inbound), dtype=np.uint64))
    print(f'calls: {len(inbound)} inbound targets, {len(pairs)} into proven images, peak {rss_mb("VmHWM")} MB',
          file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('command', choices=('setup', 'run', 'calls'))
    parser.add_argument('--cache', required=True, type=Path)
    parser.add_argument('--out', required=True, type=Path)
    parser.add_argument('--kind', choices=('p1', 'p2', 'island'), default='p1')
    parser.add_argument('--units', default='')
    parser.add_argument('--worker', default=str(os.getpid()))
    parser.add_argument('--recycle-mb', type=int, default=0)
    parser.add_argument('--no-gaps', action='store_true')
    parser.add_argument('--no-tpro', action='store_true')
    parser.add_argument('--no-noreturn-end', action='store_true')
    args = parser.parse_args()
    dict(setup=setup, run=run, calls=calls)[args.command](args)


if __name__ == '__main__':
    main()
