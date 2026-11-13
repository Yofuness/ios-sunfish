# Plan (2026-11-02): hardware video decode, apps and games

Rules: CLAUDE.md ("How to work"). Old plan: `docs/plans/2026-11-02-speed-and-heat.md`. One line per item;
details and history in the feature Logs (`docs/features/<name>.md`).

## Focus (the user, 2026-11-02)
Make more things work: video in apps like Instagram first (hardware decode), then games and App Store apps.
Interface speed and heat are good enough for daily use (Settings ~57 swaps/s, Control Center 43.8, peaks ~82 C);
the speed focus is over. Targets (Claude's numbers, the user can change them):
- Video: a 1080p H.264 video plays smoothly in Safari with hardware decode, CPU under 15 % of one core.
- 3D: a WebGL game in Safari runs 15 min without a GPU hang.
- Apps: one free App Store app installs and runs (gate for Instagram, Crossy Road, Minecraft).
- Stability: under 1 GPU hang per hour of soak.

## Test schedule
- Normal test runs: 15 min at most. A/B comparisons: 5 boots per side (tools/sunfish-perfab.sh).
- One 1 h soak per night, after `work/night` is set (9:30 pm or when the user says); results in [gpu-bugs.md](gpu-bugs.md).
- A run with a hang, a backboardd restart, the panel off or 0 swaps is void.
- Stop rule: a gain under 1 ms counts only if a 5-boot A/B confirms it.

## Priority (a couple at a time, dev speed on top; ▶ = being worked; ~half a day max each, except stage work of item 1)
Only items Claude can move now. User tasks are listed below and never gate work; parked ones in docs/backlog.md.
1. ▶ **Hardware video decode** (Snapdragon 730G video engine, "Venus"), in stages, each a go/no-go (video.md):
   0. Done 2026-11-03: all 4 clips play in software, 250-590 % of one core, max 64 C (video.md s0).
   1. Done 2026-11-02: research, staged spec in video.md (PAS ID 9, HFI gen1, plugin slot ExampleIPB.videodecoder).
   2. Done 2026-11-03: firmware boots, H.264 session opens/closes; 10/10 rounds idle, 29/29 under 15 min UI load (s7c).
   3. Done 2026-11-03 (v3e): `venusctl decode` bit-exact vs ffmpeg at 320x240 and 1280x720. Left: speed on a long clip.
   4. ▶ Done 2026-11-03: 4a venusd, 4b VT plugin, 4c Safari H.264 via Venus, venusd at boot + recovery. 2026-11-12: picture
      right (B62 was the flame-shot), no lag, start gap ~0.5 s. 4d: done 2026-11-13: GPU path is the default
      (SWEET_YCBCR_GPU=1 via install-speed; 15 min 1080p 14/24239 dropped, backboardd ~20 %; 720p/HEVC/camera ok). Left: B64
      (4 video tabs: GPU pool OOM -> WebKit.GPU crash), B63 (camera mediaserverd 500-600 %). 4e HEVC.
   5. Tuning: heat, 4K, several streams at once (feeds).
2. **3D**: done 2026-11-03: three.js games_fps (WebGL 2) 15 min, 0 hangs (7.4 fps). Left: speed.
3. **Wi-Fi throughput** (B57): 0.53 -> 3.0 (Interactive) -> 5.8 MB/s (HT20, ht1) on 2026-11-03. Next: wland's CPU
   (~68 % at 5.8 MB/s: ~10 pmem syscalls + one write per frame).
4. **App Store access**: blocked on device attestation (B56: FairPlay/Anisette fail, media token 401); waiting for the
   user's decision (Questions). Meanwhile: WebGL speed (games_fps 7 fps, GPU-bound).
5. **GPU stability**: G1 (no recovery) and G4 (backboardd restart); nightly soak; fix whichever rises (gpu.md).
6. **Garbled and undrawn images** (B44, B53): Notes attachments, Maps glitch (Safari tab tiles mostly draw now, B53).
7. **Upstream takeaways** (2026-11-12, best first; backlog U12-*): done 2026-11-12: keep VkDevice (0112, A/B 2/2),
   isb (0281), [device limits] filled (0132, 38/39 fields; check Photos/B44 next); U12-1b bridge 0133 (A/B 2/2, kept on); YCbCr sampled in place (video CPU, 6-10 h),
   cheap checks: submit cuts, FS constlen, cold cache, MSAA A/B. Older items: "Upstream" below.

After these: small Metal test apps built here (textured cube with depth, compute), then Crossy Road (Unity), Instagram,
Minecraft. Likely needed on the way: YUV surfaces in the bridge (G7 "planar iosurface refused"), louder speaker (B16),
a GPU stand-in for the missing colour-convert/scale hardware (helps Photos too; cpu.md phs).

## GPU bugs
Listed with exact log lines and rates in [gpu-bugs.md](gpu-bugs.md) (not auto-loaded). Fix one when it voids tests,
stops phone work, or doubles in rate after a change (then turn that change off first).

## Phone
Claude's since 2026-11-12 21:03 (the user). Booted t167z (2026-11-13 04:30): kernel167 (= kernel162 + xnu 0281 isb, 0282 GetStatus NotReady after a
failed recovery, 0283 atomic flame-shot, 0284 G2 submit logging, 0285 lost span), bundle c916fe4+ (+ Turnip 0112 keep VkDevice, 0113 G2 fix,
frontend 0132 device limits, 0135 snapshot sync, 0136, bridge 0133 restart redo, 0134, Turnip 0114 CS OOM sink), venusd/vtvenus 6a24d64 (stall detectors, VT QoS), wland 206585d
(HT20, Interactive, bounds checks), camd + hapticd Interactive, cam41. Everyday boot: `tools/sunfish-test.sh -k 167 TAG sweetse9=2 sweetcampmic=2 sweetswapbig=6
sweetampreset=1 sweetpmemwc=2 sweetgpucap=512 sweetgpukill=0` (sweetgpukill=0 since 2026-11-12: backboardd survives recovered hangs with 0112; t166z was booted without it). /var/local/mtl2-env = SWEET_U0011..14=1,
SWEET_SURF_FLUSH=1, SWEET_CULL=3, SWEET_YCBCR_GPU=1 (TU_FETCH_GMEM_MIN_DRAWS=20 removed: G8) (tools/sunfish-install-speed.sh); backboardd env CA_DISABLE_LUMA_BOOST=1 CA_FORCE_TIMER=1.

