@docs/plan.md

This file is the one home for the project's rules (AGENTS.md and the memory notes only point here). Start with
`docs/plan.md` (loaded above); read `README.md`, `docs/README.md` and `docs/methods.md` only when a task needs them.

# Sunfish (Pixel 4a) quick rules
- **Boot and partitions:**
  - Work from `port/`. RAM-only boots: `tools/sunfish-boot.sh NAME KERNEL [bootargs]`.
  - Never flash partitions, never relock, never select "Factory data reset" in recovery.
  - Writes to userdata are incremental only, with a backup first.
- **Battery and hangs:**
  - Stop booting below 3600 mV (`fastboot getvar battery-voltage`).
  - After a hard hang or reset: write it up in the feature log (`docs/features/<name>.md`) and today's journal,
    then go on with a smaller step ("Risky steps" below).
- **Git:** commit and push to branch `main` after each finished change without asking (the `sunfish` branch is
  frozen), never force-push.
- **Out of git:** Apple's files (IPSW parts, the root image, shared cache, kernelcache, anything translated from
  Apple's shaders), Google and Qualcomm images and firmware, partition dumps, device trees and logs from a phone
  (serials, IMEI, network names), Wi-Fi credentials (`/var/local/wlan.conf` lives on the phone only). Research notes
  and source excerpts go in `research/notes/` (`research/` is gitignored), never only in a session scratchpad.
- **Reproducible on-device changes** (the user, 2026-10-30): every change made on the phone (files, plists, launchd
  jobs, iOS settings changed by taps, config in /var/local) must be reproducible from git: an install script under
  `tools/`, or written steps in `docs/setup.md` that a script will replace later. Log each on-device change in
  `docs/device-changes.md` (dated, what/where/how, the script or setup step that reproduces it) in the same commit.
  For an unfinished feature under work, a log line is enough; script it once the feature works.
- **Destructive steps** (partition backups, userdata writes): confirm with the user first. `docs/recovery.md` gets
  back to stock Android.
- **Docs layout:** `README.md` has the status table (one row per feature), `docs/README.md` indexes the docs,
  `docs/features/<name>.md` has each feature's
  facts and its dated, append-only Log, `docs/journal/YYYY-MM-DD.md` is the daily journal, `docs/methods.md` the tools
  and methods, `docs/archive/` the old entries.
