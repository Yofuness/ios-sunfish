# iOS 26 / 27 port (arm64e userland on a non-PAC SM7150)

**State:** 🟡 **Gate C1 passed** (k308a, 2026-11-13 13:55): iOS 27.2.1 launchd ("Darwin Bootstrapper Version 7.0.0") runs on
kernel308 (xnu-12377 + xnu/patches-12377 through 1297) from the PAC-rewritten C1 root on ufsroot1, runs its boot tasks and
execs mount (pid 2), which dies with SIGBUS. MTE instructions are emulated (1294/1296/1297). Next: C2 (SSH over USB-ECM).
**Updated:** 2026-11-13.

## Facts
- Goal (the user, 2026-11-13): LibrePods development needs a current iOS host; target iOS 27, iOS 26 first if better.
- CPU: Kryo 470 (A76/A55) ARMv8.2, no PAC. iOS 17+ userland is arm64e only. Approach (as GiaSen/Bergamota, UniXNU-zeta,
  IOS-26-Hot): offline PAC lowering of the whole root (RETA*->RET, BRAA*->BR, BLRAA*->BLR, PAC/AUT->NOP, LDRAA->LDR,
  TEXT_STUBS BRAA x16,x17), dyld keys-off (`ptrauth_disabled=1`), kernel loader + slide changes, EL0 emulator for the rest
  (writeback LDRAA, PACGA, JIT PAC, FJCVTZS, FCMA).
