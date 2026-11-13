# GPU
**State:** 🟡 Adreno 618 at 650 MHz; injected and SMMU-fault hangs recover (~37 ms) and backboardd now keeps running through them (Turnip 0112 + sweetgpukill=0, 2/2 boots, 2026-11-12); real no-fault hangs (G1) don't, but none in two full 1 h soaks (n8 2026-11-02: 399 k submits, 0 G1/G2/G4; n7 397 k submits, one soak). **Updated:** 2026-11-12.

## How to use
- Default clock 565 MHz (`sweetgpufreq=5`); 430 MHz = `sweetgpufreq=4`; stock levels 650/800/825 = `sweetgpufreq=6..8` (xnu 0148).
- Recovery: `sweetgpurecover=2` (full), `sweetgpukill=1` (SIGKILL backboardd after recovery), both on by default in sunfish-boot.sh. `sweetsmmureset=0` turns off the SMMU/GBIF reset (0178).
- Hang injector `sweethangtest=N` (0167): bad IB on the Nth client submit; bit 31 = Nth present submit; bit 30 = stall IB (0177); 0xA0000200 = SMMU stall-on-fault present hang at submit 512 (0180).
- App soak: `tools/sunfish-appsoak.sh TAG SECONDS`.

## Facts
- Adreno 618, chip id 0x06010800; register map, firmware and GMU/HFI differences vs flame's A640 are in [reference/adreno618-notes.md](../reference/adreno618-notes.md).
- Metal goes through SweetMetal2 (metal2vulkan + Turnip): see [metal](metal.md).
- xnu 0174: Linux-style Fabia PLL0 restore after the DCVS vote (GX collapse wipes GPU_CC_PLL0; GMU DCVS zeroes PLL0 L).
- xnu 0181: early CB_RESUME at the start of recovery; 0182: SMMU stall-on-fault (CFCFG) by default.
- Real-hang recovery: bc1 (kernel70, 2026-10-28), 2 real hangs recovered in 26.5/26.4 ms; no-fault hangs at the stuck TLB sync still fail (gpu-bugs.md G1).
- 565 vs 430 MHz: 430 is not safer (sk430 had 1 hang in 1 h); 565 kept.

## Open
- Bug list and rates: [gpu-bugs.md](../gpu-bugs.md).
- The Reduce Transparency hang cause is unproven (did not reproduce on kernel52 + nbproto bridge).
- Silent resets during the 2026-10-25 soaks (565 MHz at 468 s, 430 MHz at ~179 s) were never explained; none since 0175/0176.

## Log
(Newest first, append-only. When this Log passes about 150 lines, move its oldest entries to the archive.)

### 2026-11-13 04:55 B53 phone test (gpu15b step 4): background tiles mostly draw; disk cache works
t167z. Safari/Thumbnails (container 2A0FE743...) holds 9 *.ktx (762 B - 198 KB), six written 04:48-04:52 during the
test. Tab switcher with 16 tabs: page A's tile drawn, a WebGL tab's tile drawn live; after backgrounding Safari 10 s,
killing MobileSafari only and relaunching: 4 of 6 visible tiles drawn, 2 compass placeholders (old tabs). oslog -n
MobileSafari history: no TabSnapshots lines (private or not logged at this level). So the disk path writes and reads
back (KTX/ASTC fine); the remaining placeholders are likely tabs never saved before earlier test kills (guess (a) of
04:50). Left: match the two placeholder tabs to files (the 762/1236-byte ones?).

### 2026-11-13 04:50 B53 background tab tiles: hibernated tabs come only from the disk cache (read-only analysis)
Observed (disassembly research/re/b53/tabctl*.s): -[BrowserRootViewController snapshotContentProviderForTab:] returns
nil for a hibernated tab (or !contentIsReadyForSnapshot) that is not blank, so TabController's snapshot request never
reaches WKWebView or the render server; such a tile can only come from the TabSnapshotCache file (_writeSnapshotImage:
withIdentifier:, KTX/ASTC via ImageIO when MG key ji56BO1mUeT7Qg9RO7Er9w is true, else PNG; read-back failures go to
Safari's os_log "TabSnapshots", not our live log). The compass tile means a nil image, not empty pixels, so 0135 can't
help. Boot 20261113-001648: Safari was a fresh process (WebKit started 10522.9 s) when tabs-fix.png was shot, so both
background tabs were restored hibernated; no SNAPSYNC line during the overview. Guess (medium): test kills (psx,
backboardd restarts) end Safari before its file queue writes those tabs (real iOS would show placeholders too); less
likely, the KTX/ASTC write or read-back fails here. Next: phone test with `oslog -l -n MobileSafari` (TabSnapshots):
two tabs, tab overview, Home, psx-kill Safari, relaunch, overview; list *-v*.ktx/png in Safari's container.

### 2026-11-13 03:35 Turnip 0113 (G2 fix) regression run t167w: clean
kernel167 everyday args + sweetgpukill=0, bundle with Turnip 0113 + frontend 0135 (4458 mV). uisoak 2 x 450 s: 91474
submits, G1 0, G2 0, G4 0, 0 restarts, 0 failed recoveries, max 78.7 C; 0 "submit bad", 0 DEVLOST, 0 crash lines,
0 SNAPSYNC. "refused" lines 2016 in 16.4 min (~123/min; no normalised baseline yet). One 15 min run can't show G2 is gone
(~1 per 400 k submits): the nightly soaks collect that.

### 2026-11-13 03:15 B53 snapshot race proven and fixed (frontend 0135)
See backlog B53: CA's render server only commits a snapshot into a client IOSurface and replies; our IOSurfaceLock
doesn't wait for GPU work, so the client read zeroed rows. Frontend 0135 (bundle 2e4a175): backboardd waits on the GPU
fence after the first render into a never-rendered client surface. Shadow-path shots 6/6 partly blank -> 12/12 good;
0 waits in normal UI. Stage 2 (later): GPU-pending count in SweetSurface trapLock for every CPU reader.
Also built: Turnip 0113 (G2: zero the tu_bo slot before its handle can be freed and reused), c916fe4.

### 2026-11-13 00:15 Bridge 0133 (U12-1b) A/B: dropped command buffers end in Error, no regressions (kdD1, kdD2 vs kdE1)
kernel167, bundle ceb6140 (Turnip 0112 + frontend 0132 + bridge 0133), everyday args + sweetgpukill=0 sweethangtest=3000,
uisoak 300 s each.
| boot | 0133 | recover2 | work lost / device kept | GPU restart line | DEVLOST | bbd PID | uisoak |
| kdD1 | on | 34572 us | backboardd / backboardd | redid 0 staging copies, 4 command buffers marked error | 0 | 61->61 | 27315 submits, G4 1, 0 restarts, 76.7 C |
| kdD2 | on | 37094 us | backboardd / backboardd | redid 0, 4 marked error | 0 | 61->61 | 27040, G4 1, 0 restarts, 79.0 C |
| kdE1 | SWEET_RESTART_REDO=0 | 34330 us | WebKit.GPU + backboardd / same | none (off) | 0 | 61->61 | 26982, G4 1, 0 restarts, 79.0 C |
"redo skipped" 0, MTLCommandBufferStatus/CA error lines 0, "refused" lines per boot 592/625/615 vs 601 on kdC1 (no
regression). Maps' map area black at every soak end with 0133 on and off (B50, not this bundle). Kept on by default
(SWEET_RESTART_REDO=0 off). Open: no staging copy was in flight in these hangs, so the redo itself is still untested.

### 2026-11-12 23:55 kernel167 (xnu 0285 lost span) first boot kdC1: hang recovered, backboardd kept
kernel167 (= 162 + xnu 0281-0285), bundle 3f069d6, everyday args + sweetgpukill=0 sweethangtest=3000, uisoak 300 s:
injecting at 104.3 s, recover2 done after 36566 us, 0285 "v2 backboardd: status work lost in a GPU reset (#1)"
(backboardd only), 0112 "device kept (1 in 60 s, total 1)", 0 DEVLOST, backboardd PID 61 -> 61, uisoak: 26380 submits,
G1 0 G2 0 G4 1, 0 restarts, max 77.0 C. Everyday boot t167z clean (4456 mV). Same per-process hits as kdA1/kdA2 (no other
process had work in the dropped range in this run). Note: 0285's log text still says "device lost for this client",
which is wrong with 0112 (the device is kept); cosmetic. Also built: xnu 0284 (logs the failing v2 submit check, G2).
Bridge 0133 (U12-1b) reviewed twice (changes made), built in bundle ceb6140; A/B kdD/kdE running.

### 2026-11-12 23:05 Turnip 0112 A/B passes: backboardd survives a recovered GPU hang (kdA1, kdA2 vs kdB1)
kernel165, bundle 3f069d6 (0112 + frontend 0132), everyday args + sweetgpukill=0 sweethangtest=3000, uisoak 300 s.
| boot | 0112 | recover2 | device kept line | DEVLOST | backboardd PID | restarts | screen after |
| kdA1 | on | 36712 us | yes (1 fault, total 1) | none | 61 -> 61 | 0 | Maps drawing |
| kdA2 | on | 37025 us | yes | none | 61 -> 61 | 0 | Calendar drawing |
| kdB1 | TU_DARWIN_KEEP_DEVICE=0 | 36341 us | no | DEVLOST first (turnip) | -> 424 | 1 | black + spinner |
All: GPU hang or fault fsr 40000002 far fff0000000 (injected), 0 G1/G2, 0 failed recoveries, max 80.9-83.8 C,
~25.5 k submits each. Frontend 0132: "native-metal: base limits: 38 of 39 fields of 264 bytes filled (maxTexture2D
16384x16384)" in SpringBoard and backboardd. Shipped: sweetgpukill=0 joins the everyday boot args (plan); the kernel's
compiled-in default (xnu 0244 + sunfish-boot.sh) stays 1 until U12-1b. Open: a dropped one-time upload stays wrong
(review, U12-1b); TU_DARWIN_KEEP_DEVICE=0 switches it off.

