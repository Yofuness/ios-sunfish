# Your tasks at the phone

Things only a person at the phone can do (feel, listen, look, plug in). Claude keeps working on other items meanwhile and
reads the answers here or in chat. Moved out of docs/plan.md on 2026-10-30 (the user's ask). Done ones go to
[completed.md](completed.md).

- U-X26 DONE 2026-11-13 06:55 (../restore/xcode/Xcode_26.1_Universal.xip). (2026-11-13, the iOS 26/27 direction) Xcode 26.1 for the new build VM: sign in at
  https://developer.apple.com/download/all/ with your Apple ID, download "Xcode 26.1" (.xip, ~3 GB) and put it in
  `../restore/xcode/` (create it). Also fine: Xcode 16.2 for a first try. Claude can't do this (Apple ID login). ~10 min.
- U-AP2 (2026-11-13, iOS 27 Bluetooth works, Gate E) AirPods Pro 2 on iOS 27, when you're home: tell Claude in chat
  ("AP2 ready"); Claude boots iOS 27 and runs `btctl scan` over SSH. Then: open the AirPods case next to the phone and hold
  the case button until the light flashes white (pairing mode), keep it open ~2 min while Claude runs `btctl pair`; then put
  the AirPods in your ears ~1 min (connect, maybe a few seconds of audio), then back in the case. btsnoop records it. ~5 min.
- U-AP1 CLOSED 2026-11-13 07:50 (the user: not available until evening; they will say when home, then Claude captures). (2026-11-13, stage 0 LibrePods capture) AirPods Pro 2 next to the phone (iOS 16, btsnoop recording is on
  from now on): open the case lid near the phone, put the AirPods in your ears ~60 s (connect; play anything for a few
  seconds if handy, e.g. Pirates.mp3 in Filza), then back in the case. Any time today; say "AP1 done HH:MM" in chat.
  Claude pulls /var/local/bt/btsnoop-*.log and decodes AACP. ~3 min.
- (The iOS 16 tasks below are parked by the new direction; answer them only if convenient.)
- U1 flashlight button by hand: tap on/off, long-press for a lower level. ~2 min.
- U3 battery % while discharging: phone off the charger 30 min, on kernel106 with sweetbattery=2 (Claude boots it). (B13)
- U4 one boot on the TB4 port + 240 W cable, to read the charger status on both sources (optional). (B14)
- U13 Files app: open Files > Browse > On My iPhone (it opens now, kernel121): create a folder or save something (e.g. share a photo to Files): does it work? ~2 min.
- U14 Touch while plugged in (B36): on the charger, leave the phone idle 3 min, then tap a few times: does it react? Also: in yesterday's Calculator freeze, were you touching the screen? ~4 min.
- U15 Headphone jack: READY (jack6 passed): Claude starts a 60-s detect run; plug wired headphones in at ~15 s, out at ~35 s. ~2 min.
- U16 [DONE 2026-10-30 16:05: vibration works] Haptics: toggle a switch in Settings (Sounds & Haptics): do you feel a tap? Is it too strong or weak? ~1 min (after Claude starts hapticd).
- U11 [DONE 2026-10-30 16:05: AirPods connect and play music] AirPods music: with the AirPods connected, play Pirates.mp3 (Filza: /var/mobile/Documents, or Music after import). ~2 min.
- U17 Proximity: Claude starts `proxon 3 60` (detection on); cover the top of the phone (earpiece area) with your hand: does the screen go off, and on again when you take it away? ~1 min.
- U18 [DONE 2026-10-30 16:15: sleep and wake at once, lock sound in AirPods] Power key: with the screen off (wait for auto-lock), press the power button once: does the screen wake right away? (kernel123 polls keys every 40 ms while dark.) ~30 s.
- U21 Speaker, listen (ready): Claude boots with sensors off and plays the 3 s 1 kHz test tone at -20 dB on your request (outside 9:30 pm-5:00 am): is it audible at the bottom grille, clean, how loud? The mic heard it (sp22); nobody has by ear. It's ~37 dB below stock, so it should be quiet. ~2 min.
- U22 Ghosting and stale strips by eye: the phone has `SWEET_DEADFILL=3` and `M2V_SHADOW_CACHE=1` now: swipe Home pages, scroll Settings, open and close apps, open and close Control Center (its background is now a quarter-size blur: blocky or shimmering?): any doubled icons, stale strip near the top, black holes at edges, or old content left behind? The webcam can't tell: its exposure doubles everything. ~2 min. (2026-11-02 mo3: 900 webcam frames at 30 fps showed nothing that lasts 2+ panel frames; only a single-frame strip would still be missed.)
- U23 Minimum brightness look: luma boost is off now (`CA_DISABLE_LUMA_BOOST=1`) for speed. At the slider's minimum, does text or colour look wrong, too dark or washed out? Off switch: `tools/sunfish-install-caenv.sh --undo`.
