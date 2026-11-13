# xnu-12377.121.6 series (iOS 26/27, stage 3)

The first kernel series for the iOS 26/27 port (docs/plan.md stage 3), on xnu-12377.121.6 (the macOS 26.5 / iOS 26
xnu; iOS 27 runs on it with the Darwin 27 syscalls). Target: **Gate C**, a RAM-booted kernel that reaches launchd on
the serial console, then SSH over USB-ECM. Plan of the rebase: `research/notes/rebase-map-12377-2026-11-13.md`.

Tree: `work/src/xnu-12377`, branch `sunfish-12377` from tag xnu-12377.121.6 (ac9718f). Its first commit (tag
`stage12377`) holds what the build does before the series patches (the stage scripts' output and dxb's own
patches/26.0); one more `stage:` commit holds 0002's header. Every other commit is one file of this directory,
in file order. As in `work/src/xnu`: commit in the tree, then save the commit as the next file here.

## Numbering (file-name order = apply order)

| range | what | source |
|---|---|---|
| `0000`-`0001`, `0019`/`0020`/`0026`/`0058` `*.sh` | stage scripts: CoreEntitlements V2 headers without a KDK + firehose stub, dxb's TrustCache headers, libpthread-539.100.4, BearSSL 7bea48e, hfs-715.120.4, IOHIDFamily-2238.120.5 (fetched at build time by pinned commit; `XNU_LOCAL_DEPS_DIR` uses local clones) | IOS-26-Hot, unchanged |
| `0002-stage-firehose-compat-header.sh` | ours: the firehose stub IOS-26-Hot's CI got from dxb bd88697, which 0134 patches (see below) | ours |
| `0003`-`0124` (116 patches) | ios-sweet + flame, ported to 12377 by the ios-sweet author; numbers and names as in IOS-26-Hot | IOS-26-Hot, byte-identical |
| `0125`, `0126` | the two sunfish edits our copies of 0086/0089 carry and Hot's lack: cpufreq cluster table A55 x6 / A76 x2, `SWEET_MIRROR_PA 0x1fa000000` (6 GB) | ours |
| `0129`-`0141` (12 patches) | IOS-26-Hot's iOS 26 generic layer: arm64e exec + shared region, sleh PAC/ISA emulator, build fixes, diagnostics entitlements, fuse query, firehose config, kmem RNG guard, SMP/QEMU guards, sandbox outputs + exit log, pmem MPSS wcomb, IPC service-port nofilter, IOMFB swap layout | IOS-26-Hot, byte-identical, Hot's numbers |
| `0199` | Darwin 27 syscall slots (pipe2, dup3, fchflagsat, getumask, aio_readv/writev, ...) | UniXNU `patches/xnu-12377/darwin26-syscalls.patch`, unchanged (header added) |
| `1NNN` | our `xnu/patches/0NNN-*` re-applied on this stack, number + 1000 (0151 -> 1151); exported from the tree with `git format-patch` (fuzzed ones refreshed) | ours |
| `1290`+ | new for this series only (no iOS 16 counterpart), numbered after the last re-applied one | ours |

New patches (1290+):
- `1290` ufs root minor: `rd=ufsroot1` (or `ufsroot2`) roots on that sweet_ufs minor, `ufsrootminor=N` overrides it
  (default: the rd digit, so `rd=ufsroot0` is unchanged). Minor 2 (`ufsroot2`) is a byte range of userdata from
  `ufsrootbase=` + `ufsrootcount=` (bytes, 4 KiB aligned, relative to the partition start; off unless ufsrootcount is
  set), e.g. a contiguous root image file inside iOS 16's /var; read-only unless `ufsrw=1`.
- `1291` TPRO emulation: the sleh EL0 emulator (0130) reads `mrs xN, S3_3_C4_C0_3` as 0 and steps over iOS 27's three
  TPRO words 0xd5940000/0xd5900040/0xd5900020 (counted as `tpro` in sysctl sweet.emu_stats); `sweettproemu=0` turns it
  off. Belt and braces: 27's userland only runs them when commpage byte 0x10c == 4, and this kernel never writes 0x10c.
- `1292` shared region 27: SHARED_REGION_SIZE_ARM64 0x180000000 -> 0x200000000 (8 GiB, region 0x180000000-0x380000000),
  the size Apple's 24B156 kernelcache uses (layout 0 of its base/end/size table in vm_shared_region_create; 23G90's is
  still 6 GiB). 27.2.1's cache ends at 0x327948000 with its max slide (0x187948000 + 0x20000000), 26.6.2's at 0x2e1574000.
  The user VA limit follows (ARM64_MIN_MAX_ADDRESS +2 GiB: device-large max 0x4d8000000). `sweetsr27=0` creates 6 GiB
  regions again (the VA limit stays raised).
