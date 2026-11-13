# GPU bugs (started 2026-10-31)

Known GPU bugs and how often they happen, so a jump in rate shows which day and change brought it. Not loaded
automatically. Details stay in [features/gpu.md](features/gpu.md); the plan is in [plan.md](plan.md).

Fix a bug now only if it:
1. voids benches,
2. stops phone testing, or
3. doubles in rate after a change (turn that change off first).

Everything else waits until the speed targets in the plan are met. `tools/sunfish-perfab.sh` adds the counts of
each of its runs to "Bench runs" below; add the counts by hand after each soak.

## Bugs
| ID | Bug | Log line to count | Latest rate or count | Recovers? | Fix now? |
|---|---|---|---|---|---|
| G1 | No-fault hang, stuck TLB sync | `GPU hang or fault` with `fsr 0`, `tlb sync -> timeout` | kernel134: 2 in ~113 k submits; kernel135: 0 in 151 k; kernel138-139: 2 in ~380 k; sweetrowa55=4: 3 in ~43 k with mode 2 (rows2), 0 in ~81 k with mode 3 (mf3) | No, 0 of 8; reboot needed | Only if it voids benches |
| G2 | Submit error, backboardd restarts | `submit failed: 0xe00002c2` | kernel135: 3 in ~34 min (151 k submits) | Restart, then G3 | Yes if it voids benches |
| G3 | Slower mode after a backboardd restart (2026-11-01: may really be low brightness, smoothness.md) | 2nd submit about 6 ms slower | Every restart seen (m1, z1) | Reboot | Yes if it voids benches |
| G4 | SMMU-fault hang | `GPU hang or fault` with `fsr 40000002` | kernel135: 2 in 151 k (z1 boot 20261031-073304; first listed as 1) | Yes, ~28 ms; since Turnip 0112 + sweetgpukill=0 backboardd keeps running (2026-11-12) | No |
| G5 | Boot with no GPU | 0 `SWEET GPU` lines, backboardd's Metal bridge closed | Once (r1, kernel134, 20261031-035915) | Reboot | Only if it returns |
| G6 | DeviceLost after Camera launches | `commandBuffer refused: command buffer: DeviceLost` | Once (kernel127, 2026-10-30) | Killing backboardd | Only if it returns |
| G7 | Planar surface refused | `planar iosurface refused` | Seen with G6; effect unknown | Unknown | No |
| G8 | Reduce Transparency hang | Hang right after turning it on | Not reproduced on kernel52 | Cause unproven | No |

Failed recoveries leave `device refused: OutOfMemory(Device)` and CPU drawing until reboot (G1). CPU drawing can reach
60 swaps/s on some screens, so a good speed number alone doesn't prove the GPU ran. Silent resets are backlog B4.

G7 facts (2026-11-03): seen from Maps (`420f fmt 540 plane 0`, boot 20261103-062614, s7c UI soak). Frontend/bridge 0127 (not yet on the phone) sends planar surfaces to the runtime's GPU YCbCr path first, with 0112's CPU copy as fallback (off: `SWEET_YCBCR_GPU=0`); bridge 0126 skips the two-plane zero-fill (off: `SWEET_M2V_TWO_PLANE_ZERO=1`). The log line to count becomes `SWEET YCBCR: ... -> refused`.

## 2026-11-01: G1 rate with SWEET_CULL=2
G1 by setup since df5: mode 2 or 3 without cull: 2 in about 500 k submits (df5, rows2 excluded: 3 more at 1248 MHz); with SWEET_CULL=2: 3 in about 143 k (cu1, ni1, br1; sy1-style runs excluded). All no-fault, recovery failed. That is more than double: by the rule, cull went off the everyday setup. Update 10:15: a76r (cull on) 1 more; lo0 and lo2 (cull off) 2 in about 34 k. Overnight mode 3 without cull had 0 in about 250 k, all at DCS 33-36 (minimum). So brightness or daytime state may matter as much as cull: confounded. G1 now voids benches often, so it qualifies for fixing.

## Bench runs
Written by `tools/sunfish-perfab.sh`, newest first. Void runs are screen runs, not boots.

