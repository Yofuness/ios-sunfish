# Plan (2026-11-13): iOS 27 (on the iOS 26 kernel) for LibrePods work

Rules: CLAUDE.md ("How to work"). Old plan: `docs/plans/2026-11-13-video-apps-games.md`. One line per item; details in
the feature Logs: [ios26.md](features/ios26.md) (this port), bluetooth.md. Research: `research/notes/ios26-27-feasibility-2026-11-13.md`
(sections 9-10 are current; read 10 before each stage).

## Focus (the user, 2026-11-13)
Use this phone for LibrePods (AirPods protocol) development: it needs a current iOS. Target iOS 27; iOS 26 first only if
it is the better route. Facts (research, OBS unless marked): iOS 17+ is arm64e-only; the 730G has no PAC, so the userland
is PAC-lowered offline (zeta's prover, GiaSen's recipe) and the rest emulated in the kernel; three non-PAC ports boot iOS 26,
one boots 27 (slow). No iOS 27 xnu source (Apple silent since 2026-06-18): 26 and 27 both run on xnu-12377.121.6 + 8 Darwin
27 syscalls (UniXNU patch), so one kernel line serves both; the root (27.2.1 or 26.6.2) is chosen at Gate A. Nobody has
paired AirPods on iOS 26/27 without hardware PAC: that is our deliverable. GUESS: Gate E in 25-45 working days.
Targets: AirPods Pro 2 paired on iOS 27 (or 26), A2DP plays, AACP session captured and decoded (btsnoop); iOS 16 stays
bootable until iOS 26/27 is daily-usable (every boot is RAM-only; never flash).