- `1293` EL0 undef log: one console `printf` line `sweet-undef: pid N (name) esr .. ec .. pc .. lr .. word .. sr_off ..
  slide .. x16 .. x17 ..[ abort] far ..` for each EL0 exception that ends in SIGILL after the emulator declined it
  (uncategorized, MSR trap, SIMD trap, WFI/WFE, and the default case, which on this non-ptrauth kernel also catches
  EC 0x1C FPAC), and for pid 1's aborts just before EXC_BAD_ACCESS is delivered. `word` = the instruction at pc
  (0xdeadbeef if unreadable), `sr_off` = pc - shared region base (0 outside it; cache offset = sr_off - slide). First 64
  per boot, pid 1 always; `sweetundeflog=0` turns it off.
- `1294` no MTE: exec_add_apple_strings clears bit 2 (0x4, MTE "sec") of `security_config=0x..` and logs the first 4
  execs' value (`sweet-nomte: security_config 0x.. (task 0x..) mask 1`, launchd first); the sleh EL0 emulator makes
  `msr tco, #imm` / `msr tco, xN` no-ops and `mrs xN, tco` read 0 (`tco` in sweet.emu_stats). iOS 27's libsystem_platform
  (__os_security_config_init -> __apply_security_config) ORs the apple[] value into ___security_config, and bit 2 (or
  `has_sec_transition=1`) picks the $VARIANT$MTE strcmp/strncmp, whose `msr tco` SIGILLed launchd (k304a). Static
  reading says 12377 never sets bit 2 here (reserved without HAS_MTE; launchd = 0x18 + entitled bits), so the log line
  settles where the bit came from. `sweetnomte` bit 0 = mask, bit 1 = TCO emulation (default 3; 0 turns both off).
- `1295` no hardened heap: also clears bit 0 (hardened_heap) of `security_config`: iOS 27 libmalloc tags allocations
  with MTE when it is set (k305a: LDG in memtag_assign_tag_contiguous from mfm_alloc). sweetnomte bit 2, default on (7).
- `1296` MTE emulation: the sleh EL0 emulator runs FEAT_MTE's EL0 tag instructions as if MTE were disabled (tags
  ignored, every allocation tag 0): LDG clears Xt[59:56] (no memory access), IRG/ADDG/SUBG give tag 0, GMI = Xm |
  1 << Xn[59:56], SUBP/SUBPS subtract the 56-bit sign-extended pointers (SUBPS/CMPP set NZCV), STG/ST2G store no tag
  (base writeback only), STZG/STZ2G copyout 16/32 zero bytes, STGP stores like STP; tag stores and STGP fault
  (EXC_BAD_ACCESS) on an address not 16-byte aligned or not writable, before any writeback. LDGM/STGM/STZGM (EL1 only)
  stay UNDEF. Counted as `mte` in sweet.emu_stats, first hit logged (`SWEET EMU: first mte emulated`). A fallback for
  k305a's LDG SIGILL whatever sets the tagging path. `sweetnomte` bit 3, default on (sleh default 15; kern_exec's 7
  only reads bits 0 and 2).
- `1297` MTE DC ops: in 1296's emulator, DC GVA and the tag clean ops (CGVAC/CGDVAC/CGVAP/CGDVAP/CGVADP/CGDVADP/
  CIGVAC/CIGDVAC) are no-ops and DC GZVA zeroes the DCZID block (k307a: launchd 27 `dc gva, x9` 0xd50b7469 after the first LDG).
- `1298` abort log for all: 1293's `sweet-undef: ... abort` line for EXC_BAD_ACCESS of any process (first 64 per boot;
  pid 1 always), for k308a's mount[2] SIGBUS.
- `1299` signal log: `sweet-sig:` (signal, pid, kernel caller) in psignal_internal for SIGBUS/SEGV/ILL/TRAP/SYS and
  `sweet-ux:` (exception, code, subcode, signal, pc, lr) in handle_ux_exception; first 64 each (k309a: mount SIGBUS unexplained).
- `1300` `sweetsrnest=0` (default 1 = as before): the shared region enters each task without pmap nesting; A/B for
  k310a (mount sees foreign data in a shared-region __DATA page; research/notes/mount27-sigbus-2026-11-13.md, H1).
- `1301` with `sweetsrnest=0`, skip pmap_trim of the shared region (k311a: "pmap_trim_internal: grand range not in nested region").
- `1302` page-in probe (off unless `sweetprobe1` is set): `sweetprobe1`/`sweetprobe2` = file offsets of two dyld cache
  pages, `sweetprobesub` = cache file (default 25 = .25.dylddata, -1 = any), `sweetprobemax` = lines per boot (64; past it
  only at request 2^n). Logs `sweet-probe: pid ... srpager ... raw/slid qword@0x1ca8 qword@0xb0 first8` per
  shared_region_pager_data_request of a target page, and `... vnpager ... kret page` after each vnode_pagein that read it
  (request counts in `req`). For k310a's "Schedule..." page and the `___security_config` page:
  `sweetprobe1=0x8e90000 sweetprobe2=0xb908000`.
