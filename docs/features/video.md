# Video playback and hardware decode
**State:** 🟡 Safari plays H.264 720p with Venus hardware decode and the picture is right: an atomic flame-shot of the playing video equals ffmpeg's frame (mean |diff| 1.22; B62 was a capture artefact), 30.0 fps, 0 dropped, no lag behind the page clock in two 65 s runs (2026-11-12). Earlier: software decode 250-590 % of one core; hardware decode: research done, decoder slot loads, the Venus engine decodes H.264 bit-exact from a phone tool, 1080p at 217 fps raw, VideoToolbox decodes H.264 through our plugin in mediaserverd, 1080p 60 fps, bit-exact (stage 4b). **Updated:** 2026-11-12.

## Facts
- The iPhone X decodes video in hardware (AppleAVD); the port has no AVD, so iOS falls back to software decoders.
  mediaserverd's CPU in Photos is probably software HEVC (VCPHEVC; a guess, cpu.md 2026-11-02 phs).
- Colour conversion and scaling (VideoToolbox pixel transfer) run in software on every core: no AppleM2ScalerCSCDriver
  (cpu.md phs, vts). The graph-path preference crashes Photos (cpu.md vt).
- Showing video frames needs YUV (biplanar 420) IOSurfaces in the Metal bridge: GPU bug G7 "planar iosurface refused"
  (gpu-bugs.md).
- The Snapdragon 730G (SM7150) has Qualcomm's video engine ("Venus"); its firmware is Qualcomm's and stays on the phone,
  out of git. Linux's open `venus` driver (HFI protocol) is the reference.
- Sound for video: speaker quiet (B16); AirPods connect but play nothing (audio.md).

## Plan (the user, 2026-11-02: hardware decode first)
Stages, each a go/no-go: 0 Safari baseline on the software path; 1 read-only research and spec; 2 kernel bring-up
(power, firmware via TrustZone, HFI ping); 3 first decoded frame from a phone tool; 4 VideoToolbox decoder plugin
(H.264, then HEVC); 5 tuning (heat, 4K, several streams). Rough size: 2-6 weeks of sessions.

## Hardware (stage 1 research, 2026-11-02; full notes research/notes/venus-stage1-2026-11-02.md)
- SM7150 = sdmmagpie, Venus VPU5/IRIS1, HFI gen1 (Linux venus HFI_VERSION_4XX; no mainline SM7150 entry, the
  downstream 4.14 msm_vidc driver is the reference, research/ext/msm-vidc-sunfish/).
- Core 0x0aa00000 +0x200000, wrapper 0xaae0000, IRQ SPI 174 level. videocc 0x0ab00000: GDSCs mvsc +0x814, mvs0 +0x874,
  mvs1 (CVP) +0x8b4; all need gcc_video_ahb (GCC+0xb004). Clocks videocc mvsc_ctl_axi 0x9cc, mvs0_axi 0x9ec, mvsc_core
  0x850, mvs0_core 0x890, venus_ahb 0xa6c, iris_ahb 0x8f4; gcc_video_axi 0xb01c. PLL0 (Fabia, +0x42c) 480 MHz /2 =
  240 MHz, the lowest step (enough for 1080p30, estimate).
- Bus: RPMh BCMs MM3 and MM2, unvoted by anyone else. SMMU: apps SMMU, stream ID 0x1080 mask 0x60 (non-secure); never
  touch 0x1081/0x1083/0x1084. Device VA 0x25800000-0xe0000000.
- Firmware: /vendor/firmware/venus.mdt + .b00-.b04 (VIDEO.IR.1.2-00053), loads at 0x94800000 size 0x500000. TrustZone
  PAS ID 9 (SMC 0x42000200|cmd), then memory protect 0x42000c08 (0, 0x25800000, 0x1000000, 0x24800000).
- Reusable code: PAS loader phone/wifi/adspboot.c (via /dev/pmem PMEM_SMC), RPMh votes by BCM name (sweet_gpu.c),
  Fabia PLL phone/tools/camclk.c, phone/wifi/smmu.c.
- Output: reference frames are UBWC; linear NV12 comes only on OUTPUT2 with the multi-stream property.
- iOS: _VTLoadVideoDecoders dlopens a fixed list; AVD.videodecoder refuses without AppleAVD. Names on the list missing
  from our cache (e.g. /System/Library/VideoDecoders/ExampleIPB.videodecoder, _ExampleIPBDecoderRegister) would load:
  our plugin goes there and registers 'avc1'/'hvc1' as hardware. The path is the flat Mach-O itself (dlopen RTLD_LOCAL,
  then the register symbol is called). Library validation is in effect off (sweet_amfi.c has no LV hook), root FS is
  writable, so an ldid-signed dylib should load (not yet tested). Safari <video> decodes in mediaserverd (AVPlayer remote;
  medium-high confidence), WebCodecs/WebRTC maybe in the GPU process: the plugin must be cheap to load anywhere.
- Firmware source: restore/factory/vendor.img /firmware/venus.{mdt,b00-b04} (1.1 MB), extracted locally to research/fw/venus.

## Stage 2 spec: `venusctl` (userland, /dev/pmem like adspboot; failed tries need no reboot)
1. `probe` (read-only): GCC video clocks, TBU vote/status, SMR scan; videocc only with AHB on.
2. `power on/off`: MM3+MM2 votes, PLL 240 MHz, mvsc then mvs0 GDSC, branch clocks; read HW version at 0xaae0000.
3. `pas-check`: is-supported, init_image(9) with the signature, shutdown. Errors come back as codes.
4. `boot`: exact SMRs, segments to 0x94800000, mem-setup, auth_and_reset, memory protect, read status, shutdown
   (most likely step to reset).
5. `init`: queues (3 MB uncached: header 0x1c8, 3 queues of 0xc8000) + SFR page, registers 0xd2064/68, 0xd2054,
   0xd2050, 0xd205c, 0xd2034-3c; 1 -> 0xd2048, poll 0xd204c bit0.
6. `ping`: SYS_INIT 0x10001 -> 0x20001, SYS_PING 0x210002 -> 0x220002 (not acked by this firmware: a note only).
   `session` (stage 2 go): SYS_SESSION_INIT 0x10007 (decoder 2, H.264 2) -> 0x20006 error 0, SESSION_END 0x10008 -> 0x20007.
   Teardown counts an SMR that reads invalid as released; other register differences are warnings (saved vs read).
7. Steps 4-6 ten times in one boot, then 15 min under GPU load (clean teardown).
Risks: register access with a clock or GDSC off hangs the bus (gate on CBCR/GDSC bit31); auth_and_reset unpowered
resets; masked SMRs reset (camera tests), use exact ones; no MX/CX votes (reset redfin); PAS shutdown before power off.
Open: free memory for queues (0xa5100000-0xbcc00000 looks free, unproven), PMEM_ALLOC32 below 4 GB likely fails,
whether CVP (mvs1) must be on, which of the four stream IDs carry traffic.

## Stage 3 spec: `venusctl decode IN.h264 OUT.yuv [--frames N]` (`tools/sunfish-venus-test.sh decode`)
1. After init: SYS_INIT, SESSION_INIT (decoder, H.264), then downstream's split mode: FRAME_SIZE input, OUTPUT format
   NV12_UBWC (the DPB), MULTI_STREAM OUTPUT2 on / OUTPUT off, FRAME_SIZE + NV12 on OUTPUT2; buffer requirements printed.
2. Counts (input 4, outputs 8 or the firmware's minimum), work mode 1 (up to 720p) / route 2, requirements again;
   SET_BUFFERS scratch, scratch_1, scratch_2, persist, persist_1; LOAD_RESOURCES, START; FTB DPBs (stream 0) + OUTPUT2s (1).
3. Size from the SPS; one access unit per ETB (ENDOFFRAME), then an empty EOS. SEQUENCE_CHANGED: sufficient = CONTINUE,
   insufficient = flush output, new size and buffers, CONTINUE. Stops at N frames, EOS, a session error or 3 s idle.
4. Each FBD: flags, filled length, timestamp, luma CRC32; OUT gets the visible rect as plain NV12. Close: flush all, STOP,
   RELEASE_RESOURCES, RELEASE_BUFFERS, SESSION_END; then the script's shutdown + power off.
5. Buffers: a bump window right after the queue block (0xa5500000, ≤ 64 MB, zeroed), physical = device address.
   Check on the PC: `tools/sunfish-venus-yuvcmp.py REF.nv12 OUT.yuv W H` (ffmpeg reference, work/stage3/).
Switches: VENUSCTL_PRIMARY=1 (linear NV12 on OUTPUT), VENUSCTL_DPB_SETBUF=1, VENUSCTL_ROUTE, VENUSCTL_NOUT, VENUSCTL_YSTRIDE/YSCAN.

## Stage 4 spec (design 2026-11-03, research/notes/venus-stage4-design-2026-11-03.md; read-only, untested)
- Root daemon `venusd` owns Venus (mediaserverd runs as mobile; /dev/pmem is root 0600) + a thin VT plugin client
  (camd/camera_client.c pattern) over a 0666 AF_UNIX socket. VT sessions decode in mediaserverd (remote session).
- Plugin registers like AVD (VTRegisterVideoDecoder 'avc1'), refuses CreateInstance when venusd is down or
  /var/local/venus-off exists, so VT falls back to software (fallback order: medium confidence).
- Frames: the plugin takes CVPixelBuffers ('420v', row align 64, IOSurface) from VT's pool and sends their IOSurface
  IDs; venusd copies each finished frame in. Venus reaches only < 4 GB (identity banks), so no direct write yet.
- Copy speed: pmem pread of the window is ~14 MB/s (device mapping); needs 0233's write-combined mapping (~3.3 ms per
  1080p frame, guess). Buffer window ~160 MB for 1080p (memtest first).
- Steps: 4a0 kernel pmem mapping (2 h) -> 4a venusd + venusc test client, fps on a 60 s 1080p clip (1 day) -> 4b plugin
  + vtdecode (1.5 days) -> 4c Safari (0.5 day) -> 4d GPU YUV->RGB in the bridge (1-2 days; display already works via a
  CPU conversion in bridge 0112, so G7 is not a blocker) -> 4e HEVC 8-bit (0.5-1 day). Zero copy (translating SMMU
  bank + IOSurface page list) is stage 5.

## Open
- Stages 4-5; stage 3 speed numbers. Stage 3 go 2026-11-03 (v3e, bit-exact). Stage 2 complete 2026-11-03 (s7b 10/10 idle, s7c 29/29 under UI load). Stage 2 go 2026-11-03 (v2c). Stage 0 done 2026-11-03 (s0): plays H.264/HEVC 720p/1080p, 250-590 % CPU.

## Log
(Newest first, append-only. When this Log passes about 150 lines, move its oldest entries to the archive.)

### 2026-11-13 03:40 Fable trace analysis: where the GPU path's time goes (corrects 02:15)
Per VIDEO frame command buffer (p50): GPU path 51.1 ms vs CPU path 9.8 ms (observed; the 24.2/9.0 per-frame means of
02:15 mix video and non-video frames). The +41 ms: +25.1 ms in the one full-screen gmem pass, only in the ~20 bins under
the video rectangle (~3,500 vs ~675 us per bin, 5.7x; same 9 draws, 0 sysmem, same pass overhead), likely the video
quad's fragment shader (1801 instructions vs 494 on the CPU path; inferred, no per-draw spans); +13.0 ms in a per-frame
plane-bytes staging chain for an extended-range two-plane surface (fmt 550 'b3a8' 1125x1536 in backboardd, routed to the
GPU only by SWEET_YCBCR_GPU); +3.0 ms the NV12 conversion itself. CORRECTION to 02:15: there is no extra conversion; the
1.40 dispatches per frame are the staging dispatch diluted over non-video frames. Bridge 0134 never ran: its gate
!device_samples() is false on Turnip (derive.rs:822-826), no "SWEET_YCBCR_HWFILTER mode" line (so the exact-filter
theory is untested). Leg A's crash: WebKit.GPU SIGSEGV after the kernel refused it an 8 MB buffer (pool 773/940 MB,
0122's 160 MB reserve): tu_cs_reserve_space fails and Turnip writes through cs->cur == NULL (backboardd held 611 MB).
Next: 0134 gate fix + frontend 0136 (550/551 back to the CPU path), then one traced leg with TU_SWEET_DRAW_TRACE=1.

### 2026-11-13 02:15 Traced A/B: bridge 0134 (hardware filter) does not help; the draws are the cost
n10 boot (kernel167), bundle f7b0c92, 1080p H.264 in Safari inline ~37 s per leg, MESA_GPU_TRACES=print SWEET_PIPESTATS=1.
| leg | GPU busy | backboardd submits/5 s, mean ms | FB fps | dropped (page) | backboardd CPU |
| A GPU path (SWEET_YCBCR_GPU=1, 0131 fast), HWFILTER=0 | 93 % | 97-99, 47-48 | 17.4-17.8 | 494/1051 | ~43 % |
| A2 GPU path, HWFILTER=1 (0134) | 92-93 % | 92-96, 49.0-50.8 | 17.0-18.0 | 514/1105 | ~42 % |
| B CPU path | 31-34 % | 152-167, 10.3-10.8 | 30.4-31.6 | 48/1111 | ~82 % (with trace overhead) |
gputrace-sum ms per frame: render_pass A 24.2 / A2 23.0 / B 9.0; compute A 7.1 / A2 6.6 / B 0; dispatches per frame
1.40 / 1.38 / 0 (confirms an extra conversion on ~40 % of frames); draw_ib_gmem mean 541 / 512 / 198 us. So the ~14 ms
extra per frame is in the draws, and 0134 changed it by ~1 ms only: either the exact routine was not the cost, or 0134
did not take effect (unchecked: no "SWEET_YCBCR_HWFILTER mode" line was looked for). A2's largest FS has 1801 instructions
vs 1031 on B. A2 picture correct (flame-shot vs ffmpeg frame 1291: mean |diff| 2.23). First A attempt: WebKit.GPU SIGSEGV +
backboardd SIGBUS right after the first "YCBCR FAST" line (boot log 4544.9 / 4546.4 s): a GPU-path crash to look at.
Files: work/0131-trace/ (tr.A/A2/B.txt traces, win*.log windows, leg.sh). Next: Fable analysis of these traces.