- Donors: ../restore/ipsw/iPhone12,1_26.6.2_23G90_Restore.ipsw, iPhone12,1_27.2.1_24B156_Restore.ipsw (out of git).
- Build: xnu-12377 needs Xcode 26.x (Xcode 15.0.1 VM can't); plan: second VM ~/VMs/macos15, Sequoia 15.7 + Xcode 26.1.
- Storage: new root (HFSX >= 24 GB) in userdata; the user allows wiping iOS 16's /var (2026-11-13).
- Licences: GiaSen/Bergamota none (ideas only); zeta BSD-2-Clause-Patent; Scion ios-sweet layer MIT; QcaBluetooth
  qbt_transport.c APSL; dada APSL; AppleKeyStoreState BSD-2-Patent.

## Log
### 2026-11-13 15:50 ROOT CAUSE: the sparse write skipped zero pages; stale data in the 27.2.1 root
- ufsroot1 vs root27-c1.img, sha256 per MiB (phone read-only, kernel167): 2314 of 13312 chunks differ; 1486 are all-zero in
  the image, 828 hold data; every differing page in 3 sampled chunks is all-zero in the image and holds old partition data
  on the phone ("lular:4C66F", "task:4C2D4", compressed blocks). Cause: `img2simg -s` made zero 4 KiB blocks DONT_CARE, so
  fastboot never wrote them. Hit files incl. dyld_shared_cache_arm64e.25/.54/.77.dylddata, .26/.55.dyldreadonly,
  .79.dyldlinkedit and ~825 others. This explains mount's "Schedule..." pointer (zero page 0 of .25.dylddata __DATA) and
  very likely launchd's MTE path (___security_config, zero word in .25.dylddata __TPRO_CONST). Hashes: ../logs/root27-verify/.
- Fix: a sparse writer that writes every allocated HFS block (zero ones as FILL) and leaves only free blocks DONT_CARE
  (implementer running); then rewrite ufsroot1 and boot. The MTE/TCO emulation (1294-1297) and probes stay as safety nets.

### 2026-11-13 15:45 k312a: no pmap nesting changes nothing: the bad shared-cache data is in the pages themselves
- kernel312 (1301) + sweetsrnest=0. OBS (../logs/k312/k312a-rescue.txt): launchd 27 bootstraps; TCO + MTE emulated again
  (___security_config still has bit 2); mount still `sweet-ux: ... pc 0x6c756465686353` ("Schedul"). H1 (nested pmap leak)
  ruled out. Remaining: page contents wrong (H2: page-in returns another block, or the on-device data differs from the
  image). Next, in parallel: ufsroot1 vs root27-c1.img chunk hashes (phone, read-only) and 1302 pager page-in probe.

### 2026-11-13 15:20 k311a: sweetsrnest=0 panics in pmap_trim (nothing nested); 1301 skips the trim
- kernel311 (1300) + `sweetsrnest=0`. OBS (../logs/k311/k311a-rescue.txt): launchd mapped the 80 cache files, then
  `panic: pmap_trim_internal: grand range not in nested region, vstart=0x199708000, size=0x187948000, state=0 @pmap.c:9342`
  (vm_shared_region.c:2120 trims the config map's pmap unconditionally). 1301 skips the trim when sweetsrnest=0. kernel312.

### 2026-11-13 15:00 mount's ASCII pointer: kernel shared-region view (Fable; research/notes/mount27-sigbus-2026-11-13.md)
- OBS: x9 = dyld's `___syscall_logger` (cache .25.dylddata `__DATA` page 0, unslid 0x1eaf71ca8), loaded at 0x180491584; zero on
  disk and in root27-c1.img (dylddata not rewritten, cmp identical); launchd's cache dyld reads the same page as zero, mount
  (7 ms after exec, deterministic in k308a/k309a/k310a) reads "Schedule..." there. Not the rewrite, not "auth GOTs:
  unmapped" (normal on a customer cache). ___security_config (k304a) is the same symptom in __TPRO_CONST (NO_REBASE page).
- GUESS H1: launchd's COW/unnest of the 0x1f0000000 block leaks its private page into the nested shared pmap; H2: pager page
  re-read through the UFS data path returns another block. 1300 adds `sweetsrnest=0` (no pmap nesting) as the A/B.

### 2026-11-13 14:50 MTE gate traced (Fable investigator; research/notes/mte-gate-2026-11-13.md)
- OBS: libmalloc (`___malloc_init` 0x1805526a0 `tbz w0,#2` -> cold.6 sets malloc_has_sec_transition -> mfm_memtag_enabled)
  and the strncmp/strcmp dispatchers read the same thing: bit 2 of `___security_config` (0x1ed9e80b0, libsystem_platform
  __TPRO_CONST). Its only writer is __apply_security_config from apple[] security_config | 4 if has_sec_transition=="1";
  our kernel pushes 0x18/0x20158 and no has_sec_transition (Apple's 24B156 kernel doesn't either; it adds dyld_hw_tpro=1).
  No commpage/sysctl input. So the run-time bit 2 is not from the inputs.
- GUESS: the word is clobbered by its __TPRO_CONST neighbour (libdyld sAllocatorBuffer 0x1ed9e80a0 / sMemoryManagerBuffer),
  or our kernel maps the rw- TPRO page differently (no dyld_hw_tpro). Possibly the same bug as mount's ASCII pointer
  (k310a): the mount investigator checks. Decisive A/B: print the 0x1ed9e8000 page at the first TCO trap.
- Fallback in the root rewrite: 4 instruction patches (malloc_init tbz -> b; strncmp/strcmp/OSAtomicDequeue csel -> mov).

### 2026-11-13 14:35 k310a: mount's SIGBUS is a jump to ASCII from dyld's _mach_vm_map
- kernel310 (1299). OBS (../logs/k310/k310a-rescue.txt): no sweet-sig line (not psignal'd); `sweet-ux: pid 2 (mount) exc 1 code
  0x101 subcode 0x6c756465686353 -> sig 10 pc 0x6c756465686353 lr 0x1857815e8`: EXC_BAD_ACCESS instruction fetch at
  "Schedul" (ASCII, little-endian). Slide 0x52f0000 (launchd's TCO site) -> lr = cache /usr/lib/dyld `_mach_vm_map+580`,
  after `blraaz x9` (0x1804915e4): x9, a function pointer, holds string bytes. Panic caller proc_prepareexit.cold.2.
- Next: a Fable investigator compares the original vs rewritten cache at x9's source (rewrite corruption vs dyld's "auth
  GOTs: unmapped" keys-off mode vs kernel shared-region mapping).

### 2026-11-13 14:20 k309a: mount's SIGBUS comes with no abort/undef log
- kernel309 (1298). OBS (../logs/k309/k309a-rescue.txt): same as k308a (launchd 27 bootstraps, mount-phase-1, exec mount,
  "pid 2 exited -- exit reason namespace 2 subcode 0xa" 7 ms later) and no `sweet-undef:` line: the SIGBUS does not come
  through handle_user_abort's EXC_BAD_ACCESS path. 1299 logs every psignal of SIGBUS/SEGV/ILL/TRAP/SYS with its kernel
  caller and every exception->signal translation with pc. kernel310 next.

### 2026-11-13 13:55 k308a: GATE C1 PASSED: launchd 27 bootstraps; mount (pid 2) dies with SIGBUS
- kernel308 (1297), same cmdline as k302b. OBS (../logs/k308/k308a-rescue.txt; the live log missed it): TCO + MTE (LDG)
  emulated once each, no sweet-undef; `com.apple.xpc.launchd ... hello, launchd UUID: B6C82430-...`; "Could not opt into 50 MB
  Jetsam high watermark: 22"; **"Darwin Bootstrapper Version 7.0.0: Wed Oct 7 23:41:26 PDT 2026;
  root:libxpc_executables-3298.42.1~13/launchd/RELEASE_ARM64E"**; boot-args echoed; (system) entering ondemand mode, created;
  lo0 127.0.0.1; boot tasks exclaves-boot and mount-phase-1; `sweet-nomte: security_config 0x18`; exec mount; 28.615 "pid 2
  exited -- exit reason namespace 2 subcode 0xa" (SIGBUS) -> "SWEET: critical exit: mount[2] exited (signal 10)" -> panic.
- Gate C1 ("serial launchd from a RAM-booted kernel + rewritten root") is met. Next: log fatal aborts of every process
  (1298) to find mount's SIGBUS; then C2.

### 2026-11-13 13:35 k307a: MTE emulation works (LDG); next SIGILL is `dc gva, x9`
- kernel307 (1296). OBS (../logs/k307/k307a-rescue.txt): `SWEET EMU: first tco emulated (pid=1 ...)`, `SWEET EMU: first mte
  emulated (pid=1 pc=0x19ab34e90 insn=0xd9600008)`, then `sweet-undef: pid 1 (launchd) ... pc 0x19ab17d40 word 0xd50b7469`
  = `dc gva, x9` (MTE tag set by VA; llvm-mc). launchd still dies before "Darwin Bootstrapper Version".
- 1297 adds the MTE DC ops to the emulator (GVA + tag clean ops as no-ops, GZVA = block zero); matcher checked against
  llvm-mc encodings. kernel308 next.

### 2026-11-13 13:15 k306a: same LDG with hardened_heap off: the MTE gate is elsewhere
- kernel306 (1295). OBS (../logs/k306/k306a-rescue.txt): `sweet-nomte: security_config 0x20158 (task 0x20159) mask 1`; TCO
  emulated once (strncmp MTE variant still chosen); `sweet-undef: pid 1 ... pc 0x198a34e90 word 0xd9600008 slide 0x184c8000`
  = unslid 0x18056ce90, the same `_memtag_assign_tag_contiguous+4` LDG as k305a. So neither security_config bit 2 nor bit 0
  is what turns MTE on in libsystem_platform/libsystem_malloc 27 (GUESS: a commpage/sysctl field whose meaning differs
  between 12377 and 27).
- iOS 16 without /var (sweetnofstab=1): SSH works, the panel stays on the Apple logo (no /var: expected).
- Next, in parallel: a Fable investigator for the real gate; 1296 EL0 MTE emulation (tags = 0) as a fallback.

### 2026-11-13 13:00 k305a: TCO emulation works; launchd 27 then SIGILLs on LDG in libmalloc's hardened heap
- kernel305 (1294). OBS (../logs/k305/k305a-rescue.txt): `sweet-nomte: security_config 0x20159 (task 0x20159) mask 1`
  (12377 layout: hardened_heap=1, tpro=0, reserved=0, platform_restrictions_version=3, script_restrictions=1,
  guard_objects=1, hardened_process_version=2); `SWEET EMU: first tco emulated (pid=1 pc=0x18f6548ac)`; then `sweet-undef:
  pid 1 (launchd) ... pc 0x1833a0e90 word 0xd9600008 ... slide 0x2e34000` = unslid 0x18056ce90
  `_memtag_assign_tag_contiguous+4` (libsystem_malloc) `ldg x8, [x0]`, called from `_mfm_alloc+652`.
- libsystem_platform `__apply_security_config` maps value bits 0/1/2/6/8 -> config 0x1/0x2/0x4/0x40/0x100 (bit 0 via a cold
  path). So the MTE strncmp variant was not from bit 2 (the source of k304a's variant choice stays open; TCO is emulated);
  hardened_heap (bit 0) makes libmalloc tag memory. 1295 clears it too (sweetnomte bit 2). Next: kernel306.

### 2026-11-13 12:45 k304a: launchd 27's SIGILL = `msr tco, #1` in the MTE variant of strncmp
- kernel304 (1293 sweet-undef log). OBS (../logs/k304/k304a-rescue.txt): `sweet-undef: pid 1 (launchd) esr 0x2000000 ec 0x0 pc
  0x19dec88ac lr 0x19952c258 word 0xd503419f sr_off 0x1dec88ac slide 0x116a8000`. Unslid 0x18c8208ac =
  `__platform_strncmp$VARIANT$MTE+60` (libsystem_platform), word = `msr tco, #1` (MTE; neither the A76/A55 nor the A13 have
  MTE); caller libsystem_c `___guard_setup+88`. The `__platform_strncmp` dispatcher picks the MTE variant when bit 2 of the
  `___security_config` byte is set (`_os_security_config_get`). So our kernel hands launchd a security config with MTE on.
- Next: patch 1294 (find the writer of ___security_config, clear the MTE bits in what the kernel provides; emulate msr/mrs
  TCO as a fallback).

### 2026-11-13 12:10 k303a: dyld cache MAPS (1292); launchd 27 then dies on SIGILL
- kernel303 (1292: 8 GiB shared region), same cmdline as k302b. OBS (../logs/k303/k303a-rescue.txt; the live log missed
  this boot): 25.461 exec launchd; libignition "hello from launchd.1"; 80 "not in trust cache" warnings; 25.750
  "dyld[1]: dyld cache mapped system-wide: customer, auth GOTs: unmapped"; 25.83 USB-ECM configured; 25.857/25.858 launchd
  "triggered unnest of range 0x1f2000000->0x1f6000000 / ->0x1fc000000"; 25.888 "pid 1 exited -- exit reason namespace 2
  subcode 0x4" (SIGILL) -> panic "initproc failed to start (signal 4)". No PC/instruction printed. No daemons exec'd.
- Next: kernel304 with an EL0-undef print (pid, PC, word, shared-cache offset) to find the instruction.

### 2026-11-13 12:00 k302b: LAUNCHD 27 RUNS on the phone (27.2.1 root on ufsroot1, rw); dies on the shared-cache map
- `rd=ufsroot1 ufsrw=1 rootrw=1 launchd_unsecure_cache=1 ignition_level=1 cs_integrity_skip=1 -v sweetgpu=0 sweetmtl=0`
  (kernel302, sunfish-26.adt, 4456 mV). OBS (../logs/k302/k302b-rescue.txt, boots/20261113-114816.log): 28.597 hfs journal
  created; 29.962 "hfs: mounted iOSRoot on device b(1, 1)"; 29.974 exec launchd (the PAC-rewritten 27.2.1 launchd runs);
  libignition "Darwin Ignition Sequence Version 1.0.0 ... RELEASE_ARM64E", "opened shared cache directory"; 29.081 USB-ECM up.
- 30.241 "map(...'dyld_shared_cache_arm64e'): not in trust cache" for all 80 files (vm_unix.c:1634: only a warning, it falls
  back to the root-owner check); 30.257 "mapping[1]: address 0x2f5b64000 size 0x2976c000 ... failed 0x1" -> dyld "syscall to
  map cache into shared region failed" -> "Library not loaded: /usr/lib/libSystem.B.dylib" -> pid 1 exit -> panic 30.3 s.
- Cause (OBS source + arithmetic): 12377's SHARED_REGION_BASE/SIZE_ARM64 = 0x180000000/0x180000000 (ends 0x300000000,
  osfmk/mach/shared_region.h:90-91); mapping[1] ends at 0x31f2d0000. The 27 cache needs a larger shared region (xnu-13432).
  No SIGILL, EXC_GUARD or signature errors seen. iOS 16 back (sweetnofstab=1).

### 2026-11-13 11:55 27.2.1 C1 root written to ufsroot1; k302a: root mount fails (journal create on a read-only device)
- Write (the user's OK 10:55; /var backup first): `fastboot -S 256M flash userdata ../restore/root27/root27-c1-at16g.simg`
  (-S 512M refused: max-download-size 0x10000000), 43 chunks OKAY, 660 s; first chunk 16 GiB DONT_CARE, output ends at
  31.1 GB of 117.7 GB userdata. No erase/format. iOS 16 root (ufsroot0) untouched.
- k302a (`rd=ufsroot1 ufsrw=0 rootrw=0 launchd_unsecure_cache=1 ignition_level=1 cs_integrity_skip=1 -v sweetgpu=0
  sweetmtl=0`, sunfish-26.adt, battery 4431 mV): "BSD root: ufsroot1, major 1, minor 1"; hfs "Initializing the journal
  (joffset 0x6a000 sz 0x800000)" -> strategy err 0x1e (EROFS) -> hfs_mountfs error 22 -> "cannot mount root, errno = 19",
  retried every 5 s (OBS, ../logs/k302/k302a-rescue.txt). mkfs.hfsplus -J leaves the journal to be created at the first
  mount, which needs writes. The HFS header parsed: ufsroot1 reads from the right place.
- iOS 16 with sweetnofstab=1 (k167nofstab): SSH in 17 s, only ufsroot0 mounted (no /var); console shows daemons starting,
  a mediaserverd crash; SpringBoard not checked.
- Next: k302b with ufsrw=1 rootrw=1 (ufsroot1 is ours now).

### 2026-11-13 11:25 27.2.1 C1 root image built and PAC-rewritten (tools/mkiosroot27.sh, docs/root27.md)
- Extract: `ipsw extract --dmg fs|sys|app` 85 s + `ipsw fw aea` 97 s (SystemOS key via --fcs-key .pem, OS key online from
  wkms, saved as .aea.key) -> root-src/: OS 9.27 GB, SystemOS 6.18 GB, AppOS 16 MB (UDIF/APFS, read with apfs-fuse).
  Uncompressed: OS 13.3 GB (System 10.6, staged_system_apps 1.15, Applications 0.43), SystemOS 7.2 GB (cache 7.0 incl. 1.25 GB .symbols).
- `--profile c1` (13 GiB image): no apps/assets/localizations/ML weights (C1_EXCLUDES) -> 11 GB used, 2.2 GB free.
  Times: copy 89 s, layout 122 s (1045 cryptex files linked into /, 12 _PanicOnCrash renamed), cache rewrite 87 s,
  tree rewrite 437 s (jobs 3), fsck 24 s, sparse 141 s: ~15 min.
- Cache (zeta rewrite, proof from 10:50, no --page-shift): 33,558,075 edits in 70 of 80 files, 1 FIPS seal
  (libcorecrypto; _noasm/_trace fail Apple's own contract, left as shipped), hard links intact (link count 2). WebCore and
  MLIR_ML (proof OOM) and the 97 unproven words (34 in TEXT_STUBS islands, 10,174 stub words lowered) keep PAC: SIGILL if run.
- Tree (zeta rewrite-zeta-userland-tree, vendored to tools/root27 + sunfish_pac's TPRO/noreturn-end fixes): 2,557 images
  (1,837 executables, 658 bundles, 61 dylibs, dyld), 6,388,290 edits, 2 refused: DriverKit libsystem_platform_debug (1
  braaz unproven) and CoreTime PeerTimeSyncPlugin (cdhash in no IPSW trust cache); both stay arm64e. Without the TPRO fix
  /usr/lib/dyld was refused (863 unproven, first run). Originals in ../restore/root27/orig-c1 (1.2 GB).
- fsck.hfsplus -fy fixed the root folder count (Linux hfsplus), then -fn OK. Out (not in git): root27-c1.img (13 GiB, 11 GB
  allocated), root27-c1.simg and root27-c1-at16g.simg (10.4 GB each: 10.4 GiB RAW, 237 MiB FILL, rest DONT_CARE, +16 GiB
  DONT_CARE head). Nothing written to the phone.
- Open: zeta marks executables CS_RUNTIME + platform id 26 (macOS AMFI rules), untested with sweet_amfi; no trust cache made
  (kernel needs none, note s2); full profile (28G) not built yet; C2 items (dropbear job, sweet-root-tweaks TODOs) not in.

### 2026-11-13 11:00 kernel302 built (1290 root on any UFS minor, 1291 TPRO emulation)
- 1290: rd=ufsrootN picks the minor (ufsrootminor=N overrides); minor 2 = userdata byte range ufsrootbase/ufsrootcount
  (4 KiB aligned, ro unless ufsrw=1). 1291: Hot's sleh EL0 emulator returns 0 for `mrs S3_3_C4_C0_3` and steps over the 3
  TPRO words (sweettproemu=0 off). Commpage SHA3/SHA512/SB/FCMA/JSCVT/DIT come from the ID registers (commpage.c:419-614),
  0x10c is unused + zeroed, timebase USER_TIMEBASE_SPEC: no patch (check `sysctl hw.optional` on the first 27 boot).
- Build (append path): exit 0, 101 s; work/kernel302/kernel.development.sweet 21254400 B, sha256 7669dd17...

### 2026-11-13 10:50 Full-cache PAC proof of 27.2.1 done; root pipeline designed (Fable investigator)
- tools/ios27-pac/prove-cache.py on 24B156 (jobs 1 then 2, 3.5 GB cap, 6 GB retry; ~1.3 h): 33,558,075 edits
  (unwind 32.79M, pointer 0.60M, landing 0.12M, start 39k, call 10k), 97 unproven (stub islands 34, gap islands 61, 2
  other), 0 unlowerable; failed by OOM: MLIR_ML, WebCore (retry with more RAM later). Output ../restore/ipsw/x/24B156/prove/.
- Pipeline (research/notes/root27-pipeline-2026-11-13.md): imageboot impossible (needs closed IOHDIXController); ramdisk
  too small for the 6.8 GB cache; plan = HFSX root built on Linux (Hot's AEA-aware mkiosroot.sh, apfs-fuse, zeta rewrites),
  /dev/ufsroot1 (userdata from 16 GiB, 1185) as root via a new `ufsrootminor` boot-arg (kernel302). Writing that region
  replaces iOS 16's /var (question to the user); fallback: an image file in /var + a sector-range minor. Signing: our
  kernel enforces none (sweet_amfi marks root binaries platform; Hot booted 26 unsigned + cs_integrity_skip=1).

### 2026-11-13 10:20 k301b: KERNEL301 BOOTS to launchd (sunfish-26.adt, iOS 16 root read-only)
- `SUNFISH_LLVM_NM=1 ADT=work/boot/sunfish-26.adt tools/sunfish-boot.sh k301b work/kernel301/kernel.development.sweet
  sweetfb_noconsole=0 -v sweetgpu=0 sweetmtl=0 ufsrw=0 rootrw=0`; battery 4456 mV. The 256-byte seed fixed k301a's silent
  death (OBS: arm_vm_init passed).
- Shim RAM log (rescued after the next boot from /dev/rufsroot0 at the sunfish-test.sh rescue offset; copy in
  ../logs/k301/k301b-rescue.txt, out of git), kernel clock: 26.387 banner; 26.55-26.58 AMFI/Sandbox stand-ins, AKS, WDT,
  SURF, HID; 26.579-26.594 8/8 CPUs up, SGI1 verified; fb 1080x2340 @0x9c000000; PM8150 RTC; battery 4456 mV; 26.632 UFS
  LUN 0 read-only; 26.643 BSD root ufsroot0; journal replay refused on the ro device (non-fatal); 26.654 hfs mounted
  iOSRoot; "root volume is not authenticated (error 25); continuing unsealed"; 26.658-26.666 exec /sbin/launchd
  (launchd.development tried first); libignition; launchd syscalls; 27.19 USB-ECM frames; "trust caches unavailable".
- 27.535 panic: `initproc exited -- exit reason namespace 23 subcode 0x2000004300800407` (OS_REASON_GUARD; GUESS: Mach
  port guard, kGUARD_EXC_DESCRIPTOR_VIOLATION, port 0x407): iOS 16 launchd on a 26 kernel, expected. Panel showed the
  panic dump from ~15 s; shim watchdog reset to fastboot between 60 and 90 s. No USB log lines before the panic.
- iOS 16 kernel167 back at the lock screen (k167back2, 4435 mV).
- Next: the 27.2.1 root (stage 4): full-cache prover, rewrite, image, boot it (imageboot from a file vs a region).

### 2026-11-13 10:05 ADT for xnu-12377 (sunfish-26.adt)
- Experiment E1 of research/notes/k301-noboot-2026-11-13.md, host only. `tools/mkadt.py --xnu12377` (implies --highmem)
  -> work/boot/sunfish-26.adt (13772 B): /chosen random-seed 256 B (was 64; 12377 panics in arm_vm_init below 256),
  dram-base 0x80000000 + dram-size 0x17cc00000 (all RAM, ends 0x1fcc00000: live DT start, Android iomem end; boot.md),
  sweet-phys-base 0x100000000 + sweet-mem-size 0xf8c00000 (the old kernel range), kernel-ctrr-to-be-enabled u32(1).
- mkpayload.py adt_dram() prefers sweet-phys-base/-mem-size (IOS-26-Hot, MIT). kernel301 + sunfish-26.adt: phys_base
  0x100000000, entry PA 0x1015b4488, kernel_end PA 0x1029cc000 (same placement as with sunfish-hi.adt).
- SUNFISH_LLVM_NM=1 (opt-in): llvm-nm finds _sweet_log_ring/_total, arming the shim RAM-log mailbox; GNU nm never did.
- iOS 16 unchanged: mkadt trees byte-identical for a fixed seed (5 flag combos); kernel167 payload byte-identical, image
  identical except avbtool's random 64-byte footer salt/digest (same for two builds of the same payload).
- Boot: `ADT=work/boot/sunfish-26.adt tools/sunfish-boot.sh k301b work/kernel301/kernel.development.sweet ...`. Not booted yet.
### 2026-11-13 09:50 k301a: first kernel301 RAM boot: no output, back in fastboot within ~1 min (reset, logged)
- Cmdline: `debug=0xc serial=3 cpus=8 keepsyms=1 -enable_kprintf_spam -noprogress rd=ufsroot0 unentitled_ios_sim_launch=1
  ignition_level=1 wdt_test=no_user_checkin launchd_unsecure_cache=1 wdt=-1 sweetmotion=0x4bf sweetrtcoff=... -v sweetgpu=0
  sweetmtl=0 ufsrw=0 rootrw=0` (iOS 16 ADT/shim via sunfish-boot.sh). Battery 4457 mV.
- Storage safe by construction (OBS source): ufsrw=0 -> sweet_ufs.c:765/830 su.writable=0, writes refused :297, EROFS :456;
  cmdline keys beat 1244's baked defaults (bootargs.c:211-218); sunfish-boot.sh drops base keys an extra arg repeats.
- Result (OBS): not one line on the USB/serial log after the boot marker; webcam at 60 s black; `fastboot devices` saw the
  phone again at 09:47. Where it died is unknown (shim handoff, early fault before console, or a watchdog).
- iOS 16 kernel167 booted right after (k167back, 4456 mV, SSH in 17 s); the webcam frame showed the verbose console, not yet
  the lock screen (as at 07:11 this morning; not rechecked).
- Next: analysis of the boot path for a 12377 kernel (shim/Mach-O/boot_args vs Hot's loader), then an early-fb-console boot.

### 2026-11-13 09:45 GATE B PASSED: kernel301 builds (Sequoia VM, builder)
- `VM_DIR=~/VMs/macos15 MACOS_VERSION=26.5 XC=/Applications/Xcode_26.1.app PATCH_DIR=xnu/patches-12377 KDK_MODE=fake
  tools/vm-build-xnu.sh 301 --clean` (8b64b9d: 26.x mirrors IOS-26-Hot's CI, dxb bd88697): exit 0, 372 s (patch stage 6 s,
  make 347 s). 7 stage scripts ran, 147/147 of our patches applied; dxb applied add_iboot_header +
  dsymutil_no_process_substitution (link_kdk, disable_bti_vmapple, remove_applefeatures_include, simplify_san_lipo not
  logged: skipped as in Hot's CI, not verified).
- Root cause of try 1's 0004 failure (OBS, host repro): dxb 6639065's patches() sed rewrites INCFLAGS_SDK (MakeInc.def:1227,
  four-space indent) before our patches; bd88697's tab-only sed leaves it and 0004 adds the FAKEROOT include itself.
- work/kernel301/kernel.development.sweet: 21254232 bytes, Mach-O arm64 PIE, "Darwin Kernel Version 25.5.0 ...
  DEVELOPMENT_ARM64_SWEET". Not booted. Next: Gate C (RAM boot to serial launchd); first boots need sweetgpu=0 sweetmtl=0.

### 2026-11-13 09:45 Gate B try 1 (Sequoia VM, builder): FAILED on build plumbing, no kernel
- VM: macOS 15.8.3 24H241, Xcode 26.1 17B55, iOS 26.1 SDK (~/VMs/macos15, 42 GB; 1.5 h install). Network OK in the VM.
- kernel300 (stock, MACHINE_CONFIG=VMAPPLE, stage scripts only): make ran 2508 s, then `TrustCache/API.h` and
  `CoreEntitlements/V2/API.h` not found: Hot's stage scripts 0000/0001 stage headers only for SWEET. VMAPPLE smoke dropped.
- kernel301 (SWEET, xnu/patches-12377): stage scripts OK, dxb link_kdk + remove_applefeatures_include skipped, then our
  fail-fast stopped at sweet-0004-sweet-machine-config.patch (makedefs/MakeInc.def:1227) after 36 s. GUESS: our dxb pin
  6639065 vs Hot's CI bd88697 (and Hot's own build.sh patch loop). Fix: mirror Hot's xnu.yml for 26.x (implementer).
- Script fixes from the builder: stage-only PATCH_DIR (`ls *.patch` under set -e), output glob kernel.development.*.

### 2026-11-13 09:20 Root decision: iOS 27.2.1 (one Fable investigator; research/notes/dyld27-proof-2026-11-13.md)
- The 3,583 unproven words of 27's hot sample were not missing roots (OBS): (1) dyld/libobjc/pthread hold 250 undecodable
  words 0xd5940000/0xd5900040/0xd5900020 next to `mrs x8, S3_3_C4_C0_3` (431 sites), all gated by commpage byte 0xc10c == 4
  (new TPRO mode in 27; 2/3 = 26's msr S3_6_C15_C1_5 path, 0 = skip); (2) 27 moved objc stubs out of the images into
  unowned exec bytes after libobjcMsgSendN.dylib's __text (10,336 PAC words there, missed by section-based sweeps);
  (3) a prover edge case: a noreturn bl at the end of __text.
- Prototype switches --tpro, --gaps, --noreturn-end (~30 lines over zeta's prover; scripts copied to
  research/notes/dyld27-proof-scripts/): 27 hot set 3,583 -> 1 unproven (the libsystem_m float constant, also in 26);
  26 control unchanged. Without them 1,619 + 1,947 real PAC words (RETAB/BLRAA/PACIA) would SIGILL on the A76.
- Kernel: commpage 0xc10c = 0; optional EL0 undef emulation of `mrs S3_3_C4_C0_3` -> 0. Stage 4: fold the switches into a
  tools/ prover and run the whole cache per image (WebCore needs > 4 GB), GUESS 0.5 day.

### 2026-11-13 08:45 Stage 2 donor census: Gate A PASSED for 23G90 (26.6.2) and 24B156 (27.2.1) (one investigator)
- Full tables: research/notes/donor-census-2026-11-13.md. Whole-cache linear sweep (26 | 27, includes data words):
  non-hint PAC 29.63M | 34.36M (zeta audit 29.52M | 34.27M); BRAA x16,x17 in TEXT_STUBS 105,678 | 10,208 (27 nearly drops
  __auth_stubs); writeback LDRAA 1,344 | 17, PACGA 687 | 732 (emulate); FJCVTZS 535 | 1,130, FCMA 25,274 | 25,270
  (emulate, allowed); LRCPC2 14 | 13, CSSC 503 | 633, MOPS 3 | 3, BF16 1,179 | 1,200, I8MM 487 | 694, SHA3/512 1,385 |
  1,420, FHM 112 | 180, MTE 13,393 | 14,293; SVE/SME/SME2/AMX 0.2-0.8M each (Accelerate, GUESS gated by hw.cpufamily).
- Hot images (prover, 49/50): UIKitCore, CoreFoundation, Foundation, libobjc, libswiftCore, CoreBluetooth, libdispatch,
  libxpc hold no non-native non-PAC code. Gated (OBS sites): DIT/SB (commpage bits 57/45), SHA512 in dyld (bit 31),
  CNTVCTSS (timebase type), MTE (runtime flags), TPRO sysreg (commpage 0xc10c). Not gated: FJCVTZS in JSC C++ (JIT probes
  FEAT_JSCVT). Prover first pass: proven 1,075,125 | 1,009,906, unlowerable 0 | 0, unproven 1 | 3,583 (27: CoreText
  1,947, dyld 1,619: real code, dyld has unwind info for 273 of 3,423 functions). WebCore OOM at 4 GB: not proven.
- Bluetooth (both): bluetoothd reads BT_HCI_TRANSPORT/BT_BAUDRATE env, then plist, then the ADT (iPhone12,1:
  /arm-io/bluetooth transport-encoding 7 = PCIE Skywalk, BCM4378); boot-arg `bt-transport-override=N`; POSIX
  "name,baud" defaults to com.apple.uart.sk.bluetooth, other names take the termios path our 0226 kctl serves, so
  H4BC:POSIX:com.apple.uart.bluetooth works unchanged (GUESS until booted). 0xfe3b asserts are send-side, no reply-length
  check (the 251-byte pad may not be needed); 0xfdf0 not found. bluetoothd job: no args, user mobile, 15 MachServices; the
  signed xpc/launchd.plist (.sig) holds the jobs.
- Kernels: 23G90 = xnu-12377.162.14; 24B156 = xnu-13432.42.3; the 8 syscalls present in 27, nosys in 26; 535
  objc_bp_assist_cfg_np -> enosys in 27; Mach traps equal.
- Root: 27.2.1 if the full two-pass prover (or a <= 1 day prover fix) proves 27's dyld, else 26.6.2 (judgement).
- New stage 3 kernel items: clear DIT/SB/SHA512/SHA3/JSCVT/FCMA commpage bits, commpage 0xc10c = 0, timebase without
  CNTVCTSS, a hw.cpufamily that keeps Accelerate off AMX/SME/BF16 paths, FEAT_JSCVT = 0. Open: launchd.plist.sig
  enforcement on 26/27, BT plist fallback key.

### 2026-11-13 08:50 xnu/patches-12377: first Gate C series assembled (implementer; not built yet)
- work/src/xnu-12377 branch sunfish-12377 HEAD 36b58f5 (148 commits above tag stage12377 = stage-script output + dxb 26.0
  patches). Exported: 7 stage scripts (Hot 0000/0001/0019/0020/0026/0058 + our 0002 firehose compat header = dxb bd88697's
  stub, so Hot 0134 applies on our dxb 6639065), Hot 0003-0124 (116, byte-identical; IOS-26-Hot d249939, MIT), 0125/0126
  (our cluster table + mirror PA lines from 0086/0089), Hot 0129-0137 + 0139-0141 (12), 0199 UniXNU darwin27 syscalls
  (7d85ede, BSD-2-Clause-Patent), ours renumbered +1000: 1125 1127 1151 1175 1176 1184-1187 1191 1192 1198 1244 1246
  1279 1281 (fuzz re-exported: 1175 1186 1281). Out: Hot 0142 (built on 0138; Gate D), ours 0189/0269 (need 0179 WDT),
  0206/0207 (A618 GPU chain), 0280 (needs 0126/0242). BTI_ENFORCED 0 is already in Hot's 0004.
- Fresh apply in dxb order (stage scripts run, KDK_MODE=fake layout): 153 applied (6 dxb + 147 ours), tree hash = HEAD.
- vm-build-xnu.sh (15.x/26.x only): a failing sweet-* patch now stops the build (dxb skips silently; Hot's CI is
  fail-fast); the Sonoma path is unchanged.
- First boots will need `sweetgpu=0 sweetmtl=0` (1244's iOS 16 defaults turn the GPU on). Untested: compile with Xcode 26.1,
  kmutil build_kc on an empty no-kdk, network for the stage scripts in the VM.

### 2026-11-13 08:20 Stage 3 rebase map (one Fable investigator, read-only; research/notes/rebase-map-12377-2026-11-13.md)
- Base CHANGED (OBS): IOS-26-Hot `xnu/patches-26` (dipa-studio, MIT; the ios-sweet author's own port of the whole sweet +
  flame 0003-0124 to xnu-12377.121.6, MACOS_VERSION 26.5) applies 116/116 clean on 12377 (+ its stage scripts 0000
  CoreEntitlements V2 without KDK, 0001 TrustCache, libpthread/hfs/IOHIDFamily-2238 pins), plus an iOS 26 generic layer
  0129-0142 (arm64e exec/shared region, sleh PAC emulator, build fixes, IOMFB swap, IOSurface ABI), 0145 apple80211, 0148
  keystore. Scion's xnu-12377-starlte branch only carries 56 Apple-file halves of ios-sweet 0003-0080: second opinion, not base.
- Our copies of 0086/0089 hide two sunfish edits Hot lacks (cluster table A55x6/A76x2, SWEET_MIRROR_PA 0x1fa000000) +
  SWEET.h BTI_ENFORCED 0: to re-add. Obsolete on 26: our 0001/0002 (Xcode 15 clang), 0005, 0082.
- Our 0125-0285 on Hot base + UniXNU darwin26-syscalls (BSD-2-Clause-Patent, clean): 143 clean, 6 fuzz, 11 conflict
  (cpufreq chain 0255 cascade ~7 h; HID/motion 0228/0243/0245 on Hot's 160-byte HID ~14 h; Hot-layer merges 8-14 h).
  0160 = 11 real lines (IOMFB log) + the vendored 8796 iokit tree: re-add by hand. GUESS: 3-5 days mechanical, 7-12 to Gate C.
- Next: xnu/patches-12377 assembled for Gate C (Hot 0000-0124 + 3 sunfish edits + Hot 0129-0142 subset + 0199 syscalls +
  20 sunfish patches renumbered +1000), implementer running.

### 2026-11-13 07:45 Stage 1 build host: scripts, regression build, Sequoia VM prep; stage 2 inputs
- VM scripts take VM_DIR, VM_INSTALL_IMG, OSX_KVM_DIR, VM_MEM/CPUS/SSH_PORT/VNC, VM_PIN_FIRST, MACOS_VERSION, XC,
  PATCH_DIR, KDK_MODE=kdk|fake (9854602 + VM_INSTALL_IMG); vm-guard.sh refuses a second live VM (test: a fake sibling
  qemu.pid with a live pid -> vm-start.sh, mac-vm.sh, vm-build-xnu.sh all exit 1 before starting anything).
- Regression (OBS): `tools/vm-build-xnu.sh 167` with no env -> kernel.development.sweet 17553504 bytes, sha256 275e53a8...
  byte-identical to the previous kernel167 (patch 18 s, make 33 s, VM resume 96 s). No boot needed.
- KDK_MODE=fake follows Bergamota's xnu.yml (KDKROOT = empty dir, drops dxb's 00_setup_coreentitlements.sh, needs our own
  CoreEntitlements stage script in PATCH_DIR); untested until Gate B. 26.x/15.x copy patches into dxb patches/26.0|15.0.
- Sequoia recovery (the user OK'd the download, 07:00): fetch-macOS-v2.py -s sequoia, 884 MB BaseSystem.dmg, chunklist
  verified (85 chunks). Note: the script ignored -o and overwrote ~/VMs/OSX-KVM/BaseSystem.dmg (the Sonoma .dmg; Sonoma's
  converted BaseSystem.img, Oct 28, is untouched); moved to ~/VMs/macos15/recovery/. Empty 128G qcow2 + OVMF vars made.
  macOS + Xcode 26.1 install delegated (one agent, GUI over QMP/VNC).
- Gate B source: apple-oss-distributions/xnu tag xnu-12377.121.6 (ac9718f) shallow-cloned to work/src/xnu-12377 (117 MB).
- Stage 2 inputs: both IPSWs extracted with ipsw 3.1.739 to ../restore/ipsw/x/{23G90,24B156} (kernelcache, devicetree,
  arm64e dsc, bluetoothd/BlueTool/audioaccessoryd/bluetoothuserd/BTLEServer/BTAudioHALPlugin, launchd + plists;
  5.9 + 7.0 GB). Census running (one investigator).

### 2026-11-13 06:40 Research rounds 1-2 (workflows, read-only)
Round 1 (6 researchers + skeptic, Fable) and round 2 (build infra, GiaSen recipe, Qualcomm Bluetooth, iOS 27 route).
Prior art (OBS/CLM in the note): GiaSen Mi 8 SDM845 iOS 26.6.2 to Home (CLM, bluetoothd up, no pairing tried);
UniXNU-zeta Surface Duo 2 iOS 26.5.2 laggy Home (OBS README); Scion Galaxy S9 iOS 27.0.1 trap-heavy (CLM); IOS-26-Hot
SD855 kernel CI real, desktop results unverifiable (OBS timestamps); AirPods on 27 only on hardware PAC (UniXNU sheng,
OBS records). marnov999/ios26-sweet (same SoC) has built nothing. Corrections in round 2: build infra 1-1.5 days with a
second VM; btbridge vendor-reply pad must grow 8 -> 251 bytes for iOS 26 bluetoothd (CLM GiaSen bcm_vsc); Scion measured
27.0.1's cache (no CSSC/MOPS, CLM). Plan: docs/plan.md stages 0-7, gates A-E.
