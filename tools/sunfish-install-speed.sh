#!/bin/bash
# Speed defaults, the on-phone parts (docs/setup.md step 6): a bundle whose defaults are SWEET_DEADFILL 3 and
# M2V_SHADOW_CACHE 1, so /var/local/mtl2-env drops those two lines; Control Center's backdrop scale; luma boost off in
# backboardd (lb0-lb3, smoothness.md); TU_FETCH_GMEM_MIN_DRAWS=20 was in mtl2-env (Control Center about +1 swap/s, cs4; removed 2026-11-03: G8, video drawn in bands;
# off: delete the line); SWEET_SURF_FLUSH=1 (skip the surface cache flush at completion, sf runs, heat only; off: delete
# the line); SWEET_CULL=3 (cover cull: draws hidden under an opaque blurred backdrop are skipped, Control Center +1.8
# swaps/s, cv runs; off: delete the line); the PowerLog, CoreDuet and Biome data moved aside. The A55 default (xnu 0260) comes with the kernel, not from here.
#   tools/sunfish-install-speed.sh           needs work/metal2-next (METAL2_VARIANT=next tools/build-metal2-linux.sh)
#   tools/sunfish-install-speed.sh --undo    bundle, mtl2-env and backdrop back; the moved data stays moved
# Safe to run twice: the first run's backup and the bundle's one level of undo stay. Reboot to apply; doesn't reboot.
set -uo pipefail
cd "$(dirname "$0")/.."
S=tools/sunfish-ssh
E=/var/local/mtl2-env EB=/var/local/mtl2-env.pre-speed M=/var/local/speed-bundle-installed DB=/var/local/idlefix-db
BUNDLE=work/metal2-next/out/phone/metal2/out
fail=0
step() { echo "== $1"; shift; "$@" || { echo "FAILED: $*"; fail=1; }; }

env_off() {
	$S "[ -f $EB ] || if [ -f $E ]; then cp -p $E $EB; else : > $EB; fi; [ -f $EB ] || exit 1
		grep -vE '^(SWEET_DEADFILL|M2V_SHADOW_CACHE|TU_FETCH_GMEM_MIN_DRAWS|SWEET_SURF_FLUSH|SWEET_CULL)=' $E > $E.new 2>/dev/null; printf 'SWEET_SURF_FLUSH=1\nSWEET_CULL=3\n' >> $E.new
		cat $E.new > $E && rm -f $E.new
		echo '$E now:'; cat $E"
}
env_undo() {
	$S "[ -f $EB ] || { echo 'no backup, $E left as is'; exit 0; }; cat $EB > $E && rm -f $EB; echo '$E now:'; cat $E"
}
bundle_on() {
	if $S "[ -e $M ]"; then echo "already installed; --undo first to install again"; return 0; fi
	tools/sunfish-metal2-install.sh "$BUNDLE" --no-restart && $S ": > $M"
}
bundle_undo() {
	if ! $S "[ -e $M ]"; then echo "not installed by this script, bundle left as is"; return 0; fi
	tools/sunfish-metal2-install.sh --undo --no-restart && $S "rm -f $M"
}
# Check first: tools/sunfish-idlefix-db.sh pauses the daemons before it finds out there is nothing to do.
db_on() {	# NAME [--biome]
	if $S "[ -e $DB/$1 ]"; then echo "already moved: $DB/$1"; return 0; fi
	tools/sunfish-idlefix-db.sh ${2:-}
}

$S true || { echo "phone not reachable over SSH; nothing done" >&2; exit 1; }
case "${1:-}" in
--undo)
	step "bundle back" bundle_undo
	step "mtl2-env back" env_undo
	step "Control Center backdrop back" tools/sunfish-install-ccscale.sh --undo
	step "luma boost back" tools/sunfish-install-caenv.sh --undo
	# The moved data stays moved: it burned a core each at idle. `tools/sunfish-idlefix-db.sh [--biome] --undo` brings it back.
	echo "PowerLog, CoreDuet and Biome data left moved aside (idle heat fix)"
	;;
"")
	[ -s "$BUNDLE/SweetMetal2.bundle/SweetMetal2" ] || { echo "no $BUNDLE: METAL2_VARIANT=next tools/build-metal2-linux.sh" >&2; exit 1; }
	step "mtl2-env: SWEET_DEADFILL and M2V_SHADOW_CACHE lines out, (no TU_FETCH_GMEM_MIN_DRAWS: G8) SWEET_SURF_FLUSH=1 SWEET_CULL=3 in" env_off
	step "bundle $BUNDLE" bundle_on
	step "Control Center backdrop" tools/sunfish-install-ccscale.sh
	step "luma boost off" tools/sunfish-install-caenv.sh CA_DISABLE_LUMA_BOOST=1
	step "PowerLog and CoreDuet moved" db_on powerlog
	step "Biome moved" db_on biome --biome
	;;
*) echo "usage: tools/sunfish-install-speed.sh [--undo]" >&2; exit 2 ;;
esac
[ $fail = 0 ] && echo "done; reboot to apply" || echo "some steps FAILED, see above; rerun after fixing them"
exit $fail