- **Logs:** each work session adds a dated entry (`### YYYY-MM-DD HH:MM <title>`, newest first, with run tags, kernel
  number and exact numbers) to the Log of every feature it touched, plus a line in today's journal file
  (`docs/journal/YYYY-MM-DD.md`; never rewrite a past day's file).
- **Experiments:** every experiment goes in the feature Log before the session ends, including dead ends. Never
  delete entries; add a new one to correct an old one.
- **Milestones:** when a feature starts working (or changes state), update its row in the status table of the main
  `README.md` (state, summary, the date in the table heading) and the State line of the feature file, in the same
  commit. Record the kernel number, boot args, exact results and what is still open in the feature Log; keep
  observations apart from guesses. A new kernel patch gets a line in the feature Log too.
- **Log size:** when a feature Log passes about 150 lines, move its oldest entries to `docs/archive/features/<name>.md`.
- **The plan:** `docs/plan.md` is the current plan, loaded into every session and agent, so keep it short (about
  6 KB): current state only, one line per item, details and history in the feature Logs. Keep it current as you
  work:
  - Mark each step done or failed in the same commit as the work; move finished items to `docs/completed.md` (not auto-loaded; the user, 2026-10-30).
  - Add new findings or next steps as you find them.
- **New plan:** move the old one to `docs/plans/YYYY-MM-DD-<topic>.md`. Put a short header on it saying
  what was done, what was not, and what replaced it, then write the new `plan.md`.
- **All builds are local** (the user's rule, 2026-10-28). The GitHub workflows have no push trigger; don't run them
  (`gh workflow run`) unless the user asks.
- **Metal bundle (Turnip and bridge patches):**
  1. `tools/build-metal2-linux.sh`
  2. `tools/sunfish-metal2-install.sh work/metal2-linux/out/phone/metal2/out --no-restart`
- **Phone tools:**
  1. `tools/build-userland-linux.sh`
  2. `python3 -I tools/flame-files.py put work/userland-linux/out/NAME /var/local/bin/NAME 755`
- **Kernel:** the tree is `work/src/xnu` (a git repo, HEAD = baseline + applied patches). Commit there, save the
  diff as the next `xnu/patches/NNNN-sunfish-*.patch`, build with `tools/vm-build-xnu.sh NN` in the local macOS VM
  (`~/VMs/macos`, ~35 s incremental) -> `work/kernelNN`. Never start a second VM instance, and never `pkill -f` a
  pattern that matches your own shell: the VM scripts use `~/VMs/macos/qemu.pid`.
- **USB cable:** keep it in the laptop's TB4 port with the 240 W cable (charges ~+950 mA under load). The link does
  not survive a physical unplug/replug: move the cable only while the phone is off or in fastboot.
- **Before booting:** start the live-log listener if it isn't running (`pgrep -af sunfish-livelog`). It also
  provides the USB network link. The log is split per boot: `../logs/boots/` (one file per boot, named by its
  start time; test markers `=== TAG` are inside); `../logs/usb-live.log` still gets every boot (old ones gzipped in
  `../logs/archive/`). Search the per-boot file, not
  everything.

# How to work (the user's rules, 2026-10-29; keep these across compactions)
- **Goal:** keep iterating until everything on iOS works (except iCloud). Getting as many systems working as
  possible comes first.
- **Speed focus** (the user, 2026-10-31): ENDED 2026-11-02 (the user). Rules below that say "during the speed focus" no
  longer apply. Current focus (the user, 2026-11-02): hardware video decode first, then apps and games (docs/plan.md).
- **Focus:** a couple of systems at a time, from the Priority list in `docs/plan.md` (at most 5, the active one
  marked). Easy things go first: the user loves seeing progress.
- **After each finished priority item** (paused during the speed focus): scan the Broken list in `docs/backlog.md` for low-hanging fruit and move the easiest items up
  into the Priority list.
- **Wins:** push-notify the user every time something starts working.
- **Backlog:** the Broken, Later and Optimize lists are in `docs/backlog.md`, not auto-loaded. Read it when waiting
  on a test or build, after finishing a priority item, and when adding something newly found broken (add it, then
  carry on).
- **While waiting** (tests, builds, boots): work on other Broken items instead of idling; during the speed focus, on
  the next speed item or its read-only research.
- **Never idle in /loop** (the user, 2026-10-30): always keep at least one agent or build/test running; when the next
  step of an item needs the user or it is quiet hours, start the next item that doesn't. Wake-ups ~10 min while work
  is in flight.
- **Need the user's input:** take the recommended path, push-notify the user, and add the question (with the
  choice made) to the "Questions for you" list in `docs/plan.md`, so they can answer later. Don't wait.
- **Needs the user's hands at the phone** (feel, listen, look, plug in; the user, 2026-10-30, 2026-11-01): the user often
  can't do these, so nothing waits on them:
  - Add it to `docs/user-tasks.md` (not the plan's priority list) and move straight on. Don't repeat the ask; one push when
    a task is added is enough. Answers come when they come.
  - A user task never gates a change: if the automated checks pass (bench, screenshots, soak), ship it as the default with
    an off switch. A later "this looks wrong" from the user is a bug report: switch it off and fix it.
  - First try to check it without the user: a better tool (faster capture, webcam, measurement) beats asking.
  - The phone is Claude's unless the user says otherwise: don't hold it free for them. "The phone's mine" stops phone work
    until they hand it back.
- **Reliability** (the user, 2026-10-31): normal test runs are 15 min at most, plus one 1 h soak per day, overnight.
  Runs with a hang, a backboardd restart, the panel off or 0 swaps are void. Outside the speed focus, a fix needing
  repeated tests of an hour or more goes to the "Later" list (`docs/backlog.md`).
- **GPU bugs** (the user, 2026-10-31): list each one with its log line and rate in `docs/gpu-bugs.md`. Fix one now only
  if it voids benches, stops phone testing, or doubles in rate after a change (turn that change off first).
- **Time limit:** if a priority item shows no visible progress in about half a day, write down where it stands in
  its feature Log, park it in `docs/backlog.md` and take the next item.
- **Hard items** (days, uncertain): do their read-only research in the background while phone tests run; keep
  quick wins at the top of the list.
- **Find the user-visible breakage too:** the backlog isn't only hardware. Now and then (after big changes, or when
  the list runs low) survey the apps and core functions and add what fails.
- **Dev-speed optimizations:** anything slowing development down goes to the top of the priority list. Give it at most about an hour;
  past that it's likely not worth it: note it and move on.
- **Risky steps** (the user, 2026-10-29): where hardware damage is possible (e.g. PMIC charger writes), proceed with
  caution: research how the system works first, then lots of baby steps. Steps that only risk a reset (hypervisor
  calls, SMMU, DSP memory) are fine with the same care; a reset is logged (feature Log + journal), then work goes
  on with a smaller step. Flash/relock/battery/factory-reset rules above stay absolute.
- **Autonomy:** decide and act without asking on normal engineering choices; root file edits (launchd.plist, jobs)
  are fine with a backup first and the escape boot available.
- **Notifications:** anytime, also at night.
- **Night** (`work/night` exists: the user sleeps, the phone is in their bedroom): keep the iOS brightness slider at
  its minimum (DCS 32; iOS keeps it across reboots), no brightness raises or tests. Never below DCS 32 and never leave the screen off on purpose: the user wants it visible on the webcam (the user, 2026-11-12); `tools/sunfish-panel-bright.sh 32` with the screen on (`flame-cmd.py 'key 0 150'`) if a boot comes up bright. Never `tools/sunfish-dim.sh`: it
  stacks on the iOS brightness and the webcam can't see the screen (`sunfish-dim.sh 100` clears a leftover dim).
  No fake-lux tests (`m fake als`) at night; once the backlight nits range is in (auto-brightness live), turn
  Auto-Brightness off with `/var/local/bin/autobright 0` when setting the flag and back on (`1`) when removing it.
  The running session sets the flag at 9:30 pm, or earlier if the user says so; the morning session removes it, or
  any session does once the user says they are up.
- **Quiet hours** (the user, 2026-10-30): no speaker tests (sound from the phone) between 9:30 pm and 5:00 am EST;
  the USB measurement mic (EM-01) is fine to use outside those hours.
- **Reuse first** (the user, 2026-11-03): before writing a piece of the Metal/GPU/video stack, check the related
  projects (tools/upstream.list, incl. metal2vulkan upstream, AdrenoMetal, darlinghq indium/darling-metal) for a
  proven implementation and pull it in rather than reinventing it; say in the commit what was reused or why not.
- **Upstream check** (the user, 2026-10-30): related ports (ios-redfin, iOSPlus10, UniXNU, metal2vulkan, hakios-*, ...)
  are listed in `tools/upstream.list`. A daily scheduled task (06:30, "sunfish-upstream-check") runs
  `tools/sunfish-upstream-check.sh`, surveys the new commits with investigators, checks each candidate against our
  actual code (grep over patch names has been wrong), writes `research/notes/upstream-YYYY-MM-DD.md` and marks them
  surveyed (`--mark NAME`). Whatever benefits our build goes in `docs/backlog.md` and on a list in `docs/plan.md`
  (the user, 2026-11-01): Priority for CPU/GPU speed, smoothness and heat; "Upstream, not CPU/GPU" for the rest during
  the speed focus. Add a project to the list when a new related port turns up.
- **Other optimization** (GPU/CPU speed and heat are exempt during the speed focus): make systems usable, not fast. Once something works and could be faster, add it to the
  "Optimize (last)" list (`docs/backlog.md`) and move on.

# Delegation and sessions (tokens)
- **Every agent starts cold:** it starts at ~13K tokens of context (measured 2026-10-31) and re-reads what it needs. So:
  - Do short things directly in the main session: up to ~5 commands, a quick SSH check, a small edit.
  - Delegate the bulky ones: builds and installs (even short ones, to `builder`), boot + test runs, reverse
    engineering, long logs, big patches.
  - Don't use `general-purpose` when an agent below fits: it starts at ~67K tokens and averaged 2.5M per run.
- **Main session (Opus):** picks the next step from `docs/plan.md`, writes precise specs, judges results, updates the
  docs and plan.
- **Sessions:** the user restarts the /loop session each morning and evening (2026-10-31); `docs/plan.md` and today's
  journal are the hand-off. The main session is the biggest token cost (one ran 36 h at a median of 507K), so keep its
  turns short and delegate.
- **Start of a /loop session** (the user, 2026-10-31), before touching the phone:
  - Check that no other session is working the phone: list running sessions and leftover test scripts
    (`ps -eo pid,ppid,args | grep -E 'scratchpad|sunfish-'`). Keep `sunfish-livelog` and `sunfish-nightsoak`.
  - If another session is still active, stay off the phone, push-notify the user and work on what doesn't need it.
  - Otherwise, kill leftover test scripts, parent first.
- **Overnight soak** (the user, 2026-10-31): run one 1 h soak per night, after `work/night` is set, as a phone-runner
  job. Add the results to `docs/gpu-bugs.md`.
- **Agents in `.claude/agents/`:**
  - `phone-runner` (sonnet, medium effort): boots, benches, webcam, log slicing; checks itself and Reads a webcam frame after every boot and visible change. It is the only agent that touches the phone.
  - `builder` (haiku): commit/export patches, push, local builds, install.
  - `implementer` (opus, medium effort): writes one patch from a spec.
  - `investigator` (opus, high effort): read-only source, binary and log analysis.
- **Specs:**
  - Every spec says exactly what to return: numbers and tables, never raw logs.
  - phone-runner specs say "foreground only, no `&` or background runs, don't end the turn until done": it stalls
    on its own background watchers.
  - After stopping a phone agent, kill the scripts it launched (`ps -eo pid,ppid,args | grep scratchpad`, parent
    first): they keep driving the phone.
  - Run waits (CI, benches) in the background and don't poll them.
- **Phone access:**
  - Only one session or agent uses the phone at a time.
  - If the user says another session is on the phone, don't run `phone-runner`.
- **Workflows / ultracode** (the user, 2026-11-12): workflow agents never touch the phone or the build VM. Phone work
  goes through one `phone-runner` at a time, builds through one `builder` at a time, both outside the fan-out.
  Workflows are for read-only analysis, research, writing patches (one tree each) and reviews.
- **When usage runs low (Max plan):** run the main session on Sonnet for long, routine plan steps. Switch back to
  Opus for design decisions or when stuck after two failed attempts.