- `1303` crash report before the critical-exit panic (k313a: launchd 27 died of a bare SIGABRT and the panic came before
  the `CRASH` printer): in proc_handle_critical_exit (initproc or crash-behavior process, current thread, once) runs
  sweet_crash_log (`CRASH` slide/mh, pc/lr, 10-frame bt) and prints `sweet-crashmsg:` lines with libsystem_c's
  gCRAnnotations message/message2 (`sweetcrann` = unslid cache address of the message pointer, default 0x1eb1c5410 for
  24B156, + the task's sr_slide) and the main image's __crash_info message (`sweetcrinfo` = offset from its Mach-O header,
  default 0x85fa8 = launchd 24B156); 0 turns each off. abort_with_payload_internal logs `sweet-abort1:` (ns, code,
  flags, reason) for pid 1, first 4. Notes: research/notes/launchd27-abort-2026-11-13.md section 4.
- No patch needed for iOS 27's CPU-feature checks: DIT, SB, SHA512, SHA3, JSCVT, FCMA commpage bits and their
  hw.optional.arm.FEAT_* sysctls come from the ID registers of the boot CPU (an A55) in osfmk/arm/commpage/commpage.c;
  A55/A76 lack all six (GUESS from the Arm TRM values; check `sysctl hw.optional` on the first 12377 boot); commpage 0x10c is zeroed and unwritten; the user timebase type is USER_TIMEBASE_SPEC (CNTVCT, not
  CNTVCTSS) since SWEET.h defines neither HAS_ACNTVCT nor __ARM_ARCH_8_6__.

`SWEET.h`'s `BTI_ENFORCED 0` is already in Hot's 0004 (our iOS 16 copy lacks it), so no patch for it.

## Sources and licences

- **IOS-26-Hot** `xnu/patches-26`: MIT (`LICENSE`: "Copyright (c) 2026 dipa-studio"), clone in
  `research/upstream/IOS-26-Hot` (remote github.com/nithinyadavamaraboina-online/IOS-26-Hot), commit
  **d249939b9c36380afaee1a76cf167aeee8347475** (2026-11-01). Built there by `.github/workflows/xnu.yml` with
  darwin-xnu-build bd88697, MACOS_VERSION 26.5.
- **UniXNU**: BSD-2-Clause-Patent (`LICENSE`), clone in `research/upstream/unixnu-main` (github.com/UniXNU/UniXNU),
  HEAD **7d85ede80092050f4d87f72ac7229bb605ce07fb**; the patch file last changed in 4b8d85d.
- **dxb 0002 stub**: blacktop/darwin-xnu-build bd88697 `patches/26.0/00_setup_coreentitlements.sh` (MIT), verbatim.
- Everything else: ours (this repo).

## IOS-26-Hot patches not taken

- 0125-0128: RMX1931 (Realme) board, touch, GPU zap region, Metal clocks: another phone.
- 0138 `ios26-pac-fastpath-overlay-thermal-touch`: 42 files mixed with RMX1931 drivers; its generic part (locore.s PAC
  fast path, sleh.c, debug.c, pe_serial.c) gets cut out later (map s5; 0130's emulator is enough to start).
- 0142 `ios26-iosurface-abi`: does not apply here: its SweetSurface.cpp hunks sit on 0138's (kSweetSurfaceSetYCbCrMatrix,
  bulk attachments). Needed for Gate D, not C; merge with 0138's surface part (and our 0235/0251/0252) then.
- 0143-0151: Hot's flame perf, Wi-Fi ABI (0145), keystore + app inject (0148), rebrand: Gate D+ items.

## Our 0125-0285: what is in, what is not

In (16): 0125 (touch panel 2340 + sunfish early-fb/A6 FB address; added beyond the Gate C list because the early
framebuffer PA/height in SWEET.h live there), 0127, 0151, 0175 (fuzz), 0176, 0184, 0185, 0186 (fuzz), 0187, 0191, 0192,
0198, 0244, 0246, 0279, 0281 (fuzz). The fuzzed hunks were read: each lands in the intended spot.

Tried and left out (they sit on patches not in this series):
- 0189 boot watchdog: SweetPlatformExpert.cpp/SweetFramebuffer.cpp; built on 0179's UI watchdog (`flame_wdt_stop`,
  swap time), fuzz 3 put its declarations inside a function. 0269 wdt crumb: on 0189.
