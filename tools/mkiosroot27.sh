#!/bin/bash
# Build the iOS 27.2.1 (24B156, iPhone12,1) HFSX root image for kernel301+ (stage 4, docs/root27.md).
#
#   mkiosroot27.sh [--profile full|c1|d] [--size SIZE] [--steps extract,image,rewrite,tweaks,finish] [--jobs N]
#                  [--force] [--keep-staging] [--keep-panic-on-crash] [--page-shift 12] [--simg-zero-skip]
#
# Steps (each one can be run alone; "image" refuses to overwrite an image unless --force):
#   extract  the OS, SystemOS and AppOS dmgs from the IPSW (ipsw; AEA keys from Apple's server, or the
#            saved .pem/.key beside them) and the Firmware/*.trustcache files -> ../restore/ipsw/x/24B156/root-src
#   image    sparse image, mkfs.hfsplus -s -J, rsync -aH the OS root + cryptexes (the c1 profile leaves out apps
#            and big assets, see C1_EXCLUDES; d, for Gate D, keeps apps, *.car, localizations and posters and
#            leaves out only D_EXCLUDES), cryptex layout, first-boot dirs, launchd.plist _PanicOnCrash off
#   rewrite  PAC lowering inside the image: the dyld cache (zeta rewrite-zeta-dyld-cache.py with the proof in
#            ../restore/ipsw/x/24B156/prove) and every thin arm64e Mach-O (tools/root27/rewrite-zeta-userland-tree.py),
#            both re-signed ad hoc; written back in place (tools/root27/apply-rewrites.py)
#   tweaks   SSH for Gate C2 (tools/root27/tweaks27.py): dropbear + dash + toybox in /var/local/bin, /bin/sh,
#            authorized_keys (work/userland/ssh/*.pub), the org.iosonpixel.dropbear job in launchd.plist;
#            Bluetooth (stage 6): btbridge + bluetool-stub, BT firmware, BlueTool/bluetoothd job edits, btbridge job
#            (off: TWEAKS_ARGS=--no-bt; profile d adds --snoop: btsnoop capture on); Wi-Fi: wland + netsvc, modem firmware + rmtfs, wland job (--no-wifi); leave it out of --steps to skip, `tweaks27.py --remove` takes it out again
#   finish   fsck.hfsplus, then tools/root27/simg-hfs.py -> root27-PROFILE-at16g.simg: every HFS-allocated block
#            written (zero pages too), free space DONT_CARE, 16 GiB DONT_CARE in front (userdata offset 16 GiB);
#            --simg-zero-skip = the old img2simg -s + simg-offset.py (skips zero pages inside files: stale data)
# Out of git: ../restore/root27/root27-PROFILE.img, root27-PROFILE-at16g.simg, reports-PROFILE/,
# orig-PROFILE/ (the Mach-Os before rewriting). Nothing is written to the phone.
#
# Reused: the image/copy/cryptex-link/logd/keybag part is IOS-26-Hot's tools/mkiosroot.sh (MIT, dipa-studio;
# itself our tools/mkiosroot.sh plus .aea handling), restructured into steps; Hot's de-pac-arm64e.py (no
# re-signing, needs cs_integrity_skip=1) is replaced by UniXNU-zeta's proof-based rewriters (BSD-2-Clause-Patent,
# tools/ios27-pac/zeta and tools/root27, LICENSE.zeta). Design: research/notes/root27-pipeline-2026-11-13.md.
set -euo pipefail

port=$(cd "$(dirname "$0")/.." && pwd)
restore=$(cd "$port/.." && pwd)/restore
ipsw_file=$restore/ipsw/iPhone12,1_27.2.1_24B156_Restore.ipsw
src=$restore/ipsw/x/24B156/root-src
dmgdir=$src/24B156__iPhone12,1
proof=$restore/ipsw/x/24B156/prove
work=$restore/root27
py=$port/work/venv-pac/bin/python3
OS_DMG=141-08279-223.dmg SYS_DMG=141-10128-235.dmg APP_DMG=141-08824-252.dmg

