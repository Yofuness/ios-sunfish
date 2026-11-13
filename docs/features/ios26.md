# iOS 26 / 27 port (arm64e userland on a non-PAC SM7150)

**State:** 🔬 Gate A passed for both roots (2026-11-13); root = iOS 27.2.1 (24B156; its dyld proves with 3 prover fixes). Kernel series
**Gate B passed**; kernel301 (xnu-12377.121.6 + xnu/patches-12377) BOOTS on the phone with the --xnu12377 ADT: 8/8
CPUs, UFS, HFS root mounted read-only, launchd exec'd (k301b); iOS 16's launchd then dies on a port guard (expected). Stage 0 btsnoop done. **Updated:** 2026-11-13.

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
