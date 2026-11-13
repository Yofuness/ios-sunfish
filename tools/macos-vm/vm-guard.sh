# Sourced by mac-vm.sh, vm-start.sh and tools/vm-build-xnu.sh with D = this VM's data dir.
# Two-VM guard: every VM in ~/VMs/* uses the same SSH port 2222, VNC :1, host cores 4-11 and 8 GB by default, so
# refuse to go on while ANOTHER VM's qemu.pid names a live process (our own VM's pid is the caller's business).
vm_guard() {
	local me other p f
	me=$(readlink -f "$D")
	for f in "${VMS_ROOT:-$HOME/VMs}"/*/qemu.pid; do
		[ -f "$f" ] || continue
		other=$(readlink -f "$(dirname "$f")")
		[ "$other" = "$me" ] && continue
		p=$(cat "$f" 2>/dev/null)
		if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
			echo "another build VM is running: $other (qemu pid $p); only one VM may run at a time." >&2
			echo "stop it first: VM_DIR=$other tools/macos-vm/vm-stop.sh" >&2
			return 1
		fi
	done
	return 0
}