### 2026-11-13 00:50 Why 0131 cost ~65 ms per frame (read-only analysis of boot 20261103-190010)
Observed: ONE conversion per backboardd submit ("ycbcr converted" 58-69 vs 68-72 submits per 5 s); per conversion one
global full barrier + bind + one dispatch, same 8x8 / 120x68 shape and fetch pattern as readbench (0131 fast.rs);
the RGBA16F image is made once per decoder surface (~20-25 live, 16.6 MB each, no per-frame clear/transition).
But shadow copies run at 2.0x conversions (118/58 ... 131/63 per 5 s) vs 0-5 per 5 s on the CPU path: one more
copy-in per frame, uncounted (non-plain use -> seed_forget(); guess: a second conversion or a WebKit BGR10XR layer).
Leading suspect (medium, guess): the consumer, not the conversion: CA samples the format-500 slot through the bridge's
emulated exact linear filter (lower/sampler/linear.rs:142-150, PackedTexels::YCbCr2048: 4 RGBA16F taps + integer math
per fragment), because only MetalSampler devices get the hardware filter. The CPU path's composite already costs
~16.5 ms per frame. The in-place port would inherit this, so: fix 0131 first. Next: traced run (MESA_GPU_TRACES,
SWEET_PIPESTATS) legs A GPU path / B CPU path, after soak n10; patch 0134 SWEET_YCBCR_HWFILTER being written.

### 2026-11-13 00:30 S0b readbench: imported surface memory is NOT slow (GO); 0131's 64-72 ms is elsewhere
m2vtest readbench 50 (9d50edf) on t167y, kernel167, idle, GPU 649 MHz, two runs (medians agree within 0.02 ms). 3.1 MB
1080p NV12, GPU ms median: IOSurface import / anonymous-page import / pool Shared: copy 0.52 / 0.52 / 0.52; NV12 ->
RGBA8 2.22 / 2.22 / 2.23; NV12 -> RGBA16F 2.51 / 2.50 / 2.51 (0131's fetch pattern, compute 960x540). All on memory
type 0, 0 wrong bytes (observed). So reading the imported planes costs nothing extra and one conversion is ~2.5 ms,
~25x less than 0131's 64-72 ms per submit. The cost is in what 0131 does around the conversion (barriers, the real
RGBA16F image, repeats per frame, pass splits; guess). Next: find it (read-only + one traced run); if fixable, a fixed
0131 may give the backboardd CPU win (47 -> 16 %) without the ~20 h in-place port.

### 2026-11-13 00:05 4d plan: in-place YCbCr sampling spec; correction to the 0131 result
Read-only workflow, spec in research/notes/ycbcr-inplace-spec-2026-11-12.md. CoreAnimation asks for ONE texture per
decoder surface, format 500 (YCBCR8_420_2P) over plane 0 with ShaderRead only, and relies on the sampler returning RGB
(observed in logs: "fmt 500 ... usage 1 ... surface 420v"). Today's CPU path converts with vImage in every setTexture
whose surface seed moved (~45 % backboardd). Upstream metal2vulkan cdf59197c (+843d22b0f, 8 fetches) samples the planes
in place through an R8G8_UINT texel buffer + SPIR-V math; AdrenoMetal 7841a9f/0035 adds a lazy image on top (MIT).
VkSamplerYcbcrConversion is refused for imported memory upstream, so it is not our route. Port: git apply fails in 24
of 36 files (our base 720ef1ce is 3385 commits behind); estimate ~20 h for the core, not 6-10 h.
Correction to the 2026-11-03 0131 entries: boot 20261103-190010 (529-568 s) shows the GPU SATURATED, not a stall:
GPU busy 96-100 %, mean 70.8 ms per submit, "ycbcr converted" 58-69 per 5 s, FB 12.2-14.4 fps (observed). One 1080p
conversion cost ~64-72 ms of GPU time even without the staging copy, so reading the imported surface pages (or linear
memory) may be the cost (guess); in-place sampling would inherit it. So first S0b: measure in m2vtest an imported
texel-buffer read vs a pool-memory read of 3.1 MB. S0a (CPU-path picture = ffmpeg) is met: b62 atomic shots 1.22.

### 2026-11-12 23:05 B62 closed: atomic flame-shots match ffmpeg (t165a); no lag without flame-shots
kernel165 (162 + xnu 0281/0282/0283), bundle 3f069d6, venusd/vtvenus 6a24d64, everyday args. h264-720p.mp4 in Safari:
two flame-shots with 0283's atomic read: counter 380 and 1174, whole video area = ffmpeg's frame at the counter, mean
|diff| 1.22 (±1 frame: 4.5-7.2; ±3: 5.8-10.7); side by side visually identical (observed). B62 = flame-shot artefact,
fixed by 0283. A shot still takes 9-16 s end to end (transfer), but the read is now one instant.
Latency (lat.html, 1 s beacons + requestVideoFrameCallback, no flame-shots), cold and warm 65 s runs: presentedFrames =
30 x mediaTime at every sample, 30.0 fps, 0 dropped, 1800 frames each; the "lag" from totalVideoFrames alternates
-0.3..1.4 s (bursty counter, not real). One gap per run at the start: 932 / 1002 ms at mt 0.033; logs at the same time:
vtvenus "no DecodeFrame call for >500 ms with 3 pending" -> "call again after 566 ms", venusd "no FBD for >500 ms: 1
inputs queued, last EBD 554 ms ago, credits 6" -> "FBD resumed after 563 ms (frame 13)" (run 2: 515 ms). So the start
gap is VT not feeding while waiting on early frames (preroll), ~0.5 s. The 3-5 s stalls of b62a did not happen: they
were likely caused by the slow 2-8 s pmem reads of the old flame-shot (guess). One socket fallback frame per run
("venusd had no credit"). QoS: no vtvenus CreateInstance line with "stall N ms, qos N" and no "switching QoS tiers"
line, though the new stall lines are from the new vtvenus (unclear; not needed now that there is no lag).

### 2026-11-12 22:22 Video lag behind the page clock: decoder stalls + no frame shedding (read-only analysis of b62a)
Correction: the two entries above headed 21:40 (gpu.md) and 22:15 were written at about 21:35 and 21:50.
Page beacons (work/shots/b62/httpd4.log, 720p mp4, dropped=0): the frame counter stalls for ~5 s twice (only 28 frames
between t=4 and 9 s; 0 frames between t=34 and 39 s) while the media clock runs on (audio track drives it although
muted); between stalls 175-185 frames per 5 s (~36 fps), so the deficit (up to 5.8 s) drains at ~6 fps (observed).
HLS: same early stall (frames 55 -> 84 between t=2.7 and 7.7). Our fixed buffering is at most 32 frames (MAX_INFLIGHT,
vtvenus.c:94), typically ~9 (0.3 s): not the cause. vtvenus keeps VT's PTS (no re-stamping). vtvenus advertises no VT
QoS property (vtvenus.c:1138-1162), so the player never skips late frames (MediaToolbox only counts them; guess from
disassembly at a few points). Catch-up ~36-39 fps although venusd alone does 66-76 fps at 1080p: limit outside venusd's
decode loop (unknown). Stall layer unknown; the early stall happens with no flame-shot running.
Next: stall detectors (venusd: no FBD > 500 ms; vtvenus: DecodeFrame blocked > 500 ms / no DecodeFrame > 500 ms with
frames pending) + kVTDecompressionPropertyKey_EnableVideoToolboxQoS (VTVENUS_QOS=0 off), then a 65 s run with a
1 s-beacon page and requestVideoFrameCallback gap reports, no flame-shots.

