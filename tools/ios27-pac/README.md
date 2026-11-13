# ios27-pac: PAC proof of an iOS 27 dyld shared cache (stage 4 root pipeline)

The 730G has no PAC, so every non-hint PAC word the arm64e userland executes is lowered offline (RETAB -> RET,
BLRAA -> BLR, PAC*/AUT* -> NOP, ...). Lowering a word that is really data would corrupt it, so only words inside
a control-flow proof are lowered. The prover and rewriter are UniXNU-zeta's; this directory adds the three fixes
iOS 27.2.1 needs and a driver that fits the proof into this laptop's memory.

- `zeta/`: vendored unchanged from https://github.com/none24smu/UniXNU-zeta `scripts/` at commit
  eb489285a1d9153872f00c93ebb519a269b249b5 (BSD-2-Clause-Patent, `zeta/LICENSE`): prove-zeta-dyld-cache.py,
  rewrite-zeta-dyld-cache.py, rewrite-zeta-userland.py, zeta_dyld_cache.py, zeta_userland_code.py,
  zeta_userland_pauth.py.
- `sunfish_pac.py`: the fixes (each on by default, applied at run time; zeta's files stay untouched) and the
  worker subcommands. Why: `research/notes/dyld27-proof-2026-11-13.md`.
  - TPRO words (`--no-tpro` turns it off): 0xd5940000, 0xd5900040, 0xd5900020 are straight-line for the oracle.
    Apple's TPRO set/clear, unallocated in Arm's A64 map, gated by commpage byte 0xc10c == 4 (the kernel keeps it 0).
  - Gap islands (`--no-gaps`): executable-mapping bytes owned by no image section become stub islands. 27 moved the
    objc stubs (`adrp; add; b objc_msgSend; brk`) out of the images to after libobjcMsgSendN in every subcache.
  - Noreturn at section end (`--no-noreturn-end`): a strict walk that falls off the decoded sections right after a
    call stops there, like zeta's udf-after-call rule. It is one `if` added to zeta's `walk()` source at import;
    it refuses to run if upstream's `walk()` changed around the anchor.
- `prove-cache.py`: zeta's main() steps (pass 1 own roots, pass 2 with the calls other images made, islands from
  inbound calls) as units in chunks over `--jobs` worker processes, each in
  `systemd-run --user --scope -p MemoryMax=CAP -p MemorySwapMax=0`. A unit that is OOM-killed is listed in
  `failed.json` and, after the round, retried alone with `--retry-mem`. Resumable: finished units are skipped; pass 2
  and island units are redone when their call set grew (an `--only` run followed by a full run).

## Usage
Needs Python with capstone 5.0.7 and numpy (a venv, e.g. `python3 -m venv work/venv-pac && work/venv-pac/bin/pip
install capstone==5.0.7 numpy`) and llvm-mc on PATH. Run with `-I` from a directory outside the IPSW tree.

    work/venv-pac/bin/python3 -I tools/ios27-pac/prove-cache.py \
        --cache ../restore/ipsw/x/24B156/dsc/24B156__iPhone12,1/dyld_shared_cache_arm64e \
        [--jobs 2] [--mem 3.5G] [--retry-mem 7G] [--only dyld --only CoreText ...]

Out dir (default `../restore/ipsw/x/<build>/prove/`, out of git): `setup.{json,npz}` (image list, ranges,
islands, slide targets; made once), `pass1/ pass2/ islands/` (JSON + npz per unit), `calls.npz`, `failed.json`,
`options.json` (an out dir keeps the switches it was made with) and `summary.json`: zeta's schema, so
`zeta/rewrite-zeta-dyld-cache.py --proof DIR` reads it, plus a `sunfish` table (proven = lowered PAC words,
unproven, unlowerable, seconds and peak RSS per image). An `--only` summary is partial: islands are proven only
from the calls of the images run. Exit 1 when units failed or errored.

## Results (2026-11-13, jobs 1, cap 3.5 GB, macOS VM running; capstone 5.0.7, llvm-mc 23.1.4)
Setup (27.2.1): 4,630 images with code, 35 stub islands, 9,478 gap islands (0x4da03e2 bytes), 14.5 M slide
targets, 35 s, peak 2.1 GB.

| 27.2.1 image | proven | unproven | unlowerable | s | peak RSS MB |
|---|---:|---:|---:|---:|---:|
| Foundation | 84,335 | 0 | 0 | 13.0 | 1,726 |
| AudioToolbox | 18,233 | 0 | 0 | 3.0 | 524 |
| CoreFoundation | 8,737 | 0 | 0 | 1.9 | 437 |
| CoreText | 7,306 | 0 | 0 | 2.3 | 374 |
| dyld | 5,391 | 0 | 0 | 0.8 | 339 |
| libobjc.A.dylib | 3,012 | 0 | 0 | 0.3 | 342 |
| FrontBoardServices | 2,630 | 0 | 0 | 0.6 | 353 |
| libdyld.dylib | 932 | 0 | 0 | 0.1 | 343 |
| libsystem_m.dylib | 356 | 1 (float constant) | 0 | 0.2 | 343 |
| libsystem_pthread.dylib | 229 | 0 | 0 | 0.1 | 343 |
| UIKitCore | OOM-killed at 3.5 GB (listed in failed.json) | | | | |

Same numbers as the prototype. Peak RSS includes the ~330 MB every worker holds (slide targets, cache pages).
Islands reached by these images: 5 stub islands (361 lowered), 4 gap islands (no PAC words: the objc stubs).
Checks: 27.2.1 with all three switches off gives zeta's unmodified result (dyld 1,619 unproven / 3,772 lowered,
CoreText 1,947 / 5,359, libdyld 3 / 929); 26.6.2 dyld with the switches on gives 0 / 5,273, same as unmodified zeta.
In 27 cross-image calls go through the TEXT_STUBS islands, so pass 2 found no direct calls into these images.

## Still to do
- Full-cache run (WebCore, JavaScriptCore, UIKitCore, ...) with more than 8 GB free (VM off): jobs 2 at 3.5 GB,
  retry 7 GB; then check failed.json and the island totals (the 10,336 PAC-class words in unowned executable
  bytes should be proven from calls there). Then the rewrite with `--page-shift 12`.
- UIKitCore needs more than 3.5 GB in one process (zeta keeps a decoded tuple per word); the census ran it at 4 GB.
