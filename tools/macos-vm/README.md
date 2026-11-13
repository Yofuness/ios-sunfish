# macOS build VM (kernel builds without GitHub runners)

A macOS 14 (Sonoma) VM under QEMU/KVM on the Linux PC, with Xcode 15.0.1 (the same as the CI runner), used by
`tools/vm-build-xnu.sh`. The scripts live here; the VM's data lives outside git in `$MACOS_VM_DIR`
(default `~/VMs/macos`): the disk `mac_hdd.qcow2`, `OVMF_VARS.fd`, the saved state `state.zst`, the SSH key
(`id_ed25519`, `known_hosts`) and `credentials` (mode 600: the `builder` login password and the VNC password).
`~/VMs/macos` holds symlinks to these scripts, and `~/VMs/OSX-KVM` (kholia/OSX-KVM) gives OpenCore, OVMF and the
recovery image.

| Script | What it does |
|---|---|
| `mac-vm.sh [install\|resume]` | QEMU: 8 vCPUs as 8 cores x 1 thread, 8 GB, Skylake-Client with `tsc-frequency=2496000000` (invtsc blocks migration otherwise), VNC 0.0.0.0:5901 with a password, SSH on localhost:2222, QMP/HMP sockets, `qemu.pid` |
| `vm-start.sh` | resume from `state.zst` if present (5-15 s), else boot and pick Macintosh HD in the OpenCore picker (~30 s); sets the VNC password, pins the vCPUs, sets the guest clock |
| `vm-stop.sh [--shutdown]` | hibernate (QEMU migrates RAM + devices to `state.zst`, 5-11 s), or a real shutdown |
| `vmstate.py save\|wait` | the hibernate / resume steps over QMP |
| `vm-pin.py` | vCPU threads 1:1 on the host E-cores 4-11, other QEMU threads on the P-cores 0-3 |
| `vssh CMD` | SSH into the VM as `builder` (passwordless sudo) |
| `vm-guard.sh` | sourced by mac-vm.sh, vm-start.sh and vm-build-xnu.sh: refuses to go on while another `~/VMs/*/qemu.pid` is live |
| `vmctl.py shot\|click\|key\|type\|typepw` | screenshots and input over QMP (for the GUI-only steps) |

Setup from scratch (2026-10-28, about 2 h, mostly the macOS download): clone kholia/OSX-KVM to `~/VMs/OSX-KVM`,
`fetch-macOS-v2.py -s sonoma`, `qemu-img convert BaseSystem.dmg -O raw BaseSystem.img`,
`qemu-img create -f qcow2 mac_hdd.qcow2 128G`, copy `OVMF_VARS-1920x1080.fd` to `OVMF_VARS.fd`, symlink these
scripts into `$MACOS_VM_DIR`, `mac-vm.sh install`, then in Recovery: Terminal `diskutil eraseDisk APFS
'Macintosh HD' GPT disk2`, Reinstall macOS, the setup assistant (local account `builder`, no Apple ID), Remote
Login + passwordless sudo, auto-login (/etc/kcpassword + loginwindow autoLoginUser; sysadminctl -autologin failed with error 22), Xcode CLT, jq/gum/ninja/cmake/bash 5.2 into /usr/local (Homebrew no longer supports
Intel), and Xcode 15.0.1 from developer.apple.com (needs an Apple ID) into `/Applications/Xcode_15.0.1.app`.

## Second VM (macos15)

For xnu-12377.121.6 (iOS 26/27): macOS Sequoia 15.7 + Xcode 26.1 in `~/VMs/macos15`, set up as above (symlink these
scripts into it; its own disk, `OVMF_VARS.fd`, key, `credentials`, `qemu.pid`). Every script takes the VM from
`VM_DIR` (or `MACOS_VM_DIR`; default `~/VMs/macos`). Both VMs use the same SSH port 2222, VNC :1, host cores 4-11 and
8 GB, so only one may run: `vm-start.sh`, `mac-vm.sh` and `vm-build-xnu.sh` stop with a message when another VM's
`qemu.pid` is live (stop it with `VM_DIR=~/VMs/macos tools/macos-vm/vm-stop.sh`).

| Env | Default | Used by |
|---|---|---|
| `VM_DIR` | `~/VMs/macos` | all |
| `OSX_KVM_DIR` | `$VM_DIR/../OSX-KVM` | mac-vm.sh |
| `VM_MEM`, `VM_CPUS` | `8192` (MB), `8` | mac-vm.sh |
| `VM_SSH_PORT`, `VM_VNC` | `2222`, `1` (= :5901) | mac-vm.sh, vssh (port) |
| `VM_PIN_FIRST` | `4` (vCPU n on host core 4+n) | vm-pin.py |
| `MACOS_VERSION` | `13.5` (dxb's xnu release) | vm-build-xnu.sh |
| `XC` | `/Applications/Xcode_15.0.1.app` | vm-build-xnu.sh |
| `PATCH_DIR` | `xnu/patches` (relative to port/) | vm-build-xnu.sh |
| `KDK_MODE` | `kdk` (build.sh's own) or `fake` | vm-build-xnu.sh |

`KDK_MODE=fake` follows Bergamota's `use_kdk=false` (same dxb commit 6639065 as ours): it drops dxb's
`00_setup_coreentitlements.sh` and builds with `KDKROOT` = an empty `~/xnubuild/no-kdk`; `PATCH_DIR` must hold a
CoreEntitlements V2 stage script (`*coreentitlements*.sh`, as IOS-26-Hot's `0000-stage-coreentitlements-v2.sh`).
With `MACOS_VERSION=26.*` (or `15.*`) our patches go into dxb's `patches/26.0` (`15.0`) with a `sweet-` prefix,
after dxb's own. Example:

    VM_DIR=~/VMs/macos15 MACOS_VERSION=26.5 XC=/Applications/Xcode_26.1.app PATCH_DIR=xnu/patches-12377 \
      KDK_MODE=fake tools/vm-build-xnu.sh 300 --stop

Apple's licence only allows macOS on Apple hardware; the user chose to run it here.