profile=full size= steps=extract,image,rewrite,tweaks,finish jobs=3 force=0 keep_staging=0 panic_off=1 page_shift= zero_skip=0
while [[ $# -gt 0 ]]; do
	case $1 in
	--profile) profile=$2; shift ;;
	--size) size=$2; shift ;;
	--steps) steps=$2; shift ;;
	--jobs) jobs=$2; shift ;;
	--force) force=1 ;;
	--keep-staging) keep_staging=1 ;;
	--keep-panic-on-crash) panic_off=0 ;;
	--page-shift) page_shift=$2; shift ;;
	--simg-zero-skip) zero_skip=1 ;;
	*) sed -n '2,25p' "$0"; exit 2 ;;
	esac
	shift
done
case $profile in
full) size=${size:-28G} ;;
c1) size=${size:-13G} ;;      # ~11 GB of content (5.8 GB dyld cache)
d) size=${size:-20G} ;;       # ~17.5 GB of content (full is ~20.5 GB)
*) echo "unknown profile $profile" >&2; exit 2 ;;
esac

img=$work/root27-$profile.img
reports=$work/reports-$profile
staging=$work/staging-$profile
mnt=$work/mnt
log=$work/build-$profile.log
mkdir -p "$work" "$mnt" "$reports"
exec > >(tee -a "$log") 2>&1
echo "=== $(date '+%F %T') mkiosroot27 profile=$profile size=$size steps=$steps"

# C1 (first launchd boot): no apps, watch faces, ML weights, movies, asset catalogs, localizations, firmware.
C1_EXCLUDES=(
	'/Applications/*' '/private/var/staged_system_apps/*' '/usr/standalone/*'
	'/System/Library/LinguisticData/*' '/System/Library/PreinstalledAssetsV2/*' '/System/Library/NanoTimeKit/*'
	'/System/Library/NanoPreferenceBundles/*' '/System/Library/Health/*' '/System/Library/OnBoardingBundles/*'
	'/System/Library/Assistant/*' '/System/Library/AppPlaceholders/*' '/System/Library/ImagingNetworks/*'
	'/System/Library/PreferenceBundles/*' '/System/Library/Snippets/*'
	'*.loctable' '*.mov' '*.weights' '*.hwx' '*.car' '*.metallib'
)
C1_FRAMEWORKS=(CoreEmoji MediaAnalysis SFSymbols NanoUniverse CVNLP VoiceServices TextToSpeechMauiSupport iWorkImport GESS \
	TextRecognition HomeUI VisionCore CoreSceneUnderstanding AvatarKit SiriSetup CoreHandwriting)
for f in "${C1_FRAMEWORKS[@]}"; do
	C1_EXCLUDES+=("/System/Library/PrivateFrameworks/$f.framework/*")
done
# D (Gate D, SpringBoard Home): C1 left out UIKitCore's Artwork.bundle/Assets.car ("The UIKit artwork manager should
# never be nil", SpringBoard abort k317b) and /Applications/PosterBoard.app. D keeps every app, asset catalog,
# localization, movie, metallib, ML model, poster and preference bundle; it leaves out only what SpringBoard, backboardd
# and PosterBoard cannot reach: baseband/firmware payloads, Watch (Nano*), Health, Siri/TTS voices, Photos/Live Text/
# handwriting analysis, avatars, iWork import, the camera's imaging networks, plus the cache's .symbols (~3.4 GB).
D_EXCLUDES=(
	'/usr/standalone/*' '/System/Library/NanoTimeKit/*' '/System/Library/NanoPreferenceBundles/*'
	'/System/Library/Health/*' '/System/Library/Assistant/*' '/System/Library/Snippets/*'
	'/System/Library/ImagingNetworks/*'
)
for f in NanoUniverse AvatarKit SiriSetup iWorkImport TextToSpeechMauiSupport VoiceServices MediaAnalysis CVNLP \
	TextRecognition CoreHandwriting; do
	D_EXCLUDES+=("/System/Library/PrivateFrameworks/$f.framework/*")