### 2026-11-12 21:40 U12-1 keep VkDevice after a recovered GPU restart: Turnip 0112 written, Fable review, fixes in progress
0112 (port of UniXNU c72a8a5): on a rise of the kernel's per-client faults count, keep the device (VK_SUCCESS + log)
instead of vk_device_set_lost; TU_DARWIN_KEEP_DEVICE=0 = old behaviour. Not built yet. Fable review (3 lenses + skeptic):
- Blocker for testing: sweetgpukill=1 is the compiled-in default (xnu 0244), so the kernel kills backboardd after every
  recovery whatever Turnip does: A/B tests need sweetgpukill=0 on the boot line.
- Major: no cap: a client that hangs the shared ring every frame would stall everyone forever (now: cap 3 per 60 s).
- Major: dropped work finishes as Completed with no error; one-time uploads stay stale (bridge staging.rs:200-208);
  nothing reads tu_darwin_restarts yet (follow-up, backlog U12-1b). Can look like B44/B53 garbling.
- Minor: fault_count race between threads (atomic xchg now); a failed recovery looked "kept" until the next submit
  (kernel 0282: GetStatus NotReady after a failed recovery); the counter counts status checks, not restarts; the
  warning went only to the backboardd Mesa log (now also /dev/console like 0108).
Plan: 0112 v2 + xnu 0282 -> bundle + kernel164; A/B kdA (patch on, 3 boots) vs TU_DARWIN_KEEP_DEVICE=0, all with
sweetgpukill=0 sweethangtest=3000; pass = recover2 done, no DEVLOST/backboardd kill, PID kept, UI draws after.

### 2026-11-02 22:39 n8: second full soak, first with 0 hangs of any kind (everyday setup)
- Soak n8, kernel158 everyday args + `sweetwdtcrumb=1`, bundle 82f6b41, mtl2-env with SWEET_CULL=3, slider at minimum
  (nits 33), 21:31-22:31: 3607 s, 398 526 submits, G1 0, G2 0, G4 0, backboardd restarts 0, max 82.8 C, caps 0,
  critical 0, failed recoveries 0. SWEET_CULL=3 did not raise G1. Two clean full soaks in a row (n7, n8).

### 2026-11-02 00:51 n7: first full clean soak: 397 k submits, 0 G1 with stock SMMU walks
- Soak n7, kernel152, base args + `sweetcxcycle=1 sweetwdtcrumb=1 sweetsmmutcr=3`, luma boost off, boot 20261101-235007, 23:50:57-00:51:05: 3608 s, 397 k submits, G1 0, G2 0, G4 1 (2564 s, fsr 40000002, recovered), 1 backboardd restart, no silent reset, no CX cycle.
- At the old rate (about 1 G1 per 100 k: n4 31 k, n6 76 k, n5 reset at 61 k) about 4 G1 were expected; P(0) about 2 %. One soak, so not proof, and two changes went in together (TCR and ACTLR), plus lower GPU load from luma boost off. Not split: `sweetsmmutcr=1`, `2` only if G1 comes back.
- Default now (xnu 0271, kernel153): `sweetsmmutcr=3`, `sweethwcg=1`, `sweetgpufreq=6`. `sweetsmmutcr=0` on the boot line turns it off. `sweetcxcycle` stays off: it failed the one real G1 (n6) and nothing else uses it.
- The silent reset (n1, n5) didn't happen in this hour; pet crumb had nothing to catch.

### 2026-11-01 23:50 tm: sweetsmmutcr=3 applied, no speed cost; soak n7 next
- `SWIPE_MS=3000 SETTLE=60 tools/sunfish-perfab.sh`, kernel152, 3 boots a side, settings,home, luma boost off, 5 nits, 0 hangs, 0 void. Settings swaps/s, p95 tcr 57.0, 19.5 / 56.4, 20.3 / 43.8, 34.0 (42 % busy, the known low run); off 56.4, 20.4 / 52.8, 32.9 / 55.1, 30.1. Home tcr 54.3, 54.4, 54.8 (32 ms); off 52.7, 53.0, 52.4 (33 ms). Max C about 84 on both.
- Applied: `smmu: tcr 802019 actlr 70000000 (sweetsmmutcr 3)` in boots 20261101-233634 and -233735. The GMU bank's line (802020) wasn't seen: before USB logging starts, not proven. Early GPU lines are in the live log on only some boots: USB starts about 22 s, bring-up 22-27 s. An earlier reading of `tcr 803519` was from an older boot (lb2b).
- G1 prevention untested: 6 boots say nothing. Soak n7: kernel152 sweethwcg=1 sweetcxcycle=1 sweetwdtcrumb=1 sweetsmmutcr=3, luma boost off.

### 2026-11-01 23:25 Correction: kernel150 and kernel151 lack their newest patch
- tools/vm-build-xnu.sh builds from xnu/patches, not work/src/xnu, and both were built before their patch was exported. By string count: kernel150 has no `sweetwdtcrumb`; kernel151 has it but no `sweetsmmutcr`. So sm3a's `sweetsmmutcr=3` tested nothing (0 `smmu: tcr` lines). lb0-lb3 on kernel150 stand: they need neither. Kernel152 has both. Export first, then build.

### 2026-11-01 23:01 CX refusal, read-only: no reference forces it down; stock SMMU attributes to test
- gdscr f8222001: bit 0 collapse request accepted, PWR_ON still 1, HW_CONTROL and SW_OVERRIDE 0; hw ctrl 88809fe0 on, 5ff4 off. Linux only logs `cx gdsc didn't collapse` (a6xx_gpu.c:1627) and carries on; no source here forces it. Guess: waits on a bus-idle handshake from GBIF or SMMU to the NoC (a6xx_gmu.c:564-567, Qactive, not gated for A618). Notes in research/notes/g1-sources.
- SMMU +0x6000 differs: all 4 G1 read 2270, the 3 non-G1 2378, 2378, 2370; bit 8 meaning unknown. Correction to the 17:45 entry: `+1554` going 0 isn't G1 only, G4 at 461.251 reads 0 with ack 3. HUPCF is out as a cause: G1 has fsr 0, far 0 (n6's far is stale from G4).
- New: our CB_TCR walks are IS, WBWA (0x803519); Linux on this non-coherent SMMU uses OS, NC, NC; stock also sets ACTLR 0x70000000, we don't. Guess about 20 % and about 10 % that they cause G1. Weak guess: a cached walk could also link to the whole-phone freezes (n1, n5).
- Next: xnu 0270 `sweetsmmutcr` (1 TCR, 2 ACTLR), 5 min Settings for TLB miss cost, then a soak: at 1 G1 per about 100 k submits, 47 min at 106 submits/s predicts 3. Later: `sweethangtest=0xA0000040 sweetcxcycle=2` as a test bed for collapse with a transaction outstanding, then Qactive and GPU_CC_CX_BCR +0x1068, reset risk only.

### 2026-11-01 22:50 n6: first real G1 under CX cycle: the CX GDSC won't collapse
- Soak n6, kernel149 base args + `sweetcxcycle=1` (boot 20261101-223608), 22:37-22:49, 76.5 k submits. G4 at 461 s, `recover2: done after 36911 us`, `exec backboardd` 86 ms later. G1 at 897.349 s: `fsr 0`, `gbif halt ack 1 TIMEOUT`, soft reset + CP init -1, GBIF halt path -1, then CX cycle: stage `cp stop + gbif halt + reset -> -1` (carries on), `gx off -> 0`, `gmu reset + rsc sleep -> 0`, `gdsc collapse, gdscr f8222000`, `gdsc won't collapse, TIMEOUT after 500005 us, gdscr f8222001 hw ctrl 88809fe0`, `cx cycle: done rc -1 after 641794 us`, `recover2: FAILED after 1350076 us`.
- On the injected hang (cx3b, `ack 3`) the same collapse took 16 us. So the stuck memory path also holds CX up, which fits G1 being stuck below the GPU. Recovery failed cleanly: no reset, 0 hangs after, CPU drawing.
- Next: what lets the GDSC go with a transaction outstanding (read-only: GCC/GPUCC block resets, what stock KGSL does).