### 2026-11-12 22:15 B62 is very likely a flame-shot capture artefact (Fable forensics on b62a shots); correction to 21:10
Every 15-row band of the video area in the b62a shots is an exact, undisplaced copy (dx=dy=0, SAD < 3) of ONE real
clip frame, and that frame rises monotonically top to bottom: mp4-1 419 -> 534, mp4-2 1000 -> 1116, mp4-3 1489 -> 1543,
hls-1 805 -> 868, hls-3 1709 -> 1761 (observed). Band starts sit at framebuffer rows ceil(k*65536/4352) (64 KB of the
4352-byte stride; max error 1 row over 19 boundaries), the same for 720p and 1080p clips. A composite built from the
matched frame per band reproduces the shot: mean |diff| 1.5-1.7 vs 6.6-9.5 for the counter frame. So flame-shot reads
the framebuffer in 64 KB pieces over 2-8 s and moving content tears into 15-row bands from different moments; static
parts look right because they don't change. The "wrong angle" diagonal pieces and the striped grey blob are bands from
frames 20-115 later (testsrc2's moving line/cross). The 2026-11-03 "grey rows at fixed screen positions" fit the same
artefact (guess). Video lags the page clock by ~3-5 s (page beacons vs bands, +-1 s, observed): a separate latency item.
Judge: capture artefact ~95 %; no atomic playing shot exists yet. Next: xnu 0283 (file server reads ranges <= 16 MB in
one go before sending) -> one playing shot must match ffmpeg's frame at the burned counter on every row.
Work files: work/b62-forensics/image-forensics/ (rowprofile.py, composites, band tables).

### 2026-11-12 21:10 B62 is real (b62a): every shot differs from ffmpeg at the same burned-in frame number
kernel162 everyday args, bundle d3316ff, venusd used (session 8: 1800 AUs, 1800 frames, 30.0 fps). Page video `muted`.
Compared 5 shots side by side with ffmpeg's frame at the burned-in frame number (and ±2): h264-720p.mp4 frames 419, 1000,
1489 and HLS 1080p frames 805, 1709: ALL WRONG. Static parts (colour bars, checker block, timecode box, frame counter) are
right; the moving shapes are not: the rainbow diagonal shows as short slanted pieces at another angle/position, the grey
vertical bar shows as a horizontal blob with stripes, stray coloured slivers lower right. No grey macroblock blocks.
The frame counter matches but the moving content matches neither that frame nor its ±2 neighbours (observed); guess:
stale/wrong content in the moving regions after decode (references, conversion cache, or which buffer is shown).
Shots: work/shots/b62/*-sbs-*.png (shot | ffmpeg). 0 GPU hangs, no backboardd restart. Next: Fable read-only analysis
(region-by-region match against nearby ffmpeg frames + code paths vtvenus -> IOSurface -> bridge -> backboardd).
Night brightness: panel set to 8 by mistake (screen looked black to the user); back to 32, the floor (CLAUDE.md).

### 2026-11-03 20:49 B62 is video-only (rsA): non-video flame-shots clean; phone handed to the user
WebGL cube (2 shots), stage0 page scroll, home pages, Control Center: CLEAN. One garbled link row right after a Safari
reload while HLS played (t1-reload), clean in the next shot. h264-720p.mp4: grey bars/cross + checker block over the
bars (clip vs artefact not separated: compare with ffmpeg's frame at the same burned-in timecode first tomorrow).
Session ended 20:49: night soak n9 cancelled, phone booted user1 (kernel162, everyday args, credit path on) for the user.

### 2026-11-03 20:42 Not the shadow cache or SWEET_SURF_FLUSH either; state at end of day
M2V_SHADOW_CACHE=0 (X1) and also without SWEET_SURF_FLUSH (X2): BROKEN in all 4 flame-shots (grey blob/rows in the
green/yellow bars, diagonal fragmented; the pink/cyan checker block is in the clip). One shot also showed a ghosted page
link above the video, like the earlier white line on Safari's toolbar (G8). mtl2-env back to 6 lines.
Ruled out today: Venus decode (bit-exact over 700 frames, both paths), credit path, socket copy, resync, IOSurface use
counts / pool reuse, CPU conversion variants (vImage, direct planar), bridge 0130, every mtl2-env line, shadow cache.
Fixed: banding (TU_FETCH_GMEM_MIN_DRAWS=20, G8). Correction: the video pictures reported "right" earlier today were webcam
judgements that likely saw the page's still test card; no correct playing frame has been confirmed by flame-shot.
Leads for tomorrow: (1) flame-shot the 720p mp4 and a non-video animated page for the same stale/ghost pattern (general
partial-redraw bug vs video only); (2) dump the converted RGB texture or the NV12 IOSurface backboardd reads at the moment
of a shot (is the surface itself damaged?); (3) the bundle from before 691c87d (direct planar) and kernel158, to find when
it started; (4) Safari drops 13-16 frames in the first 10 s: check vtvenus's emitted PTS order.

### 2026-11-03 20:38 Not resync either (rsA): broken with VTVENUS_RESYNC=0 and in sessions with no error at all
HLS H.264 1080p flame-shots (clip timecodes 16.9/34.7/46.5/54.9 s with resync on; 18.7/36.6/55.0 s with RESYNC=0): all
BROKEN (grey bars/blobs, diagonal missing). The shot session had no session error, resync, reopen or flush (vtvenus.log),
and RESYNC=0's single session was clean in the logs. Grey rows stay at the same screen position across shots, as if those
regions of the video texture are never refreshed: next suspect the bridge's shadow cache (M2V_SHADOW_CACHE, hashed copies)
or SWEET_SURF_FLUSH. Test running.

### 2026-11-03 20:28 Venus decode bit-exact over 700 frames (3 GOPs) on both paths
venusc in-s0-1080p-700.h264 (first 700 frames of h264-1080p.mp4, IDRs at 0/250/500): socket 700/700 per-frame md5 equal to
ffmpeg (25.2 fps wall, copy-out 1.33 ms), --surf 700/700 (34.2 fps, 460 credited / 240 socket). The decoder is right past
frame 640; the Safari damage comes from what vtvenus feeds it during playback (resync/drops/flush) or from later stages.

### 2026-11-03 20:06 Not a pool-reuse race (read-only check): IOSurface use counts work; looks like reference errors
SweetSurface implements the cross-process use count (traps 0/1, SweetSurface.cpp:1088-1123, global u32[2] in the shared
state page, 0252 on by default); IOSurfaceIsInUse reads it (IOSurface.s 0x1a39832e8); CoreVideo's pool refuses reuse while
in use (CoreVideo.s okToReuse ~0x1a1ec09ac); CoreAnimation increments/decrements. The broken shot isn't a tear (no
two-frame seam): static background right, moving parts missing/stale, grey macroblock rows = a decoder covering for
wrong/missing references. The 90-frame check covered only the first GOP (IDRs at 0, 250, 500; the shot is at frame ~640).
Next: 700-frame venusc md5 check; then vtvenus.log resync/EOS lines and VTVENUS_RESYNC=0. Note: the env bisect never
turned off M2V_SHADOW_CACHE / SWEET_SURF_FLUSH (on when unset).

### 2026-11-03 19:58 Venus decode is bit-exact over 90 frames of the Safari clip: the tearing is after decode
venusc on in-s0-1080p-90.h264 (High, B-frames): socket path 90/90 bit-exact vs ffmpeg (cmp IDENTICAL, crc per frame);
--surf path (60 credited / 30 socket) same md5 on the phone. So the torn pieces come later: suspect VT's pixel-buffer pool
reusing a surface backboardd still reads (IOSurface in-use count across processes in SweetSurface), or lazy conversion.
Investigation running. Tool note: flame-files get times out on 280 MB (30 s socket timeout); 8 MB READ chunks work.

### 2026-11-03 19:51 Stale pieces are not mtl2-env (wvB): long decode check next
With the banding fixed, the picture still holds torn pieces of older frames in moving areas. Bisect (one run each, all
STALE): without SWEET_CULL=3; without SWEET_SURF_FLUSH=1; without SWEET_U0011..14; empty mtl2-env; empty + PLANAR_DIRECT=0
+ VIMAGE=0. mediaserverd ran the socket path (SURF=0 from boot), so the credit path isn't required for it. Next: decode
90 frames of the Safari clip with venusc (socket and --surf) and compare per frame with ffmpeg
(work/stage3/in-s0-1080p-90.h264, ref-s0-1080p-90.nv12): decode error vs reorder vs display.

### 2026-11-03 19:42 Video bands caused by TU_FETCH_GMEM_MIN_DRAWS=20 (mtl2-env); stale pieces remain
Bisect (wvB, kernel162, bundle 4C4C44D4), flame-shots during HLS 1080p: without SWEET_CULL=3 still bands; without
TU_FETCH_GMEM_MIN_DRAWS=20 the whole video area is drawn (S2, S2r confirmed) and the white line on Safari's toolbar is
gone. Line left out of /var/local/mtl2-env (6 lines now; backup mtl2-env.pre-bis). Remaining: the picture holds pieces of
older frames (the clip's continuous diagonal shows as slivers at old positions, grey trails; ffmpeg's frame at 26 s is
clean: research scratch ref26.png). Bisect of the other lines continues. Earlier "picture right" webcam checks today were
likely the page's still test card.

### 2026-11-03 19:30 White video A/B (wvA/wvB, kernel162): wrong on every config; not the credit path, not 0130
flame-shots, 15 s playback each: credit path (bundle 4C4C44D4): HLS 1080p white then partial bands with white gaps, 720p
top strip only; VTVENUS_SURF=0: same (strip, wide bands with gaps); bundle 0129-only (hwres, socket path): partial bands /
one band. Beacons normal (1077/4 etc.). No config ever drew full bars + the moving box. Earlier "picture right" webcam
checks may have seen the page's own still test card (the page shows colour bars before playback). Next suspect: the CPU
conversion into a buffer-backed texture (SWEET_PLANAR_DIRECT, 691c87d) or vImage (SWEET_VIMAGE); A/B running.

### 2026-11-03 19:14 Regression: Safari's video area white in the framebuffer (skC, kernel162, bundle 4C4C44D4, credit path)
flame-shot during HLS H.264 1080p (beacon t=41.4 frames=1136 dropped=5): the 16:9 box is white except a 1-2 px strip of
colour bars at its top edge, which moves with the video (hls-a/hls-b). Webcam agrees. MTL2 SHADOW lines say "ycbcr
converted 0" (CPU path). cg1/cg2 at ~17:58 (same bundle, credit path, kernel161) looked right on the webcam. A/B running:
fresh boot credit path vs VTVENUS_SURF=0, then the 0129-only bundle.

### 2026-11-03 19:10 Bridge 0131 on the phone (skC, kernel162): faster but drops half the frames; not kept
"YCBCR FAST: 1920x1080 Converted in place (base 0)". HLS H.264 1080p, % of one core over 30 s, webcam pictures:
| side | backboardd | mediaserverd | venusd | total | frames/dropped | GPU busy | GPU ms/submit |
| CPU (default) | 47.0 | 25.1 | 10.6 | 229.6 | 899/2 | 2-3 % | ~1.5 |
| FAST (SWEET_YCBCR_GPU=1) | 16.0 | 22.3 | 10.7 | 176.8 | 899/492 | 16-17 % | 2.9-19 mean, max 21-109 |
FAST: backboardd -31 points, GPU only 16 % busy, yet 492 dropped: a stall, not GPU load (guess: the full barrier or a
wait on the conversion's fence per frame). The webcam showed the video area white on BOTH sides (also on the CPU side, and
in earlier seek runs on other bundles): not judged as a 0131 colour bug until checked with flame-shot. Bundle back to
the previous one (--undo), mtl2-env restored (7 lines).

### 2026-11-03 19:01 Seek A/B (skB/skC, kernel162): the ~15 s freeze after a seek happens on both paths
HLS H.264 1080p, SEEK 30 ~20 s after the tap: credit c3 and socket s2 both froze at t=30.0 for ~15 s, then played on
(venusd closed those sessions cleanly, no error); credit c2 had one -60 ("at frame 169, reopen") and recovered in ~2 s with
88 dropped, blank white video area at +20 s; socket s1 seeked in ~3 s. mp4 seek trials void (seek hit before load) except
credit c5: no stall. So the credit path isn't the cause; guess: the segment fetch after a seek over the slow network
(B57), or AVPlayer re-buffering. Backlog B61. Credit path stays on.

### 2026-11-03 18:46 Bridge 0131 SWEET_YCBCR_FAST (9509b3a): in-place YCbCr conversion, bit-exact, not yet on the phone
Compute pass kept (RGBA16F output unchanged), but it reads the planes through an R8G8_UINT uniform texel buffer over the
surface's VkBuffer (binding taken from upstream cdf59197 bind/ycbcr_in_place.rs): no staging copy; one invocation per
chroma pair writes 2x2 texels (11 fetches per 4 texels vs 18 SSBO word loads per texel); old integer maths, bit-exact
(tests vs the old kernel over sizes 1x1..40x24, all range/matrix pairs, sRGB). Not the YCbCr sampler (a1f16771): our pin
doesn't enable samplerYcbcrConversion and upstream still copies into an optimal image. Falls back to the old path on
other layouts. Build work/metal2-next-ycbcrfast, LC_UUID 4C4C4448. Test needs SWEET_YCBCR_GPU=1; guess 3-8 ms GPU/frame.

### 2026-11-03 18:40 Credit path on all stage-0 clips (spC, kernel162): all right; a seek stalls (-60)
40 s each, % of one core over 30 s, links tapped (openapp URL never navigates: Code=4; links added to work/stage0/index.html):
| clip | frames/dropped | credited/socket/handed back | mediaserverd | venusd |
| hls-h264-1080p | 896/0 | 1073/1/0 | 25.1 | ~11 |
| hls-hevc-1080p | 955/0 | 1165/0/0 | 19.1 | 9.7 |
| h264-1080p.mp4 | 1168/0 | 1215/5/0 | 25.7 | 11.7 |
| h264-720p.mp4 | 1256/12 (loop end) | 1256/3/0 | 23.7 | 7.6 |
| hevc-720p.mp4 | 1240/11 (loop end) | 1241/1/0 | 19.2 | 6.9 |
| hevc-1080p.mp4 | 1178/0 | 1365/1/0 | 21.6 | 10.3 |
HEVC (hvc1) goes through credited surfaces too; 0 handed back, pictures right. Pause 5 s + resume fine (2 dropped). Seek
to 30 s (HLS H.264 1080p): stalled at t=30.0 with a blank white video area; vtvenus "venusd session error -60 at frame 124
... reopen", again at frame 167; "invalidated: 295 frames in, 129 out (289 through credited surfaces), 166 dropped, 4
venusd session(s)"; session 40 credited 6 / socket 120. Not yet known whether the socket path stalls the same way.

### 2026-11-03 18:15 Why the GPU YCbCr path (G7, SWEET_YCBCR_GPU) is slow (read-only study)
Per new frame: 22 shape words + copy_buffer of both planes (3.1 MB) to staging, full barrier, one 8x8 compute dispatch
(one texel per invocation, SSBO word loads + Metal's exact fixed-point maths), writes RGBA16F (16.6 MB). Measured total
(27b96cb, kernel160): ~45-60 ms GPU per conversion, GPU 99-100 % busy, 883/1800 dropped; bake cut it 35 % => latency-bound
kernel, not bandwidth (~23 MB should be 2-5 ms). Reuse: upstream metal2vulkan (693 commits ahead of our pin) reads planes
in place on integrated GPUs (cdf59197), converts through VkSamplerYcbcrConversion (a1f16771, 2f033d30). Turnip's
G8_B8R8_2PLANE_420_UNORM supports linear images with MIDPOINT chroma + linear filter (tu_formats.cc:198-207). Plan:
fragment pass sampling linear R8/R8G8 aliases of the surface (or a 2-plane linear image + YCbCr sampler, from a1f16771)
into RGBA8, no staging; expected ~1-2 ms GPU. Off switch SWEET_YCBCR_FAST=0.

### 2026-11-03 18:11 First-session "venusd session error -60 at frame 17" (read-only study)
venusd's no-firmware-progress rule fires (venusd.c:790-800: 3 s quiet once the session has a first picture; the 20 s cold
allowance ends at frame 0); vtvenus only relays it. crH: session 1 opened 71.321, frame 0 71.862, failed 76.968 "17 AUs
in, 10 frames" (no picture ~4.8 s after frame 9). Same AU in crB and crH; session 2 decodes the same 18 AUs in 731 ms;
seg000 has one keyframe at AU 0, so not content. Guess: a first-use stall at 1080p on freshly booted firmware (the warm-up
is 320x240 and powers Venus down again). Seen on the socket path twice; credit path cg1 (n=1) didn't hit it. Parked
(backlog B60): pull an unfiltered venusd.log / VENUSD_VERBOSE=1 boot, then A/B a 1080p warm-up or VENUSD_WARMUP=0.

### 2026-11-03 18:04 Credit path works (crG/crH/crI, kernel161, venusd 06f9715 + vtvenus 331e616): mediaserverd -35, venusd -22
"venusd: memory limit 6/6 MB -> 512 MB: 0" (launchd gave a 6 MB limit). venusc --surf bit-exact (inf dB, every frame):
720p 9 credited / 1 socket, 1080p-10 8 / 2, 0 handed back, 0 CRASH lines. Safari HLS H.264 1080p, % of one core, 30 s:
| run | WebContent | Networking | GPU | backboardd | mediaserverd | venusd | kernel_task | total* | frames/dropped |
| cg1 credit | 6.7 | 52.3 | 14.7 | 45.8 | 21.9 | 10.6 | 18.6 | 326.6 | 932/0 |
| cg2 credit | 5.9 | 38.5 | 13.4 | 45.4 | 19.7 | 10.2 | 15.3 | 193.7 | 1199/0 |
| ch1 SURF=0 | 8.0 | 69.8 | 16.2 | 44.4 | 59.1 | 34.2 | 24.4 | 432.9 | 716/8 |
| ch2 SURF=0 | 6.8 | 46.0 | 14.4 | 46.8 | 54.8 | 31.9 | 18.7 | 377.4 | 1195/0 |
*total = psx TOTAL incl. trustd (61-63 %) and accessoryupdater (38 %) in cg1/ch1/ch2 (post-boot noise); cg2 is clean.
Run 2 vs run 2: mediaserverd -35.1, venusd -21.7 (= the -58 upper bound). vtvenus: 1420 of 1423 frames through credited
surfaces, 0 dropped (first/last frame of a session over the socket). Picture right (colour bars, moving box). ch1's 8 drops
= the known first-session "venusd session error -60 at frame 17" resync on the socket path. Credit path stays on (default).

### 2026-11-03 17:49 Credit path retest (crD): JetsamMemoryLimit 128 in the job did not help
`--check` shows JetsamProperties {JetsamMemoryLimit: 128} in the launchd.plist cache; first `venusc --surf` (720p, 6
credits): boot log 20261103-174030 "[64.183] CRASH venusd[37] sig 9", "reason ns 1 code 0x7" right after "SWEET SURF:
venusd sel 4" again. So either launchd ignores JetsamProperties for this job or the lookup maps far more than 3 MB.
VTVENUS_SURF=0 again (crS0). Next: venusd logs its phys_footprint around each lookup and sets its own limit
(memorystatus_control) as root.

### 2026-11-03 17:40 Credit path (331e616) first test (crA): jetsam killed venusd at the first credited frame
venusd logged "session 1: frame 0 into credited IOSurface 119 (4.2-5.2 ms read)" then died, every session; boot log
20261103-173338: "CRASH venusd[37] sig 9 ... reason ns 1 code 0x7" right after "SWEET SURF: venusd sel 4" = jetsam
per-process memory limit (mapping a 3 MB surface on top of fbuf). VTVENUS_SURF=0 set (crB; SURF=0 baseline first session:
716/9 dropped, 428.8 % total, "venusd session error -60 at frame 17" + resync). Fix 8636309: venusd job
JetsamProperties JetsamMemoryLimit 128 MB. Bit-exact and CPU A/B pending (crD).

### 2026-11-03 17:13 Upper bound of the copy saving: -58 % of a core (npA, kernel161, venusd/vtvenus 836d076)
HLS H.264 1080p, 30 s windows, % of one core (WebKit roles guessed by CPU level):
| run | WebContent | Networking | GPU | backboardd | mediaserverd | venusd | kernel_task | total | frames/dropped |
| A1 | 6.3 | 43.2 | 14.2 | 46.6 | 52.5 | 32.7 | 16.8 | 238.8 | 1196/0 |
| A2 | 6.5 | 44.1 | 14.4 | 46.0 | 53.0 | 32.3 | 16.9 | 244.3 | 1196/0 |
| B1 nopayload | 6.2 | 38.6 | 13.7 | 45.4 | 20.0 | 9.9 | 15.2 | 179.2 | 1197/1 |
| B2 nopayload | 6.0 | 39.0 | 13.4 | 45.1 | 20.1 | 9.8 | 15.3 | 182.9 | 1198/0 |
| A3 (file removed) | 6.1 | 39.3 | 15.4 | 45.0 | 53.0 | 32.0 | 16.6 | 237.4 | 1195/0 |
B-A: mediaserverd -32.9, venusd -22.5 (copy 1 still done in B: the socket write dominates venusd), kernel_task -1.7,
total -58.4. B picture solid green as expected; A3 right. No hang. Note: A is ~241 % on kernel161/a71ea11 (was 383 at
17:30 on kernel160). Next: the credit path (vtvenus hands pool IOSurface IDs, venusd preads into them).

### 2026-11-03 17:00 Per-frame copy path at 1080p (read-only study): 4 copies, ~12.5 MB/frame
1 venusd pread Venus window -> fbuf 3.13 MB (measured 1.5-2.1 ms); 2 venusd write -> AF_UNIX (guess 2-3 ms); 3 mediaserverd
read -> rx (guess 1.5-2.5 ms); 4 vtvenus row memcpy -> VT pool IOSurface (guess 1.5-2 ms). Copies 2-4 can go with "credits":
vtvenus sends pool IOSurface IDs, venusd preads /dev/pmem straight into them (SweetSurface lookup by ID, no owner check).
vtvenus can't mmap /dev/pmem (no mmap, root-only 0600). Decoding straight into IOSurfaces (sweet_surface_create_physical)
needs two-plane + cached + buffer holding: stage 5, 2-4 days. Reuse: no related project hands frames to VT. mediaserverd's
~58 %: profile can't split it (pstack misses kernel time); guess ours ~9-14 %, rest Apple's player/XPC. Saving estimate
15-25 % of a core (guess); first an upper-bound A/B: venusd sends DECODED without pixels (/var/local/venusd-nopayload).
Note: the 281 % breakdown is from kernel160/bundle 691c87d; not re-measured on kernel161.

### 2026-11-03 15:35 Correction: today's Log heading times run ahead of the clock
Claude's session clock drifted: the `### 2026-11-03 HH:MM` headings written today after about 12:00 EST carry times up
to ~6.5 h ahead of the real time (e.g. "21:40" was ~15:15 EST). The order of the entries is right; the real times are
the wall/boot stamps quoted inside them and the per-boot logs (../logs/boots/). From here on headings use `date`.

### 2026-11-03 21:40 vfix1: client leak fixed: 12/12 clips decoded on Venus, 0 "too many clients"
venusd 09b15004 + vtvenus 05645f58 (f87343c leak, 41a2e8e BCM retry, f461433 timestamps), boot vfix1
(20261103-151222.log, kernel160; no RPMh timeout this boot). Start line `[25.200] [wall 2026-11-03 15:12:10] venusd: start,
... idle client 30 s, max 16 clients` (stamp = kernel's 25.203). 13 HLS 1080p clips alternating H.264/HEVC: 12 ended, each
with its own venusd session (1800 AUs / 1800 frames each); 149 client connects, max 1 at a time; 0 too many clients,
0 power on failed, 0 BCM retries; page dropped 0. vtvenus: one `given up: venusd connection closed ... a fresh try` per
clip end (the 30 s idle-client close) — harmless. Clip 104 never started: `DEVLOST first (turnip) VK_ERROR_DEVICE_LOST
... submit failed: 0xe00002c2` in backboardd at 322.453 s, backboardd restarted, 4 GradientPosterEx CRASH right after;
no venusd session was open (session 3 opened at 252.153, closed at 314.5): this GPU loss is not tied to a Venus start.
Max 81.6 C.

### 2026-11-03 21:00 vsoak (15 min, 13 HLS 1080p clips): venusd client leak; MM3 vote failures; one GPU hang
Boot bat1b (20261103-144012.log), 14:44-14:59. 12 of 13 clips reached k=ended (HLS beacons report frames=0: the page's
counter doesn't work for HLS). /var/local/venusd.log (cut at 1 MB) shows only 4 session opens for 13 clips, then 21x
`venusd: too many clients`; vtvenus: `venusd connection lost or bad message ... giving up (errors from now on)` ->
software decode for the rest. Earlier starts in that log: `venus: STOP: bcm MM3 vote failed`, `venusd: power on failed`.
One GPU hang at 766.054 s, 33 s into clip 8 (HEVC): `present: GPU hang or fault (fence 9658, done 9651, smmu fsr
40000002 far 1f620000 fsynr0 2): reset`, backboardd killed after recovery; offset from a session open unknown (venusd
log lines have no timestamps). Max 72.2 C, no cap. Fixes being written: client slot leak (both sides), MM3 vote retry,
timestamps in venusd's log.

### 2026-11-03 18:10 Direct planar conversion (691c87d): backboardd 92 -> 45 % during 1080p video
Bundle work/metal2-next-direct (LC_UUID 4C4C44C2): vImage converts each frame straight into a buffer-backed texture
(rows at the linear pitch, read via a linear alias) instead of temp -> replaceRegion -> Turnip host-image-copy retile
(3 x 8.3 MB copies per 1080p frame before). Safari HLS H.264 1080p via Venus, % of one core over 30 s:
| run | backboardd | mediaserverd | venusd | WebKit (3 pids) | total | dropped |
|---|---|---|---|---|---|---|
| direct on (default) | 45.5 | 57.5 | 33.6 | 95.7 | 280.8 | 0 |
| SWEET_PLANAR_DIRECT=0 | 92.4 | 68.9 | 37.1 | 122.6 | 376.3 | 0 |
`cpu conversion direct into the texture (rowBytes 6144)`; B29 for the 1920x1080 RGBA8 buffer textures: 18x `-> wider
alias`, never `-> shadow`. Still frame at 10 s right, no tearing. UI: Settings, CC, Photos fine; Camera UI fine but the
viewfinder looked black on the webcam (lens on the desk). Checked with flame-shots (work/shots/cam-direct.png vs cam-off.png):
both show the same live dark green-tinted desk image (ON mean RGB 7/12/6, OFF 12/17/9, both textured): the direct path
works for the camera (`420f fmt 500 1128x1504`, rowBytes 4512); the dimmer ON shot is likely auto-exposure timing.

### 2026-11-03 17:45 The network process cost is general (B57), not video
work/stage0/dl.html (random 46 MB file from the PC, no video): paced 0.75 MB/s -> Networking 32 % of a core; flat out only
1.20 MB/s -> 39 % (kernel_task 5-6 %; the USB link is the xnu ECM/NCM driver, no userland bridge). ~3-4 % per 100 KB/s,
matching the 52-93 % during HLS. Network throughput itself is low (backlog B57). For video CPU, the next fix is
backboardd's conversion (vImage into a temp buffer, then an 8 MB replaceRegion copy per frame).

### 2026-11-03 17:30 HLS (as real sites stream): 0 dropped; total 315-383 % of a core
work/stage0/hls-{h264,hevc}-1080p (ffmpeg -c copy, fmp4 segments ~8 s), index.html `#hls-<clip>`. 30 s window, % of one core:
| clip | WebContent | Networking | GPU proc | backboardd | mediaserverd | venusd | kernel_task | total | frames/dropped |
|---|---|---|---|---|---|---|---|---|---|
| HLS H.264 1080p | 10 | 93 | 20 | 95 | 67 | 36 | 30 | 383 | 1674/0 at t=60 |
| HLS HEVC 1080p | 8 | 52 | 17 | 95 | 60 | 35 | 23 | 315 | 1734/0 at t=60 |
venusd: 1800/1800 AUs, 29.8 fps, first frame 543 ms, copy-out ~2.1 ms, error 0. Still frame (paused at 10 s) right.
No GPU hang. Remaining CPU, biggest first: backboardd's CPU YCbCr conversion (~95 %), the network process (52-93 % for
~6 Mbit/s: a general networking cost? download-only test next), mediaserverd (~60-67 %), venusd (~35 %).

### 2026-11-03 17:10 Remeasure: Range doesn't remove the network-process burn; venusd 4 ms tick small gain
Range server on :8077 (206 seen). % of one core, 30 s window, single-mp4 clips:
| run | clip | WebKit (Networking?) | WebContent | GPU proc | backboardd | mediaserverd | venusd | total | dropped |
|---|---|---|---|---|---|---|---|---|---|
| old venusd | H.264 1080p | 150 / 149 | 12 | 22 | 102 / 100 | 74 / 71 | 41 / 43 | 471 / 460 | 8-10 |
| venusd 007f8b1 | H.264 1080p | 148 | 11 | 21 | 101 | 72 | 38 | 454 | 8 |
| venusd 007f8b1 | HEVC 1080p | 84 | 9 | 18 | 99 | 62 | 37 | 363 | 10 |
(WebKit roles assigned by exec order; totals include kernel_task 27-34.) Safari asks `bytes=0-` and streams the whole
file anyway, and WebKit re-grows one buffer per chunk. Real sites stream HLS/MSE segments: HLS test running
(work/stage0/hls-*; index.html plays `#hls-<clip>`). venusd: 43 -> 38 % (one run each). Still frame right.
- r1 void: GPU hang 2 s after a venusd session opened (smmu fsr 40000002), backboardd + SpringBoard restarted. The vd1 wedge
  (11:00) also came 1 s after a session opened, same fsr: a possible Venus-start / GPU-fault link (gpu-bugs.md).

### 2026-11-03 16:50 videoprof: where Safari hardware-video CPU goes (H.264 1080p, ~392 % total)
pstack x60 per process (research/notes/videoprof-2026-11-03/). % of one core over 30 s:
- WebKit Networking ~142 %: `FragmentedSharedBuffer::append` -> `Vector<DataSegmentVectorEntry>::reserveCapacity` on every
  received chunk of the mp4: the PC's python http.server ignores Range, so Safari streams the whole file. Test artefact;
  fixed with tools/sunfish-httpd.py (Range support, 99f8a9d), now on :8077.
- backboardd ~101 %: vImage `vConvert_420Yp8_CbCr8ToARGB8888_vec` on dispatch_apply workers + memmove (the CPU YCbCr
  path) and CA commit. Real fix: native GPU YCbCr sampling (VkSamplerYcbcrConversion), later.
- mediaserverd ~70 %: spread thin (mach messages, CF hashing, malloc), no hot function.
- venusd ~42 %: poll(..., 1 ms) 1 kHz loop + writing each 3 MB frame to the socket. Fix 007f8b1: 4 ms tick (VENUSD_TICK_MS).
- WebContent ~13-22 %. Remeasure running.

### 2026-11-03 15:20 Still frames: the hardware-decoded picture is right for H.264 and HEVC
index.html `?pause=10` (pauses the video, beacons k=paused) → flame-shot 3 s later, no tearing:
work/shots/still-h264.png and still-hevc.png show the full testsrc2 frame (bars, rainbow diagonal, grey +, checker
patch, timecode 00:00:10.1 / frame 300-302). Mid-row RGB: (254,0,0) (0,255,1) (255,255,0) (0,0,255) (255,0,254)
(1,255,255) — exact bar colours (HEVC's sixth sample hit the diagonal). venusd sessions `H.264` and `HEVC` opened.
Picture confirmed; the earlier white/blank webcam frames were exposure and the flame-shot tearing was capture time.

### 2026-11-03 15:00 hevc1 (stage 4e): HEVC 8-bit Main decodes on Venus, bit-exact; Safari plays HEVC via Venus
venusctl/venusd/venusc/vtvenus 438e168 + 391985b (wall-clock waits; HEVC), installed then a reboot (no mediaserverd
restart). Boot hevc1 (kernel160, 4455 mV). venusd `hevc 1`, warm-up first frame 430 ms (890 ms in all).
- venusctl HEVC 1080p 10 frames (x265 main): `decoded 10 of 10 frames, EOS in 0.25 s`, `CTRL_STATUS ... after 8 ms`
  (real ms now), yuvcmp all 10 luma exact, frame 0 crc 2aa7df4e = ffmpeg's.
- HEVC 1080p 300 frames to null: `EOS in 5.36 s`, copy-out mean 1.48 ms, 56.2 fps end-to-end.
- H.264 1080p regression: bit-exact (crc 38f51ff4 last frame).
- Safari hevc-1080p: venusd `session 2 opened (fd 8, HEVC, hint 1920x1080)`, `HEVC decoder session (codec 0x2000)`,
  `1800 AUs in, 1800 frames, first frame 518 ms after it, 29.8 fps, copy-out mean 2.26 ms, error 0`; page 1800 frames, 8
  dropped. CPU (% of one core): backboardd ~99, WebKit ~81, mediaserverd ~68 (software HEVC this morning: 101-115),
  venusd ~39. Flame-shot: bars in the right colours and order in strips with white gaps (tearing, as with H.264);
  the webcam frame at 27 s looked blank (exposure, as before?): picture not fully confirmed.
- H.264 1080p after it: 1647 frames at t=57, 6 dropped, bars on the webcam.
- vtdecode --raw reads H.264 only (HEVC not tested through vtdecode).

### 2026-11-03 13:50 lat1: venusd as an Interactive launchd job: first frame 0.6 s after OPEN (was 7.5-9 s)
Cause (research/notes/venus-latency-2026-11-03.md): launchd started venusd in its default (throttled) class, so XNU's
timer coalescing stretched every 1 ms wait ~14x (`CTRL_STATUS ... after 1-2 ms` loop counts instead of 7); the HFI
exchange was identical. Fix 5a974c8: tools/venusd.plist ProcessType/POSIXSpawnType Interactive (as dropbear).
Boot lat1 (kernel160, 4455 mV; ../logs/boots/20261103-111247.log): `warm-up done (status 0): 1 frame(s), first frame
551 ms after the decoder start, 1271 ms in all (bring-up 720 ms)`; `CTRL_STATUS 0x40000001 after 7 ms`.
- Safari 1080p: 1800 frames, 10 dropped (page counter; vtvenus 0), venusd first frame 647 ms after OPEN, 29.9 fps.
- Safari 720p: 1800 / 5, first frame 585 ms, 30.0 fps; one few-second stall early (frames 209 -> 216 over 5 s).
- No reset, crash or GPU hang. Still to do: wall-clock deadlines instead of loop-pass counts (a throttled venusd also
  stretched every timeout ~14x).

### 2026-11-03 13:30 wedge1: 5 Safari clips through Venus on a fresh boot, no wedge; venusd recovery works (K=3, K=4)
Boot wedge1 (kernel160, 4455 mV; ../logs/boots/20261103-105302.log), venusd 73803de2 + vtvenus 34372e4c (cfbebf1),
bundle vimage. venusd warm-up at boot: first frame 7475 ms. mediaserverd pid 29 the whole time (never restarted).
| clip | frames | dropped | mediaserverd CPU (s) before -> after |
|---|---|---|---|
| 720p | 1800 | 0 | 6.0 -> 29.6 |
| 720p | 1800 | 48 | 30.1 -> 67.3 |
| 1080p | 1800 | 1 | 67.8 -> 107.2 |
| 1080p, fake clock-off at frame 300 (K=3) | 1800 | 41 | 107.7 -> 147.4 |
| 1080p, K=4 (power-on-first path) | 1800 | 40 | 147.5 -> 185.3 |
- Recovery K=3: `clock check: fake off (1/3..3/3)`, `STOP at doorbell ...`, `recovering from STOP 1 (session 8 running,
  client attached)`, `Venus down (recovery after a STOP)`, `recovery done`, `Venus up in 191 ms`, new session; vtvenus
  `session error -5 ... at frame 306: ... reopen`, `resync: parameter sets + 57 access unit(s) from tag 250 sent again
  in 9680 ms (their pictures discarded)`. K=4: `recovery: a clock or GDSC still reads off: power on first`, then the
  same. venusd pid 37 throughout.
- No wedge: the two "Safari video won't start" cases both followed manual mediaserverd restarts. Rule: after a plugin
  install, reboot rather than restart mediaserverd (the restart also execs camclk/camid many times).
- Open: each session's first frame comes 7.5-8.7 s after OPEN (`first frame 8667 ms after it`; vd4a was ~0.6 s), and a
  resync of 57 AUs took ~9.7 s: Safari waits ~8 s before a video starts. Next item.

### 2026-11-03 13:10 "Safari video won't start" = a wedged mediaserverd, not the plugin
After the install-time `psx -k mediaserverd`, the new mediaserverd (pid 563) spun (CPU 5 -> 58 s in ~10 min), Safari
never requested the mp4 (`frames=0 w=0`, one AbortError), oslog showed only `SecTaskLoadEntitlements failed error=22`.
vtdecode through that same mediaserverd still worked (`--hw require`: 10/10, `using hardware decoder: yes`; first
frame ~10 s after a cold Venus warm-up), software playback with venus-off worked. One more mediaserverd restart with
Venus down fixed it: Safari 720p via Venus `t=60.0 frames=1487 dropped=6` (vtvenus session 2 with resync). Cause of
the wedge unknown (the restart execs camclk/camid many times; suspect). Rule for installs: after restarting
mediaserverd, check Safari/vtvenus, restart once more if it spins.

### 2026-11-03 12:55 Careful installs (no reset); vImage; the clock-off STOP happens in normal use
Boot stopR (kernel160). One step at a time, venusd idle between.
- A/B: bundle fcdf6de (CPU YCbCr via Accelerate vImage): Safari 1080p via Venus (old venusd) 1800 frames, 0 dropped,
  backboardd 66.3 %, `SWEET YCBCR: cpu conversion via vImage (fmt 70, matrix BT.601, range video)`, bars right; with
  SWEET_VIMAGE=0: backboardd 68.5 % (the copy into the texture likely dominates; vImage helps little).
- During the SWEET_VIMAGE=0 run the OLD venusd hit `STOP at doorbell (0xaadf018): a video clock or GDSC is off` at
  frame 1591 and exited; vtvenus: `FRAME 1591: send failed ... (Broken pipe)`, reconnect refused, gave up. So the
  transient clock-off is real in normal playback (the cfbebf1 recovery is the fix).
- New venusd 73803de2 installed via temp + rename (7caeb4d), restarted with Venus down: `warm-up 1, recover 1`, warm-up
  first frame 10378 ms, bring-up 246 ms.
- vtvenus 34372e4c installed without --restart; `psx -k mediaserverd` with Venus down: survived. The mediaserverd
  restart execs camclk/camid repeatedly (785-807 s) — no reset this time.
- After that, Safari video did not start at all (frames 0, w 0; nothing in vtvenus.log): diagnosing.

### 2026-11-03 12:35 RESET during the vdstop install (mediaserverd restart + venusd kill at once)
Boot vdcold (kernel160). Steps: `tools/sunfish-install-venusd.sh` (printed installed; but /var/local/bin/venusd stayed
the old 6d0b2c94: the PUT over the running binary did not take), `tools/sunfish-install-vtvenus.sh install --restart`
("killed 29 mediaserverd", restarted), then `psx -k venusd` ("killed 345 venusd"). Within seconds: SSH and ping gone,
phone in fastboot (hard reset, no panic/CRASH/watchdog line). Last lines of ../logs/boots/20261103-095610.log:
`[1432.607] exec camclk`, `[1432.718] exec camid`, SWEET FB lines, end at 1432.762. Back up with stopR (kernel160,
4436 mV; log 20261103-102209.log); old binaries still installed.
Guess (not proven): the camera clock tools started by the mediaserverd restart (camclk/camid) and venusd's shutdown of
Venus (GDSC/clock/MMCX votes) at the same moment collided (shared MMCX rail / RPMh votes / GCC). Earlier
`install --restart` runs (vt4b) did not reset, but venusd was not being killed then. Next, smaller steps: install with
venusd idle and Venus down, never restart mediaserverd while venusd is powering Venus up or down, one step at a time
with a wait between; check what runs camclk/camid on a mediaserverd restart.

### 2026-11-03 12:10 The WPT line is harmless; venusd died on a transient clock-off reading (read-only analysis)
research/notes/venus-wpt-2026-11-03.md. The `VFW_F ... h264HWProgVpp(1035): WPT wrap-around` ring lies inside scratch_1
(1080p: 0x19800 into 0xa5df7000, 816 x 400 B; 720p: 560 x 400 B); our scratch_1 sizes equal the firmware's
requirements (15847936 / 8411904 B), set again per session; the same line at the same address appears in 6 sessions
that decoded all 1799 frames: content-dependent and harmless. 0x1204004 = CONFIG_VDEC_ENTROPY (1 CAVLC, 2 CABAC).
venusd's exit came from core_gate's clock/GDSC check (exit(1)); the relaunched venusd passed core_ok() without
powering anything, so the reading was transient (inferred). Fix being written: re-read and name the register, a
failure hook so venusd recovers (VD_ERROR to the client, clean teardown, bring-up on the next OPEN) instead of exiting,
vtvenus reconnect retries for up to 20 s, frame numbers on firmware debug lines.

### 2026-11-03 11:55 vdcold: cold-start fixes (68ebbab); a firmware fatal kills the session and venusd exits
venusd 6d0b2c94 + vtvenus 1c30d842 (68ebbab: cold timeouts, reconnect, lazy OPEN, resync, venusd warm-up), boot vdcold
(kernel160, 4454 mV); logs pulled to research/notes/venus-runs/2026-11-03-vdcold-{venusd,vtvenus}.log.
- Warm-up at start: `1 frame(s), first frame 8286 ms after the decoder start, 13748 ms in all (bring-up 5461 ms)`.
- 1080p clip right after boot: vtvenus first refused (venusd still warming up -> software for that instance), then
  session 1 open in 11291 ms, session 2 in 1013 ms, resync ok; played to frame 1455 (dropped 146 by then), then the
  firmware: `<VFW_F:VppCr0:...> h264HWProgVpp(1035): WPT wrap-around happened, wpt 0xa5e60200 len 0x190 beg 0xa5e10800
  size 0x4fb00`, the core's clock/GDSC went off, venusd's shared code: `STOP at doorbell (0xaadf018): a video clock or
  GDSC is off` -> venusd exited (launchd restarted it, warm-up again); vtvenus's one reconnect got "Connection refused"
  and gave up. The same VFW_F line appears several times in the log (also beg 0xa5906800 size 0x36b00).
- 720p clip after that: 1800 frames, 0 dropped (first frame 7418 ms after the first OPEN).
- The first frame takes 7-8 s after each venusd OPEN through vtvenus (not once per boot).
- Next: investigator on the WPT ring (which buffer, why too small) + venusd must survive a firmware fatal.

### 2026-11-03 11:15 stall A-C: the first-use stall does not reproduce in 3 fresh boots
venusctl f191422 with VENUSCTL_TS=1 (per-line stamps on the phone); first decode of each boot ~60 s after SSH, venusd
idle (launchd respawns it; /var/local/venus-off kept it from opening Venus). Files research/notes/venus-runs/
2026-11-03-stall-stall{A,B,C}-{1,2}.txt. 1080p 10 frames:
- A (pmemwc=2, 160 MB): 0.21 s decode (0.80 s to SESSION_END), twice. B (pmemwc=1): 0.48 s, twice (the copy-out).
  C (pmemwc=2, 64 MB): `STOP: dpb: 0x302000 bytes don't fit the buffer window` (64 MB is too small for 1080p), then
  160 MB 0.21 s. Largest gap in any run 0.13 s (firmware boot to SYS_INIT); buffer allocation ~50-60 ms.
- Not reproduced: the 13 s (v4a1) and the vdboot failure. Differences: vdboot's first decode came through venusd/vtvenus
  from Safari, and venusd logged `Venus up in 1520 ms` (normally ~150 ms): the system was busy right after boot (guess).
  The plugin's cold-start timeouts/reconnect (being written) cover it either way.

### 2026-11-03 11:00 vdboot: venusd from launchd works; the first Safari video after boot fails on the first-use stall
Bundle a458398 (G7 GPU path default off; SWEET_YCBCR_GPU=0 line removed from mtl2-env). tools/sunfish-install-venusd.sh
added job org.iosonpixel.venusd to /System/Library/xpc/launchd.plist (backup launchd.plist.pre-venusd). Boot vdboot
(kernel160, sweetpmemwc=2 sweetgpucap=512, 4455 mV): venusd pid 37 from launchd, socket present, Venus off.
- First Safari 1080p clip after boot: `Venus up in 1520 ms`; vtvenus's 1-frame probe session: no EOS_DONE in 2017 ms,
  no CLOSE answer in 2000 ms; real session opened 4918 ms later; `FRAME 2: send failed (Resource temporarily
  unavailable): decoder unusable`; venusd: client gone, 1 AU in, 0 frames. Nothing played (flame-shot: page, no video).
- Before the reboot, warm: 1150 frames at 29.7 fps, first frame 641 ms after OPEN.
- Reading: the one-time first-decode stall (v4a1, up to 13 s) outlasts vtvenus's 2 s timeouts and the plugin then stays
  dead. Next (running): stall timing with VENUSCTL_TS=1 over 3 boots (pmemwc 2/1, buffers 160/64 MB); vtvenus/venusd
  cold-start timeouts + reconnect + no probe session + an optional venusd warm-up at start.

### 2026-11-03 10:45 vd4e: framebuffer shots: the Safari picture is right on the hardware path
tools/flame-shot during H.264 1080p playback at ~20 s: work/shots/vd4e-{cpu-hw,gpu-hw,cpu-sw}.png. All three show the six
testsrc2 bars fully saturated (RGB samples e.g. (254,0,0) (0,255,1) (255,255,0) (0,0,255) (255,0,254) (1,255,255)), the
moving line and the grey/checker patches of the clip; white bands are tearing from the ~16 s framebuffer read. The
washed-out look was the webcam (exposure), not the pixels. So stage 4c works: **Safari plays H.264 1080p decoded by
Venus, correct picture, 63/1800 dropped, mediaserverd 72 %** (with 0112's CPU YCbCr conversion; GPU path default off
from a458398). Left: 4d (backboardd's ~96 % CPU conversion -> GPU, without the G7 path's stall), 4e HEVC, venusd as a
launchd job, the 1-frame probe session per clip, the 13 s first-use stall after boot.

### 2026-11-03 10:30 vd4d: the drops are the G7 GPU YCbCr path; with the CPU conversion, Venus playback drops 63/1800
Same boot; H.264 1080p, one fresh tab (SafariTabs.db* moved to /var/local/safari-tabs-bak/), start < 60 C.
| run | YCbCr GPU | decode | dropped | backboardd | WebKit (2 busiest) | mediaserverd | venusd | max temp |
|---|---|---|---|---|---|---|---|---|
| 1 | on | sw | 1212 | 15 % | 124 / 19 | 199 % | - | 72.2 C |
| 2 | off | sw | 82 | 96 % | 147 / 21 | 262 % | - | 79.0 C |
| 3 | off | hw | **63** | 96 % | 148 / 21 | **72 %** | 43 % | 78.3 C |
| 4 | on | hw | 1187 | 16 % | 129 / 18 | 59 % | 38 % | 71.6 C |
- Observed: the GPU YCbCr path (bridge 0127, fe2d169) loses ~2/3 of the frames on both decode paths with backboardd
  nearly idle (15 %): presentation stalls, it isn't busy. With the CPU conversion (0112) hardware decode drops 63 and
  saves ~190 % of a core in mediaserverd vs software, but backboardd spends ~96 % converting (the 4d item).
- venusd: 1799/1799 frames, 29.8 fps, copy-out 2.42 ms mean, error 0.
- Webcam at 30 s with the CPU path (runs 2, 3): the video area looks washed-out white with faint pink/green where the
  bars should be (checked by Claude, frame_103.jpg), while the beacons say it plays: picture not confirmed. With the
  GPU path (run 4): faint pink/green tint. Next: phone-side screenshots (`shot`) to see the real pixels.
- Left SWEET_YCBCR_GPU=0 in /var/local/mtl2-env.

### 2026-11-03 10:10 Stage 4c (vd4c): Safari plays H.264 through Venus; display drops ~2/3 of frames on both paths
Plugin + venusd (by hand) as in vt4b; bundle 4da54f0 with SWEET_YCBCR_GPU on (G7 GPU path); kernel160 maps512 boot;
per-boot log ../logs/boots/20261103-082158.log. CPU as s0 (psx, 30 s window, % of one core).
| clip | path | frames | dropped | CPU total | mediaserverd | venusd | WebContent | backboardd | max temp |
|---|---|---|---|---|---|---|---|---|---|
| H.264 720p (vd1) | hw | void: GPU wedge at 2084 s, 1 s after the venusd session opened; backboardd killed, SpringBoard restarted | | | | | | | |
| H.264 720p (vd2) | hw | 1800 | 769 | 274 % | 42 | 24 | 128 | 19 | 68.7 C |
| H.264 1080p (vd3) | hw | 1800 | 1207 | 297 % | 60 | 38 | 124 | 16 | 71.6 C |
| HEVC 1080p (vd4) | sw | 1800 | 1140 | 209 % | 101 | 0 | 52 | 14 | 68.7 C |
| H.264 1080p venus-off (vd5) | sw | 1800 | 1228 | 503 % | 240 | 0 | 122 | 22 | 76.7 C |
- Observed: picture and colours right on the hardware path (webcam vd2/vd3 at 40 s: bars + moving line). venusd decoded
  every frame on time (1799/1799, 29.9 and 29.8 fps, error 0); vtvenus 1800 in / 1800 out / 0 dropped; the decoder is
  created in mediaserverd (pid 944). mediaserverd 60 % vs 240 % for the same 1080p clip in software; total 297 vs 503 %.
- The dropped counts are high on both paths (software 1228 vs 100 in s0): the loss is after decode (display path), not
  the decoder. Since s0: G7 GPU YCbCr path on, bundles 4ca1221..4da54f0, kernel160, sweetgpucap=512, hotter phone, old
  Safari tabs. Beacons arrived late in a burst, so the per-clip drop pairing may be off. A/B next (SWEET_YCBCR_GPU 1/0).
- Each clip opens two venusd sessions (a 1-frame probe, then the real one): ~0.6 s start-up each (optimize later).
- GPU wedge in vd1: `SWEET GPU: wedge (hang): ... after 5 ms rptr 840 -> 840`, `killed backboardd pid 732 after
  recovery` (G4-like; 1 in 5 runs; link to Venus unknown).

### 2026-11-03 09:55 Stage 4b (vt4b): VideoToolbox decodes H.264 on Venus through our plugin, in mediaserverd
vtvenus.dylib + vtdecode 3405244 (sha256 446abe4b..., 77401726...), plugin in /System/Library/VideoDecoders/
ExampleIPB.videodecoder (tools/sunfish-install-vtvenus.sh), venusd a2752c1 started by hand; kernel160 (per-boot log
../logs/boots/20261103-082158.log). Clip work/stage3/in-1080p-{10,300}.h264.
- VTIsHardwareDecodeSupported(avc1): 1 (was 0, vd1).
- Software reference (`vtdecode --raw --hw off`, mediaserverd): 10 frames CRCs 2a544a75 ... ; 300 frames 47.1 fps.
- Plugin in vtdecode's process (`--hw require --inproc`): OSStatus 0, `using hardware decoder: yes`, CRCs equal per
  frame; 300 frames 40.7 fps, 0 dropped (venusd: 44.5 fps, copy-out 1.54 ms).
- Plugin in mediaserverd (`install --restart`): vtvenus.log `944 mediaserverd: first CreateInstance in this process:
  venusd connected`; 300 frames `0 dropped, 0 errors ... 4.97 s = 60.4 fps` (venusd 68.7 fps, first frame 600 ms after
  OPEN); 10 frames CRC-identical to software.
- Order: hardware returns the last two frames in display order (AU 9 before AU 8, as ffmpeg's reference), the software
  decoder in decode order; frames carry their own PTS, so players should not care (watch in Safari).
- Fallback: /var/local/venus-off -> CreateInstance -12906; `--hw enable/any` sessions fall back to software (OSStatus
  0); `--hw require` fails cleanly. vtdecode's default is require. No CRASH, nothing left powered.

### 2026-11-03 09:25 Stage 4a (vd4a): venusd + venusc work: 1080p 66 fps end-to-end over the socket, bit-exact
Binaries a2752c1 (venusctl 512ac1ed, venusd 6d8f7e50, venusc 638446f3) via tools/sunfish-install-venusd.sh --tools;
kernel160 boot maps512 (sweetpmemwc=2). Outputs research/notes/venus-runs/2026-11-03-vd4a-*.txt. The test script
used `nohup`, which the phone lacks (fixed: plain `env ... &`).
- 1080p 10 frames: `Venus up in 150 ms`; bit-exact (yuvcmp ok, crc 2a544a75); first frame 637 ms after OPEN.
- 1080p 300 frames to null, 2 sessions: venusc `300 frames of 300 sent; wall 4.54 s = 66.0 fps` and 65.6 fps; venusd
  `76.3 fps (frame 0 -> 299), copy-out mean 1.21 ms max 3.89 ms, error 0` and 76.0 fps; OPEN 154 ms then 0 ms
  (Venus stayed up). Round trip per frame mean ~92 ms (pipeline depth, not decode time), max ~650 ms (start-up).
- 320x240: bit-exact, copy-out 0.06 ms.
- Refusals: a second OPEN during a session -> -EBUSY (`one session at a time`), /var/local/venus-off -> -ENODEV.
- Idle 70 s -> `Venus down (idle)`, pas shutdown 0/0, clean power off. No reset, nothing left powered.
- Observed: the daemon path is faster than venusctl's serial loop (66-76 vs 52 fps). First frame ~0.6 s after OPEN
  (session setup + SEQUENCE_CHANGED reconfig) — a start-up latency Safari will see on every new video.

### 2026-11-03 08:45 v4a1: kernel160 sweetpmemwc=2 (cached + DC CIVAC): copy-out 1.54 ms, 1080p 52.6 fps, bit-exact
Kernel160 = kernel159 + xnu 0278, boot v4a1 (4455 mV) with `... sweetpmemwc=2`. venusctl 94e5e5c. Outputs
research/notes/venus-runs/2026-11-03-v4a1-*.
- 1080p 10 frames: bit-exact (all 10 luma 2073600/2073600, PSNR inf, crc 2a544a75). This first run after boot took
  13.08 s for 10 frames (copy-out itself 2.86 ms mean): a one-time cost on first use, cause not known yet (mapping the
  160 MB window cacheable? first touch?). Must be understood before =2 becomes the default.
  Rerun later in the same boot: 10/10 in 0.21 s (copy-out 1.77 ms, 55.5 fps). The 13 s sat between frame 0 and 9
  while each copy took ~3 ms, so it is a one-time decode stall after boot, not the copy (cause open; venusd boots once).
- 1080p 300 frames to /dev/null, twice: `copy-out 300 frames: mean 1.54 ms, max 3.86 ms ... frame 0 -> 299: 5.68 s =
  52.6 fps` and `mean 1.54 ms, max 3.39 ms ... 52.4 fps`. Per CPU: A55 1.56-1.72 ms, A76 0.97-1.06 ms (was 29.3 / 3.5 ms
  on the WC mapping, v4a0d).
- 720p 10 frames: bit-exact (921600/921600, crc bff84fb8), copy-out 0.83 ms mean.
- Observed: cached + clean/invalidate by range is correct for Venus's non-coherent writes (bit-exact twice) and ~18x
  faster than WC on the A55s. The overall 52 fps is now bound by venusctl's serial loop (poll, copy, CRC, re-queue),
  not by copy-out or the engine (217 fps). Phone left on kernel160 + sweetpmemwc=2.

### 2026-11-03 08:30 v4a0d: copy-out speed is the CPU type: A55 29.3 ms, A76 3.5 ms per 1080p frame
venusctl 94e5e5c (copy time per CPU via TPIDR_EL0), kernel159 (0277 WC). 1080p 300 frames to /dev/null:
research/notes/venus-runs/2026-11-03-v4a0d-1080p-300-percpu.txt. 300/300, 21.9 fps overall, copy mean 27.58 ms.
Per CPU: cpu0-4 (A55) 91/85/56/31/16 frames, 29.31-29.39 ms each; cpu6/7 (A76) 3/15 frames, 3.49 ms each; 3 moved.
So the WC path works (A76 ~900 MB/s, as camd's 0233), and the in-order A55 stalls on every uncached load (~107 MB/s),
as the investigator predicted (research/notes/venus-copy-2026-11-03.md). Fix being written: sweetpmemwc=2 = cached
mapping + clean/invalidate by range (expected 1.5-3 ms on any core).

### 2026-11-03 08:20 Stage 4a0 (v4a0): kernel159 (0277 WC window); 1080p bit-exact; Venus decodes 1080p at 217 fps
Kernel159 = kernel158 + xnu 0277 (sweetpmemwc default 1), boot v4a0 07:44 (4456 mV), per-boot log
../logs/boots/20261103-074436.log (starts at 25 s, so 0277's "/dev/pmem ready ... Venus window" line from init is not in
it). venusctl 555f5a3 + NOCOPY switch. Outputs research/notes/venus-runs/2026-11-03-v4a0*.
- Memtest of the whole window 0xa5500000+0xa000000 (160 MB): 0 of 41943040 words changed.
- 1080p x264 High, 10 frames, VENUSCTL_BUF_MB=160: 10/10, EOS in 0.49 s; yuvcmp all 10 frames luma exact
  2073600/2073600, PSNR inf, frame 0 crc 2a544a75 = ffmpeg's.
- 1080p 300 frames to /dev/null (buffers 0xa5500000-0xadf2b000, 141 MB): 300/300 in 12.75 s; `copy-out 300 frames:
  mean 25.17 ms, max 38.17 ms (3133440 bytes each); frame 0 -> 299: 12.70 s = 23.5 fps` (~124 MB/s: ~9x the device
  path's 14 MB/s, far from camd's ~900 MB/s with 0233).
- Same with VENUSCTL_NOCOPY=1 (no copy, no CRC, no write): 300/300, EOS in 1.41 s, frame 0 -> 299 in 1.38 s =
  **216.7 fps**. The engine is ~2x the CPU decoder's 112 fps (vtdecode) at no CPU decode cost; the copy is the limit.
- Next: fast frame copy (why 124 not ~900 MB/s: 64 KB pread chunks? mapping per call? try a user mmap of the WC
  window or a cached mapping + invalidate), or skip the copy (stage 5 zero-copy). At 25 ms/frame, 1080p30 would cost
  ~75 % of a core in copies, against the < 15 % target.

### 2026-11-03 08:20 Stage 3 GO (v3e): Venus decodes H.264 bit-exact, 320x240 and 1280x720
venusctl dba0c44 (sha256 2432c900...), boot venusR (kernel158). Outputs research/notes/venus-runs/2026-11-03-v3e-
{decode-320,decode-720}.txt and the decoded .nv12 files. With BUFFER_SIZE_MINIMUM sent for OUTPUT2:
- 320x240 (10 frames x264 baseline): `SEQUENCE_CHANGED sufficient`, `decoded 10 of 10 frames, EOS in 0.15 s`; frame 0
  `FBD flags 0x30 filled 147456 ts 0 us, 320x240 at 0,0, pic type 0x1, luma crc32 aba7ae5c` (= ffmpeg's). yuvcmp:
  all 10 frames luma exact 76800/76800, Y and CbCr PSNR inf.
- 1280x720: 10 of 10, EOS in 0.97 s (includes session setup), filled 1413120 per frame; yuvcmp all 10 luma exact
  921600/921600, PSNR inf, frame 0 crc bff84fb8 = ffmpeg's.
- Both: exit 0, clean close, shutdown, power off; no reboot. No firmware error lines.
- Observed: Qualcomm's video engine decodes H.264 on our kernel with output identical to ffmpeg. Not yet measured:
  steady-state speed (fps on a long clip), CPU and power. Next: stage 4, a VideoToolbox decoder plugin in the slot that
  already loads in mediaserverd (ExampleIPB.videodecoder), with venusctl's decode path as a library.

### 2026-11-03 08:05 Stage 2 step 7 part 2 (s7c): 29/29 rounds under 15 min of UI load; stage 2 complete
venusctl dcf8abc, boot venusR (kernel158). research/notes/venus-runs/2026-11-03-s7c-{session,uisoak}.txt. One
bring-up round (power, PAS boot, init, session init/end, shutdown, power off) every 30 s during `sunfish-uisoak.sh s7c
900`. 29/29 exit 0; init 7-8 ms; session errors 0 every round. Soak: `s7c: 907 s (done), 117994 submits, G1 0, G2 0,
G4 0, backboardd restarts 0, max 82.2 C, caps 0, critical 0, failed recoveries 0`. No reset. Stage 2 spec done.

### 2026-11-03 08:00 Stage 3: why "Not enough output2 buffers" (read-only, firmware disassembly)
research/notes/venus-stage3-continue-2026-11-03.md. In venus.b02 (A32), h264Dec_Continue (0x8aa1c) calls a check
(0xe0658) that fails on count (dec[0x130] < dec[0x11c]), on output2 size (required > dec[0x14c]) or an internal flag;
all three print the same line 224. dec[0x14c] is written only by BUFFER_SIZE_MINIMUM for type 3 (0xdf2c4), reset to 0
at 0xdb214. venusctl never sent it; downstream does in start_streaming (msm_vidc.c:1183-1196, file added to
research/ext). That fits all of v3-v3d (count and order made no difference). 0x700000e in SEQUENCE_CHANGED is the
input-crop extradata (vidc_hfi.h:86); our copy stopped at 32 of 44 words.
Fix cb07f29 + dba0c44: `output2 size minimum` {OUTPUT2, size} in alloc_outputs (first pass and reconfig), whole event
parsed. Guess (investigator ~80 %): no INSUFFICIENT event at all now, or CONTINUE gets past line 224. Run v3e next.

### 2026-11-03 07:50 Stage 2 step 7 (s7b): 10 of 10 bring-up rounds in one boot
venusctl dcf8abc (sha256 72a7e3a9...), boot venusR (kernel158). research/notes/venus-runs/2026-11-03-s7b-session-x10.txt,
07:01:46-07:02:00. Each round: power on, PAS boot, init, SYS_INIT, session init/end, shutdown, power off.
- 10/10 exit 0; init 7 ms (8 in round 1); SESSION_INIT_DONE and SESSION_END_DONE error 0 every round; ~1.1 s per
  round (max ~1.4). No new panic/watchdog/GPU hang lines, SSH fine, no reboot.
- Banks now repeat: SMR15-18 -> CB4, CB14, CB15, CB16 every round (leak fixed). Observation: CB4 is low; it passes
  the free test (no SMR points at it, translation off, CBAR 0 or ours) but may be a bootloader leftover. Watch it.
- Left of step 7: 15 min under GPU load.

### 2026-11-03 07:45 Stage 2 step 7 (s7): round 2 out of SMMU banks; leak fixed
venusctl f0c3847, same boot. research/notes/venus-runs/2026-11-03-s7-session-x10.txt. Round 1 ok (init 7 ms,
session errors 0, took CB54-57). Round 2: CB58-60, then `smmu: no free SMR/bank (SMR 18, bank -1)`, undone, power
off 0, no reboot. Cause: a released bank keeps CBAR 0001f000 (the write back to 0 doesn't take), and the free test
wanted CBAR 0, so every run since v2a used up 4 of the 61 banks (CB14 ... CB60 today). Fix dcf8abc (phone/wifi/smmu.c,
shared with wland/adspboot, not rebuilt there): an unreferenced, non-translating bank with exactly our CBAR is free.
Rerun s7b next.

### 2026-11-03 07:40 Stage 3 v3d: the decoder switches: split mode and queue-only DPBs are right, count is not it
venusctl f0c3847, same boot. Outputs research/notes/venus-runs/2026-11-03-v3d-{a,b,c,d}.txt (switches passed through a
scratch copy of the script; tools/sunfish-venus-test.sh now forwards VENUSCTL_* itself).
- a VENUSCTL_PRIMARY=1: FRAME_SIZE on OUTPUT refused: `h264Dec_SetIntProperty(390): Unsupported buffer type in frame
  size set property!`, session error 0x1008. Split mode (OUTPUT2) is required on this firmware.
- b VENUSCTL_DPB_SETBUF=1: the internal buffers are acked, all 18 DPBs refused: `vDec_SetBuffers(1882):
  Dec_SetBuffers, Invalid 2 buffer`, session error 0x1010 per DPB. DPBs go by FTB only (as the default does).
- c both: as a.
- d VENUSCTL_NOUT=24: min_host follows to 24, 24 output2 queued, CONTINUE -> same `Not enough output2 buffers!`.
- All four: 0 frames, clean power off, no reboot. Investigator on the reconfig packets vs msm_vidc.

### 2026-11-03 07:30 Stage 3 v3c: buffers queued before CONTINUE, same firmware error
venusctl f0c3847 (sha256 686bf9f5...), same boot. Output research/notes/venus-runs/2026-11-03-v3c-decode-320.txt.
- Order now: FLUSH output (36 back, filled 0), FRAME_SIZE OUTPUT2 320x240, requirements (output/output2 min 5,
  min_host 18, actual 18), dpb size min 0x26000, counts 18/18, 36 FTBs (no FBD comes back: the firmware holds them),
  then CONTINUE (`cmd 0x21100d`). Firmware: `h264Dec_Continue(224): Not enough output2 buffers!` again; 0 of 10 frames
  in 3.19 s; clean close and power off, no reboot.
- So neither the count (v3b) nor the order (v3c) is it. Next: the decoder's switches (v3d: primary mode, DPB
  SET_BUFFERS, 24 outputs) on the phone, and an investigator comparing our FTB/reconfig packets with msm_vidc.

### 2026-11-03 07:20 Stage 3 v3b: 18 output2 buffers set, still 0 frames: CONTINUE went before the buffers
venusctl 1ace6d0 (sha256 0da2f602...), same boot. Output research/notes/venus-runs/2026-11-03-v3b-decode-320.txt.
- Before the event: output/output2 min 18, min_host 0; 18 DPBs + 18 output2 set; START_DONE 0. After SEQUENCE_CHANGED
  (properties 0x1005 = 32 16, 0x1003007 = 2 0, 0x1003009 = 1, 0x100300a = 0, 0x1204004 = 1; 0x700000e not parsed):
  output/output2 min 5, min_host 18, actual 18; the tool set 18 + 18 this time.
- Order in the log: FLUSH output (all 36 come back filled 0), FRAME_SIZE, requirements, counts, then `cmd 0x21100d`
  (CONTINUE), then the 36 FTBs. Firmware again: `h264Dec_Continue(224): Not enough output2 buffers!`. 0 of 10 frames
  in 3.19 s; close all error 0, clean power off, no reboot.
- Reading: the firmware counts the output2 buffers it holds when CONTINUE arrives, which was none after the flush.
  Fix f0c3847: FTB first, then CONTINUE. Run v3c next.

### 2026-11-03 07:10 Stage 3 first decode (v3): session runs to START, 0 frames: too few output2 buffers
venusctl 3d06aae (sha256 3ac87217...), boot venusR (06:26, kernel158). Outputs research/notes/venus-runs/
2026-11-03-v3-{install,memtest-buf,decode-320}.txt. Input work/stage3/in-320x240.h264 (16681 bytes, 10 frames).
- Buffer window memtest 0xa5500000+0x4000000: 0 of 16777216 words changed in 60 s.
- decode: buffers 0xa5500000-0xa5ca1000 (7812 KB), split mode (OUTPUT UBWC DPB + OUTPUT2 linear NV12, stride 384,
  scanlines 256). Requirements: input 155648 x min 4; output 155648 min 18; output2 147456 min 18; scratch 345600;
  scratch_1 1422848; persist_1 147456. Every property set answered without error; 18 DPBs + 18 output2 buffers;
  LOAD_RESOURCES and START_DONE error 0; ETB 0-3 (5128, 1343, 1467, 1295 bytes).
- SEQUENCE_CHANGED insufficient (320x240, capture min 5; property 0x700000e not parsed). After reconfig the tool
  set 8 DPBs + 8 output2 buffers (new table: min 5 but min_host 18, scratch_1 1136640), then CONTINUE; firmware:
  `h264Dec_Continue(224): Not enough output2 buffers!`. FBDs only came back empty (filled 0). 0 of 10 frames in
  3.15 s; close sequence all error 0 (SESSION_END_DONE), clean shutdown and power off, no reboot.
- Fix 1ace6d0: output and DPB counts are at least the firmware's min_host. Run v3b next.

### 2026-11-03 07:00 Stage 2 go (v2c): clean boot, ping, H.264 decoder session open/close
venusctl ee0ffd4 (sha256 c3ea219f...), boot venusR (06:25:56, kernel158), VENUS_PHYS=0xa5100000. Outputs
research/notes/venus-runs/2026-11-03-v2c-{boot,ping,session}.txt. All three exit 0 with a clean power off, no reboot.
- boot: `boot ok, undone -> ok`. Saved vs read per released bank, e.g. `SMR15/CB14 saved vs read: SMR 00000000/00000000
  S2CR 000200ff/0000000e CBAR 00000000/0001f000 CBA2R 00000000/00000000 SCTLR 2a75810a/2a75810a`: S2CR and CBAR
  writes back to the saved values don't take (S2CR reads the bank index, CBAR keeps 0001f000); the SMR is invalid, so
  nothing streams through. Guess: the hypervisor's SMMU emulation keeps its own S2CR/CBAR. SCTLR is restored.
- ping: not acked, non-fatal; same session-error event (HFI_EVENT_SESSION_ERROR, 0x1004 invalid session ID).
- session: SYS_INIT_DONE error 0 (75 properties); `SESSION_INIT_DONE session 0x76656e75 error 0, 0 properties`;
  `SESSION_END_DONE session 0x76656e75 error 0`; pas shutdown 0/0, power off 0.
- Stage 2 is a go. Left from the spec: step 7 (ten rounds in one boot, then 15 min under GPU load). Stage 3 (first
  decoded frame, `venusctl decode`) is with the implementer.

### 2026-11-03 06:50 Stage 2 (v2b): the firmware boots and speaks HFI; ping not answered; reboot after
Same boot as v2a until the planned everyday reboot at 06:25:56 (tag venusR, 4456 mV). Outputs in
research/notes/venus-runs/2026-11-03-{boot-v,memtest,ping}.txt (gitignored). VENUS_PHYS=0xa5100000.
- boot (VENUS_V=1) FAIL again only in teardown. smmu_identity: SIDs 0x1080/0x10a0/0x10c0/0x10e0 -> CB19-22 via
  SMR15-18 (`SMR 80001080 S2CR 00000013 SCTLR 000000e0 CBAR 0001f000 -> ok`). Release: SMRs read 00000000, S2CR
  0000000e, SCTLR a different random-looking value per bank (e.g. 20438118), "NOT as saved". Bank numbers move
  between runs (CB23-26 in ping).
- memtest PASS: 0 of 787456 words changed in 60 s (0xa5100000+0x301000).
- ping: PAS loads 1101228 bytes at 0x94800000, auth 0/0; queues at 0xa5100000 (cmdq +0x1c8, msgq 0xa51c81c8,
  dbgq 0xa52901c8, SFR 0xa53fe000); **CTRL_STATUS 0x40000001 after 7 ms (init 1, error 0)**, VERSION_INFO 5,
  **SYS_INIT_DONE error 0, 75 properties**, firmware log `QC_IMAGE_VERSION_STRING=VIDEO.IR.1.2-00053-PROD-1`, BUILD_TIME
  May 24 2021. SYS_PING (0x210002) is not acked: firmware logs `HostDriver_GetSessionIdx fail, ID 76656E75 not find`
  and sends type 0x21001 `0000001c 00021001 76656e75 00000002 00001004 00000000 00000001` (reads word 2 as a session
  ID). STOP after 1000 ms; pas shutdown 0/0, then the SMMU release check fails -> LEFT POWERED -> everyday reboot.
- Observed: the Venus core runs Qualcomm's firmware under our kernel and answers HFI over the shared queues. Stage 2's
  goal (alive and talking) is reached except the ping reply.
- Next (implementer): release counts as done when the SMR reads invalid (warn on the rest, print saved vs found);
  ping non-fatal; new `session` step (SYS_SESSION_INIT H.264 decoder + SESSION_END) as the real round trip.

### 2026-11-03 06:35 Stage 2 on the phone (v2a): probe, power, pas pass; firmware authenticates; boot teardown check fails
venusctl d0f1da4 (sha256 93726b46...) installed; /var/local/fw/venus: b00 212, b01 6808, b02 1060680, b03 40516,
b04 32, mdt 7020 bytes. Kernel158 boot of 2026-11-02 21:31, no reboot, VENUS_PHYS=0xa5100000. Markers `=== venus-*`.
- probe PASS: `gcc_video_ahb 0x10b004 = 0x80000003` (HW_CTL, en 1); 15 valid SMRs, none for SIDs 0x1080-0x10e0.
- power PASS: pll0 locked at 384.0 MHz (MODE 0xd0800005); WRAPPER_HW_VERSION = 0x5011020a; power off restores the start.
- pas PASS: supported(9) 0/0, init_image 0/0, shutdown 0/0.
- boot FAIL (exit 1), but only in teardown: auth_and_reset 0/0 and mem protect 0/0 (image linked at 0xf500000,
  relocated to 0x94800000). Right after auth CTRL_STATUS, VERSION_INFO, CPU_STATUS, INTR_STATUS all 0 (expected
  before init, guess). Then smmu_release reports CB15-18 "NOT as saved", e.g. `SMR15 (00000000) S2CR 0000000e CB15
  SCTLR 07836516 CBAR 0001f000 CBA2R 00000000`. Shutdown and power off returned 0, final probe = start state, SSH
  fine, no panic/watchdog/GPU hang. Not run: memtest, ping.
- Guess: the SMRs read back invalid (0), so no stream uses those banks; the hypervisor's SMMU emulation or the
  auth/mem-protect call may rewrite them. Next: verbose boot rerun to see saved vs found, then memtest and ping.

### 2026-11-03 06:25 Stage 0: Safari baseline on the software path (s0), WebGL lost at creation
Kernel158 everyday boot (2026-11-02 21:31, no reboot), bundle 82f6b41, external power 4427 mV, iOS slider minimum.
Per-boot log ../logs/boots/20261103-004005.log, 06:10-06:22. Page work/stage0/index.html (gitignored; clips 60 s,
30 fps testsrc2, muted autoplay, beacons to the PC's http.server on 192.168.7.1:8077). CPU = psx CPU-seconds delta
over 30 s (10-40 s into the clip), % of one core; temp = max SWEET THERM a55.
| clip | plays | frames | dropped | CPU total | top processes | max temp |
|---|---|---|---|---|---|---|
| H.264 720p | yes, t=60 | 1800 | 3 (17 in a first run) | ~400 % (sum of top 3; total lost) | WebContent 127, mediaserverd 124, backboardd 53 | 59.9 C |
| H.264 1080p | yes, t=60 | 1800 | 100 (5.6 %) | 590 % | mediaserverd 257, WebContent 138, backboardd 96 | 64.1 C |
| HEVC 720p | yes, t=60 | 1800 | 5 | 247 % | mediaserverd 70, WebContent 64, backboardd 50 | 62.2 C |
| HEVC 1080p | yes, t=60 | 1800 | 49 (2.7 %) | 346 % | mediaserverd 115, backboardd 93, WebContent 63 | 63.2 C |
- Observed: all four play to the end with no error beacon, no GPU hang, no backboardd restart. The live log has no
  decoder line at all (VideoToolbox, vtdecode, ExampleIPB, "planar iosurface", AppleAVD, H264/HEVC: 0 each), so it
  doesn't show which path decodes. Webcam frames at 10 s showed the colour bars for H.264 and a blank area for HEVC
  (first paint late; the beacons show full playback).
- Guess: mediaserverd is the software decoder; HEVC costing less CPU than H.264 at the same size is unexpected (maybe a
  different, better-threaded decoder, or the HEVC files' lower bitrate: 31 MB vs 46 MB). Target (under 15 % of one core)
  is 20-40x away.
- WebGL (webgl.html, 400 cubes): `getContext('webgl')` returns a context that is already lost: isContextLost true,
  getError 37442 (CONTEXT_LOST_WEBGL), RENDERER null, createShader null. No frames. Nothing about GL in oslog
  (research/notes/webgl/wgl-2026-11-03.oslog); the GPU process logs `lowMemoryHandler: critical=1` a second later.
  New backlog B55; investigator on it.

### 2026-11-02 23:10 venusctl: pre-run review fixes
(research/notes/venus-stage1-2026-11-02.md 8.5; built with phone/wifi/build.sh, not run on the phone yet)
- 1 Stale state: STATE and AHB_STATE carry `boot <kern.bootsessionuuid>` (fallback kern.boottime); a file from another boot (or without the line) is dropped unread ("stale state from an earlier boot: dropped"; VENUSCTL_NO_BOOTID=1 keeps it). Teardown releases an SMR only if it still reads exactly 1<<31|sid with S2CR translate -> our CB, else prints why and leaves it.
- 2 `power off` refuses while STATE says pas 1 (`--force` overrides). Script: an exit 124 or a failed shutdown stops the run with no power off and prints "LEFT POWERED: reboot needed".
- 3 Script passes `--cvp` to every power on/off.
- 4 init re-reads the mnoc_sf_0_tbu vote (0x17d044 PWR_ON) right before CTRL_INIT, q_write before each doorbell; STOP if off (status 0x15182220 printed, bits unknown; VENUSCTL_NO_TBUCHECK=1 skips). No vote of our own.
- 5 gdsc_on clears a set HW_CONTROL (SW mode, as downstream) and prints it; STOP if it stays set.
- 6 `init --phys` (and the queue check): 1 MB aligned, ADDR+3 MB+4 KB within 0xa5030000-0xbcc00000 and 0x25800000-0xe0000000.
- 7 `pas-check --no-shutdown` writes STATE pas 1 (with the boot id), so `shutdown` undoes it.
- 8 New `venusctl memtest ADDR SIZE write|check` (pattern addr ^ 0x5a5a5a5a, /dev/pmem as init; count + first 5 mismatches); script step `memtest` (0xa5100000+0x301000, 60 s, check).

### 2026-11-02 23:00 venusctl: boot, init, ping, shutdown written (stage 2 steps 4-6), not run yet
- phone/wifi/venusctl.c: `boot [--fw DIR] [--keep]` (exact SMRs via smmu.c smmu_identity mask 0 for 0x1080/0x10a0/
  0x10c0/0x10e0, one translation-off bank each; refuses if any SMR already matches; CPU_CGC_DIS/CPU_CLOCK_CONFIG = 0;
  PAS init_image/mem_setup/load to 0x94800000/auth_and_reset(9); memory protect 0x42000c08 (0, 0x25800000,
  0x1000000, 0x24800000); status reads), `init [--phys ADDR]` (3 MB block from PMEM_ALLOC32, else only an explicit
  1 MB-aligned address in 0xa5100000-0xbcc00000; table/queues as downstream, SFR at +0x2fe000; UC/QTBL/SFR/VMIMSG
  registers, CTRL_INIT = 1, 1 s poll), `ping [--debug MASK]` (SYS_INIT, debug config, IMAGE_VERSION, SYS_PING, message
  queue polled), `shutdown` (PAS shutdown, queue memory, SMRs from /var/tmp/venusctl.state). Every core access gated on
  the clocks/GDSCs. Off switches: VENUSCTL_SID1=1, VENUSCTL_NO_CLKCFG=1, VENUSCTL_NO_MEMPROT=1.
- Guesses: SFR inside the UC region at +0x2fe000 (downstream allocates it right after the 0x2fe000 queue block);
  debug mask 0x18 (ERROR|FATAL; downstream default not in our source copy); doorbell only when cmdq rx_req = 1 (as
  downstream); ping client_data is our cookie; interrupt_init_vpu5 (INTR_MASK) left out (we poll).
- tools/sunfish-venus-test.sh probe|power|pas|boot|ping: the venusctl sequence per step over sunfish-ssh, always ending
  with shutdown + power off (probe excepted: read-only).

### 2026-11-02 22:50 venusctl: AHB HW_CTL handling
- Seen in vd1 `venusctl probe`: gcc_video_ahb 0x10b004 = 0x80000003 (CLK_ENABLE 1, HW_CTL 1, CLK_OFF 1), gcc_video_axi
  0x10b01c = 0x80000000, gcc_video_xo 0x10b028 = 0x80000000. The "AHB on" gate (CLK_OFF = 0) never passed.
- Source: no downstream gcc-sdmmagpie.c in research/ext/msm-vidc-sunfish/ (only the dt-bindings header). Mainline
  research/re/gcc-sm7150.c: gcc_video_ahb and gcc_video_xo are not clk_branches at all, only
  `qcom_branch_set_clk_en` (CLK_ENABLE bit 0) in probe, "keep some clocks always-on" (:3007 0x0b004, :3011 0x0b028);
  no hwcg_reg, no halt_check. gcc_video_axi (:2618-2629): BRANCH_HALT on 0xb01c, no hwcg; its BCR at :2921.
  Linux clk-branch.c:72 skips every halt check while a branch is in HW_CTL mode, so CLK_OFF = 1 under HW_CTL is
  normal idle gating, not "off". Downstream DT: GCC_VIDEO_AHB_CLK is the ahb_clk of mvsc/mvs0/mvs1 GDSCs
  (sdmmagpie.dtsi:4013,4019,4026); no video node uses GCC_VIDEO_XO_CLK (videocc parent is bi_tcxo,
  videocc-sdmmagpie.c:60,100; venus PIL node takes VIDEO_CC_XO_CLK, dtsi:3408).
- Change (phone/wifi/venusctl.c): power on clears HW_CTL on gcc_video_ahb (CLK_ENABLE kept), saves the old CBCR in
  /var/tmp/venusctl.ahb, then polls CLK_OFF = 0 for 100 ms (BRANCH_HALT style, as gcc_video_axi: no source gives a
  halt_check for this branch); power off restores HW_CTL from that file after the videocc teardown. probe prints
  "hw-gated (HW_CTL)" for a GCC CBCR with CLK_OFF + HW_CTL and still skips videocc then (read-only kept).
  gcc_video_xo is not added to the allow-list (no video consumer). Off switch: VENUSCTL_KEEP_HWCTL=1. Not run yet.

### 2026-11-02 22:45 vd1: decoder slot loads in mediaserverd; venusctl probe; software baseline (night, read-only)
- Run vd1, kernel158 everyday boot of soak n8 (20261102-213020), markers `=== vd1 *`.
- vtstub at /System/Library/VideoDecoders/ExampleIPB.videodecoder: loaded by vtdecode (pids 1478, 1498, 1500) and by
  mediaserverd right after `psx -k mediaserverd` (pid 1485). No crash lines; stub removed, mediaserverd back (pid 1512).
  One of four vtdecode runs left no log line (unexplained). Stage 4 entry point works.
- vtdecode, synthetic testsrc2 H.264 10 s / 300 frames, software path (`using hardware decoder: no`,
  VTIsHardwareDecodeSupported 0, hardware-required session -12906): 720p 212.6 fps (1.41 s), 1080p 112.2 fps (2.67 s);
  same with the stub (218.8, 213.8, 110.5). Every run prints `IOServiceMatchingfailed for: AppleM2ScalerCSCDriver`.
  CPU share not measured (fps is decode-as-fast-as-possible; a CPU % at 30 fps playback is stage 0's job).
- venusctl probe: gcc_video_ahb 0x10b004 = 0x80000003 (enable and HW_CTL set, CLK_OFF 1: hardware-gated, so the
  probe's AHB-on check skipped videocc); gcc_video_axi 0x80000000, gcc_video_xo 0x10b028 0x80000000 (off); TBU vote
  0x17d044 = 0x80000001; SMMU 79 SMRs, 15 valid, none for SIDs 0x1080-0x10e0 (boot step must add exact SMRs); cmd-db
  has MM3 and MM2 (aux 00197b70 00040020).
- For `power on`: with HW_CTL set the AHB branch reads off until something uses it; clear HW_CTL (bit1) before polling
  CLK_OFF, or the gate check never passes (guess, check against downstream gcc-sdmmagpie).

### 2026-11-02 22:00 Plugin loading checked (read-only)
- Free slot /System/Library/VideoDecoders/ExampleIPB.videodecoder, symbol _ExampleIPBDecoderRegister (0x194fe0c5f/c95).
  No library validation hook in sweet_amfi.c; SunfishAudio.driver already runs inside mediaserverd. Phone test next: a
  stub that only logs which processes load it.

### 2026-11-02 21:50 venusctl written (stage 2 steps 1-3), not run yet
- phone/wifi/venusctl.c (3851cad): `probe` (read-only), `power on/off [--cvp]`, `pas-check [--fw DIR] [--no-shutdown]`.
  Writes only to a fixed allow-list (GCC video branches, videocc PLL0/RCG/GDSCs/branches, RPMh MM3+MM2); no SMR writes;
  videocc access gated on gcc_video_ahb bit31; 100 ms poll timeouts; a failed `power on` runs `power off`.
- Guesses in it: MM3/MM2 vote x=1,y=1 (probe prints whether cmd-db has them); GDSC SW_COLLAPSE bit0 from Linux;
  gcc_video_ahb left on at power off; efuse 0x786018 bit10 picks PLL L=0x14 vs 0x19 (downstream). PAS shutdown only
  after a successful init_image (adspboot adsp3: shutdown with nothing loaded blocked forever).
- Phone step needed first: copy venus.mdt + .b00-.b04 to /var/local/fw/venus (iOS has no /vendor), log in device-changes.

### 2026-11-02 22:00 Stage 1 research done (read-only)
- No blocker found: firmware is on the phone's vendor partition, TrustZone PAS ID 9, register map, clocks, GDSCs, SMMU IDs
  and memory region come from the phone's own live DT (../recon/live.dts) and the downstream sunfish 4.14 driver.
  VideoToolbox entry point found (a free name on its decoder load list). Facts and the stage 2 spec above. Confidence:
  high on DT/firmware/PAS ID/packet IDs/load list (source or binary), medium on the order of power steps and bus votes.

### 2026-11-02 20:10 Plan adopted: hardware video decode is priority 1
- The user's goals: video-heavy apps like Instagram, then games (Minecraft). Video playback was never tested on the port.
  Stage 1 research can run without the phone; stage 0 needs it back.
