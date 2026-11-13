#!/usr/bin/env python3
"""Android sparse image of a raw HFS+/HFSX image: allocated blocks written, free blocks DONT_CARE.

  simg-hfs.py IMG OUT.simg [--offset 16G]          write
  simg-hfs.py IMG OUT.simg [--offset 16G] --verify check OUT against IMG

Why (2026-11-13, docs/root27.md): `img2simg -s` turns every all-zero 4 KiB block into
DONT_CARE, including zero pages inside files. fastboot never writes those, so the
partition's old data showed through (the 27.2.1 dyld cache and __TPRO_CONST words).
Here the HFS+ allocation bitmap decides: every allocated block is RAW (FILL 0 for
zero runs of at least --min-fill blocks; FILL is written by fastboot), every free
block run and everything past the volume is DONT_CARE, and the blocks holding the
volume header and the alternate header are always RAW. --offset puts one DONT_CARE
chunk in front (userdata byte 16 GiB = /dev/ufsroot1), like simg-offset.py.

--verify walks OUT: RAW/FILL chunks must equal IMG byte for byte, DONT_CARE chunks
must hold no allocated block, and every allocated block must be covered once.
stdlib only; run with python3 -I.
"""
import argparse, struct, sys

MAGIC, RAW, FILL, DONT_CARE = 0xed26ff3a, 0xcac1, 0xcac2, 0xcac3
HEADER = '<IHHHHIIII'          # magic, major, minor, file_hdr_sz, chunk_hdr_sz, blk_sz, total_blks, total_chunks, csum
FHS, CHS, BS = 28, 12, 4096
MAX_CHUNK = 4096               # blocks per RAW/FILL chunk (16 MiB): no giant chunks for ABL


def size(text):
    units = {'K': 1 << 10, 'M': 1 << 20, 'G': 1 << 30}
    return int(text[:-1]) * units[text[-1].upper()] if text[-1].upper() in units else int(text)