| Date | Tag | Kernels and configs | Boots | Submits | G1 | G2 | G4 | Void runs |
|---|---|---|---|---|---|---|---|---|
| 2026-11-02 | sbn2 | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3 | 1 | 7 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | sbo2 | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3 | 1 | 7 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | sbn1 | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3 | 1 | 7 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | sbo1 | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3 | 1 | 7 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | dab5 | da=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3,+SWEET_CULL_DEADATT=1 | 1 | 9 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | daa5 | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3 | 1 | 9 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | dab4 | da=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3,+SWEET_CULL_DEADATT=1 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | daa4 | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | dab3 | da=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3,+SWEET_CULL_DEADATT=1 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | daa3 | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | dab2 | da=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3,+SWEET_CULL_DEADATT=1 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | daa2 | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3 | 1 | 9 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | dab1 | da=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3,+SWEET_CULL_DEADATT=1 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | daa1 | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3 | 1 | 9 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | dax0 | da=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3,+SWEET_CULL_DEADATT=1 | 1 | 6 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | gmb5 | d25=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=25,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | gma5 | d20=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | gmb4 | d25=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=25,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | gma4 | d20=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | gmb3 | d25=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=25,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3 | 1 | 9 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | gma3 | d20=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | gmb2 | d25=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=25,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | gma2 | d20=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | gmb1 | d25=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=25,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3 | 1 | 11 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | gma1r | d20=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | gma1 | d20=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3 | 1 | 4 k | 0 | 0 | 0 | 2 |
| 2026-11-02 | rab5 | ra=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3,+SWEET_M2V_RENDER_AREA=1 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | raa5 | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | rab4 | ra=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3,+SWEET_M2V_RENDER_AREA=1 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | raa4 | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | rab3 | ra=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3,+SWEET_M2V_RENDER_AREA=1 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | raa3 | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | rab2 | ra=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3,+SWEET_M2V_RENDER_AREA=1 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | raa2 | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | rab1 | ra=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3,+SWEET_M2V_RENDER_AREA=1 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | raa1 | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | mkb2 | m0=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3,+SWEET_CULL_MASK0=1 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | mka2 | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | mkb1 | m0=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3,+SWEET_CULL_MASK0=1 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | mka1 | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | cvt1 | c3=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3 | 1 | 3 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | cvb5 | c3=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | cva5 | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | cvb4 | c3=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | cva4 | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | cvb3 | c3=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | cva3 | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | cvb2 | c3=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | cva2 | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | cvb1 | c3=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+SWEET_CULL=3 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | cva1 | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | atb5 | atp=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+TU_AUTOTUNE_ALGO=profiled | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | ata5 | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1 | 1 | 9 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | atb4 | atp=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+TU_AUTOTUNE_ALGO=profiled | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | ata4 | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | atb3 | atp=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+TU_AUTOTUNE_ALGO=profiled | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | ata3 | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | atb2 | atp=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+TU_AUTOTUNE_ALGO=profiled | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | ata2 | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | atb1 | atp=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+TU_AUTOTUNE_ALGO=profiled | 1 | 9 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | ata1 | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | ts2c | atp=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+SWEET_SURF_FLUSH=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+TU_AUTOTUNE_ALGO=profiled | 1 | 5 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | ts2b2 | d100=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+SWEET_SURF_FLUSH=1,+TU_FETCH_GMEM_MIN_DRAWS=100 | 1 | 6 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | ts2b | d100=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+SWEET_SURF_FLUSH=1,+TU_FETCH_GMEM_MIN_DRAWS=100 | 1 | 235 | 0 | 0 | 0 | 2 |
| 2026-11-02 | ts2a | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+SWEET_SURF_FLUSH=1,+TU_FETCH_GMEM_MIN_DRAWS=20 | 1 | 5 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | ts1c | atp=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+SWEET_SURF_FLUSH=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+TU_AUTOTUNE_ALGO=profiled | 1 | 6 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | ts1b | d100=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+SWEET_SURF_FLUSH=1,+TU_FETCH_GMEM_MIN_DRAWS=100 | 1 | 6 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | ts1a | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+SWEET_SURF_FLUSH=1,+TU_FETCH_GMEM_MIN_DRAWS=20 | 1 | 5 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | po0b | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1; po0=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+TU_SWEET_PRIM_ORDER=0 | 2 | 11 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | po0a | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1; po0=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1,+TU_SWEET_PRIM_ORDER=0 | 2 | 12 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | sfb5 | f1=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | sfa5 | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | sfb4 | f1=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | sfa4 | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | sfb3 | f1=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | sfa3 | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | sfb2 | f1=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | sfa2 | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | sfb1 | f1=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+SWEET_SURF_FLUSH=1 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | sfa1 | def=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | k158 | ev=158,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | mlx2 | ev=157,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20 | 1 | 7 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | mlo2 | ev=157,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20 | 1 | 6 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | mlx1 | ev=157,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20 | 1 | 7 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | mlo1 | ev=157,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20 | 1 | 6 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | k157 | ev=157,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | vpb5 | off=156,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20 | 1 | 23 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | vpa5 | p5=156,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetvsyncphase=5000,+TU_FETCH_GMEM_MIN_DRAWS=20 | 1 | 23 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | vpb4 | off=156,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20 | 1 | 22 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | vpa4 | p5=156,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetvsyncphase=5000,+TU_FETCH_GMEM_MIN_DRAWS=20 | 1 | 23 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | vpb3 | off=156,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20 | 1 | 22 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | vpa3 | p5=156,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetvsyncphase=5000,+TU_FETCH_GMEM_MIN_DRAWS=20 | 1 | 23 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | vpb2 | off=156,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20 | 1 | 22 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | vpa2 | p5=156,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetvsyncphase=5000,+TU_FETCH_GMEM_MIN_DRAWS=20 | 1 | 23 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | vpb1 | off=156,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20 | 1 | 23 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | vpa1 | p5=156,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetvsyncphase=5000,+TU_FETCH_GMEM_MIN_DRAWS=20 | 1 | 23 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | vp13 | p13=156,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetvsyncphase=13500,+TU_FETCH_GMEM_MIN_DRAWS=20 | 1 | 18 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | u6c | trf=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+MESA_GPU_TRACES=print,+TU_GPU_TRACEPOINT=-draw_ib_gmem -gmem_load -gmem_store -binning_ib | 1 | 5 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | u6b | tr=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20,+MESA_GPU_TRACES=print | 1 | 234 | 0 | 0 | 0 | 2 |
| 2026-11-02 | u6a | notr=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20 | 1 | 6 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | stb | base=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1 | 1 | 24 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | sta | base=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1 | 1 | 22 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | ctd | d20=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20 | 1 | 22 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | ctc | base=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1 | 1 | 20 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | ctb | d20=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20 | 1 | 20 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | cta | base=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1 | 1 | 23 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | cta | base=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1 | 1 | 19 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | cs4d | base=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1; d5=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=5; d20=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20 | 3 | 11 k | 0 | 0 | 0 | 2 |
| 2026-11-02 | cs4c | base=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1; d5=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=5; d20=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20 | 3 | 17 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | cs4b | base=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1; d5=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=5; d20=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20 | 3 | 17 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | cs4a | base=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1; d5=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=5; d20=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20 | 3 | 17 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | mo3 (by hand) | 154, everyday args, webcam check; G4 at 210.020 s (`fence 2955, done 2948, smmu fsr 40000002 far 119e04470`), recover2 45.5 ms, backboardd killed after recovery | 1 | about 3 k (fence 2955) | 0 | 0 | 1 | 1 |
| 2026-11-02 | va4 | ahead=155,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetvsyncahead=4000 | 1 | 22 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | vg4 | grid=155,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetvsyncgrid=1 | 1 | 19 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | va3 | ahead=155,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetvsyncahead=4000 | 1 | 23 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | vg3 | grid=155,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetvsyncgrid=1 | 1 | 21 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | va2 | ahead=155,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetvsyncahead=4000 | 1 | 21 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | vg2 | grid=155,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetvsyncgrid=1 | 1 | 22 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | va1 | ahead=155,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetvsyncahead=4000 | 1 | 19 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | vg1 | grid=155,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetvsyncgrid=1 | 1 | 21 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | csr3 | base=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1; d5=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=5; d20=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20 | 2 | 6 k | 0 | 0 | 0 | 2 |
| 2026-11-02 | csr2 | base=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1; d5=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=5; d20=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20 | 3 | 19 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | csr1 | base=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1; d5=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=5; d20=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20 | 3 | 13 k | 0 | 0 | 0 | 2 |
| 2026-11-02 | csa | base=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1; d5=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=5; d20=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,+TU_FETCH_GMEM_MIN_DRAWS=20 | 2 | 6 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | rl4 | base=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1,+SWEET_CTL=/var/local/turnip/ctl.txt | 1 | 21 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | rl3 | base=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1,+SWEET_CTL=/var/local/turnip/ctl.txt | 1 | 22 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | rl2 | base=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1,+SWEET_CTL=/var/local/turnip/ctl.txt | 1 | 21 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | rl1 | base=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1,+SWEET_CTL=/var/local/ctl.txt | 1 | 23 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | rl1 | base=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1,+SWEET_CTL=/var/local/ctl.txt | 1 | 20 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | qs1e | qos=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1,+SWEET_BRIDGE_QOS=1 | 1 | 7 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | qs0e | off=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1 | 1 | 8 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | qs1d | qos=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1,+SWEET_BRIDGE_QOS=1 | 1 | 7 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | qs0d | off=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1 | 1 | 8 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | qs1c | qos=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1,+SWEET_BRIDGE_QOS=1 | 1 | 8 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | qs0c | off=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1 | 1 | 8 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | qs1b | qos=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1,+SWEET_BRIDGE_QOS=1 | 1 | 7 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | qs0b | off=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1 | 1 | 8 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | qs1a | qos=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1,+SWEET_BRIDGE_QOS=1 | 1 | 8 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | qs0a_r | off=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1 | 1 | 7 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | qs0a | off=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1 | 1 | 8 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | fg1f | fg=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1,sweetfgbig=1 | 1 | 5 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | fg0f | off=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1 | 1 | 5 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | fg1e | fg=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1,sweetfgbig=1 | 1 | 4 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | fg0e | off=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1 | 1 | 4 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | fg1d | fg=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1,sweetfgbig=1 | 1 | 5 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | fg0d | off=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1 | 1 | 4 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | fg1c | fg=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1,sweetfgbig=1 | 1 | 4 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | fg0c | off=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1 | 1 | 5 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | fg1b | fg=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1,sweetfgbig=1 | 1 | 5 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | fg0bb | off=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1 | 1 | 5 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | fg0b | off=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1 | 1 | 2 k | 0 | 1 | 0 | 1 |
| 2026-11-02 | fg1a | fg=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1,sweetfgbig=1 | 1 | 5 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | fg0a | off=154,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1 | 1 | 5 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | fa1e | fence=153,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1,sweetfencepoll=200,@work/metal2-fence/out/phone/metal2/out | 1 | 7 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | fa0e | off=153,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1,@work/metal2-next/out/phone/metal2/out | 1 | 8 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | fa1d | fence=153,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1,sweetfencepoll=200,@work/metal2-fence/out/phone/metal2/out | 1 | 8 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | fa0d | off=153,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1,@work/metal2-next/out/phone/metal2/out | 1 | 8 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | fa1c | fence=153,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1,sweetfencepoll=200,@work/metal2-fence/out/phone/metal2/out | 1 | 8 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | fa0c | off=153,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1,@work/metal2-next/out/phone/metal2/out | 1 | 8 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | fa1b | fence=153,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1,sweetfencepoll=200,@work/metal2-fence/out/phone/metal2/out | 1 | 8 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | fa0b | off=153,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1,@work/metal2-next/out/phone/metal2/out | 1 | 8 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | fa1a | fence=153,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1,sweetfencepoll=200,@work/metal2-fence/out/phone/metal2/out | 1 | 8 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | fa0a | off=153,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetcpusample=1,@work/metal2-next/out/phone/metal2/out | 1 | 8 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | df2 | def=153,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-02 | df1 | def=153,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-01 | tm0c | off=152,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetrowa55=6,sweetgpufreq=6,sweethwcg=1,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1 | 1 | 8 k | 0 | 0 | 0 | 0 |
| 2026-11-01 | tm3c | tcr=152,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetrowa55=6,sweetgpufreq=6,sweethwcg=1,sweetsmmutcr=3,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1 | 1 | 7 k | 0 | 0 | 0 | 0 |
| 2026-11-01 | tm0b | off=152,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetrowa55=6,sweetgpufreq=6,sweethwcg=1,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1 | 1 | 8 k | 0 | 0 | 0 | 0 |
| 2026-11-01 | tm3b | tcr=152,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetrowa55=6,sweetgpufreq=6,sweethwcg=1,sweetsmmutcr=3,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1 | 1 | 7 k | 0 | 0 | 0 | 0 |
| 2026-11-01 | tm0a | off=152,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetrowa55=6,sweetgpufreq=6,sweethwcg=1,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1 | 1 | 8 k | 0 | 0 | 0 | 0 |
| 2026-11-01 | tm3a | tcr=152,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetrowa55=6,sweetgpufreq=6,sweethwcg=1,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1,sweetsmmutcr=3 | 1 | 8 k | 0 | 0 | 0 | 0 |
| 2026-11-01 | sm3a | tcr=151,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetrowa55=6,sweetgpufreq=6,sweethwcg=1,sweetsmmutcr=3,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1 | 1 | 8 k | 0 | 0 | 0 | 0 |
| 2026-11-01 | sm0a | off=151,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetrowa55=6,sweetgpufreq=6,sweethwcg=1,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1 | 1 | 8 k | 0 | 0 | 0 | 0 |
| 2026-11-01 | lb3b | base=150,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetrowa55=6,sweetgpufreq=6,sweethwcg=1,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1 | 1 | 8 k | 0 | 0 | 0 | 0 |
| 2026-11-01 | lb3 | base=150,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetrowa55=6,sweetgpufreq=6,sweethwcg=1,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1 | 1 | 8 k | 0 | 0 | 0 | 0 |
| 2026-11-01 | lb2b | base=150,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetrowa55=6,sweetgpufreq=6,sweethwcg=1,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1 | 1 | 7 k | 0 | 0 | 0 | 0 |
| 2026-11-01 | lb2 | base=150,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetrowa55=6,sweetgpufreq=6,sweethwcg=1,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1 | 1 | 7 k | 0 | 0 | 0 | 0 |
| 2026-11-01 | lb1b | base=150,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetrowa55=6,sweetgpufreq=6,sweethwcg=1,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1 | 1 | 7 k | 0 | 0 | 0 | 0 |
| 2026-11-01 | lb1 | base=150,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetrowa55=6,sweetgpufreq=6,sweethwcg=1,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1 | 1 | 8 k | 0 | 0 | 0 | 0 |
| 2026-11-01 | lb0b | base=150,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetrowa55=6,sweetgpufreq=6,sweethwcg=1,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1 | 1 | 7 k | 0 | 0 | 0 | 0 |
| 2026-11-01 | lb0 | base=150,sweetse9=2,sweetcampmic=2,sweetswapbig=6,sweetampreset=1,sweetrowa55=6,sweetgpufreq=6,sweethwcg=1,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1 | 2 | 8 k | 0 | 0 | 0 | 0 |
| 2026-11-01 | fg1 | base=146,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,sweetgpufreq=6,sweetcpusample=1,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1; fg=146,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,sweetgpufreq=6,sweetcpusample=1,sweetfgbig=1,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1 | 4 | 22 k | 0 | 0 | 0 | 0 |
| 2026-11-01 | ph1 | ph=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,sweetgpufreq=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1,+SWEET_PASSHASH=1,@work/metal2-passhash/out/phone/metal2/out | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-11-01 | hw2 | off=144,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,sweetgpufreq=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1,@work/metal2-scratch/out/phone/metal2/out; hwcg=144,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,sweetgpufreq=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1,@work/metal2-scratch/out/phone/metal2/out,sweethwcg=1; scr=144,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,sweetgpufreq=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1,@work/metal2-scratch/out/phone/metal2/out,+SWEET_M2V_SCRATCH=1 | 15 | 143 k | 1 | 0 | 0 | 4 |
| 2026-11-01 | cc3 | tr=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,sweetgpufreq=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1,+MESA_GPU_TRACES=print | 1 | 2 k | 0 | 0 | 0 | 0 |
| 2026-11-01 | hw1d | off=144,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,sweetgpufreq=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1; on=144,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,sweetgpufreq=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1,sweethwcg=1 | 2 | 20 k | 0 | 0 | 0 | 0 |
| 2026-11-01 | hw1c | off=144,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,sweetgpufreq=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1; on=144,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,sweetgpufreq=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1,sweethwcg=1 | 2 | 19 k | 0 | 0 | 0 | 0 |
| 2026-11-01 | hw1 | off=144,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,sweetgpufreq=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1; on=144,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,sweetgpufreq=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1,sweethwcg=1 | 4 | 29 k | 0 | 0 | 0 | 0 |
| 2026-11-01 | gv1 | g0=142,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetgpufreq=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1; g1=142,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetgpufreq=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1,sweetgov=1 | 8 | 94 k | 0 | 0 | 0 | 2 |
| 2026-11-01 | gd2 | g5=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1; g6=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1,sweetgpufreq=6 | 10 | 92 k | 1 | 0 | 0 | 3 |
| 2026-11-01 | hot1 | a2208=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1; a1939=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1,sweetrowa76=10 | 3 | 162 k | 0 | 0 | 0 | 0 |
| 2026-11-01 | cp1 | base=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,@work/metal2-cpu/out/phone/metal2/out; cpu=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,@work/metal2-cpu/out/phone/metal2/out,+SWEET_U0011=1,+SWEET_U0012=1,+SWEET_U0013=1,+SWEET_U0014=1 | 10 | 68 k | 0 | 0 | 0 | 0 |
| 2026-11-01 | sw3 | s=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1 | 4 | 31 k | 0 | 0 | 0 | 0 |
| 2026-11-01 | mf4 | fl1=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1; fl0=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,sweetmapflush=0 | 16 | 144 k | 1 | 0 | 0 | 4 |
| 2026-11-01 | lo3 | luma=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1 | 3 | 29 k | 0 | 0 | 0 | 0 |
| 2026-11-01 | lo2 | low=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1 | 3 | 14 k | 1 | 0 | 0 | 5 |
| 2026-11-01 | lo1 | fix=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1 | 3 | 28 k | 0 | 0 | 0 | 1 |
| 2026-11-01 | lo0 | low=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1 | 3 | 20 k | 1 | 0 | 0 | 3 |
| 2026-11-01 | a76r | r12=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_CULL=2; r11=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_CULL=2,sweetrowa76=11; r10=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_CULL=2,sweetrowa76=10 | 12 | 109 k | 1 | 0 | 0 | 1 |
| 2026-11-01 | br1 | br=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_CULL=2 | 3 | 26 k | 1 | 0 | 0 | 1 |
| 2026-11-01 | dd1 | base=140,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_CULL=2; dd0=140,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_CULL=2,sweetddmin=0; dd500=140,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_CULL=2,sweetddmin=500; bl50=140,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_CULL=2,sweetblmin=50 | 8 | 28 k | 0 | 0 | 0 | 1 |
| 2026-11-01 | cs1 | cs=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,+SWEET_CULL=2 | 4 | 36 k | 0 | 0 | 0 | 0 |
| 2026-11-01 | cu1 | c0=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,@work/metal2-shadow/out/phone/metal2/out; c2=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,@work/metal2-shadow/out/phone/metal2/out,+SWEET_CULL=2 | 8 | 67 k | 1 | 0 | 0 | 2 |
| 2026-11-01 | gd1 | base=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1; gpu6=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,sweetgpufreq=6; ddr1=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,sweetddr=1 | 12 | 106 k | 0 | 0 | 0 | 2 |
| 2026-11-01 | mf3 | fl1=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=4,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1; fl0=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=4,+SWEET_DEADFILL=3,+M2V_SHADOW_CACHE=1,sweetmapflush=0 | 16 | 81 k | 0 | 0 | 0 | 1 |
| 2026-11-01 | d4 | df2=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+M2V_SHADOW_CACHE=1,@work/metal2-shadow/out/phone/metal2/out,+SWEET_DEADFILL=2; df3=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+M2V_SHADOW_CACHE=1,@work/metal2-shadow/out/phone/metal2/out,+SWEET_DEADFILL=3 | 10 | 83 k | 0 | 0 | 0 | 1 |
| 2026-11-01 | d3 | df2=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+M2V_SHADOW_CACHE=1,@work/metal2-shadow/out/phone/metal2/out,+SWEET_DEADFILL=2; df3=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+M2V_SHADOW_CACHE=1,@work/metal2-shadow/out/phone/metal2/out,+SWEET_DEADFILL=3 | 6 | 49 k | 0 | 0 | 0 | 0 |
| 2026-11-01 | dw1 | dw=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+SWEET_DEADFILL=2,+M2V_SHADOW_CACHE=1,+SWEET_DFWHY=1 | 1 | 4 k | 0 | 0 | 0 | 0 |
| 2026-11-01 | nd1 | nd=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+SWEET_DEADFILL=2,+M2V_SHADOW_CACHE=1 | 3 | 11 k | 0 | 0 | 0 | 0 |
| 2026-11-01 | mf2 | fl1=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+SWEET_DEADFILL=2,+M2V_SHADOW_CACHE=1; fl0=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+SWEET_DEADFILL=2,+M2V_SHADOW_CACHE=1,sweetmapflush=0 | 6 | 49 k | 0 | 0 | 0 | 0 |
| 2026-11-01 | mf1 | m0=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=4,sweetmapflush=0,+SWEET_DEADFILL=2,+M2V_SHADOW_CACHE=1 | 8 | 35 k | 0 | 0 | 0 | 0 |
| 2026-11-01 | sy1 | gmem=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+SWEET_DEADFILL=2,+M2V_SHADOW_CACHE=1; sysmem=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,sweetrowa55=6,+SWEET_DEADFILL=2,+M2V_SHADOW_CACHE=1,+TU_DEBUG=sysmem | 4 | 20 k | 0 | 0 | 1 | 5 |
| 2026-11-01 | rows2 | r6=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,+SWEET_DEADFILL=2,+M2V_SHADOW_CACHE=1,sweetrowa55=6; r4=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,+SWEET_DEADFILL=2,+M2V_SHADOW_CACHE=1,sweetrowa55=4 | 10 | 86 k | 3 | 0 | 0 | 9 |
| 2026-10-31 | sh1 | s0=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,+SWEET_DEADFILL=2,@work/metal2-shadow/out/phone/metal2/out; s1=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,+SWEET_DEADFILL=2,@work/metal2-shadow/out/phone/metal2/out,+M2V_SHADOW_CACHE=1; s2=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,+SWEET_DEADFILL=2,@work/metal2-shadow/out/phone/metal2/out,+M2V_SHADOW_CACHE=2 | 9 | 78 k | 0 | 0 | 0 | 0 |
| 2026-10-31 | rows1 | base=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,+SWEET_DEADFILL=2; a55l=139,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,+SWEET_DEADFILL=2,sweetrowa55=6 | 10 | 55 k | 0 | 0 | 0 | 2 |
| 2026-10-31 | df5 | base=138,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1; df2=138,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,+SWEET_DEADFILL=2 | 10 | 69 k | 1 | 0 | 0 | 4 |
| 2026-10-31 | cpu1 | base=137,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1; a76=137,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1,@work/metal2-a76/out/phone/metal2/out | 10 | 100 k | 0 | 0 | 0 | 2 |
| 2026-10-31 | smoke3 | base=137,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1 | 1 | 10 k | 0 | 0 | 0 | 0 |
| 2026-10-31 | smoke1 | base=137,sweetswapbig=6,sweetse9=2,sweetcampmic=2,sweetampreset=1 | 1 | 9 k | 0 | 0 | 0 | 0 |

