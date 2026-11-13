#!/usr/bin/env python3
"""Prove a whole arm64e dyld shared cache image by image, each worker process under a memory cap; resumable.

  python3 -I tools/ios27-pac/prove-cache.py --cache .../dsc/24B156__iPhone12,1/dyld_shared_cache_arm64e
        [--out DIR] [--jobs 2] [--mem 3.5G] [--retry-mem 7G] [--only NAME ...] [--chunk 32]
        [--no-tpro] [--no-gaps] [--no-noreturn-end] [--no-scope] [--python PY]

The python running this must have capstone (5.0.7) and numpy; llvm-mc must be on PATH. Same steps as zeta's
prove-zeta-dyld-cache.py main() (pass 1 with own roots, pass 2 with the calls other images made, stub islands
from inbound calls), with the sunfish iOS 27 fixes of sunfish_pac.py on unless switched off. Every worker is
`systemd-run --user --scope -p MemoryMax=CAP -p MemorySwapMax=0`: an image that does not fit is OOM-killed, listed
and, after the round, retried alone with --retry-mem (0: no retry). Workers restart themselves when their RSS
passes 60 % of the cap (fragmentation). Units already done are skipped, so a run can be stopped and started again;
--only runs fill the same out dir a full run later reuses (pass 2 and islands are redone when their call set grew).

Out dir (default <x>/<build>/prove next to x/<build>/dsc/, out of git): setup.{npz,json}, pass1/ pass2/ islands/
(one JSON + one npz per unit), calls.npz, failed.json, and summary.json: zeta's schema (images, islands, totals;
rewrite-zeta-dyld-cache.py --proof DIR reads it) plus a 'sunfish' table (proven/unproven/unlowerable per image).
"""
import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import subprocess
import sys
import threading
import time

HERE = Path(__file__).resolve().parent
WORKER = HERE / 'sunfish_pac.py'
EXIT_RECYCLE = 75


def size_bytes(text):
    units = dict(K=1 << 10, M=1 << 20, G=1 << 30)
    text = text.strip().upper().rstrip('B')
    return int(float(text[:-1]) * units[text[-1]]) if text[-1:] in units else int(text)