def allocation(f, img_size):
    """bytearray, one entry per 4 KiB image block: 1 = must be written."""
    f.seek(1024)
    vh = f.read(512)
    if vh[:2] not in (b'H+', b'HX'):
        sys.exit(f'no HFS+ volume header (signature {vh[:2]!r})')
    hbs, total = struct.unpack_from('>II', vh, 40)
    vol = hbs * total
    if vol > img_size:
        sys.exit(f'volume ({vol} bytes) is larger than the image ({img_size})')
    if hbs % 512 or (BS % hbs and hbs % BS):
        sys.exit(f'unsupported HFS block size {hbs}')
    # allocationFile fork data at 112: logicalSize, clumpSize, totalBlocks, 8 extents
    logical, _, fork_blocks = struct.unpack_from('>QII', vh, 112)
    extents = [struct.unpack_from('>II', vh, 128 + 8 * i) for i in range(8)]
    if sum(n for _, n in extents) < fork_blocks:
        sys.exit('allocation file continues in the extents overflow file (not handled)')
    bitmap = bytearray()
    for start, count in extents:
        if count:
            f.seek(start * hbs)
            bitmap += f.read(count * hbs)
    need = (total + 7) // 8
    if len(bitmap) < need:
        sys.exit(f'allocation bitmap is short: {len(bitmap)} < {need} bytes')
    bitmap = bitmap[:need]

    nblk = (img_size + BS - 1) // BS        # past the volume: stays 0 = DONT_CARE
    alloc = bytearray(nblk)
    used = 0

    def mark(first, n):                     # HFS blocks [first, first+n) -> 4 KiB blocks
        a, b = first * hbs // BS, ((first + n) * hbs + BS - 1) // BS
        alloc[a:b] = b'\1' * (b - a)

    run = None                              # start of the current allocated run (HFS blocks)
    for i, byte in enumerate(bitmap):
        if byte == 0xff:
            if run is None:
                run = i * 8
            used += 8
            continue
        if byte == 0 and run is None:
            continue
        for bit in range(8):
            blk = i * 8 + bit
            if byte & (0x80 >> bit):
                used += 1
                if run is None:
                    run = blk
            elif run is not None:
                mark(run, blk - run)
                run = None
    if run is not None:
        mark(run, min(len(bitmap) * 8, total) - run)
    used = min(used, total)
    # the volume header (byte 1024) and the alternate header (vol - 1024): always written
    for byte in (0, 1024, vol - 1024, vol - 512):
        alloc[byte // BS] = 1
    return alloc, hbs, total, used, vol


def runs(alloc):
    """(start, count, allocated) over the whole array."""
    n, i = len(alloc), 0
    while i < n:
        v = alloc[i]
        j = alloc.find(b'\0' if v else b'\1', i)
        j = n if j < 0 else j
        yield i, j - i, v
        i = j


def write(a, f, alloc, head):
    zero = bytes(BS)
    stats = {'raw': 0, 'fill': 0, 'dc': 0, 'raw_b': 0, 'fill_b': 0, 'dc_b': 0, 'max_fill': 0}
    out = open(a.output, 'xb')
    out.write(bytes(FHS))
    chunks = 0

    def chunk(kind, blocks, payload=b''):
        nonlocal chunks
        out.write(struct.pack('<HHII', kind, 0, blocks, CHS + len(payload)))
        out.write(payload)
        chunks += 1
        key = {RAW: 'raw', FILL: 'fill', DONT_CARE: 'dc'}[kind]
        stats[key] += 1
        stats[key + '_b'] += blocks * BS
        if kind == FILL:
            stats['max_fill'] = max(stats['max_fill'], blocks * BS)

    if head:
        chunk(DONT_CARE, head // BS)
    for start, count, used in runs(alloc):
        if not used:
            chunk(DONT_CARE, count)
            continue
        for s in range(start, start + count, MAX_CHUNK):
            n = min(MAX_CHUNK, start + count - s)
            f.seek(s * BS)
            data = f.read(n * BS)
            data += bytes(n * BS - len(data))
            # split into zero / data sub-runs; zero runs shorter than min_fill stay RAW
            pieces, i = [], 0
            while i < n:
                z = data[i * BS:(i + 1) * BS] == zero
                j = i + 1
                while j < n and (data[j * BS:(j + 1) * BS] == zero) == z:
                    j += 1
                pieces.append([i, j - i, z and j - i >= a.min_fill])
                i = j
            merged = []
            for p in pieces:
                if merged and merged[-1][2] == p[2]:
                    merged[-1][1] += p[1]
                else:
                    merged.append(p)
            for i, m, z in merged:
                if z:
                    chunk(FILL, m, bytes(4))
                else:
                    chunk(RAW, m, data[i * BS:(i + m) * BS])
    total_blks = head // BS + len(alloc)
    out.seek(0)
    out.write(struct.pack(HEADER, MAGIC, 1, 0, FHS, CHS, BS, total_blks, chunks, 0))
    out.close()
    return chunks, total_blks, stats


def verify(a, f, alloc, head):
    bad = 0
    covered = 0
    with open(a.output, 'rb') as s:
        magic, major, _, fhs, chs, bs, total_blks, nchunks, _ = struct.unpack(HEADER, s.read(FHS))
        if magic != MAGIC or major != 1 or bs != BS:
            sys.exit('not a v1 4096-byte sparse image')
        s.seek(fhs)
        pos = 0                                         # output block
        for c in range(nchunks):
            kind, _, blocks, tot = struct.unpack('<HHII', s.read(CHS)[:12])
            payload = tot - chs
            lo, hi = pos - head // BS, pos + blocks - head // BS   # image blocks
            if kind == DONT_CARE:
                if hi > 0 and alloc.find(b'\1', max(lo, 0), hi) >= 0:
                    print(f'chunk {c}: DONT_CARE over allocated blocks {lo}..{hi}'); bad += 1
            elif kind in (RAW, FILL):
                if lo < 0 or hi > len(alloc):
                    print(f'chunk {c}: data outside the image ({lo}..{hi})'); bad += 1
                pat = s.read(payload) if kind == FILL else None
                for b in range(lo, hi, MAX_CHUNK):
                    n = min(MAX_CHUNK, hi - b)
                    want = s.read(n * BS) if kind == RAW else pat * (n * BS // 4)
                    f.seek(b * BS)
                    got = f.read(n * BS)
                    got += bytes(n * BS - len(got))
                    if got != want:
                        print(f'chunk {c}: differs from the image in blocks {b}..{b + n}'); bad += 1
                covered += alloc[max(lo, 0):hi].count(1)
            else:
                sys.exit(f'chunk {c}: unknown type {kind:#x}')
            pos += blocks
        if pos != total_blks:
            print(f'block count {pos} != header {total_blks}'); bad += 1
    want = alloc.count(1)
    if covered != want:
        print(f'allocated blocks covered {covered} != {want}'); bad += 1
    print(f'verify: {nchunks} chunks, {total_blks} blocks, {covered}/{want} must-write blocks equal the image, '
          f'{bad} problems')
    return bad


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('image'); ap.add_argument('output')
    ap.add_argument('--offset', default='0', help='leading DONT_CARE bytes (16G = ufsroot1)')
    ap.add_argument('--min-fill', type=int, default=16, help='shortest zero run (blocks) sent as FILL')
    ap.add_argument('--verify', action='store_true')
    a = ap.parse_args()
    head = size(a.offset)
    if head % BS:
        sys.exit(f'offset is not a multiple of {BS}')
    with open(a.image, 'rb') as f:
        f.seek(0, 2)
        alloc, hbs, total, used, vol = allocation(f, f.tell())
        print(f'HFS: block {hbs}, {total} blocks ({vol >> 20} MiB), {used} allocated, {total - used} free; '
              f'{alloc.count(1)} of {len(alloc)} 4 KiB blocks to write')
        if a.verify:
            sys.exit(1 if verify(a, f, alloc, head) else 0)
        chunks, blocks, st = write(a, f, alloc, head)
    print(f'{a.output}: {chunks} chunks, {blocks} blocks ({head >> 20} MiB DONT_CARE in front)')
    print(f"  RAW {st['raw']} chunks {st['raw_b'] / 2**20:.0f} MiB, FILL {st['fill']} chunks "
          f"{st['fill_b'] / 2**20:.0f} MiB (largest {st['max_fill'] >> 10} KiB), DONT_CARE {st['dc']} chunks "
          f"{st['dc_b'] / 2**20:.0f} MiB; device writes {(st['raw_b'] + st['fill_b']) / 2**20:.0f} MiB")


if __name__ == '__main__':
    main()