### 2026-11-01 22:46 n5 reset, read-only: probably not the churn, and not instant; correction to the entry below
- Correction: "at the GPU pool limit" was wrong. Pool was 611 of 940 MB (448 + 492); the refusals come from the 256 MB per-client cap. First fit returns -1 when full; boot 20261031-210239 reached 936-937 MB and ran on.
- 633 boots: `texture refused: OutOfMemory` on 34 (first 20261029-093657), 33 lived on after it; 43/54 MB allocations 7,589 on 21 boots; n5's burst 142, longest 183 (n6, alive). Old pattern, n5 no outlier.
- Printing stopped on the whole phone, USB dropped later: n5 18.3 s, n1 19.8 s (n1 had no big Maps allocation for 111 s before it); controls n2 1.6 s, n4 3.9 s. cx2a about 20 s with printers alive. So guess: all CPUs or the memory path freeze, then a reset 18-20 s on. The shim arms a 30 s bite (shim.c:334), uw2 measured about 49 s (boot.md:67): the source of the reset isn't confirmed.
- One 54 MB cycle: `bzero` 54 MB fresh each time, as the reuse cache stops at 64 MB (:771), 13,824 PTEs in 14 flushes; locks are mutexes, TLB sync gives up at 10 ms. Maps writes about 0.4-1.3 GB/s this way (arithmetic). Rescue log has 485 bit flips in 244 KB, don't trust it byte for byte.
- xnu 0269, kernel150: `sweetwdtcrumb=1` logs `SWEET CRUMB: wdt pet t N cpu M` per 5 s pet and pushes it to DRAM (not run). The next soak uses it.
- Next: read that crumb after the next silent reset. For Maps speed, A/B: reuse cache 128 MB, `sweetgpucap=320` (no code).

### 2026-11-01 22:36 n5: silent reset at 695 s in Maps, no GPU hang
- Soak n5, kernel149 base args + `sweetcxcycle=1` (boot 20261101-222256), started 22:23:46; `ssh lost at 658 s`, phone in fastboot, 4455 mV, 61 k submits, G1 0, no CX cycle ran, 0 backboardd restarts. Last lines at 695.4-695.5 s: Maps holds 230 MB of GPU pool, `native-metal: texture refused: texture: OutOfMemory(Device)` x4, `command buffer refused`, `pool: 557 / 513 / 459 / 513 MB in use (peak 620)`, then nothing, no panic line.
- Not heat: cpu6 reached 88.3 C at 217 s and the phone ran on; last reading 81.9 C on cpu6, 73.5 C on the GPU sensor, caps 0.
- Rescue ../logs/n5-rescue.txt, no panic or watchdog text; it ends 90 ms later than the live log, at 695.575 s, with the same cycle every 12-14 ms: Maps holds 176 -> 230 MB, pool 557 -> 611 MB (peak 620), a 54 MB image allocated and freed each time.
- Guess: this alloc/free churn at the pool limit, or the map and unmap work it causes. n1's silent reset not compared yet. `SWEET_U0011..14` and kernel149 are not known to matter.

### 2026-11-01 22:30 cx3: CX-cycle recovery works on an injected hang; kernel149 (xnu 0268)
- cx3a: kernel149 base args + `sweetcxcycle=1` (boot 20261101-221835, 4456 mV): snapshot of sCR0 only at 27.362 s, CPUs at about 100 % as on a healthy boot, SpringBoard and backboardd up, no panic. First `sweetcxcycle` boot past the snapshot, so a read in the wider snapshot is the likely cause of cx1 and cx2a (which register not known).
- cx3b: `sweetcxcycle=2 sweethangtest=0xC0000040` (boot 20261101-222025, 4456 mV): stall injected 74.683 s, `GPU hang or fault` 76.702 s, `gbif halt ack 3`, all stages 0, `gdsc off after 16 us`, `smmu after cx on: 0 regs differ from boot` (sCR0 only), `smmu ok, tlbstatus 0`, `cx cycle: done rc 0 after 87456 us`, `recover2: done after 93087 us`. Warnings: `gcc gpu_memnoc_gfx still running, 220 TIMEOUT`, `gcc ddrss_gpu_axi still running, 0 TIMEOUT`.
- After it: backboardd 60 -> 312 and SpringBoard 26 -> 314, `exec backboardd` 130 ms after the reset; cause not looked up. Settings opened and scrolled, 0 missed submits, 649 MHz, 0 `device refused`: the GPU draws.
- Not shown yet: a real G1 (`ack 1`, stuck SMMU), which is the point: this hang had `ack 3`, the case recover2 already handled. Soak n5 runs `sweetcxcycle=1` to meet one. Steps 3-5 of cx1 folded into that.

### 2026-11-01 22:20 cx2a: silent reset at 45 s with sweetcxcycle=1, kernel147; CPU0 stuck both times
- kernel147, base args + `sweetcxcycle=1` (boot 20261101-220633, 4457 mV): `cx cycle: boot snapshot` and `... done` both at 25.353 s, `GPU ready in 287 ms`, then the log runs on until 45.166 s (THERM, USB, ARP from interrupts and timers), then fastboot: no panic line, rescue ../logs/cx2a-rescue.txt ends at the same line. 4456 mV after.
- Observed: `SWEET THERM: busy` 97 2 1 1 1 1 at 30 s, then 100 0 1 0 1 1 until the end: CPU0 alone at 100 %, the rest idle, and no userland line after launchd's map lines. Healthy boots (20261101-205241, -204358, -200324) have all 8 CPUs at about 100 % in this window. Same kernel with `sweetcxcycle=0` (rescue boot, 20261101-221204) boots normally.
- So cx1 (kernel145, spinlock owned by cpu 0, 2 s after the snapshot) and cx2a both look like CPU0 stuck right after the snapshot. Dropping the impl registers (0266) didn't fix it. Guess: a read in the snapshot (global space or banks) has a side effect, or the hypervisor doesn't like it; the walk itself ends, so what is stuck is whatever runs next on CPU0. Reset 20 s later: guess the hardware watchdog, since FLAME WDT's pet may not run; not checked.
- Next, smaller: the same boot with no snapshot, or only registers the default path already reads (xnu 0268). Step 2 of cx1 not run.

### 2026-11-01 20:50 cx1: first boot with sweetcxcycle panicked before any hang; xnu 0266
- kernel145 (xnu 0264) base args: fine, Settings scrolled, 5 boots in all. Base + `sweetcxcycle=2 sweethangtest=0xC0000040` (boot 20261101-200433, 4453 mV): panic at 22.79 s, before userland: `Spinlock[0xfffffe166e322cb0] timeout after 12585600 ticks; current owner ... (on cpu 0)` on cpu 6; `cpu 0 failed to halt`, `cpu 1 failed to halt`, cores 0 and 1 PC=0 and the rest in `0xfffffe00074c946c`. Phone back in fastboot, base args restored it. Rescue: ../logs/cx1s2-rescue.txt. No `cx cycle:` or `hangtest:` line: GPU ready at 20.41 s, injection comes about 49 s, so neither the cycle nor the hang had run. The first panic of this kind in all boot logs; the difference on this boot was the boot snapshot of 83 SMMU registers that only runs with `sweetcxcycle`, some of them impl registers never read before. Guess: a read left a CPU stuck on the bus; about 2 s after the snapshot, so not proven.
- Smaller step: xnu 0266, kernel147: snapshot without impl registers, a log line either side. Next: kernel147 with `sweetcxcycle=1` alone, boot only, then the injected hang. Steps 3-5 of cx1 not run.