## Daily soak (1 h, overnight)
Newest first. Earlier soaks were shorter or used other loads, so compare rates, not raw counts.

| Date | Kernel, bundle | Length | Submits | G1 | G2 | G4 | Other |
|---|---|---|---|---|---|---|---|
| 2026-11-13 n10 | kernel167 (0281-0285) everyday args + sweetgpukill=0 sweetwdtcrumb=1, bundle ceb6140 (Turnip 0112, frontend 0132, bridge 0133) | 60 min (3597 s, 8 uisoak chunks), done; VALID | 465 k | 0 | 1 | 1 | 0 backboardd restarts: G4 at 1351 s recovered in 36 ms, device kept (backboardd: 2 command buffers marked error, 0 staging redos). G2 at 3552 s in WebKit.GPU (DEVLOST for that client, recovered), cause logged by xnu 0284: `submit bad buffer 1/4 (iova below window) handle 0 iova 0x0 bytes 0x2b4`. 0 RPMh/SPMI/panics, max 84.8 C, 0 caps |
| 2026-11-12 n9 | kernel163 (= 162 + xnu 0281 isb, first boot) sweetse9=2 sweetcampmic=2 sweetswapbig=6 sweetampreset=1 sweetpmemwc=2 sweetgpucap=512 sweetwdtcrumb=1, bundle d3316ff | 60 min, full soak, done (3600 s); VOID (1 backboardd restart) | 371 k | 0 | 1 | 0 | First G2 since kernel135 (then 3 in 151 k; now 1 in 371 k: not risen). 0 RPMh timeouts, 0 SPMI retries, no panic/reset, 0 failed recoveries, max 84.1 C, 0 caps, last DCS 51 = 33. Webcam: Maps ghosted text at 22:05 (B50), Safari tab thumbnail with a black garbled block at 22:35 (B53) |
| 2026-11-02 n8 | kernel158 sweetse9=2 sweetcampmic=2 sweetswapbig=6 sweetampreset=1 sweetwdtcrumb=1 (everyday), bundle 82f6b41, SWEET_CULL=3 | 60 min, full soak, done (3607 s) | 399 k | 0 | 0 | 0 | First soak with 0 hangs of any kind; 0 backboardd restarts, max 82.8 C, 0 caps, nits 33 |
| 2026-11-02 n7 | kernel152 sweethwcg=1 sweetcxcycle=1 sweetwdtcrumb=1 sweetsmmutcr=3, metal2-cpu, mode 3, cache, knobs on, luma boost off, A55 1497 MHz, GPU 650 MHz | 60 min, full soak, done | 397 k | 0 | 0 | 1 | First full clean soak. G4 at 2564 s recovered, 1 backboardd restart; no silent reset, no CX cycle; max 95.7 C, 60 of 730 readings at 90 C or more, 0 caps, nits 5 |
| 2026-11-01 n6 | kernel149, as n5 | 12.6 min of 60; G4 at 461 s recovered in 36.9 ms; real G1 at 897 s, `ack 1`, CX cycle ran: `gdsc won't collapse` after 500 ms, recovery failed | 76.5 k | 1 | 0 | 1 | backboardd restart 1, max 93.8 C, 0 caps, nits 5; no silent reset |
| 2026-11-01 n5 | kernel149 sweethwcg=1 sweetcxcycle=1, metal2-cpu, mode 3, shadow cache, knobs on, A55 1497 MHz, GPU 650 MHz | 11 min of 60; silent reset at uptime 695 s in Maps, just after `texture refused: OutOfMemory(Device)` (pool peak 620 MB) | 61 k | 0 | 0 | 0 | Reset to fastboot, no panic line, no CX cycle ran; 0 restarts, max 88.3 C (at 217 s; 79 C at the end), nits 5 |
| 2026-11-01 n4 | kernel144 sweethwcg=1, metal2-cpu, mode 3, shadow cache, knobs on, A55 1497 MHz, GPU 650 MHz | 5.2 min valid of 60; G1, failed recovery (uptime 3873 s, recover2 FAILED after 2.47 s) | 31.5 k | 1 | 0 | 0 | 0 backboardd restarts, no silent reset, max 80.3 C, 0 caps. One G1 can't tell if clock gating raises the rate (baseline about 1 per 100 k: 1 in 31 k is about 27 %) |
| 2026-11-01 n2 | kernel139, shadow cache, mode 2, A55 1497 MHz | 14.5 min valid of 60; G1, failed recovery | about 86 k total | 1 | 0 | 0 | CPU drawing for the rest; no silent reset |
| 2026-10-31 n1 | kernel139, shadow cache, mode 2, A55 1497 MHz | 24.5 min, silent reset | 127 k | 0 | 0 | 0 | Reset to fastboot, no panic line |
| 2026-10-31 z1 | kernel135, allocator | ~34 min, stopped early | 151 k | 0 | 3 | 2 | - |
| 2026-10-31 soak1 | kernel134, allocator | 2 boots | ~113 k | 2 | at least 1 | not counted | - |

