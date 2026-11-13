# iOS 16 on a Google Pixel 4a (sunfish)

**Apple's iOS 16 userland running on a Pixel 4a, booted from RAM with Google's own bootloader.**

Pixel 4a (`sunfish`): Qualcomm SM7150 (Snapdragon 730G), Adreno 618 GPU, 1080x2340 OLED panel.

## Lineage

A port of [ios-flame](docs/archive/flame/) (the Pixel 4 port), which is itself a port of
[ios-sweet](https://github.com/dipa-studio/ios-sweet) (Redmi Note 10 Pro). Apple's open-source XNU kernel
(xnu-8796, the iOS 16 generation), with ios-sweet's, flame's and the sunfish patches on top, runs the iOS 16.7.16
userland of the iPhone X. The phone is booted with `fastboot boot`; nothing is flashed to the boot chain, and the
iOS root lives in the `userdata` partition.

- flame docs (Pixel 4): [docs/archive/flame/](docs/archive/flame/)
- sweet docs (Redmi Note 10 Pro): [docs/archive/sweet/](docs/archive/sweet/)

> Experimental bring-up, not a usable phone OS. It **erases Android's user data**, Apple's security model is
> mostly switched off (permissive AMFI and sandbox, stub keystore), and many parts are missing. Do not put
> anything personal on it.

## Status (2026-11-13)

States: ✅ works, 🟡 partial, ❌ broken, ⬜ not started. Each row links to the feature file with the details; the
plan is [docs/plan.md](docs/plan.md).

| Area | State | Summary |
|---|---|---|
| [Boot](docs/features/boot.md) | ✅ | RAM-only `fastboot boot`; iOS 16.7.16 (iPhone X userland) root on userdata |
| [CPU](docs/features/cpu.md) | ✅ | 8 cores; A55 1497 MHz, A76 1939 MHz by default (2026-11-02, kernel158: soak peaks about 6 C lower, none at 90 C); temperature logged; idle 54 C after 1 h with 2 stuck daemons fixed (was 79-85 C) |
| [Storage](docs/features/storage.md) | ✅ | /private/var on a 94 GB HFSX volume (ufsroot1) via /private/etc/fstab; direct (uncached) I/O fixed |
| [USB network](docs/features/usb-network.md) | ✅ | Ethernet 192.168.7.2, live kernel log; boot to SSH 16-18 s |
| [SSH](docs/features/ssh.md) | ✅ | dropbear + dash + toybox; boot to SSH 16-18 s |
| [Display](docs/features/display.md) | ✅ | 1080x2340, GPU-composited (Metal → Turnip), vsync-paced; apps rotate to landscape and back on command (`R 3`/`R 1`), touch follows; auto-rotate waits for sensors |
| [WebGL](docs/features/webgl.md) | ✅ | WebGL 1 and 2 draw in Safari: a three.js 3D game (games_fps, WebGL 2) ran 15 min with 0 GPU hangs at 7.4 fps (GPU-bound); 400 textured cubes 24 fps, 18 with MSAA (2026-11-03) |
| [Video](docs/features/video.md) | 🟡 | Safari plays H.264 and HEVC 720p/1080p with hardware decode; the picture equals ffmpeg's frame and keeps up with the page clock (2026-11-12); GPU colour conversion on by default (SWEET_YCBCR_GPU=1; 15 min 1080p clean, backboardd ~20 % CPU, was ~45 %; 2026-11-13) (Venus via our VideoToolbox plugin + venusd, started at boot): 0-48/1800 dropped, recovers from engine faults, mediaserverd ~4x less CPU than software, first frame 0.6 s after a session opens; HEVC 8-bit plays through Venus too; decoded frames go straight into the player's buffers (mediaserverd 55 -> 20 %, venusd 32 -> 10 % at 1080p, 2026-11-03) |
| [Smoothness](docs/features/smoothness.md) | 🟡 | Safari 60, Settings 57 (p95 19.3 ms, no low launches since kernel157's vsync phase, 2026-11-02), Home about 53, Control Center 43.8 swaps/s (TU_FETCH_GMEM_MIN_DRAWS=20 and the cover cull SWEET_CULL=3, 2026-11-02), full resolution, defaults since 2026-11-02: luma boost off, was env SWEET_DEADFILL=3 M2V_SHADOW_CACHE=1 SWEET_U0011..14=1 + tools/sunfish-install-ccscale.sh (2026-11-01, kernel139, not default yet); target 60 |
| [Haptics](docs/features/haptics.md) | ✅ | iOS haptics work: switch taps pulse the motor (DRV2624 via hapticd, launchd job, `HAPTICS=1` boot); feel check by the user open |
| [Brightness](docs/features/brightness.md) | ✅ | Control Center slider drives the panel brightness (DCS 0x51, `sweetbl=2`) |
| [GPU](docs/features/gpu.md) | 🟡 | Adreno 618 at 650 MHz; SMMU-fault hangs recover (~37 ms) without a backboardd restart (2026-11-12); no-fault hangs still need a reboot but none in two full 1 h soaks (n8: 399 k submits, 0 hangs of any kind, everyday setup, 2026-11-02) |
| [GPU memory](docs/features/gpu-memory.md) | ✅ | leak fixed (spare command pools capped): pool flat over a 20 min app soak |
| [Metal](docs/features/metal.md) | ✅ | Metal via SweetMetal2 (metal2vulkan + Turnip) |
| [Touch](docs/features/touch.md) | ✅ | ST FTM5 over I²C |
| [Buttons](docs/features/buttons.md) | ✅ | power, volume down, volume up |
| [Flashlight](docs/features/flashlight.md) | ✅ | Control Center button turns the LED on and off |
| [Clock](docs/features/clock.md) | ✅ | PM6150 RTC |
| [Wi-Fi](docs/features/wifi.md) | ✅ | joins the home network at boot (from a config file on the phone); iOS shows the Wi-Fi icon and the network in Settings (`sweetwifiev=1`); 802.11n HT20, downloads ~5.8 MB/s (2026-11-03); joining a new network from Settings is untested |
| [Battery](docs/features/battery.md) | 🟡 | real reading; % shows no jumps at idle, discharge unchecked |
| [Charging](docs/features/charging.md) | 🟡 | charges (set up by the bootloader: 2 A charge, 1.5 A input); a weak USB port cannot keep up under load, a strong one gives ~+1 A |
| [Apps](docs/features/apps.md) | ✅ | garbled icons fixed on lock screen, Control Center, Settings, Home (2026-10-31, kernel132), Tips banner and Photos thumbnails still wrong; 32 stock apps installed; survey 2026-10-29: 17 of 18 open fine; Files "On My iPhone" opens; app extensions work: widgets, share sheet, emoji keyboard (2026-10-30) |
| [Sleep and wake](docs/features/sleep-wake.md) | ✅ | power-button sleep/wake; the OLED panel really switches off and back on (`sweetpanelsleep=1`, 10/10) |
| [Audio](docs/features/audio.md) | ✅ | iOS sound plays through the bottom speaker (first time 2026-10-31, capped at -20 dB, quiet); AirPods play music; earpiece and mics not done |
| [Camera](docs/features/camera.md) | 🟡 | iOS lists both cameras (Back 16 formats, Front 18); Camera.app works: live colour preview on both cameras, auto-exposure, autofocus and sharp saved photos (2026-10-30); camera opens in 0.7 s (was 5.7 s), 30 fps to clients (2026-11-03); switching cameras takes ~7 s + ~10 s until the picture shows; Live Photo off; both cameras stream from tools (rear 60 fps, front 30 fps) |
| [Bluetooth](docs/features/bluetooth.md) | ✅ | iOS Settings: devices listed, Xbox controller and AirPods Pro 2 pair and connect (noise control works); AirPods play music (2026-10-30); pairs with a Linux laptop, A2DP (AAC)/AVRCP/HFP connect, btsnoop capture in btbridge (2026-11-13) |
| [iOS 26/27 port](docs/features/ios26.md) | 🟡 | New direction (2026-11-13): iOS 27 (or 26) arm64e userland, PAC-lowered, on xnu-12377; Gate A passed; root iOS 27.2.1 (its dyld proves); **Gate C1 passed**: iOS 27.2.1 launchd runs all early-boot tasks (24 processes) on our xnu-12377 kernel, then aborts; btsnoop done |
| [Cellular](docs/features/not-started.md) | ⬜ | not planned |
| [Sensors](docs/features/sensors.md) | ✅ | Compass works (heading + dial, 2026-10-30, kernel126); auto-rotate works (accelerometer -> rotation); proximity turns the screen off when near (kernel122); all 6 sensors answer on the audio DSP; auto-brightness parked |

## Quick start

Safety rules (all rules: [CLAUDE.md](CLAUDE.md)):
- Never flash ABL, XBL, TZ, modem or other firmware partitions.
- Never relock the bootloader on modified software.
- Stop booting below 3600 mV (`fastboot getvar battery-voltage`).

From `port/`, with the phone in fastboot:

```sh
tools/sunfish-livelog.sh ../logs/usb-live.log &      # live kernel log + USB network link (phone 192.168.7.2)
tools/sunfish-boot.sh NAME KERNEL [bootargs]         # RAM-only boot
tools/sunfish-install-ssh.sh                          # once
tools/sunfish-ssh                                     # root shell in iOS
```

From a stock Pixel 4a: [docs/setup.md](docs/setup.md); every on-device change: [docs/device-changes.md](docs/device-changes.md).
Everything else (building, benches, logs, profiling): [docs/methods.md](docs/methods.md).
Back to Android: [docs/recovery.md](docs/recovery.md).

## Repository layout

| Path | What |
|---|---|
| `xnu/patches/` | XNU patches: ios-sweet's, flame's, then the `NNNN-sunfish-*` ones |
| `shim/` | The bare-metal shim ABL boots; it acts as iBoot |
| `phone/` | Code that runs in iOS: `tools/` (debug tools), `wifi/` (wland), `metal2/` + `turnip/` (Metal on Turnip), `metal/`, `gpu/` |
| `tools/` | Host tools: boot, live log, SSH and file access, benches, GPU debugging |
| `docs/` | [README.md](docs/README.md) (docs index), [features/](docs/features/), [journal/](docs/journal/) (one file per day), [plan.md](docs/plan.md), [archive/](docs/archive/), [reference/](docs/reference/) |

## Credits and license

Built on ios-sweet by dipa-studio, with Wi-Fi from ios-topaz and HackiOS, and Metal from UniXNU, metal2vulkan
and Mesa. The repository keeps ios-sweet's [MIT License](LICENSE); `xnu/patches/` modify Apple's XNU and stay
under the APSL 2.0, and files from other projects keep their own licence. Details in [CREDITS.md](CREDITS.md).
Nothing from Apple's iOS, Google's images or Qualcomm's firmware is in this repository.
