# iOS 26 / 27 port (arm64e userland on a non-PAC SM7150)

**State:** 🔬 Research done 2026-11-13 (research/notes/ios26-27-feasibility-2026-11-13.md, sections 9-10 current): one
kernel line (xnu-12377.121.6 + 8 Darwin 27 syscalls) for both; root iOS 27.2.1 or 26.6.2 (iPhone12,1) chosen at Gate A;
stage 0 (iOS 16 btsnoop) next. **Updated:** 2026-11-13.

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