class Runner:
    def __init__(self, args):
        self.args, self.lock, self.serial = args, threading.Lock(), 0
        self.flags = [f for f, on in (('--no-tpro', args.no_tpro), ('--no-noreturn-end', args.no_noreturn_end)) if on]

    def command(self, sub, cap, extra=()):
        cmd = [self.args.python, '-I', str(WORKER), sub, '--cache', str(self.args.cache), '--out', str(self.args.out),
               *extra]
        if self.args.no_scope:
            return cmd
        return ['systemd-run', '--user', '--scope', '--quiet', '-p', f'MemoryMax={cap}', '-p', 'MemorySwapMax=0', *cmd]

    def simple(self, sub, extra=()):
        cap = size_bytes(self.args.mem)
        if subprocess.run(self.command(sub, cap, extra)).returncode:
            sys.exit(f'prove-cache: {sub} failed (memory cap {self.args.mem}?)')

    def units(self, kind, units, cap, failed, label):
        """Run units in chunks over --jobs workers; returns the units that died (OOM or crash) with the exit code."""
        pending, died, total = list(units), {}, len(units)
        work = self.args.out / {'p1': 'pass1', 'p2': 'pass2', 'island': 'islands'}[kind]

        def worker(_):
            while True:
                with self.lock:
                    if not pending:
                        return
                    chunk, pending[:] = pending[:self.args.chunk], pending[self.args.chunk:]
                    self.serial += 1
                    name = f'{kind}-{self.serial}'
                marker = self.args.out / 'run' / f'{name}.cur'
                result = subprocess.run(self.command('run', cap, ['--kind', kind, '--worker', name,
                                                                  '--units', ','.join(map(str, chunk)),
                                                                  '--recycle-mb', str(cap * 6 // 10 >> 20),
                                                                  *self.flags]))
                with self.lock:
                    if result.returncode not in (0, EXIT_RECYCLE):
                        dead = int(marker.read_text().split()[1]) if marker.exists() else None
                        marker.unlink(missing_ok=True)
                        if dead is None:
                            sys.exit(f'prove-cache: worker {name} exited {result.returncode} outside a unit')
                        died[dead] = result.returncode
                        print(f'{label}: unit {dead} died (exit {result.returncode}, cap {cap >> 20} MB)',
                              file=sys.stderr, flush=True)
                    alive = [u for u in chunk if u not in died and u not in failed]
                    if kind == 'p1':
                        left = [u for u in alive if not (work / f'{self.unit_name(kind, u)}.json').exists()]
                    else:                 # p2/island JSONs may stem from an older call set
                        left = self.stale(kind, alive)
                    pending[:0] = left
                    done = total - len(pending)
                    print(f'{label}: {done}/{total}', file=sys.stderr, flush=True)

        (self.args.out / 'run').mkdir(exist_ok=True)
        with ThreadPoolExecutor(self.args.jobs) as pool:
            list(pool.map(worker, range(self.args.jobs)))
        return died

    def unit_name(self, kind, unit):
        if kind == 'island':
            return f'island-{self.islands[unit][0]:x}'
        return self.names[unit]

    def label(self, kind, unit):
        return f'island {self.islands[unit][0]:#x}' if kind == 'island' else f'{kind} {self.paths[unit]}'

    def stale(self, kind, units):
        """p2/island units whose JSON is missing or was made from another call count."""
        work = self.args.out / ('pass2' if kind == 'p2' else 'islands')
        left = []
        for unit in units:
            path = work / f'{self.unit_name(kind, unit)}.json'
            if not path.exists() or json.loads(path.read_text()).get('calls_used') != self.call_counts[kind].get(unit):
                left.append(unit)
        return left

    def stage(self, kind, units, label):
        """One round at --mem, then each unit that died alone at --retry-mem; failures persist in failed.json."""
        failed_path = self.args.out / 'failed.json'
        failed = json.loads(failed_path.read_text()) if failed_path.exists() else {}
        known = {int(u.split(':')[1]) for u in failed if u.startswith(kind + ':')}
        first = [u for u in units if u not in known]
        died = self.units(kind, first, size_bytes(self.args.mem), set(), label) if first else {}
        retry = sorted(set(died) | known)
        cap = size_bytes(self.args.retry_mem)
        for unit in retry:
            failed[f'{kind}:{unit}'] = dict(unit=self.label(kind, unit), exit=died.get(unit), cap=self.args.mem)
            if cap:
                again = self.units(kind, [unit], cap, set(), f'{label} retry')
                if again:
                    failed[f'{kind}:{unit}'] = dict(unit=self.label(kind, unit), exit=again[unit],
                                                    cap=self.args.retry_mem)
                else:
                    failed.pop(f'{kind}:{unit}')
        failed_path.write_text(json.dumps(failed, indent=1) + '\n')
        return failed


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--cache', required=True, type=Path, help='main cache file (subcaches beside it)')
    parser.add_argument('--out', type=Path, help='default: x/<build>/prove beside x/<build>/dsc')
    parser.add_argument('--jobs', type=int, default=2)
    parser.add_argument('--mem', default='3.5G', help='memory cap per worker process')
    parser.add_argument('--retry-mem', default='7G', help='cap for retrying OOM-killed units alone (0: none)')
    parser.add_argument('--chunk', type=int, default=32, help='units per worker process')
    parser.add_argument('--only', action='append', help='image path or its last component(s); repeatable')
    parser.add_argument('--no-tpro', action='store_true', help='zeta oracle without the iOS 27 TPRO words')
    parser.add_argument('--no-gaps', action='store_true', help='no stub islands from unowned executable bytes')
    parser.add_argument('--no-noreturn-end', action='store_true', help='zeta walk() unchanged')
    parser.add_argument('--no-scope', action='store_true', help='no systemd-run (no memory cap)')
    parser.add_argument('--python', default=sys.executable)
    args = parser.parse_args()
    args.cache = args.cache.resolve()
    if args.out is None:
        if args.cache.parent.parent.name != 'dsc':
            sys.exit('prove-cache: --out needed (the cache is not under x/<build>/dsc/)')
        args.out = args.cache.parent.parent.parent / 'prove'
    args.out = args.out.resolve()
    args.out.mkdir(parents=True, exist_ok=True)
    options = dict(tpro=not args.no_tpro, gaps=not args.no_gaps, noreturn_end=not args.no_noreturn_end)
    options_path = args.out / 'options.json'
    if options_path.exists() and json.loads(options_path.read_text()) != options:
        sys.exit(f'prove-cache: {args.out} was made with {options_path.read_text().strip()}: use another --out')
    options_path.write_text(json.dumps(options) + '\n')
    started = time.time()
    runner = Runner(args)
    if not (args.out / 'setup.json').exists():
        runner.simple('setup', ['--no-gaps'] if args.no_gaps else [])
    info = json.loads((args.out / 'setup.json').read_text())
    if Path(info['cache']).name != args.cache.name or Path(info['cache']).parent.name != args.cache.parent.name:
        sys.exit(f'prove-cache: {args.out} belongs to {info["cache"]}')
    import numpy as np          # only for the island list and the call counts
    runner.islands = np.load(args.out / 'setup.npz')['islands'].tolist()
    runner.names = {e['index']: e['name'] for e in info['images']}
    runner.paths = {e['index']: e['path'] for e in info['images']}
    entries = sorted(info['images'], key=lambda e: -e['code_bytes'])
    if args.only:
        entries = [e for e in entries if any(e['path'] == o or e['path'].endswith('/' + o) for o in args.only)]
        missing = [o for o in args.only if not any(e['path'] == o or e['path'].endswith('/' + o) for e in entries)]
        if missing:
            sys.exit(f'prove-cache: no image matches {missing}')
    selected = [e['index'] for e in entries]

    failed = runner.stage('p1', selected, 'pass 1')
    runner.simple('calls')
    calls = np.load(args.out / 'calls.npz')
    runner.call_counts = dict(p2=Counter(calls['image'].tolist()), island={})
    inbound = calls['inbound']
    for unit, (start, end, _, _, _) in enumerate(runner.islands):
        low, high = np.searchsorted(inbound, [start, end])
        runner.call_counts['island'][unit] = int(high - low)

    def pass1(index):
        path = args.out / 'pass1' / f'{runner.names[index]}.json'
        return json.loads(path.read_text()) if path.exists() else None
    second = [i for i in selected if (r := pass1(i)) and r.get('unproven_count') and runner.call_counts['p2'].get(i)]
    failed = runner.stage('p2', runner.stale('p2', second), 'pass 2') if second else failed
    # Islands: all of them for a full run (zeta does), only those with inbound calls for an --only run.
    islands = [u for u in range(len(runner.islands)) if not args.only or runner.call_counts['island'][u]]
    failed = runner.stage('island', runner.stale('island', islands), 'islands') if islands else failed

    summary = dict(schema='zeta-dyld-cache-proof-v1', cache=str(args.cache), images={}, islands=[])
    table, errors = [], []
    for index in selected:
        result = pass1(index)
        if result is None:
            continue
        p2 = args.out / 'pass2' / f'{runner.names[index]}.json'
        if p2.exists():
            again = json.loads(p2.read_text())
            if again.get('calls_used') == runner.call_counts['p2'].get(index) and 'error' not in again:
                result = again
        if 'error' in result:
            errors.append(dict(path=result['path'], error=result['error']))
            continue
        summary['images'][result['path']] = result
        table.append(dict(path=result['path'], proven=result['edit_count'], unproven=result['unproven_count'],
                          unlowerable=len(result['unlowerable']), proven_instructions=result['proven_instructions'],
                          seconds=result['wall_seconds'], peak_rss_mb=result['peak_rss_mb'],
                          pass2=result.get('reproven_with_calls', False)))
    for unit in islands:
        path = args.out / 'islands' / f'{runner.unit_name("island", unit)}.json'
        if path.exists():
            result = json.loads(path.read_text())
            if 'error' in result:
                errors.append(dict(path=result['address'] if 'address' in result else unit, error=result['error']))
            else:
                summary['islands'].append(result)
    totals = Counter()
    for entry in list(summary['images'].values()) + summary['islands']:
        totals['edits'] += entry['edit_count']
        totals['unproven'] += entry['unproven_count']
        totals['unlowerable'] += len(entry['unlowerable'])
        for grade, count in entry['edits_by_evidence'].items():
            totals['edits:' + grade] += count
    summary['totals'] = dict(totals)
    island_totals = Counter()
    for entry in summary['islands']:
        island_totals[entry['kind'] + '_islands'] += 1
        island_totals[entry['kind'] + '_edits'] += entry['edit_count']
        island_totals[entry['kind'] + '_unproven'] += entry['unproven_count']
    summary['sunfish'] = dict(options=options, partial=bool(args.only), images=table, island_totals=dict(island_totals),
                              failed=failed, errors=errors, images_selected=len(selected),
                              images_done=len(table), seconds=round(time.time() - started, 1))
    (args.out / 'summary.json').write_text(json.dumps(summary, indent=1) + '\n')

    print(f'{"image":44} {"proven":>9} {"unproven":>8} {"unlow":>5} {"s":>7} {"MB":>6}')
    for row in table:
        print(f'{row["path"].rsplit("/", 1)[-1][:44]:44} {row["proven"]:9} {row["unproven"]:8} {row["unlowerable"]:5} '
              f'{row["seconds"]:7.1f} {row["peak_rss_mb"]:6}' + ('  (pass 2)' if row['pass2'] else ''))
    print(f'islands: {dict(island_totals)}')
    print(f'totals: {dict(totals)}; failed: {sorted(v["unit"] for v in failed.values())}; errors: {len(errors)}; '
          f'{summary["sunfish"]["seconds"]} s')
    return 1 if failed or errors else 0


if __name__ == '__main__':
    sys.exit(main())