- 0206 recovery crumbs, 0207 recovery TLB wait: sweet_a6xx.c/sweet_gpu.c, need the A618 GPU chain (0129-0174).
- 0280 SPMI write retry: sweet_keys.c/sweet_spmi.c, needs 0126 (vol-up on PM6150L) / 0242.

Not attempted yet (the map, pass 3 on the Hot base without Hot's iOS 26 layer: 143 clean / 6 fuzz / 11 conflict of
our 160, 0160 skipped). Since Hot 0137 (sweet_ufs/sweet_amfi) and 0139 (sweet_pmem) now come first, re-check our
pmem (0232/0233/0277/0278) and AMFI (0194, 0219, 0240) patches against them:
- cpufreq chain (conflict): 0255, 0256, 0257, 0258, 0260, 0261, 0265, 0276 (sched_prim.c sits where 12377 has
  CONFIG_SCHED_SMT; 0255 adds sweet_thermal.c). Boots run at bootloader clocks without it.
- HID/motion (Hot's 0058 stages IOHIDFamily-2238 and rewrote SweetHID.cpp): 0228, 0243, 0245 conflict; 0230, 0241
  fuzz.
- Hot-merge items: 0235/0251/0252 vs Hot 0142 (SweetSurface.cpp), 0188/0193/0199 vs Hot 0145 (redwood_apple80211.c),
  0240 vs Hot 0148 (kern_exec.c); 0238, 0240 fuzz.
- iOS 16-only (by subject; apply clean, keep switched off): 0154/0155/0196 census, 0162 charger dump, 0171/0266/0268
  gpucc/cx snapshots, 0177/0180 stall injection, 0211 camprobe, 0220-0222 MDP dumps.
- 0160: never (149,079 lines of 8796's iokit); its 11 real lines (IOMFB async log in SweetFramebuffer.cpp) by hand.
- The rest (GPU A618 0129-0174, display, touch 0126+, battery, Wi-Fi, BT 0226, audio, camera, video): clean on the
  map's stack, for after Gate C.

## Build

```
VM_DIR=~/VMs/macos15 MACOS_VERSION=26.5 XC=/Applications/Xcode_26.1.app PATCH_DIR=xnu/patches-12377 KDK_MODE=fake tools/vm-build-xnu.sh NN
```

What the build does (dxb 6639065, `patches()`): copies every file here as `patches/26.0/sweet-<name>`, deletes dxb's
`00_setup_coreentitlements.sh` (needs a KDK) and points KDKROOT at an empty `~/xnubuild/no-kdk`; runs all `*.sh` from
the xnu root in name order (0000 also writes its CoreEntitlements V2 headers into no-kdk, as Hot's CI fills its
fake-kdk), then dxb's 26.0 patches (link_kdk and remove_applefeatures_include do not apply on 12377 and are skipped,
as in Hot's CI), then ours, which must all apply (a sweet-* patch that fails `git apply --check` stops the build).
The stage scripts fetch their sources from GitHub and bearssl.org on each full or re-patch run.

Checked 2026-11-13 (no build): the whole series applies from scratch on ac9718f in that order (153 patches: 6 dxb +
147 ours; the result's tree hash equals `sunfish-12377` HEAD), no new whitespace errors in our patches. Re-checked with
1290/1291 (149 ours, in a temporary index from the `stage:` commit c3a78d5 + 089e3fb's header): tree hash equals HEAD.
Re-checked with 1292 (150 ours, same method): tree hash d7c5c63 equals the tree with 1292's edits (uncommitted at check time).
Re-checked with 1293 (151 ours, same method): tree hash f75d960 equals `sunfish-12377` HEAD be0f2d2, no whitespace errors.
Re-checked with 1294 (152 ours, 1294 applied to HEAD~1 in a temporary index): tree hash 367d655 equals `sunfish-12377` HEAD db2e009, no whitespace errors.
Re-checked with 1296 (1296 applied to HEAD~1 = 693f39a in a temporary index, `--whitespace=error`): tree hash 7a53cf1 equals `sunfish-12377` HEAD 09673bf.
Re-checked with 1303 (applied to HEAD~1 in a temporary index, `--whitespace=error`): tree hash faf59e9 equals `sunfish-12377` HEAD 6d41d36.

Differences from Hot's CI kept on purpose: dxb 6639065 instead of bd88697 (it adds `define_esr_ec_pac_fail_unconditionally`
and `guard_sptm_user_pointer_ops_with_pac`, both apply under the series), Xcode 26.1 instead of runner's Xcode 26.x.

## First boot

1244's compiled-in defaults are the iOS 16 ones (`sweetgpu=1 sweetmtl=2 sweettouch=2 ...`); this series has Hot's
SM8150/A640 GPU code without our A618 chain, so boot with `sweetgpu=0 sweetmtl=0` (or `sweetnodefaults=1` and a
full line) until the GPU patches are in.