### 2026-11-01 19:00 hm1: flush hammer: flushes aren't the trigger; the whole SMMU is stuck in G1
- kernel144 (xnu 0263), `sweettlbhammer=500`, base args, `tools/sunfish-uisoak.sh` 300 s, 2 boots, 54 k submits, 432 k flushes (627-758/s; the 2 k/s asked for wasn't reached). G1 1 (hm1a, boot 20261101-184200, uptime 327 s), hm1b none, 0 backboardd restarts. If flushes triggered it, 1 G1 per about 80 k flushes predicts about 5; got 1 (P about 3 %). 1 per 54 k submits fits the baseline of about 1 per 100 k. So the flush looks like the detector, not the cause. The first timeout was on the hammer thread itself. Not proof: 1 G1. Fix 4 in the notes (deferring flushes) is dropped for now.
- New probes on that G1: `smmu micro 2270 idle 0 sgfsr 0`, same at first timeout, hang and +1 s; `gpucc +1534 0 +1554 0`, gcc branches on; CP didn't move over 5 ms (`rptr 250 -> 250`, `ib1 rem e67 -> e67`). `gbif halt ack 1 TIMEOUT`. Sync probes, about 5 s later: GMU context bank `timeout after 100003 us, status 0 -> 1` and `tlbgsync timeout after 100011 us, status 0 -> 1`. So both the bank and the global sync are stuck, no fault latched. Guess: this is also why recover3's GMU boot fails, since the GMU goes through the same SMMU. Idle 0 isn't compared to a healthy read yet, and `smmu_bank` writes bit 3 itself, so it's weak on its own.
- After that run the webcam showed Fastboot Mode (`reboot bootloader`); boot log ends at 340 s without a panic or watchdog line and the next boot started 40 s later. Guess: the run's own reboot, not a reset; not checked.
- Next: CX-cycle recovery (`sweetcxcycle`), the one thing Linux does that we don't, in baby steps from a healthy injected hang.

### 2026-11-01 17:45 G1 is a stuck memory path, not a stuck lock; why recovery fails (read-only)
- Observed, all 578 boot logs: `gbif halt 3 ack 1` in 24 boots, `recover2 done` in 0 of them; `gbif halt 3 ack 3` in 8 boots, `recover2 done` in all 8 (counts rechecked by grep). In the ack-1 boots the TLB sync stays stuck (still 1 at +30 s). Our log hid this: `gbif_halt_bounded` (sweet_a6xx.c:~901) passes on either ack bit, so it printed "ack ok". `rbbm halt ack ok` is false too: 0x17 reads `deafbead` on A618.
- Timeline in boots 20261101-001940, -002702, -003311, -103432: first sync timeout on a backboardd thread with both GDSCs on, RBBM status already the same as at the hang 2 s later, recovery aborts on `TLB sync busy`, recover3's GMU boots then `gfx rail TIMEOUT, sptprac TIMEOUT`, `hfi: ctrl init TIMEOUT`. About 2.07 s in total. `gpucc +1554` goes 1 to 0 in all 24 and in none of the 8; meaning unknown.
- Not the lock: a timeout holds it 270 of 309 ms and 710 of 764 ms, then it's free for 1.2-1.9 s before the hang is declared, with rptr and IB unchanged. Not GX power: the stuck state survives a GX collapse.
- Gap against Linux: `a6xx_recover` ends with a CX GDSC power-off and resume, which resets the SMMU. We never cycle CX. This SMMU is `qcom,smmu-v2`, not MMU-500. Linux also sets HUPCF for Adreno and stock sets CB ACTLR 0x70000000; we do neither.
- Guess: one transaction out of GBIF is stuck in the TBU or NoC and both the sync and the halt wait on it. Whether flushes trigger it is still open. Next: xnu 0263: exact ack check, more probes at the hang, flush hammer `sweettlbhammer=N` as a fast reproducer; if it reproduces, CX-cycle recovery can be tried in baby steps. Notes: research/notes/g1-wedge-2026-11-01.md, reference sources in research/notes/g1-sources/.

### 2026-11-01 11:10 mf4: flushes on or off in the daytime state: 1 against 0 G1 in 144 k
- `tools/sunfish-perfab.sh mf4 8 --secs 15 --screens home,cc,settings`, kernel139 sweetrowa55=6, SWEET_DEADFILL=3, M2V_SHADOW_CACHE=1, nits 32, 16 boots, 144 k submits. G1 1 (flushes on, b4, boot 20261101-103432, uptime 172 s), G2 0, G4 0. Too few to say. Speed the same: Control Center 35.8 / 35.8; Settings 52.8 (49.6-55.5) / 53.4 (47.5-56.6). 2 Control Center runs read 0 swaps (fl1 b1, b4), not explained.
- Today's G1 uptimes: 84, 103, 156, 162, 172, 242 s: all early in a boot, but benches only run early, so that isn't shown to be a pattern. sweetmapflush stays default.

### 2026-11-01 03:45 mf3: 1248 MHz didn't reproduce G1: 0 in 81 k with flushes on or off
- `tools/sunfish-perfab.sh mf3 8 --secs 15 --screens home,apps`, kernel139 sweetrowa55=4, SWEET_DEADFILL=3, M2V_SHADOW_CACHE=1, 16 boots, 81 k submits, flushes on against off, G1 0, G2 0, G4 0, 1 void (too hot). So the control side, flushes on, had 0 in about 40 k where rows2 had 3 in 43 k.
- Reading: row 4 isn't a reliable reproducer; "reproducer" in rows2 and mf1 was premature. Either rows2's 3 were chance, or mode 2 matters (rows2 ran mode 2, this ran mode 3, which drops more fills: untested guess). mf1 says nothing about flushes. sweetmapflush stays default. No more boots on this for now.
- Speed: Home 44.5 / 41.9 swaps/s, apps 21.5 / 21.1, on / off: flushes off isn't faster.

### 2026-11-01 01:30 mf1, mf2: sweetmapflush=0: no G1 in 8 boots at the reproducer; not proof
- Reproducer: A55 at 1248 MHz gave 3 G1 in about 43 k submits (rows2; analysis below). In all 3: normal syncs, first TLB sync timeout in a map flush from a backboardd client thread (`sweet_gpu_map_at` -> `a6_tlb_flush`, sweet_a6xx.c:339, GPU running), `done` frozen, hang declared 2 s later, recovery FAILED about 1.6 s. Boots 20261101-001940, -002702, -003311. Order of GPU stop and sync timeout still not known.
- mf1: kernel139 sweetrowa55=4 sweetmapflush=0, home and apps, 8 boots, 35 k submits, 0 G1, 0 G2, 0 G4. Expected about 2.5 at the old rate: P of 0 about 8 %. Not proof. mf2: sweetrowa55=6, flushes on against off, 3 boots a side, 49 k submits, 0 G1; speed the same within noise (Home 31.6 / 31.7, Control Center 25.8 / 26.1, Settings 52.0 / 49.6).
- Guesses: flush timing against GPU traffic, or the GPU wedges first and the sync is a symptom, or lower L3 or bus speed. BoMap doesn't check the range is free, so skipping flushes has its own risk. Stays off. Longer row 4 run next when phones allow it: more submits per boot.

### 2026-10-31 16:45 Bug list and test schedule (the user's choice; no phone run)
- Added docs/gpu-bugs.md: G1-G8 with log lines and rates, plus a soak table seeded with soak1 and z1. Hangs wait unless they void benches, stop testing or double in rate after a change. Normal runs 15 min at most, one 1 h soak per day overnight. The ✅ state was wrong (0 of 8 no-fault hangs recovered): now 🟡.
- GPU clock governor waits until these hangs are under control.

### 2026-10-31 08:10 z1: kernel135 soak, stopped early by the user at ~34 min: 151 k submits, 0 no-fault hangs
- 20261031-073304.log, kernel135 sweetse9=2 sweetcampmic=2 sweetswapbig=6 sweetampreset=1, soak.sh. TLB sync histogram: lt10us 83667, lt100us 38314, lt1ms 241, lt10ms 7, timeout 0, max 2144 us, busy_before 0. Map 69243, unmap 52985 flushes.
- 1 hang at 886.947 s: fence 62562 done 62495, fsr 40000002 (SMMU fault type), recover2 done after 28009 us: recovered. No tlb first timeout. kernel134 had 2 no-fault hangs in 113 k. Guess: 0254's change from 1 ms sleep to 5 us spin in the sync wait could matter, or chance: too few to say.
- 3 times `submit failed: 0xe00002c2` (BadArgument), DEVLOST first turnip, backboardd exits and restarts (573, 1094, 1284 s); source unknown: under this soak about one per 6 min. It costs a UI restart and leaves the slower mode (2nd submit +6 ms) until reboot. Next item with the sync timing log.
- Boot used to show the phone off: kernel135 with those args, tag showoff.

### 2026-10-31 07:25 soak1: kernel134 everyday args: 2 real no-fault hangs in ~113 k submits; the TLB sync never clears
- App + long-swipe loop, boots 20261031-063606.log, 20261031-070415.log, research/notes/hang-soak1.txt. Hang 1 ~1423 s: fence 69595 done 69580, fsr 0, `tlb sync timeouts 174`. Hang 2 ~580 s: same, count 27. Every recovery: `tlb sync -> timeout after 100000 us, gbif released first, tlbstatus 1`; recover2, recover3, GBIF path failed; `recover failed +1s/+5s/+30s: tlbstatus 1`: the sync stays stuck. White screen in Safari; no GPU lines after. Owner lines not logged. DEVLOST at 1277 s in the first boot, 146 s before the hang.
- So 0253's order doesn't clear it and a later retry wouldn't either. Correction after reading research/notes/gpu-tlb-wedge.md: timeouts cost 10 ms each, so 174 = 1.74 s and 27 = 0.27 s fit inside hang detection's 2 s window: they needn't come before the GPU stopped; the order is unproven (estimate ~60 % GPU first). 1277 s wasn't a GPU loss: submit error 0xe00002c2 (BadArgument), source unknown. Rate ~1.8 per 100 k submits: at full speed about one per 15-20 min of hard scrolling; a daily-use problem. Analysis running: research/notes/gpu-tlb-wedge.md.

### 2026-10-31 06:20 kernel134: injected hangs still recover with the new order
- htA 20261031-055651.log (sweethangtest=0xA0000040, present submit 64, SMMU stall): injected 48.866 s, "tlb sync -> done after 0 us, gbif released first, tlbstatus 0", timeouts 0, recover2 done after 35042 us, fsr 40000002, GPU lines and swipes after. htB 20261031-055920.log (0x00000040, bad client IB): 51.947 s, sync done after 0 us, recover2 done after 35083 us, backboardd killed, GPU after. Base was ~27 ms; 8 ms slower is the new path.
- htC2 20261031-060809.log (0xC0000040, stall IB, fsr 0): injected 206.719 s, hang 208.754 s, recover2 done 208.780 s: recovered. Correction: the run's report called htC and htC2 "no GPU" boots; their logs have 43 and 34 SWEET GPU 5 s lines. Only r1 (035915) stands as the no-GPU boot. Also rc 2 from sunfish-test twice after these, phone in fastboot, rerun worked.
- Real busy-pipe no-fault hangs (TLB sync timeout) still haven't run on 0253: wait for one; read gpu.md 04:05 entry's lines.

### 2026-10-31 04:55 s1: kernel134: 35 min app soak, 0 hangs; injector regression not exercised
- s1: kernel134 sweetse9=2 sweetcampmic=2 sweetswapbig=6 (no trace flags), boot 20261031-041744.log: ~35 min with 8 apps (Preferences, Safari, Notes, Calendar, Clock, Photos, Maps, Compass) + 9 min Preferences only; 47 SWEET GPU 5 s lines, so ~4 min of GPU activity: a light load. 0 hangs, 0 recover lines, 0 resets. One open failure on Maps (FBS error Code=5).
- r1, r2: sweethangtest=0xA0000200: injector never fired: under 512 present submits in 6-10 min. So 0253's new order has not run on a real recovery. Lower the count or make the load heavier next time.
- r1 (20261031-035915.log): no GPU at all in that boot: SpringBoard never got the Turnip device, backboardd's Metal bridge closed at 89.8 s, 0 SWEET GPU lines, ~10 swaps/s by CPU copies, Settings sidebar torn on the webcam. No hang line. r2 with the same args had the GPU. Not explained: a boot-time failure seen once.

### 2026-10-31 04:05 xnu 0253 kernel134: GBIF released before the TLB sync poll, hang diagnostics (not run)
- Release GBIF then poll up to 100 ms (sweetgbiforder=0 for the old order); `tlb sync timeouts N` at each hang; `fence F pid P ib1 X` for the oldest unfinished; `fastfail diag: gmu cb.. fsr`; `recover failed +1s/+5s/+30s: tlbstatus S`. sweettlbwait=2 opt-in, last try starting the SQE (k81/k82 reset risk). sweethangdiag=0 turns the logs off. Each reset can now spin 100 ms under sweet_gpu_lock.

### 2026-10-31 04:00 Five no-fault hangs in one night; recovery fails at the TLB sync (research/notes/gpu-hangs-1031.md)
- Hangs, all fsr 0, in a pass (sqe stat 0, CP_BUSY, SP, UCHE, VPC, VBIF busy): 20261030-222005:45752 (k130), 20261030-230323:8172 (k131), 20261031-012907:56047 (k132, Maps), 20261031-023756 at 654.099 s (k132), 20261031-032917 at 766 s (k133). Correction: h1's (654.099 s) did NOT recover: logs show a new backboardd with `device refused: OutOfMemory(Device)` and CPU drawing after it. CPU fallback reaches 60 swaps/s on some screens, so its low fps isn't a fixed sign.
- Since Oct 29: SMMU-fault type recovered 2 of 2 in ~27 ms; no-fault type 0 of 8: `tlb sync -> timeout` x6, then `recovery aborted: TLB sync busy` x3 (the 0207 guard); recover3 fails at OOB 6, sptprac, HFI init. `gpu_ready=false` stays until reboot. Code: a6_smmu_gbif_reset polls the sync with GBIF still halted.
- Rate: k127-129 287 k submits, 0 no-fault hangs; k130-133 253 k submits, 5. p ~2 %, small numbers. Since k120: boots with sweettrace=1 sweetcpusample=1 had 5 in 232 k, others 1 in 524 k: confounded with bridge 0114 + LTO and heavier loads. Bind 0250, dead fill, 0251, 0252 aren't necessary for it (222005 predates them or lacks them). Everyday boot has neither flag.
- Next: recovery patch (GBIF order, diagnostics, sync-timeout counter), soak with the everyday args.

### 2026-10-30 18:15 backboardd lost its Vulkan device (kernel127, ~365 s, after Camera.app launches): the screen cycled old frames
- The user: "display is doing all kinds of whacky things". Webcam, 4 frames in 1 s: home screen flipping between old pictures (with/without dock, sharp/blurred). Kernel: swaps 60/s -> 10.0 fps at ~370 s; "SWEET FB: backboardd notifications type 5 off/on" every 50 ms from 365.57 s; GPU submits 51 per 5 s (0 missed, no fault line). Just before: SpringBoard "orient: R front now none" (364.05), touch at 362.8.
- /var/local/mtl2.log: "native-metal: commandBuffer refused: command buffer: DeviceLost" + "texture refused: texture: DeviceLost", 129506 lines kept after "log truncated at 37582208 bytes": the first cause scrolled away. backboardd state R, 2:04 CPU. Saved: work/mtl2-devlost.log. Also seen: "planar iosurface refused: b3a8 fmt 550 plane 0".
- kill -9 backboardd (pid 60 -> 403) recovered the UI in < 25 s, no reboot.
- The earlier full UI hang (sleep-wake.md 20:30, kernel126) started with the same "notifications type 5 off". Related? Not known: that one ended in U state.
- Cause not found. Bridge change in progress: first-cause line, flood stop, backboardd exits so launchd restarts it.

### 2026-10-28 15:44-16:44 k83s: 1 h app soak, 0 GPU hangs (kernel83 + sweetpresentwait=1)
- 204 app opens, no STOP, 0 hangs / crumbs / tlb-sync lines, 0 resets; pool 199 -> peak 341 -> 287 MB (flat); PhotosFileProvider x1. The 0207 TLB gate was not exercised. Note: the hang-heavy runs today (sk70, sk71, k77s, k81, k82) all ran with sweetpresentwait=0; this one with =1. Possibly the put-off present path (0158) is part of the busy-hang trigger: watch the hang rate with presentwait=1 (now the default).

### 2026-10-28 15:30 k82: the breadcrumbs pin the silent reset: SQE start during recovery
- kernel82 (0206), app soak k82s, 10 opens, then the phone reset at ~285 s (no fastboot for a moment: the soak said "no fastboot either", then fastboot came). Rescue (logs/k82-rescue.txt, total 445822, n 258048): `present: GPU hang or fault (fence 4158 done 4133)` (rbbm status1 13010301 status2 100 status3 f00001) -> crumbs `present: hang detected, recovery start`, `recover2 enter`, gx off/on, `smmu/gbif reset: sctlr e7 fsr 400 tlbstatus 1`, `cp_init enter (resume 0)`, `cp_init: init table done`, `cp_init: sqe written`, then nothing. The missing next crumb `cp_init: sqe_cntl=1` follows the CP_SQE_INSTR_BASE / CP_RB_BASE / CP_RB_CNTL writes and CP_SQE_CNTL=1.
- Every recovery logs `tlbstatus 1` (CB TLB sync still active). Strong suspect: starting the SQE (it fetches microcode through the SMMU) while the TLB sync is pending wedges the bus -> SoC reset. xnu 0207 (sweettlbwait): poll TLBSTATUS until clear, and never start the SQE with a sync pending (fail the recovery instead).

### 2026-10-28 15:10 the recover2 window looks safe; suspect lost log lines + zap_load
- Every access between `smmu/gbif reset` and `pre-me_init` (sweet_a6xx.c ~1489-1786: SMMU CB reads, GBIF_HALT writes, ~45 GX init-table writes, perfctr, SQE write to DRAM, CP_SQE/RB base, SQE_CNTL=1, the pre-me_init reads) also ran in 12 surviving recoveries from the identical state; there are no SMC calls in it. "rbbm halt ack deafbead" = RBBM_GBIF_HALT_ACK (0x17), harmless and unimplemented on A618. So the RAM log probably lost its last lines and the reset came later: zap_load (TZ PAS on an already-loaded image; Linux loads zap once per boot and then resumes) ~55%, SQE_CNTL=1 with TLB sync busy ~25%. Next: xnu 0206 with flushed breadcrumbs (a cache-clean after each crumb, in case the console ring is cacheable).

### 2026-10-28 15:00 k81 rescue: the silent reset happened inside recover2
- RAM-log rescue after the k81 reset (logs/k81-rescue.txt): GPU hang at 421.912 s (fence 12181 done 12162), recover2 ran gx off -> `gx on: rail+sptprac ok, dcvs acked ret 0, oob gpu_set acked` -> `stage gx on -> 0, rbbm status 1` -> `SWEET FB: GPU present re-armed` -> `recover2: smmu/gbif reset: sctlr e7 fsr 400 tlbstatus 1` at 421.949 s, then nothing. In recoveries that survive, the next line is `recover2: pre-me_init: ...`. So the SoC reset is triggered by the code between those two prints. Earlier silent resets (sk70, k77s) showed no hang line in their rescued logs: a different trigger, or the hang line was not reached.

### 2026-10-28 14:56 k81: silent reset right after a bench; the bootloader state shows nothing
- kernel81 (0205), during the dim A/B benches: the phone fell into fastboot right after bench d10b ended (14:55:50); the babysitter flagged it at 14:56:03. `fastboot getvar all` taken at once (logs/getvar-reset-k81.txt) is identical to the clean-reboot baseline (logs/getvar-clean.txt), so ABL keeps no reset reason either. RAM-log rescue on the next boot (k81r).

### 2026-10-28 14:50 lead: the vsync tick stops ~83 ms after display off
- From the k79 panel test: in 6/10 cycles the framebuffer fade stopped at step 5, i.e. the vsync tick ran ~5 times after `display off` and then not at all for 3 s. Nothing in SweetFramebuffer.cpp stops it (vsyncFired re-arms itself first, line 372; sel 72 only clears the notify entry; the fade has no gate), so the workloop thread is probably blocked by something else at display off (GPU/present path?). The unrecoverable GPU hangs cluster 0.1-6 s after display on/off. Worth checking whether the same thing blocks the GPU side; a stack sample of the workloop thread right after display off would show it.

### 2026-10-28 14:15 k78: recover3 (cold GMU restart) also fails; display power changes as a trigger
- kernel78, boot k78, during the panel-sleep test: hang at 490.88 s, 1.0 s after `display off` (fence 3155 done 3143, rbbm c30d15, cp_status1 8113471f: the busy type). recover2 failed (me_init rptr 0, cp_status1 81104006), the GBIF-halt path failed, then recover3 FAILED after 8412393 us; recover2 total 12813545 us. Diag before gx off: cp hw_fault 0 int 0 protect 0, gbif halt 3 ack 1, gmu cx busy 71000000, cx gdsc f8222000. gpucc diff: 8 regs differ from boot (+0000 d1000005 -> d1800005, CBCRs +105c..+1094 80000000 -> 0, +1554 1 -> 0).
- `gbif halt 0 ack 1` before me_init is the same in recovered hangs (17x), so not the difference.
- Timing over all logged hangs: many failures came 0.1-6 s after a display on/off (mostly the earlier sleep tests); recovered ones mostly came > 40 s after; bl1/sk71 failed 160 s after. Display power changes look like one trigger of the unrecoverable type, not the only one.
- The panel-sleep hook ran only on some cycles (PANEL lines after 3 of the off/on pairs up to 490 s): details from the phone run.

### 2026-10-28 14:02-14:07 k77s: silent reset at ~283.6 s (kernel77)
- kernel77 (0200) + sweetwifiev=1, 4455 mV; app soak cycle 2 (10 opens), then fastboot. No GPU hang, panic, UIWDT or reset text; the last lines are routine (SWEET GPU 5s at 278.5 s: 33 submits, 6% busy; FB 5s at 281.0 s: 45 swaps). Pool 160 -> 451 peak -> 258 MB. PhotosFileProvider x1. The third silent reset (sk70 337.8 s, k77s 283.6 s; sk71 had none in 2 h). Next boot kernel78 reads the PON reason (0201 repeat) + the RAM-log rescue.

### 2026-10-28 14:50 correction: the failing hangs are not SMMU stalls
- One SMMU (kgsl-iommu 0x05040000), GPU bank cb1 (SMR2 SID 0, SCTLR e7 = stall-on-fault on, `sweetsmmustall`). `smmu fsr 0` (masked with 0xc00001fe) and `cb fsr raw 400` are the same CB_FSR: 0x400 = FSR.FORMAT [10:9] = AArch64, read-only (survives the write-1 clear; every hang, recovered or not, shows it). Real stalled faults read 40000402 (SS + TF) and recover through xnu 0181/0182 (8 injected). The "(bit24 smmu stalled)" text is a fixed string (sweet_gpu.c:696); 0xce00000 has bit 24 clear.
- What separates them: recovered (26x, ~26 ms) = rbbm 800005, status3 20000, ib2 rem 0 (CP idle); failed (6x, ~3.9 s) = rbbm c30d15/c30d35, status3 ce00000, ib2 rem 1236 (busy mid-IB2); after GX off/on the registers look clean but me_init gets rptr 0 three times. Suspect (~50%): state outside GX (GBIF/GMU side) survives our GX power cycle.

### 2026-10-28 11:49-13:51 sk71: 2 h soak, no reset, but an unrecoverable SMMU-stalled GPU hang at 256.8 s
- kernel70, bundle 7053013, booted as sk70r (no census). 122 min, 414 app steps (sk71a 60 + sk71b 62 min), no open failures, 0 panics / UIWDT / reboots; PhotosFileProvider 1 crash (254.97 s).
- 256.8 s: fence 2361 done 2345, smmu fsr 0; rbbm status3 bit24 (SMMU stalled), cb fsr raw 400 -> recover2 failed, GBIF-halt path: soft reset + CP init -> -1 twice, "GPU not recovered", backboardd killed once, "recover2: FAILED after 3994512 us". No SWEET GPU lines after 261 s.
- Yet the UI kept working for 2 h (webcam frames 11:49-1:51 show changing apps; SWEET FB 5s lines to 7475 s, ~30 swaps/5 s): presumably CPU compositing after the GPU died (not checked).
- The same signature as bl1 (kernel70, 227 s, also unrecovered). The recovered real hangs (bc1, bl2, ab-off) had no SMMU stall. Pool data stops at 261 s (160 / peak 416 / 24 MB): the "pool flat" check could not be made.
- Verdict for plan priority 1: reboots PASS, unrecovered hangs FAIL, pool flat not measurable.

### 2026-10-28 12:00 silent resets: analysis (read-only)
- Nothing records a reset reason: the shim writes 0x77665500 to IMEM 0x146aa65c at every boot (shim/shim.c:27, :80), so every reset lands in fastboot and the IMEM word says nothing.
- Ruled out for sk70: the kernel's own reboot paths (flamereboot, boot watchdog 0189, UI watchdog rung 2) all log a FLAME WDT / SWEET BOOTWDT line first, and none is in sk70-rescue.txt. The UFS rst3 reset was a real panic, fixed in 0175.
- What fits: a hang that stops every printer, including the 5 s APSS watchdog pet thread (SweetPlatformExpert.cpp:49-104; the shim arms a 20-30 s bite), or an instant TZ/XPU/NoC or PMIC reset. Ranked: GPU/SMMU bus stall ~45% (kernel70 had 3 real GPU hangs in ~45 min, one with the SMMU stalled and not recovered; sk68 on kernel68 had 0 in 2 h); XPU/TZ from Wi-Fi ~20% (exec wifip2pd 45 ms before the end); non-GPU hard hang ~15%; PMIC UVLO ~10%.
- Next: log the PMIC PON/POFF/fault reason registers (SID 0 periph 0x08) at boot (read-only SPMI), so the boot after the next reset says what it was; then a kernel68-vs-kernel70 soak with the same bundle.

### 2026-10-28 11:40-11:55 sk70: silent reset to fastboot at 337.8 s (2 h soak aborted)
- kernel70 `sweetbocensus=600`, bundle 7053013 (bridge 0105), 4455 mV. Fresh-boot bench sk70p: 22.7 / 22.1 swaps/s, 16.1 / 15.6 panel updates/s (below the 21-24 of earlier kernels/bundles; not yet explained).
- App soak cycle 2: the phone fell into fastboot at uptime ~337.8 s. RAM-log rescue (sk70r boot; header total 495807, n 258048, logs/sk70-rescue.txt) ends mid-swipe at `[ 337.776] SWEET CMD: swipe 540,1800 -> 540,1000 in 30 steps`: no panic, watchdog, GPU hang, SError, jetsam or thermal line. GPU pool 160 MB (backboardd), GPU busy 13%. Same pattern as the unexplained 10-25 soak resets (468 s, ~179 s; storage suspect: the UFS I/O error path), the first since 0175/0176. sk68 (2 h, kernel68) had none.
- Retrying the 2 h soak on the sk70r boot.

### 2026-10-28 08:30 bl2: real GPU hang recovered
- kernel70, uptime 615.9 s: fence 11512 done 11420, smmu fsr 0; recovered in 26326 us; backboardd pid 58 killed, pid 740 came up and the soak went on. (bl1's failed recovery had the SMMU stalled; this one did not.)

### 2026-10-28 07:49 bl1: real GPU hang, recovery failed (new signature)
- kernel70 + turnip 0106, 2nd app-soak cycle, uptime 227.4 s: fence 2892 done 2858, smmu fsr 0 far 0; rbbm status c30d35, status3 ce00000 (bit24 smmu stalled), cb fsr raw 400, cp_status1 8113471e. recover2 went through cp stop / gbif halt / sw reset / gx off / gx on, then "GPU not recovered" at 231.4 s; the kernel killed backboardd anyway. Swaps came back (99 in the 5 s to 246 s), then the screen idled. Unlike bc1's hangs (rbbm 800005, no SMMU stall), this one has the SMMU stalled. 3 real hangs in ~45 min of kernel70 soaks vs 0 in sk52b-sk68: kernel70 (0196) or turnip 0106 still a suspect.

### 2026-10-28 02:05-03:15 overnight run, part 3: the GPU pool leak
- See [gpu-memory](gpu-memory.md): bc1 had 2 real GPU hangs (rbbm 800005, ring pending, no SMMU fault), both recovered on the first path in 26.5/26.4 ms. Real-hang recovery is now proven.

### 2026-10-28 02:05-03:15 overnight run, part 3: the GPU pool leak
- See [gpu-memory](gpu-memory.md) for this entry; it also touches this feature.

### 2026-10-27 ~07:55-09:00 kernel58 (xnu 0182: SMMU stall-on-fault by default)
- 0182: GPU context bank SCTLR gets CFCFG (0x80) at setup and again after the recovery's SMMU/GBIF reset; a6_clear_fault terminates a stalled fault (CB_RESUME) before clearing FSR. Off with `sweetsmmustall=0`. CI run 40499063303 -> work/kernel58.
- es1 (565 MHz, `sweethangtest=0xA0000200`): injected at 130.3 s; "early smmu resume: fsr 40000402"; full path, cp init + zap -> 0; **recover2 done after 26440 us**; reset leaves sctlr e7 (stall bit on). backboardd respawned at 132.4 s, lock screen on webcam, then **21.5 swaps / 20.5 panel updates per s at +60-120 s with swipes**: the 6-8/s after er4-er7 was the idle lock screen, not a slow GPU. (Boot-time smmu sctlr line not captured: the live log came up 14 s late.)
- sk58 (430 MHz, appsoak 3600 s): 204/204 opens, 0 resets, 0 GPU hangs, 0 SMMU fault lines, 0 "clearing smmu", 0 UIWDT. Pool 97 -> 342 MB, peak 436. Battery 4436 -> 4432 mV. Mean 2.4 swaps/s over the hour (lower than sk57's 9.0; not checked whether that is the averaging window or real).
- Noise: 108x CRASH assetsd, 36x CRASH TipsSpotlightInd, 256x EXC_CORPSE_NOTIFY, 154x CATransformLayer allowsGroupOpacity.
- Phone left on final58 (kernel58, default args incl. watchdog), home screen, 4456 mV.

### 2026-10-27 06:29-07:31 sk57: 1 h app soak, kernel57 at 430 MHz (sweetgpufreq=4)
- 61.6 min, 35 cycles x 6 apps: 210/210 opens, 0 resets, **0 GPU hangs** (sk430 on kernel52 had 1 in the same mix). So the real-hang test of 0181 is still open.
- Pool 161 MB at 89 s -> 345 MB at end, peak 444. Battery 4455 -> 4428 mV. Mean 9.0 swaps/s over the run (includes lock/idle time).
- Noise: 411x "Failed to send exception EXC_CORPSE_NOTIFY ... pid 1148" (from 821 s), 273x apple80211 CURRENT_NETWORK error 6.
- Phone left on kernel57 at 565 MHz (sweetpresentwait=1 flamereboot=0), home screen.

### 2026-10-27 kernel57 (xnu 0181) er4-er7: early CB_RESUME recovery repeats
- Same args as er3 (`sweethangtest=0xA0000200`). Injected at 110.2 / 152.6 / 139.9 / 153.5 s; SMMU fault ~2.0-2.15 s after each injection; fsr 40000402 every time.
- er4 / er5 / er6: first me_init idle (rptr 9 wptr 9), first path, **26.06 / 26.10 / 26.24 ms**. er7: backboardd respawned at 155.6 s and screen was back on the webcam, but the me_init / "recover2: done" lines are missing from the live log (lost lines), so its path is unproven.
- Together with er3: 5/5 recoveries, 4 of them timed at ~26 ms.
- Open: swaps 25-30 s after recovery were 6.1 / 6.7 / 8.2 / 6.1 per s against ~19 before (rec10 on kernel50 was back to 19 at full speed). Could be the lock screen after the respawn rather than a slow GPU; check in the next soak (+2-3 min window).
- er7 boot also logged "SWEET USB: busERR addr 0; SMMU cb fsr 400" every ~5.6 s from 43 to 105 s (not seen on er4-er6).
- Phone left on kernel57, no injection, 100% brightness, 4456 mV. Next: sk57, 1 h app soak at 430 MHz (running).

### 2026-10-27 experiments.md lines
- 2026-10-27 er4-er7: kernel57 SMMU-stall injector (0xA0000200), 4/4 injected; er4-er6 recovered on the first path in 26.06/26.10/26.24 ms (fsr 40000402), er7 respawned + screen back but recovery lines lost from the log. With er3: 5/5 recovered. Swaps after recovery 6-8/s (pre-hang ~19).
- 2026-10-27 sk57: kernel57 at 430 MHz, 1 h app soak (61.6 min, 210/210 opens): 0 hangs, 0 resets, pool 161 -> 345 MB (peak 444); no real hang to test 0181 against.
- 2026-10-27 es1: kernel58 (0182 SMMU stall-on-fault by default) injected SMMU-stall hang: early resume fsr 40000402, recovered first path in 26.4 ms, sctlr e7 after reset (stall bit kept), 21.5 swaps/s at +60-120 s with swipes (so er4-er7's 6-8/s was the idle lock screen).
- 2026-10-27 sk58: kernel58 at 430 MHz, 1 h app soak: 204/204 opens, 0 resets, 0 hangs, 0 SMMU faults, 0 UIWDT; pool 97 -> 342 MB (peak 436). Stall mode causes no extra hangs; still no real hang met.

### 2026-10-26 ~23:15 kernel57 (xnu 0181) er3: early CB_RESUME fixes the stall-on-fault recovery
- `sweethangtest=0xA0000200` (present submit 512): injected at 83.7 s, fault at 85.8 s.
- "recover2: early smmu resume: fsr 40000402"; after GBIF halt rbbm status3 4f20101; first me_init idle (rptr 9 wptr 9 status 1, cp_status1 1000000), zap rc 0; **recover2 done after 26308 us** (kernel56 with the late resume: 2.6 s on the 3rd path; reset off: FAILED). backboardd killed and respawned; 'SWEET GPU: 5s' continues; lock screen at 5.6-7.8 swaps/s after (pre-hang home ~19).
- One run only (er1/er2 at index 1536 never injected). Phone left on night5 (kernel53, 5%), 4435 mV.
- Open: does the real hang (sk430, terminate mode, fsr 0) also clear with 0181? Next real-hang soak on kernel57 at 430 MHz will tell; consider enabling CFCFG (stall mode) in normal operation so real faults look like this injector.

### 2026-10-26 ~22:50-23:06 kernel57 (xnu 0181: CB_RESUME at the start of recovery) — inconclusive
- er1, er2 (`sweethangtest=0xA0000600`, boot-args tail confirmed): no "hangtest: injecting" line in 4 min of swipes each, so recovery was never exercised. 0181 only touches sweet_a6xx.c recovery code, not the arm path, so the cause is likely the run (present submit 1536 not reached: swaps dropped to 0.2/s around 426 s; possibly not unlocked), not the kernel. Not verified.
- Next: rerun er with a lower present index (e.g. 0xA0000200) and confirm the home screen first.
- Phone left on night4 (kernel53, 5%), 4435 mV.

### 2026-10-26 ~22:35-22:43 kernel56 (xnu 0180) SMMU stall-on-fault injector
- `sweethangtest=0xA0000600`: present blit from unmapped VA with CB SCTLR CFCFG (stall on fault). Hang: smmu fsr 40000002, rbbm status1 10301 status2 10100 status3 1f00101 (bit 24 SMMU stalled), cb fsr raw 40000402.
- **ss2, reset off (sweetsmmureset=0): reproduces the real-hang failure exactly**: me_init `rptr 0 wptr 9 status c00015 cp_status1 81104006 TIMEOUT` on every path, "GBIF halt + soft reset + CP init -> -1", recovery FAILED, UI on CPU copies (same as sk430).
- **ss1, reset on: recovers, but slowly**: "smmu stalled fault terminated (CB_RESUME)" seen; first me_init still TIMEOUT (c20015), GBIF-halt path TIMEOUT (c20001), then soft reset + CP init idle -> "recover2: done after 2618248 us". GPU 5 s lines continue.
- Reading: a stalled SMMU transaction is enough to make CP init fail; terminating it (CB_RESUME) is what lets the CP come back. The resume comes too late in the full path (after GBIF halt + GX cycle), so the first attempts still fail. The real sk430 hang printed fsr 0 in terminate mode, so whether it was an SMMU stall is not proven, but the failure signature is identical.
- Phone on night3 (kernel53, 5%), 4455 mV.

### 2026-10-26 ~22:00 Control: kernel54 (xnu 0178) sweetsmmureset=0, stall hangs, 565 MHz
- ctl1/ctl2 present stall (0xC0000600), ctl3 client stall (0x40000BB8): 3/3 injected, "smmu/gbif reset: skipped", me_init idle (status 1, cp_status1 1000000), recover2 done 25.96-26.41 ms. 'SWEET GPU: 5s' lines continue.
- So the stall injector recovers WITH and WITHOUT the SMMU/GBIF reset: it does not reproduce the real-hang failure, and 0177's reset is neither proven nor disproven. Kept on by default (harmless: +0 ms).
- Difference to the real hang (sk430): the real one had ring work pending (rptr 570, wptr 949), ib1 rem 7e and rbbm cf9495 (many blocks busy). The stall leaves the ring drained and rbbm 800005/c00005.
- Also built: kernel55 = xnu 0179 UI watchdog (`sweetuiwdt=30`: touch within 10 s + no swap for 30 s -> kill backboardd; still frozen 30 s later -> stop APSS pets -> fastboot; backboardd also killed once after a failed GPU recovery). CI ok (run 40435125065), not booted yet.
- Brightness: at 3/5/8/12% the webcam sees nothing; icons show from 16%. Phone left on a night boot (kernel53, no injection) at 5%; 4456 mV.

### 2026-10-26 ~21:00-21:50 kernel53 (xnu 0177) stall-hang recovery, 565 MHz
- 0177: `sweethangtest` bit 30 = stall IB (CP_WAIT_REG_MEM on a never-written scratch dword, no SMMU fault); SMMU CB reset (SCTLR.M off, FSR clear, TLBIALL+SYNC, restore) + GBIF halt release before every recovery gpu_cp_init; `recover2: pre-me_init:` diagnostics. Hex boot-args parse fine.
- 5 boots (st1-st5; 3 present 0xC0000600, 2 client 0x40000BB8): 5/5 injected, 5/5 "recover2: done" in 26.0-26.4 ms, me_init idle, display back ~6.7 s after the hang; home screen on webcam after unlock; 16.6-17.8 swaps/s and 12.5-12.7 ms/submit on the home screen after (st4, st5).
- Hang state: fsr 0 (no fault, as intended) but rptr == wptr, ib rem 0, rbbm 800005 (one c00014): NOT the real-hang state (sk430: rptr 570 wptr 949, ib1 rem 7e, rbbm cf9495). Pre-reset CB state every time: sctlr 67, fsr 400, tlbstatus 0, GBIF halt 0 ack 1.
- Open: whether the reset is what helps. Control (sweetsmmureset=0, xnu 0178 / kernel54) next.

### 2026-10-26 Why recovery fails after a real hang (investigator, logs + code only)
- Real (sk430 2296 s) vs injected (kernel50, uptime ~190): identical through sw reset, GX off/on, pll0 restore (both locked). Differences: real hang had no SMMU fault (fsr 0), pending ring work (rptr 570 wptr 949, ib1 rem 7e), rbbm cf9495, cp_status1 8113xxxx, two extra gpucc diffs (+1534 0->1, +1554 1->0); injected = SMMU fault fsr 2, ring empty, rbbm 800005, gets "clearing smmu cb1 fault" + TLB flush.
- After GX on both show rbbm 1 / cp_status1 1000000 (idle); real me_init then times out with rptr 0 (CP never fetched the ring): status c00015, cp_status1 81104006. Same signature as pre-0167 soft-reset failures, so the stuck state survives a GX power cycle.
- Leading theory (~40%): stuck state in the CX domain (GPU SMMU context bank / TBU / GBIF) after an in-flight mid-IB hang; the injected path only recovers because the fault handler clears the SMMU. Our "full" recovery is a GX-only cycle with the GMU running; Linux does a full GMU/CX collapse + re-boot.
- Fix candidates: (a) always reset SMMU CB1 (SCTLR.M off, clear FSR, TLBIALL+SYNC, on) and GBIF before gpu_cp_init; (b) escalate to CX collapse + a6_power_up if me_init still fails; (c) log CB1 SCTLR/FSR/TLBSTATUS, GBIF halt/outstanding, CP_RB_BASE/SQE base, gpucc +1534/+1554 before me_init.
- The bad-IB injector (SMMU fault) cannot reproduce this. Need a hang inside valid memory: CP_WAIT_REG_MEM on a never-written dword, or an endless shader.

### 2026-10-26 sk430: 1 h app soak at 430 MHz (kernel52, sweetgpufreq=4), step 2b
- 19:53:05 to 20:54:48, 35 cycles, 210 opens, 0 openfail, 0 resets, 0 panics. Core 429-430 MHz.
- **1 real GPU hang, NOT recovered** at uptime 2296.098 (present: fence 46266, done 46247, smmu fsr 0; rb rptr 570 wptr 949, ib1 rem 7e, rbbm cf9495).
  - recover2 ran every stage OK (cp stop, GBIF halt, sw reset, gx off/on, DCVS, pll0 restore "locked"), then `ring me_init ... status c00015 cp_status1 81104006 TIMEOUT`; GBIF-halt fallback timed out the same way; FAILED after 3.94 s.
  - The UI kept going without the GPU: "GPU present not used: GPU blit failed", swaps resumed at 2303 s with CPU panel copies (~2.4 ms), 22-27 swaps/s, no more `SWEET GPU: 5s` lines. The soak finished all opens on that path.
- Pool: 198 MB at 121 s, 317 / 325 / 312 at 10-min marks, peak 399, 348 at the hang.
- Battery 4078 -> 4390 mV, +870 mA (charging).
- **565 vs 430:** sk52b (565) 0 hangs in 1 h; sk430 1 unrecovered hang in 1 h. 430 is not safer -> keep 565 MHz (sweetgpufreq=5) as default. Pre-hang swap rates are not comparable (app-open mix).
- New open item: recovery after a real (not injected) hang fails at CP me_init; injected hangs (rec10) recovered. Next: compare the CP/GMU state on that path with the injected one.

### 2026-10-26 ~19:20-19:35 nbproto bridge + Reduce Transparency repro (kernel52, sk52b boot)
- See [metal](metal.md) for this entry; it also touches this feature.

### 2026-10-26 sk52b: 1 h app soak on kernel52 (clean)
- Boot: kernel52, `sweetpresentwait=1 flamereboot=0` + defaults (recover=2, kill=1), 3978 mV at start.
- `sunfish-appsoak.sh sk52b 3600`: 18:18:17 to 19:19:55, 35 cycles x 6 apps = 210 opens, 0 openfail.
- 0 GPU hang/fault, 0 recoveries, 0 panics, 0 resets. First full hour without a reset since 0175/0176.
- GPU pool: 198 MB at start, 319 after 10 min, then flat at 373-424 MB (saw-tooth), 410 at end.
- Average 11.0 swaps/s over 601 stats lines (app-open mix, not a swipe bench).
- Battery on TB4: +965 mA charging early on (chg=1).

### 2026-10-26 experiments.md lines
- 2026-10-26 sk52b: kernel52 1 h appsoak, 210 opens, 0 resets/hangs/panics; pool 198 -> flat ~380-420 MB; 11.0 swaps/s avg.
- 2026-10-26 sk430: kernel52 430 MHz 1 h appsoak: 0 resets, 1 real GPU hang at 2296 s, recovery FAILED (me_init TIMEOUT), UI continued on CPU copies; 565 kept as default.
- 2026-10-26 recovery-fail analysis: real hang = no SMMU fault, ring pending; me_init rptr 0 after clean GX cycle; suspect CX-side SMMU/GBIF state; injector can't reproduce (needs wait-forever IB).
- 2026-10-26 st53: kernel53 stall injector + SMMU/GBIF reset, 565 MHz: 5/5 stall hangs recovered in 26 ms; stall state milder than the real hang (ring drained, rbbm 800005).
- 2026-10-26 ctl54: sweetsmmureset=0 control, 3/3 stall hangs still recover in 26 ms -> stall injector too mild; SMMU/GBIF reset unproven. kernel55 (0179 UI watchdog) built, untested.
- 2026-10-26 ss1/ss2: kernel56 SMMU stall injector reproduces the real me_init c00015 failure with reset off; with CB_RESUME reset, recovery succeeds on the 3rd path after 2.6 s.
- 2026-10-26 er1/er2: kernel57 early SMMU resume: injection never fired in 4 min (present 1536 not reached?), untested.
- 2026-10-26 er3: kernel57 (0181 early CB_RESUME) SMMU-stall hang recovered on the first try in 26.3 ms (kernel56: 2.6 s; reset off: FAILED). 1 run.

Older entries (before 2026-10-26): [archive/features/gpu.md](../archive/features/gpu.md).