### 2026-11-13 01:35 G2 cause caught (soak n10, xnu 0284)
`[3552.997] SWEET MTL: v2 com.apple.WebKit.GPU: submit bad buffer 1/4 (iova below window) handle 0 iova 0x0 bytes 0x2b4
win 0x1200000000+0x100000000`, same timestamp as `MTL2[369 com.apple.WebKit.GPU]: DEVLOST first (turnip) ...
tu_knl_darwin.cc:908: submit failed: 0xe00002c2; submits 52603 faults 1` (observed). Entry 1 of 4 has handle 0 and
iova 0 with a 692-byte size: a submit entry built from a tu_bo that was already finished (zeroed) - the 22:50 guess
holds. Next: find which CS/BO is freed while still referenced (Fable read-only analysis), fix in Turnip.

### 2026-11-12 22:50 G2 analysis (read-only, soak n9)
n9's G2: uptime 2259.440 s (~22:08), backboardd `DEVLOST first (turnip) ... tu_knl_darwin.cc:907: submit failed:
0xe00002c2; submits 80745 faults 0 heap_used 293568 KB ... inflight 8`, during Maps GPU pool swings (178-286 MB, total
548-657 MB, peak 762); no SMMU fault, hang or v2_err line; backboardd restarted 2260.009 (observed). All 8 G2s on the PC
are backboardd with 0xe00002c2. Kernel BadArgument submit returns are all silent (SweetAccelerator.cpp:804/805/1030/
1037-1038). Only the per-buffer iova-in-window check (:1037-1038) is plausibly reachable from Turnip's real input. Guess
(~50 %): a submit entry built from a tu_bo already finished (darwin_bo_finish zeroes it, tu_knl_darwin.cc:667) -> iova
below fWinBase. Rate history: kernel135 ~2 per 100 k; n7+n8 0 in ~796 k; n9 1 in 371 k (not rising). Next: xnu 0284
logs the failing check (handle, iova, bytes, window); then fix by what it names.

### 2026-11-03 08:15 G7 GPU YCbCr path on the phone (fe2d169, kernel159)
Observed: `SWEET YCBCR: 420f fmt 500 plane 0 1128x1504 -> gpu (offset 64 row 1152 matrix 0)` (camera, backboardd),
`b3a8 fmt 550 plane 0 1125x1500 -> gpu`, `b3a8 fmt 550 plane 0 1536x1536 -> gpu` (WebKit.GPU), `420v fmt 500 plane 0
1920x1080 -> gpu` (Safari video): 4 gpu, 0 cpu, 0 refused. Camera viewfinder green with GPU on and off alike (not this
build). Safari 1080p colour bars right (one diagonal artefact line). Maps crashed 2/2 ~10 s after launch with GPU on:
`MISSING NBFunction -libraryData`, `-bitCodeOffset`, `-bitCodeFileSize`, then `CRASH Maps[633] sig 11 ... far 0x0`
(the 4ca1221 fallback answers nil); with SWEET_YCBCR_GPU=0 no crash in ~50 s. Left SWEET_YCBCR_GPU=0 set in
/var/local/mtl2-env. Matrix reads 0 (BT.601) for all: the matrix key lookup may be wrong. Investigator on libraryData
(possible B50 link). Markers g7a..g7d in ../logs/boots/20261103-074436.log.

### 2026-11-03 09:00 Maps after the stitching fix (a1f3952) and with sweetgpucap=512
Bundle a1f3952 (function stitching refused with an error; SWEET_STITCH=1 off), SWEET_YCBCR_GPU=0 removed (GPU path on).
- maps1 (kernel160, default cap 256 MB): Maps up 90 s, no crash, map area black. 0 MISSING, 0 `function stitching
  refused` (the stitching path was not hit this time, so the fix is not proven yet), 0 SWEET YCBCR lines from Maps,
  1 `54 MB buffer refused (holds 254 MB, 482 MB of the pool free): its cap`, 28 `texture refused: OutOfMemory(Device)`,
  13 `RenderPass(NoTargets)` command buffers refused.
- maps2 (reboot, `sweetgpucap=512`): no crash, 0 cap refusals, 0 OutOfMemory, 0 NoTargets, map area still black.
- Observed: the cap starves Maps of render targets at 256 MB, but lifting it does not bring the map back, so B50 is
  something else. Phone left on kernel160 + sweetpmemwc=2 + sweetgpucap=512 with bundle a1f3952.

### 2026-11-03 10:30 G7 GPU path drops ~2/3 of video frames (vd4d)
With SWEET_YCBCR_GPU on, Safari 1080p30 drops 1187-1212 of 1800 frames (82 / 63 with the CPU conversion) with
backboardd at 15 % CPU: the presenter stalls. Default set back to SWEET_YCBCR_GPU=0 on the phone; the fe2d169 default
(GPU on) must change in the frontend before the next bundle (or the stall fixed). video.md vd4d.

### 2026-11-03 11:00 G7 GPU path cost explained (research/notes/g7-gpu-stall-2026-11-03.md)
Not a CPU stall: GPU saturated. Every encoder that samples the on-surface YCbCr texture re-runs a full-frame
YCbCr->RGBA16F compute conversion (runtime ycbcr.rs:46-52, record :538-573), ~2 per CA frame at ~45 ms GPU each;
backboardd submits 88-95 ms mean, GPU busy 98-101 %, SWEET FB 9-12 fps; SHADOW copies 98-117 per 5 s. The CPU path
converts once per IOSurface seed. Fix being written: seed-gated conversion + cheaper 8-bit kernel.
Also: a GPU wedge "surface remap" (smmu fsr 40000002) at t=3923.034 in ../logs/boots/20261103-082158.log, 4 s after a
backboardd restart with the GPU path off (vd4d test; G4-like).

### 2026-11-03 12:25 G7 seed gating + baked kernel (27b96cb): better, still GPU-bound
Safari H.264 1080p30, software decode, bundle work/metal2-next-g7seed (LC_UUID 4C4C4415). Dropped of 1800 / backboardd
CPU / GPU busy / backboardd submit mean / SHADOW ycbcr converted (seed-skipped) per 5 s:
a GPU+seed+bake 883 / 19.6 % / 99-100 % / ~61 ms / 81-85 (0-3); b GPU+seed, BAKE=0 1192 / 14.9 % / 99-101 % / ~93.5 ms /
51-61 (1); c CPU path 89 / 94.9 % / 23-26 % / ~8.4 ms. Pictures right in all three (flame-shots work/shots/g7s-*.png).
Reading: baking cuts the conversion ~35 %, but most conversions are of new frames (few seed skips), and ~60 ms per
1080p conversion is far too slow (the plane copy from imported host memory and RGBA16F output are suspects). The CPU
path stays the default; next: the CPU path via Accelerate vImage (backboardd 95 % today); later a native
VkSamplerYcbcrConversion (Turnip samples G8_B8R8_2PLANE_420 directly).

### 2026-11-03 16:30 One GPU fault/hang during the games_fps A/B
kernel160 boot hevc1, t=2703.671: `SWEET GPU: v2 fence wait: GPU hang or fault (fence 73108, done 73101, smmu fsr 40000002 far 0 fsynr0 2): reset` — between two WebGL runs (the aa=0 page still open), recovered, no backboardd restart. smmu fsr 40000002 = same signature as the 'surface remap' wedge at 3923 s in 20261103-082158.log.

### 2026-11-03 17:10 Suspect: GPU faults right after a Venus session starts
Two GPU hangs with `smmu fsr 40000002` came 1-2 s after `venusd: session N opened` (vd1 at 2084 s in
20261103-082158.log; r1 at 3698 s in the hevc1 boot), each with a backboardd restart. Others today (2703 s games_fps, 3923 s)
had no Venus session nearby. Rate per Venus session start unknown (dozens of starts today without one). Watch: log the
offset from the last session open for every hang; if the link holds, look at what Venus start does to shared state
(MMCX/RPMh votes, the CB4 SMMU bank venusctl picks (a possible bootloader leftover, s7b), memory bandwidth votes).

### 2026-11-03 21:40 Venus-start suspect weakened
With timestamped venusd logs (vfix1): a backboardd `VK_ERROR_DEVICE_LOST ... submit failed: 0xe00002c2` (no smmu fsr line)
at 322.453 s came 70 s after the last venusd session opened and 8 s after it closed, 3 s after a new WebKit.GPU started:
not tied to a Venus start. The two earlier fsr-40000002 hangs 1-2 s after a session open may be coincidence; keep logging
offsets.

### 2026-11-03 15:35 Correction
Today's entry headings after ~12:00 EST run up to ~6.5 h ahead of the real clock (session clock error); the order and the quoted log stamps are right.


## G8 (2026-11-03) TU_FETCH_GMEM_MIN_DRAWS=20 leaves parts of render passes undrawn
Safari video (and a white line on Safari's toolbar): only horizontal bands of the video layer reached the framebuffer
(flame-shots wvA/wvB/wvV0). Gone with the line removed from /var/local/mtl2-env (S2/S2r). Rate: every video frame checked.
Line removed from the phone; tools/sunfish-install-speed.sh still writes it (to change).