## Next (in this order)
0. 2026-11-13 05:00: a) done: GPU video path default (video.md 05:00). b) G2: Turnip 0113 installed, watch soaks for
   "submit bad". c) B53 mostly works (disk cache; gpu.md 04:55). d) Turnip 0114 installed (t167z): forced refusals don't
   crash; B64 = new OOM crash site with 4 video tabs (A/B + analysis running). e) Night soak tonight on kernel167 + 0114.
1. Wi-Fi CPU: userland batching (356c09a) didn't help (bat, 20:40); the per-frame reads + one /dev/wlan write per frame
   dominate: a kernel batched input path is the next step (parked behind the items below).
2. Video CPU: credit path done (mediaserverd 55 -> 20, venusd 32 -> 10, 0 drops). Left: backboardd ~45 (vImage; bridge 0131
   in-place GPU conversion: backboardd 47 -> 16 % but 492/899 dropped, a stall: not kept), network ~40, the first-session "error -60 at frame 17" resync.
3. Done: launchd Interactive A/B: camd (open 5.7 -> 0.7 s, 30 fps) and hapticd kept; sensors, btbridge cost CPU, reverted.
4. GPU: suspect link Venus session start → GPU fault (2 of ~5 hangs today); B53 render-server snapshots intermittently
   empty; B50 Maps; WebGL speed (Optimize).
5. Night soak n9 done 2026-11-12 (kernel163): 60 min, 0 RPMh/SPMI/G1/G4, 1 G2 + backboardd restart (void). Next soak: kernel166 + sweetgpukill=0.

## User tasks (details in user-tasks.md; nothing waits on these)
proximity by hand (U17), battery discharge (U3), headphone plug test (U15), Files check (U13), touch while plugged in (U14).
Parked for later (the user, 2026-10-30): Compass accuracy, camera far focus, auto-brightness (B42), headphone jack iOS side.
Back in play now the speed focus is over: speaker volume (B16), garbled images (B44), stale clock (B49), battery + camera
CPU (O14), camera polish (B48).
Finished items: [completed.md](completed.md) (not auto-loaded).

## Upstream, older (2026-11-01; details in backlog.md; new ones go on Priority 7)
- Touch poll under 8 ms while touched (hakios-xnu 6d8f818; ~3.5 ms input lag, guess; needs a latency tool).
- RPMh try-lock: retry on EBUSY, a vote can fail silently now (0.5 h; found reading ours for e5b01a0).
- xpcproxy identity version (hakios-xnu 78b518b): first count the errors in one Safari oslog.
- Privilege table (hakios-xnu 502aee8, 2 h): may wake daemons quieted for heat, watch idle CPU.
- Speaker guard for louder sound (315e973, 3-5 h), iOS microphone (2bb073e, 1-2 days, B23 risk): with B16.
- Driver review reports: wifi/ADSP findings fixed (d7f8d59, to install + check); camera ring (1800069), battery, cpufreq not checked.

## Questions for you (Claude took the recommended path meanwhile)
- App Store (B56): it fails on Apple's device attestation (FairPlay hardware info -42184, Anisette -45061, media token
  401), not on the network. Getting past it means making the phone present an Apple device identity to Apple's
  servers (spoofing FairPlay/Anisette data), which circumvents Apple's DRM/attestation and is likely against Apple's
  terms. Claude has not started on it. Do you want this pursued, and if so within what limits? (Parked meanwhile.)
- PowerLog and CoreDuet databases on the phone were moved aside (not deleted) to /var/local/idlefix-db, to stop the idle
  CPU burn; `tools/sunfish-idlefix-db.sh --undo` restores them. OK to delete them later? (Kept for now.)

## Your tasks at the phone
In [user-tasks.md](user-tasks.md) (not auto-loaded): 11 open. Claude doesn't wait on them; it moves to the next item.

## Dev speed (on top of the priority list when found; ~1 h max each)
- (none)

## Backlog
The Broken, Later and Optimize lists are in [backlog.md](backlog.md) (not auto-loaded); leftover speed items in Optimize.

## Verification
Each item: numbers in the feature Log, this plan and the README status table in the same commit, a journal line,
a webcam check for anything visible, battery ≥ 3600 mV before each boot.
