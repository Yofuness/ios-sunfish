#!/usr/bin/env python3
"""Shift an Android sparse image by a leading DONT_CARE run.

  simg-offset.py IN.simg OUT.simg [--offset 16G]

OUT is IN with one DONT_CARE chunk of OFFSET bytes in front, so
`fastboot -S 512M flash userdata OUT.simg` writes IN's blocks starting at byte
OFFSET of userdata and leaves the first OFFSET bytes (the iOS 16 root, read by
rd=ufsroot0) untouched. OFFSET must be a multiple of the block size. Make IN
with `img2simg -s` so the image's never-written blocks are DONT_CARE too (no
slow FILL chunks for ABL). Chunks are copied unchanged, streamed.
Not for HFS roots any more: -s also skips zero pages inside files (stale data on
the phone, 2026-11-13); tools/root27/simg-hfs.py replaces both steps there.
"""
import argparse, shutil, struct, sys

MAGIC, DONT_CARE = 0xed26ff3a, 0xcac3
HEADER = '<IHHHHIIII'          # magic, major, minor, file_hdr_sz, chunk_hdr_sz, blk_sz, total_blks, total_chunks, csum


def size(text):
    units = {'K': 1 << 10, 'M': 1 << 20, 'G': 1 << 30}
    return int(text[:-1]) * units[text[-1].upper()] if text[-1].upper() in units else int(text)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('input'); ap.add_argument('output')
    ap.add_argument('--offset', default='16G')
    a = ap.parse_args()
    offset = size(a.offset)
    with open(a.input, 'rb') as src:
        head = src.read(struct.calcsize(HEADER))
        magic, major, minor, fhs, chs, bs, blocks, chunks, csum = struct.unpack(HEADER, head)
        if magic != MAGIC or major != 1:
            sys.exit('not a version 1 sparse image')
        if offset % bs:
            sys.exit(f'offset is not a multiple of the {bs}-byte block')
        src.seek(fhs)
        with open(a.output, 'xb') as dst:
            out = struct.pack(HEADER, magic, major, minor, fhs, chs, bs, blocks + offset // bs, chunks + 1, 0)
            dst.write(out + bytes(fhs - len(out)))
            chunk = struct.pack('<HHII', DONT_CARE, 0, offset // bs, chs)
            dst.write(chunk + bytes(chs - len(chunk)))
            shutil.copyfileobj(src, dst, 8 << 20)
    print(f'{a.output}: {chunks + 1} chunks, {blocks + offset // bs} blocks of {bs} '
          f'({offset >> 20} MiB DONT_CARE in front)')


if __name__ == '__main__':
    main()
