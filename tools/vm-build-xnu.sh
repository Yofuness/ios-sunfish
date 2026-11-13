#!/bin/bash
# Build the sunfish xnu kernel in the local macOS VM (~/VMs/macos) instead of GitHub CI.
# Mirrors .github/workflows/xnu.yml: blacktop/darwin-xnu-build @ DXB_SHA, xnu/patches, ARCHS sed, xcodes stub,
# Xcode 15.0.1, MAKEFLAGS=-k. The VM keeps ~/xnubuild/dxb between runs (instead of actions/cache): after a good
# build the next run compares the patch hashes with ~/xnubuild/dxb/.vm-patchsums: unchanged -> straight to make;
# only new patches appended -> git apply just those to dxb/xnu; otherwise re-patch the persistent prep/xnu (reset in
# place) and rsync only changed files, so make rebuilds just those.
# dSYM and CTF are skipped by default (BUILD_DSYM=0 DO_CTFMERGE=0 on the kernel make line; saves ~14 s); --full
# builds them as CI does. The VM is left running: back-to-back builds reuse it, pass --stop (or run
# ~/VMs/macos/vm-stop.sh) at the end of a session.
# Env (defaults = the iOS 16 build in the Sonoma VM): VM_DIR=~/VMs/macos, MACHINE_CONFIG=SWEET, MACOS_VERSION=13.5 (dxb's xnu release),
# XC=/Applications/Xcode_15.0.1.app, PATCH_DIR=xnu/patches (relative to port/), KDK_MODE=kdk (build.sh's own KDK
# handling) or fake (no KDK: an empty ~/xnubuild/no-kdk as KDKROOT, after Bergamota's use_kdk=false). Second VM
# (macos15, xnu-12377): VM_DIR=~/VMs/macos15 MACOS_VERSION=26.5 XC=/Applications/Xcode_26.1.app
# PATCH_DIR=xnu/patches-12377 KDK_MODE=fake tools/vm-build-xnu.sh NN. 26.x builds as IOS-26-Hot's CI does (dxb bd88697,
# its build.sh edits and patch loop; see the REMOTE part). Only one VM may run (tools/macos-vm/vm-guard.sh).
# Usage: tools/vm-build-xnu.sh NN [--clean] [--full] [--stop]   -> work/kernelNN/ (same layout as gh run download -n xnu-kernel)
set -euo pipefail
NN=${1:?usage: $0 NN [--clean] [--full] [--stop]}; shift
CLEAN=0; STOP=0; FULL=0
for a in "$@"; do case $a in --clean) CLEAN=1;; --full) FULL=1;; --stop) STOP=1;; *) echo "unknown arg $a" >&2; exit 2;; esac; done
PORT=$(cd "$(dirname "$0")/.." && pwd)
VM=${VM_DIR:-${MACOS_VM_DIR:-$HOME/VMs/macos}}
export VM_DIR=$VM MACOS_VM_DIR=$VM   # vm-start.sh, vssh and the .py helpers then use the same VM
MACOS_VERSION=${MACOS_VERSION:-13.5}
XC=${XC:-/Applications/Xcode_15.0.1.app}
PATCH_DIR=${PATCH_DIR:-xnu/patches}; case $PATCH_DIR in /*) ;; *) PATCH_DIR=$PORT/$PATCH_DIR;; esac
KDK_MODE=${KDK_MODE:-kdk}
case $KDK_MODE in kdk|fake) ;; *) echo "KDK_MODE must be kdk or fake" >&2; exit 2;; esac
[ -d "$PATCH_DIR" ] || { echo "no patch dir $PATCH_DIR" >&2; exit 2; }
OUT=$PORT/work/kernel$NN
JOBS=${VM_JOBS:-}   # empty = build.sh default; set e.g. VM_JOBS=6 if the 8 GB VM swaps
T0=$(date +%s)
vs() { "$VM/vssh" -o ConnectTimeout=5 "$@"; }

# two-VM guard before the first ssh: another VM on port 2222 would answer instead of ours
D=$VM; . "$PORT/tools/macos-vm/vm-guard.sh"; vm_guard || exit 1
if ! vs true </dev/null 2>/dev/null; then
  "$VM/vm-start.sh"
  for i in $(seq 60); do vs true </dev/null 2>/dev/null && break; sleep 5; done
  vs true </dev/null || { echo "VM ssh not answering (OpenCore picker? vmctl.py key right; key ctrl+ret)" >&2; exit 1; }
fi

# patches in, fresh each run (removed patches must not linger)
vs 'rm -rf ~/xnubuild/patches-in && mkdir -p ~/xnubuild/patches-in' </dev/null
tar -C "$PATCH_DIR" -cf - . | vs 'tar -C ~/xnubuild/patches-in -xf -'

vs "CLEAN=$CLEAN FULL=$FULL JOBS='$JOBS' MACOS_VERSION='$MACOS_VERSION' MACHINE_CONFIG='${MACHINE_CONFIG:-SWEET}' XC='$XC' KDK_MODE='$KDK_MODE' /usr/local/bin/bash -s" <<'REMOTE' || FAIL=1
set -euo pipefail
export PATH=/usr/local/bin:$PATH
DXB_REPO=https://github.com/blacktop/darwin-xnu-build
DXB_SHA=663906528d1cd5ea8fde7de6f16de73db9511549
# 26.x (xnu-12377, patches-12377): build exactly as IOS-26-Hot's CI (research/upstream/IOS-26-Hot/.github/workflows/xnu.yml):
# its dxb pin (yml l.31). dxb 6639065's widened INCFLAGS_SDK sed in patches() rewrites MakeInc.def's line 1227 (four
# spaces; bd88697's sed wants a tab and leaves it alone), so Hot's 0004 hunk there no longer applies.
HOT=0
case $MACOS_VERSION in 26.*) HOT=1; DXB_SHA=bd88697145b2d8008bbed951fef99795308262f0 ;; esac
export MACOS_VERSION KERNEL_CONFIG=DEVELOPMENT MACHINE_CONFIG=${MACHINE_CONFIG:-SWEET} MAKEFLAGS=-k
export -n XC KDK_MODE   # came in through ssh's env prefix: keep them out of build.sh's environment, as before
export DEVELOPER_DIR=$XC/Contents/Developer
[ "$(xcode-select -p)" = "$DEVELOPER_DIR" ] || sudo xcode-select -s "$XC"
[ -x /usr/local/bin/xcodes ] || { printf '#!/bin/sh\nexit 0\n' | sudo tee /usr/local/bin/xcodes >/dev/null; sudo chmod +x /usr/local/bin/xcodes; }
cd ~/xnubuild
LOG=~/xnubuild/build.log
: > "$LOG"
stamp() { echo "VMSTAMP $1 $(date +%s)" >> "$LOG"; }
stamp start
INC=0
[ "$CLEAN" = 0 ] && [ -f dxb/.vm-ok ] && INC=1
# a kept dxb from the other pin is refetched (only differs when switching between 26.x and 13.5/15.x builds)
[ $INC = 1 ] && [ "$(git -C dxb rev-parse HEAD 2>/dev/null)" != "$DXB_SHA" ] && INC=0
if [ $INC = 0 ]; then
  rm -rf dxb; git init -q dxb
  git -C dxb fetch -q --depth 1 "$DXB_REPO" "$DXB_SHA"
  git -C dxb checkout -q FETCH_HEAD
fi
cd dxb
rm -f .vm-ok
# (name, hash) of every patch/script, scripts first; compared with the last good build's list
NEWSUMS=$( (cd ~/xnubuild/patches-in && { ls *.sh 2>/dev/null || true; ls *.patch 2>/dev/null || true; } | while read -r f; do echo "$f $(shasum -a 256 "$f" | cut -c1-64)"; done) )
OLDSUMS=$(cat .vm-patchsums 2>/dev/null || true); rm -f .vm-patchsums
MODE=full
if [ $INC = 1 ] && [ -n "$OLDSUMS" ]; then
  if [ "$OLDSUMS" = "$NEWSUMS" ]; then MODE=same
  elif [ "$(printf '%s\n' "$NEWSUMS" | head -n "$(printf '%s\n' "$OLDSUMS" | wc -l)")" = "$OLDSUMS" ]; then MODE=append
  else MODE=repatch; fi
elif [ $INC = 1 ]; then MODE=repatch; fi
# pristine build.sh and patches dir, then ours on top (as CI's fresh checkout)
git checkout -q -- build.sh patches; git clean -fdq patches
case $MACOS_VERSION in
  26.*) PSUB=patches/26.0; PPRE=sweet- ;;
  15.*) PSUB=patches/15.0; PPRE=sweet- ;;
  *) PSUB=patches; PPRE= ;;
esac
if [ $HOT = 1 ]; then :   # 26.x: dxb's patches/26.0 stays pristine; build.sh runs ours from patches-in (edit below)
elif [ -z "$PPRE" ]; then cp ~/xnubuild/patches-in/*.patch ~/xnubuild/patches-in/*.sh patches/
else for f in ~/xnubuild/patches-in/*.patch ~/xnubuild/patches-in/*.sh; do [ -e "$f" ] || continue; cp "$f" "$PSUB/$PPRE$(basename "$f")"; done; fi
if [ "$KDK_MODE" = fake ] && [ $HOT = 1 ]; then
  # Hot's fake-kdk (yml l.110-112): our CoreEntitlements stage script fills an empty KDKROOT with the V2 headers;
  # dxb's own 00_setup_coreentitlements.sh stays and copies them from there (as in Hot's CI).
  CE=$(ls ~/xnubuild/patches-in/*.sh 2>/dev/null | grep -i coreentitlements | head -1) || { echo "KDK_MODE=fake: no CoreEntitlements stage script (*coreentitlements*.sh) in PATCH_DIR" >&2; exit 1; }
  rm -rf ~/xnubuild/fake-kdk; mkdir -p ~/xnubuild/fake-kdk; export KDKROOT=~/xnubuild/fake-kdk
  (cd ~/xnubuild && bash "$CE")
elif [ "$KDK_MODE" = fake ]; then
  # no KDK (Bergamota use_kdk=false; IOS-26-Hot's fake-kdk): SWEET links no closed KDK libs. Drop dxb's KDK header
  # copy (a CoreEntitlements V2 stage script in PATCH_DIR stands in) and point KDKROOT at an empty dir so build.sh
  # does not download a KDK.
  ls ~/xnubuild/patches-in/*.sh 2>/dev/null | grep -qi coreentitlements || { echo "KDK_MODE=fake: no CoreEntitlements stage script (*coreentitlements*.sh) in PATCH_DIR" >&2; exit 1; }
  rm -f "$PSUB/00_setup_coreentitlements.sh"
  mkdir -p ~/xnubuild/no-kdk; export KDKROOT=~/xnubuild/no-kdk
fi
# our sweet-* patches must all apply (IOS-26-Hot's CI applies its series fail-fast); dxb's patches loop skips any
# patch whose --check fails, which would hide a broken series (dxb's own patches may still be skipped). 26.x: Hot's
# own loop; 15.x: a check in dxb's loop. The Sonoma path is unchanged.
if [ $HOT = 1 ]; then
  # Hot's build.sh edits (yml l.55-92): 1. KDKROOT honours the environment (fake-kdk); 3. after dxb's conditional loop
  # over patches/26.0 (bd88697 skips link_kdk, remove_applefeatures_include and its malformed disable_bti_vmapple and
  # simplify_san_lipo, as in Hot's CI), run all our *.sh from the xnu root, then git apply all our *.patch. Edit 2
  # (libfirehose ARCHS) is the common perl below. Fail-fast: an unapplied patch stops build.sh (errexit, plus an
  # explicit exit so the eval'd repatch path stops too).
  SPD=$HOME/xnubuild/patches-in perl -0777 -pi -e '
    my $o = qq{        for PATCH in "\${PATCH_DIR}"/*.patch; do\n            if git apply --check "\$PATCH" 2> /dev/null; then\n                running "Applying patch: \${PATCH}"\n                git apply "\$PATCH"\n            fi\n        done};
    my $n = $o . qq{\n        SWEET_PATCH_DIR="$ENV{SPD}"\n        for SCRIPT in "\${SWEET_PATCH_DIR}"/*.sh; do\n            running "Running sweet stage script: \${SCRIPT}"\n            bash "\${SCRIPT}"\n        done\n        for PATCH in "\${SWEET_PATCH_DIR}"/*.patch; do\n            running "Applying sweet patch: \${PATCH}"\n            git apply --verbose "\$PATCH" || { error "sweet patch does not apply: \${PATCH}"; exit 1; }\n        done};
    my $i = index($_, $o); die "vm-build: dxb patch loop not found\n" if $i < 0;
    substr($_, $i, length $o) = $n;
    s{KDKROOT=\x27(/Library/Developer/KDKs/[^\x27]+)\x27}{KDKROOT="\${KDKROOT:-$1}"}g or die "vm-build: KDKROOT not found\n";' build.sh
  grep -q 'sweet patch does not apply' build.sh
elif [ -n "$PPRE" ]; then
  perl -pi -e 's/^(\s+)(warning "Skipping patch \$\{PATCH\})/$1case "\$(basename "\$PATCH")" in sweet-*) error "sweet patch does not apply: \$\{PATCH\}: \$\{APPLY_CHECK\}"; exit 1;; esac\n$1$2/' build.sh
  grep -q 'sweet patch does not apply' build.sh
fi
perl -pi -e 's/ARCHS="x86_64 arm64e" VALID_ARCHS="x86_64 arm64e"/ARCHS="x86_64 arm64e arm64" VALID_ARCHS="x86_64 arm64e arm64"/' build.sh
grep -q 'VALID_ARCHS="x86_64 arm64e arm64"' build.sh
# build.sh hardcodes make -j8 (= the VM vCPUs); VM_JOBS=N lowers it if 8 GB swaps
[ -n "$JOBS" ] && perl -pi -e "s/make install -j8/make install -j$JOBS/" build.sh
if [ $MODE = same ]; then
  echo "patch set unchanged: make only"
elif [ $MODE = append ]; then
  echo "patches appended: applying only the new ones to dxb/xnu"
  (cd xnu && printf '%s\n' "$NEWSUMS" | tail -n +"$(( $(printf '%s\n' "$OLDSUMS" | wc -l) + 1 ))" | while read -r f h; do
    case $f in *.patch) ;; *) echo "new script $f: not supported on the append path" >&2; exit 1;; esac
    [ -n "$PPRE" ] && ! git apply --check ~/xnubuild/patches-in/"$f" && { echo "  $f does not apply" >&2; exit 1; }
    git apply --check ~/xnubuild/patches-in/"$f" && git apply ~/xnubuild/patches-in/"$f" && echo "  applied $f"
  done)
elif [ $MODE = repatch ]; then
  echo "patch set changed: re-patching the persistent prep/xnu"
  P=~/xnubuild/prep; mkdir -p "$P"; rm -f "$P/patches"
  [ -d "$P/xnu/.git" ] || { rm -rf "$P/xnu"; cp -a xnu "$P/xnu"; }
  (cd "$P/xnu" && git checkout -q -- . && git clean -fdqx)
  ln -s "$PWD/patches" "$P/patches"
  (
    WORK_DIR=$P CODEQL=0 KDKROOT=${KDKROOT:-/nonexistent}
    running() { echo "$*"; }; warning() { echo "$*"; }; error() { echo "$*" >&2; }
    eval "$(sed -n '/^patches() {/,/^}/p' build.sh)"
    patches
  )
  rsync -rlc --no-times --delete --exclude .git --itemize-changes "$P/xnu/" xnu/ | grep -v '^\.' | head -50 || true
fi
if [ $INC = 1 ]; then
  perl -pi -e 's/^    patches$/    true # patched by the cache step/' build.sh
  rm -rf build/xnu.obj/kernel.* fakeroot/System/Library/Kernels/kernel.*
else
  echo "full build"
fi
echo "vm-build: patch path $MODE" | tee -a "$LOG"
# no dSYM/CTF unless --full (command-line make vars beat MakeInc.def's :=)
[ "$FULL" = 1 ] || perl -pi -e 's/("\$\{CTF_TOOL_OVERRIDES\[@\]\}") SDKROOT=macosx TARGET_CONFIGS/$1 BUILD_DSYM=0 DO_CTFMERGE=0 SDKROOT=macosx TARGET_CONFIGS/' build.sh
# bd88697's make lines have no CTF_TOOL_OVERRIDES
[ "$FULL" = 1 ] || [ $HOT = 0 ] || perl -pi -e 's/(make install -j\d+ VERBOSE=YES) SDKROOT=macosx TARGET_CONFIGS/$1 BUILD_DSYM=0 DO_CTFMERGE=0 SDKROOT=macosx TARGET_CONFIGS/' build.sh
[ "$FULL" = 1 ] || grep -q 'BUILD_DSYM=0 DO_CTFMERGE=0' build.sh
stamp patched
if ! bash build.sh >> "$LOG" 2>&1; then
  stamp built; echo "BUILD FAILED; errors:"; grep -E 'error:|\*\*\*' "$LOG" | head -15; echo "--- tail $LOG"; tail -30 "$LOG"; exit 1
fi
stamp built
rm -rf ~/xnubuild/out && mkdir -p ~/xnubuild/out
cp -R fakeroot/System/Library/Kernels/. ~/xnubuild/out/
(cd ~/xnubuild/out && shasum -a 256 kernel.* > SHA256SUMS 2>/dev/null) || true  # kernel.*.link is a dir, as in CI
ls ~/xnubuild/out/kernel.development.* >/dev/null
printf '%s\n' "$NEWSUMS" > .vm-patchsums
touch .vm-ok
stamp done
awk '/^VMSTAMP/{t[$2]=$3} END{printf "vm-build: patch %ds, make %ds, post %ds, total %ds\n", t["patched"]-t["start"], t["built"]-t["patched"], t["done"]-t["built"], t["done"]-t["start"]}' "$LOG"
REMOTE

if [ "${FAIL:-0}" = 1 ]; then echo "build failed after $(( $(date +%s) - T0 )) s" >&2; exit 1; fi
mkdir -p "$OUT"
vs 'tar -C ~/xnubuild/out -cf - .' </dev/null | tar -C "$OUT" -xf -
(cd "$OUT" && sha256sum -c SHA256SUMS)
ls -la "$OUT"
echo "wall time (with upload/download): $(( $(date +%s) - T0 )) s"
[ $STOP = 1 ] && "$VM/vm-stop.sh"
exit 0
