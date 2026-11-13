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
### 2026-11-13 07:20 Research rounds 1-2 (workflows, read-only)
Round 1 (6 researchers + skeptic, Fable) and round 2 (build infra, GiaSen recipe, Qualcomm Bluetooth, iOS 27 route).
Prior art (OBS/CLM in the note): GiaSen Mi 8 SDM845 iOS 26.6.2 to Home (CLM, bluetoothd up, no pairing tried);
UniXNU-zeta Surface Duo 2 iOS 26.5.2 laggy Home (OBS README); Scion Galaxy S9 iOS 27.0.1 trap-heavy (CLM); IOS-26-Hot
SD855 kernel CI real, desktop results unverifiable (OBS timestamps); AirPods on 27 only on hardware PAC (UniXNU sheng,
OBS records). marnov999/ios26-sweet (same SoC) has built nothing. Corrections in round 2: build infra 1-1.5 days with a
second VM; btbridge vendor-reply pad must grow 8 -> 251 bytes for iOS 26 bluetoothd (CLM GiaSen bcm_vsc); Scion measured
27.0.1's cache (no CSSC/MOPS, CLM). Plan: docs/plan.md stages 0-7, gates A-E.
