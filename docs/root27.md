# iOS 27.2.1 root image (stage 4)

How the iOS 27.2.1 (24B156, iPhone12,1) root for kernel301+ is built on the Linux host. Design and why:
research/notes/root27-pipeline-2026-11-13.md; results in [features/ios26.md](features/ios26.md). Everything it makes is out of
git (Apple's files). Nothing here touches the phone.

## Needs
- `../restore/ipsw/iPhone12,1_27.2.1_24B156_Restore.ipsw` (sha1 in iphone12,1.sha1), `ipsw` (3.1.739), apfs-fuse,
  hfsprogs (mkfs.hfsplus, fsck.hfsplus), rsync, img2simg (android-tools), passwordless sudo (loop + FUSE mounts).
- The dyld cache proof: `tools/ios27-pac/prove-cache.py` (README there) -> `../restore/ipsw/x/24B156/prove/summary.json`.
- `work/venv-pac` (capstone 5.0.7 + numpy) and llvm-mc on PATH.

## Build
```sh
tools/mkiosroot27.sh --profile c1          # first-launchd root, 13G image (~11 GB content)
tools/mkiosroot27.sh                       # full root, 28G image
tools/mkiosroot27.sh --profile c1 --steps rewrite,finish    # redo one part
```
Steps (log in `../restore/root27/build-PROFILE.log`):
1. **extract**: `ipsw extract --dmg fs|sys|app` into `../restore/ipsw/x/24B156/root-src/24B156__iPhone12,1/`, then
   `ipsw fw aea` decrypts the two .aea dmgs: SystemOS with the key from `ipsw extract --fcs-key` (saved as .pem), the OS dmg
   with the key ipsw fetches from Apple's wkms server (network), saved as `.aea.key` for offline re-runs. The IPSW's
   `Firmware/*.trustcache` go to `root-src/trustcache/` (the rewriters copy the original entries' attributes from them).
2. **image**: sparse file, `mkfs.hfsplus -s -J -v iOSRoot`, loop mount (force), `rsync -aH --numeric-ids` of the OS root
   to /, SystemOS to /private/preboot/Cryptexes/OS, AppOS to .../App. The OS root already has the
   /System/Cryptexes/{OS,App} links. The shared cache is hard-linked into /System/Library/Caches/com.apple.dyld
   (ignition level 1 looks there) and every cryptex file without an OS counterpart into /. First boot: logd stores
   (owner 272 + .migrated), plain-plist system keybag, launchd.plist `_PanicOnCrash` renamed (`--keep-panic-on-crash` off).
   The c1 profile leaves out /Applications, staged_system_apps, firmware, watch/health/Siri assets, 16 big resource
   frameworks and *.loctable/*.car/*.mov/*.weights/*.hwx/*.metallib (list `C1_EXCLUDES`), plus the cache's .symbols.
3. **rewrite** (in the mounted image, as root):
   - dyld cache: zeta `rewrite-zeta-dyld-cache.py` with the proof (lowered PAC words, CodeDirectories re-hashed,
     corecrypto `__fips_hmacs` refilled), staged outside the image, then written into the existing files
     (`tools/root27/apply-rewrites.py cache`, original SHA-256 checked first). No `--page-shift` (cache pages are 16 KiB like
     the kernel's). Images whose proof failed (WebCore, MLIR_ML: OOM) keep their PAC words.
   - every other thin arm64e Mach-O: `tools/root27/rewrite-zeta-userland-tree.py` (zeta's, vendored, with
     tools/ios27-pac/sunfish_pac.py's TPRO and noreturn-end fixes, without which 27's dyld is refused; per-image proof,
     lowering, header -> arm64 ALL, ad hoc re-hash, platform id 26, CS_RUNTIME on executables), applied in place; the
     originals go to `../restore/root27/orig-PROFILE/`. Reports: `../restore/root27/reports-PROFILE/{cache,tree}.json`.
4. **finish**: `fsck.hfsplus -fy` (Linux name decomposition), `fsck.hfsplus -fn`, `img2simg -s` (free space = DONT_CARE),
   and `tools/root27/simg-offset.py --offset 16G` -> `root27-PROFILE-at16g.simg`.

## Writing it (destructive, needs the user's OK first; not done by the script)
`fastboot -S 256M flash userdata ../restore/root27/root27-c1-at16g.simg` writes the image at userdata byte 16 GiB, the start
of /dev/ufsroot1 (iOS 16's /var region, 1185): the first 16 GiB (iOS 16's root) are DONT_CARE. Back up /var/local first.
Boot with kernel302+ and `rd=ufsroot1` (1290); iOS 16 then needs `sweetnofstab=1`. See the pipeline note, section 5.