done

t0=$SECONDS
lap() { echo "--- $1: $((SECONDS - t0)) s"; t0=$SECONDS; }
need_disk() {   # need_disk GB: stop while the host keeps at least 15 GB free after the step
	local free
	free=$(df -BG --output=avail "$work" | tail -1 | tr -dc 0-9)
	if (( free - $1 < 15 )); then echo "host disk: ${free} GB free, step needs ~$1 GB: stopping" >&2; exit 1; fi
}
has_step() { [[ ",$steps," == *",$1,"* ]]; }

mounts=()
cleanup() {
	local m
	for m in "${mounts[@]}"; do
		sudo mountpoint -q "$m" && { sudo umount "$m" 2>/dev/null || echo "still mounted: $m" >&2; }
	done
	mounts=()
}
trap cleanup EXIT
# apfs-fuse splits its options on ',' (iPhone12,1 in the path) and only parses UDIF when the name ends in .dmg:
# mount through links. As root: a user's FUSE mount is unreadable to the root rsync.
apfs_mount() {
	ln -sfn "$dmgdir/$1" "$mnt/$2.dmg"
	mkdir -p "$mnt/$2"
	sudo mountpoint -q "$mnt/$2" || sudo "$(command -v apfs-fuse)" "$mnt/$2.dmg" "$mnt/$2"
	mounts+=("$mnt/$2")
}
root=$mnt/root
root_mount() {
	mkdir -p "$root"
	mountpoint -q "$root" || sudo mount -t hfsplus -o loop,force "$img" "$root"
	mounts=("$root" "${mounts[@]}")
}