## The user's decisions (2026-11-13)
- New direction approved; iPhone 11 (iPhone12,1) IPSWs approved (26.6.2 23G90 and 27.2.1 24B156 downloaded to
  ../restore/ipsw, sha1 in iphone12,1.sha1; 27.0.1 24A446 may be fetched too if 27.2.1's census fails).
- iOS 16's data area (/var, ufsroot1) may be wiped entirely if the new root needs the space. Still: check the target,
  write a dated log line first, keep docs/recovery.md working, never flash or relock.

## Stages (go/no-go gates; ▶ = being worked; stage work is exempt from the half-day limit, sub-steps are not)
0. **iOS 16 btsnoop**: capture DONE (d61f019, validated bt0snoop 07:20: 2391 HCI records, tshark + apple-wireshark OK;
   bluetooth.md State fixed). AirPods session: when the user says they're home (U-AP1 closed). ▶ Now: phone <-> laptop
   ("glizzy") pairing test with btsnoop on; flag /var/local/btbridge.snoop off afterwards.
1. ▶ **Build host** (1-1.5 d): scripts DONE (9854602, kernel167 byte-identical); parameterise tools/vm-build-xnu.sh + tools/macos-vm/* (VM_DIR, MACOS_VERSION, XC, PATCH_DIR,
   KDK_MODE=fake), guard against a second live VM; then a second VM `~/VMs/macos15` (Sequoia 15.7 + Xcode 26.1, 40-50 GB).
   Xcode 26.1 is on disk: ../restore/xcode/Xcode_26.1_Universal.xip (the user, 2026-11-13 06:55). **Gate B:** stock
   xnu-12377.121.6 DEVELOPMENT links (VMAPPLE smoke test, then SWEET).
2. **Donor census**: **Gate A PASSED both** (2026-11-13 08:45, research/notes/donor-census-2026-11-13.md). Root 27.2.1 if the
   full prover proves 27's dyld (3,583 unproven words in the hot sample: dyld 1,619, CoreText 1,947; weak unwind info),
   else 26.6.2. Kernel must hide DIT/SB/SHA512/SHA3/JSCVT/FCMA commpage bits, 0xc10c = 0, no CNTVCTSS timebase, a safe
   hw.cpufamily. BT: BT_HCI_TRANSPORT env + bt-transport-override boot-arg in both; our H4BC:POSIX string fits.
3. **Kernel rebase** (7-12 d): base = IOS-26-Hot xnu/patches-26 (MIT, 116/116 clean on 12377; rebase map 2026-11-13) [was: Scion's layer], UniXNU's 8-syscall patch, our 0125-0285
   without 0160's vendored tree, PAC layer (zeta plain-auth + an EL0 emulator), GiaSen facts re-implemented (no licence:
   ideas only). New tree work/src/xnu-12377, patches xnu/patches-12377/. **Gate C:** RAM-booted kernel reaches serial
   launchd, then SSH over USB-ECM, on a rewritten root in its own region; iOS 16 still boots.
4. **Root pipeline** (2-4 d, inside 3): mkiosroot for the new IPSW + PAC rewrite incl. TEXT_STUBS (BRAA x16,x17), ad hoc
   signing / trust cache, N104 ADT (random-seed, CTRR props), HFSX >= 24 GB in its own userdata region (iOS 16 /var may go).
5. **Desktop** (10-15 d): IOMFB/IOSurface/HID (160-byte records) ABI, identity, AMFI/keystore, Wi-Fi (wland), software
   compositing first, then the Metal bridge. **Gate D:** SpringBoard Home + touch, no backboardd loop, 15 min without a hang.
6. **Bluetooth + AirPods** (5-10 d; note s9.3): 0226 kctl + exec_env/exec_swap boot-args, 251-byte vendor-reply pad
   (btbridge.c:66), BlueTool deepsleep, keystore cap (0123), 0231 + BTAudioHALPlugin, pair, btsnoop. **Gate E:** AirPods
   paired, survive a reboot, A2DP plays, AACP handshake + 0x4D decoded. The LibrePods deliverable.
7. **Parity** (open): camera, video (Venus), haptics, audio polish on the new root; the other root version if useful.
Switches: 27 -> 26.6.2 root if a 27 root stalls > 3 days before Gate D on an ABI break 26 lacks; 26 -> 27 after Gate E
when 27's census is clean. xnu-13 source appearing changes nothing before Gate E (the daily upstream check watches it).

## Next (in this order; a fresh /loop session starts here)
1. Stage 0 btsnoop (implementer for btbridge, builder, one phone-runner boot). 2. Stage 2 census in parallel (one
investigator; both IPSWs are on disk, sha1 verified; extracted files under ../restore/ipsw/x/, out of git).
3. Stage 1: VM script parameterisation, then the Sequoia 15.7 VM with Xcode 26.1 (on disk).
4. Done 2026-11-13 07:20: gpu15e: 4 video tabs no longer crash; SWEET_YCBCR_GPU=1 default again (video.md). iOS 16 parked.

## Phone
Claude's (the user, away 2026-11-13). iOS 16 everyday boot: `tools/sunfish-test.sh -k 167 TAG sweetse9=2 sweetcampmic=2
sweetswapbig=6 sweetampreset=1 sweetpmemwc=2 sweetgpucap=512 sweetgpukill=0`; kernel167, bundle with Turnip 0114/0115 +
bridge 0137 (gpu15e); mtl2-env SWEET_U0011..14=1, SWEET_SURF_FLUSH=1, SWEET_CULL=3 SWEET_YCBCR_GPU=1 (default again 2026-11-13).
Never kill mediaserverd/camd in tests (hard reset 2026-11-13 05:10): reboot instead.

## Questions for you (Claude took the recommended path meanwhile)
- App Store (B56, attestation spoofing) and the PowerLog/CoreDuet deletion: still open, parked with the old plan.

## Your tasks at the phone
In [user-tasks.md](user-tasks.md): U-X26 done (Xcode 26.1); U-AP1 closed (AirPods capture waits for the user to be home); the old iOS 16 ones are parked.

## Backlog
Broken/Later/Optimize in [backlog.md](backlog.md); iOS 16 items stay there, parked by the new direction.

## Verification
Each stage: numbers in features/ios26.md's Log, this plan and the README status table in the same commit, a journal
line, a webcam frame after every boot, battery >= 3600 mV before each boot, `=== TAG` markers per run.