if has_step extract; then
	mkdir -p "$dmgdir"
	for kind in fs:$OS_DMG sys:$SYS_DMG app:$APP_DMG; do
		dmg=${kind#*:}
		[[ -f $dmgdir/$dmg ]] && { echo "have $dmg"; continue; }
		need_disk 20
		(cd "$src" && ipsw extract --dmg "${kind%%:*}" "$ipsw_file" -o .)
		if [[ -f $dmgdir/$dmg.aea ]]; then
			# The SystemOS key comes with `ipsw extract --fcs-key` (.pem); the OS key from Apple's wkms server
			# (network); a saved key (`ipsw fw aea -k`, file $dmg.aea.key) works offline.
			[[ -f $dmgdir/$dmg.aea.pem ]] || (cd "$src" && ipsw extract --fcs-key "$ipsw_file" -o .) || true
			if [[ -f $dmgdir/$dmg.aea.pem ]]; then
				ipsw fw aea "$dmgdir/$dmg.aea" -p "$dmgdir/$dmg.aea.pem" -o "$dmgdir"
			elif [[ -f $dmgdir/$dmg.aea.key ]]; then
				ipsw fw aea "$dmgdir/$dmg.aea" -b "$(sed 's/^base64://' "$dmgdir/$dmg.aea.key")" -o "$dmgdir"
			else
				ipsw fw aea "$dmgdir/$dmg.aea" -o "$dmgdir"
				ipsw fw aea -k "$dmgdir/$dmg.aea" > "$dmgdir/$dmg.aea.key" 2>/dev/null || rm -f "$dmgdir/$dmg.aea.key"
			fi
			rm -f "$dmgdir/$dmg.aea"
		fi
		[[ -f $dmgdir/$dmg ]] || { echo "no $dmg after extraction" >&2; exit 1; }
	done
	[[ -d $src/trustcache ]] || unzip -o -j -q "$ipsw_file" 'Firmware/*.trustcache' -d "$src/trustcache"
	lap extract
fi

if has_step image; then
	if [[ -e $img ]]; then
		[[ $force == 1 ]] || { echo "refusing to overwrite $img (--force)" >&2; exit 1; }
		rm -f "$img"
	fi
	# A new image needs a new rewrite: drop the old reports and originals.
	sudo rm -rf "$reports" "$work/orig-$profile" "$staging"
	mkdir -p "$reports"
	need_disk $(case $profile in c1) echo 13 ;; d) echo 20 ;; *) echo 23 ;; esac)
	apfs_mount $OS_DMG os
	apfs_mount $SYS_DMG sysos
	apfs_mount $APP_DMG appos
	truncate -s "$size" "$img"
	mkfs.hfsplus -s -J -v iOSRoot "$img"
	root_mount
	excl=() sysexcl=()
	if [[ $profile == c1 ]]; then
		for e in "${C1_EXCLUDES[@]}"; do excl+=(--exclude "$e"); done
		sysexcl=(--exclude '*.symbols')      # 1.2 GB of symbol names, never mapped
	elif [[ $profile == d ]]; then
		for e in "${D_EXCLUDES[@]}"; do excl+=(--exclude "$e"); done
		sysexcl=(--exclude '*.symbols')
	fi
	copy() {   # copy SRC DST [rsync args]
		echo "copying $1 -> ${2#"$root"}"
		sudo mkdir -p "$2"
		sudo rsync -aH --numeric-ids "${@:3}" "$1/" "$2/"
	}
	copy "$mnt/os/root" "$root" "${excl[@]}"
	copy "$mnt/sysos/root" "$root/private/preboot/Cryptexes/OS" "${sysexcl[@]}"
	copy "$mnt/appos/root" "$root/private/preboot/Cryptexes/App"
	lap copy

	# Shared cache where dyld looks at ignition level 1: hard links, no extra space.
	dsc=private/preboot/Cryptexes/OS/System/Library/Caches/com.apple.dyld
	sudo mkdir -p "$root/System/Library/Caches/com.apple.dyld"
	for f in "$root/$dsc"/*; do
		sudo ln -f "$f" "$root/System/Library/Caches/com.apple.dyld/${f##*/}"
	done
	# dyld does not search the cryptexes at ignition level 1: hard-link every cryptex file that has no
	# counterpart in the OS root (libobjc-trampolines, libffi-trampolines, ...) to its root path.
	linked=0
	for c in OS App; do
		while IFS= read -r -d '' f; do
			f=${f#./}
			if ! sudo test -e "$root/$f" && ! sudo test -L "$root/$f"; then
				sudo mkdir -p "$root/$(dirname "$f")"
				s="$root/private/preboot/Cryptexes/$c/$f"
				# Linux hfsplus cannot hard-link symlinks: copy those.
				if sudo test -L "$s"; then sudo cp -P "$s" "$root/$f"; else sudo ln "$s" "$root/$f"; fi
				linked=$((linked + 1))
			fi
		done < <(cd "$root/private/preboot/Cryptexes/$c" && sudo find . ! -type d ! -path './System/Library/Caches/com.apple.dyld/*' -print0)
	done
	echo "cryptex files linked into /: $linked"
	# The OS root already has /System/Cryptexes/{OS,App,Supplemental} -> ../../private/preboot/Cryptexes/*.
	for c in OS App; do
		sudo test -L "$root/System/Cryptexes/$c" || { sudo mkdir -p "$root/System/Cryptexes"; sudo ln -s "../../private/preboot/Cryptexes/$c" "$root/System/Cryptexes/$c"; }
	done

	# First boot, before launchd's jobs run (from Hot's script = ours): logd's stores (owner _logd 272 and a
	# .migrated marker, else "BUG IN LIBTRACE: Failed to migrate directory") and the plain-plist system keybag
	# for the built-in AppleKeyStore (no passcode; /defaults/no-effaceable-storage in the ADT).
	# TODO after C1 (tools/sweet-root-tweaks.py, iOS 16): /private/var/containers skeleton, LastSystemVersion
	# (DataMigration), Setup skipped, mobileactivationd data ark, CommCenter jobs removed, VirtualAudio and
	# MediaToolbox StartRecorderServer, SpringBoard BKNoWatchdogs. (SSH for C2: step tweaks.)
	db="$root/private/var/db"
	sudo install -d -o 272 -g 272 -m 0751 "$db/diagnostics"
	sudo install -d -o 272 -g 272 -m 0755 "$db/uuidtext" "$db/diagnostics/timesync"
	for d in diagnostics uuidtext diagnostics/timesync; do
		sudo install -o 272 -g 272 -m 0644 /dev/null "$db/$d/.migrated"
	done
	sudo install -d -m 0700 -o 0 -g 0 "$root/private/var/keybags"
	printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
		'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
		'<plist version="1.0"><dict><key>KeyBagKeys</key><data>U1dFRVQ=</data></dict></plist>' |
		sudo install -m 0600 -o 0 -g 0 /dev/stdin "$root/private/var/keybags/systembag.kb"
	# A crashing daemon must not panic the system while we bring it up (as sweet-root-tweaks.py does for 16;
	# --keep-panic-on-crash keeps Apple's plist). launchd_unsecure_cache=1 reads the plist without its .sig.
	if [[ $panic_off == 1 ]]; then
		sudo python3 -I - "$root/System/Library/xpc/launchd.plist" <<-'EOF'
			import os, plistlib, sys
			path = sys.argv[1]
			st = os.stat(path)
			with open(path, 'rb') as f:
			    fmt = plistlib.FMT_BINARY if f.read(8) == b'bplist00' else plistlib.FMT_XML
			    f.seek(0)
			    plist = plistlib.load(f)
			n = 0
			for job in plist['LaunchDaemons'].values():
			    if '_PanicOnCrash' in job:
			        job['_PanicOnCrasX'] = job.pop('_PanicOnCrash')
			        n += 1
			with open(path, 'wb') as f:
			    plistlib.dump(plist, f, fmt=fmt)
			os.chown(path, st.st_uid, st.st_gid)
			os.chmod(path, st.st_mode & 0o7777)
			print(f'launchd.plist: {n} _PanicOnCrash renamed')
		EOF
	fi
	df -h "$root"
	cleanup
	lap layout
fi

if has_step rewrite; then
	tc=(--apple-trust-cache "$src/trustcache/$OS_DMG.aea.trustcache"
		--apple-trust-cache "$src/trustcache/$SYS_DMG.aea.trustcache"
		--apple-trust-cache "$src/trustcache/$APP_DMG.trustcache")
	root_mount
	cache_dir=$root/private/preboot/Cryptexes/OS/System/Library/Caches/com.apple.dyld
	# 1. dyld cache. Images whose proof failed (failed.json: WebCore, MLIR_ML OOM-killed at 6 GB) are not in
	#    summary.json and keep their PAC words: they would SIGILL only when run (Safari/WebKit, Core ML).
	if [[ ! -f $reports/cache.json ]]; then
		need_disk 7
		sudo rm -rf "$staging/cache"
		mkdir -p "$staging"
		ps_args=()
		[[ -n $page_shift ]] && ps_args=(--page-shift "$page_shift")
		sudo "$py" -I -c 'import runpy, sys; sys.path.insert(0, sys.argv[1]); sys.argv = sys.argv[2:]; runpy.run_path(sys.argv[0], run_name="__main__")' \
			"$port/tools/ios27-pac/zeta" "$port/tools/ios27-pac/zeta/rewrite-zeta-dyld-cache.py" \
			--cache "$cache_dir/dyld_shared_cache_arm64e" --proof "$proof" --output "$staging/cache" \
			"${tc[@]}" "${ps_args[@]}" --report "$reports/cache.json.tmp"
		sudo "$py" -I "$port/tools/root27/apply-rewrites.py" cache "$reports/cache.json.tmp" "$staging/cache" "$cache_dir"
		sudo mv "$reports/cache.json.tmp" "$reports/cache.json"
		[[ $keep_staging == 1 ]] || sudo rm -rf "$staging/cache"
		lap "rewrite cache"
	fi
	# 2. Every other thin arm64e Mach-O (launchd, dyld, daemons, plug-ins, cryptex dylibs), proof per image.
	if [[ ! -f $reports/tree.json ]]; then
		need_disk 4
		sudo rm -rf "$staging/tree" "$reports/tree.json.tmp"
		mkdir -p "$staging"
		sudo "$py" -I "$port/tools/root27/rewrite-zeta-userland-tree.py" --root "$root" --output "$staging/tree" \
			"${tc[@]}" --jobs "$jobs" --report "$reports/tree.json.tmp" || echo "tree rewrite: some images refused (see report)"
		sudo "$py" -I "$port/tools/root27/apply-rewrites.py" tree "$reports/tree.json.tmp" "$staging/tree" "$root" \
			--backup "$work/orig-$profile"
		sudo mv "$reports/tree.json.tmp" "$reports/tree.json"
		[[ $keep_staging == 1 ]] || sudo rm -rf "$staging/tree"
		lap "rewrite tree"
	fi
	sudo chown -R "$(id -u):$(id -g)" "$reports"
	df -h "$root"
	cleanup
fi

if has_step tweaks; then
	# Gate C2: the iOS 16 SSH setup (tools/sunfish-install-ssh.sh) offline. No network job: the kernel brings
	# ue0 up as 192.168.7.2/24 (patch 0075). Stage 6: the iOS 16 Bluetooth + Wi-Fi setups too (TWEAKS_ARGS=--no-bt / --no-wifi: without).
	root_mount
	# shellcheck disable=SC2086
	# Profile d: btsnoop capture on from the first boot (/var/local/btbridge.snoop) for the LibrePods work.
	snoop=()
	[[ $profile == d ]] && snoop=(--snoop)
	sudo python3 -I "$port/tools/root27/tweaks27.py" --root "$root" --backup "$work/orig-$profile" "${snoop[@]}" ${TWEAKS_ARGS:-}
	cleanup
	lap tweaks
fi

if has_step finish; then
	# Linux hfsplus decomposes some non-ASCII names differently from Apple's tables: fsck_hfs rewrites them.
	fsck.hfsplus -f -y "$img" | grep -v 'Illegal name' || true
	fsck.hfsplus -f -n "$img"
	lap fsck
	# simg-hfs writes one simg about the size of the allocated blocks; img2simg -s needs a second, temporary one.
	need_disk $(( $(du -BG "$img" | cut -f1 | tr -dc 0-9) * (zero_skip + 1) ))
	rm -f "${img%.img}.simg" "${img%.img}-at16g.simg"
	if [[ $zero_skip == 1 ]]; then
		# Old way: img2simg -s makes every all-zero block DONT_CARE, also zero pages inside files, and fastboot
		# leaves the partition's old data there (the 2026-11-13 dyld cache corruption). Only for comparisons.
		img2simg -s "$img" "${img%.img}.simg"
		"$py" -I "$port/tools/root27/simg-offset.py" "${img%.img}.simg" "${img%.img}-at16g.simg" --offset 16G
		rm -f "${img%.img}.simg"
	else
		# The HFS allocation bitmap decides: allocated = RAW/FILL (written), free = DONT_CARE; then a full check.
		python3 -I "$port/tools/root27/simg-hfs.py" "$img" "${img%.img}-at16g.simg" --offset 16G
		python3 -I "$port/tools/root27/simg-hfs.py" "$img" "${img%.img}-at16g.simg" --offset 16G --verify
	fi
	ls -l "$img" "${img%.img}-at16g.simg"
	du -h "$img"
	lap sparse
fi
echo "=== $(date '+%F %T') done"
