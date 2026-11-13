#!/usr/bin/env python3
"""SSH and Bluetooth for the iOS 27 root (Gate C2, stage 6): the iOS 16 setups (tools/sunfish-install-ssh.sh,
tools/sunfish-install-btbridge.sh), applied offline to the loop-mounted root image, as root (mkiosroot27.sh step
"tweaks", docs/root27.md).

  sudo python3 -I tools/root27/tweaks27.py --root MNT [--bin DIR] [--keys DIR] [--btfw DIR] [--backup DIR]
                                           [--wififw DIR] [--no-ssh] [--no-bt] [--no-wifi] [--remove]

Installs into the image:
- /var/local/bin/{dropbearmulti,dash,toybox} from work/userland-linux/out (tools/build-userland-linux.sh; plain
  arm64, ad hoc signed, link only libSystem (toybox: + libiconv/libresolv/libutil/libz, all in the 27 cache)),
  dropbear/dropbearkey/scp/dbclient and the toybox applets as symlinks; /bin/sh = a copy of dash (27 has none;
  root's shell in /etc/passwd is /bin/sh).
- /private/etc/dropbear (0700, host keys made by dropbear -R on the first connection, as on iOS 16),
  /var/root/.ssh/authorized_keys = work/userland/ssh/*.pub, /var/root/.profile.
- The launchd job org.iosonpixel.dropbear (the same dict as iOS 16) in /System/Library/xpc/launchd.plist's
  LaunchDaemons: launchd_cache_loader 27 reads that file without its .sig under launchd_unsecure_cache=1 (k315a:
  "Using unsecure cache: /System/Library/xpc/launchd.plist", "Cache sent to launchd successfully").
No network job: the kernel brings ue0 up as 192.168.7.2/24 (patch 0075).
Bluetooth (--bt part, default on; --no-bt leaves it out):
- /var/local/bin/{btbridge,bluetool-stub} from --bin (plain arm64, ad hoc, libSystem only), btctl (Bluetooth CLI: power,
  scan, pair, connect without Settings; Foundation + MobileBluetooth by dlopen, signed with phone/tools/btctl-ents.plist)
  and the WCN3990 firmware
  crbtfw21.tlv + crnv21.bin into /var/local/fw/bt (--btfw: the iOS 16 /var backup or ../restore/fw/vendor/bt; Qualcomm
  firmware, image only, never git). No /var/local/btbridge.snoop: btsnoop capture stays off (touch it to turn it on).
- launchd.plist as on iOS 16: com.apple.BlueTool ProgramArguments [/usr/sbin/BlueTool, -R] -> [bluetool-stub]
  (MachService com.apple.BlueTool kept); com.apple.bluetoothd env BT_HCI_TRANSPORT=H4BC:POSIX:com.apple.uart.bluetooth,
  115200 + BT_BAUDRATE=115200 (bluetoothd 27 reads both, research/notes/donor-census-2026-11-13.md s4); job
  org.iosonpixel.btbridge. Needs the kernel's /dev/btbridge + kctl (xnu 0226, boot-arg btbridge=1) and /dev/pmem.
  Off on the phone: /var/local/btbridge.off (btbridge exits; BlueTool stays the stub).
Wi-Fi (--wifi part, default on; --no-wifi leaves it out; btbridge waits up to 60 s for wland's "modem ready"):
- /var/local/bin/{wland,netsvc} (tools/sunfish-install-wifi.sh; wland libSystem only, netsvc + Foundation/CoreFoundation/
  libobjc/SystemConfiguration), the modem + WLAN firmware into /var/local/fw/modem, the rmtfs images (modemst1/2, fsg,
  fsc: this phone's EFS, image only, never git) into /var/local/fw/rmtfs (0700), an empty /var/local/fw/rw; --wififw:
  the iOS 16 /var/local/fw backup. Job org.iosonpixel.wland (`wland auto`). No /var/local/wlan.conf (credentials stay
  on the phone; wland runs without it: no join). Off on the phone: /var/local/wland.off or boot-arg sweetwifi=0.
--remove takes the parts out again (with --no-ssh / --no-bt / --no-wifi: only the others).
"""
import argparse
import os
import plistlib
import shutil
import sys

PORT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
JOB_KEY = '/System/Library/LaunchDaemons/org.iosonpixel.dropbear.plist'
PATH = '/var/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'
JOB = {
    'Label': 'org.iosonpixel.dropbear',
    # -R: host keys on the first connection; -F foreground for launchd (no -E: syslog off; passwords compiled out)
    'ProgramArguments': ['/var/local/bin/dropbear', '-F', '-R', '-p', '22'],
    'RunAtLoad': True, 'KeepAlive': True, 'UserName': 'root',
    'ProcessType': 'Interactive', 'POSIXSpawnType': 'Interactive',
    'EnvironmentVariables': {'PATH': PATH},
}
DROPBEAR_LINKS = ['dropbear', 'dropbearkey', 'scp', 'dbclient']
# The applets tools/sunfish-install-ssh.sh links on iOS 16.
TOYBOX_APPLETS = '''ls cat cp mv rm mkdir rmdir ln chmod chown ps kill grep sed head tail wc find xargs sort uniq cut tr df du
mount uname date env id whoami hexdump od dd sleep touch stat which file tee printf echo true false test basename dirname
readlink realpath uptime free top hostname nc ping ifconfig netstat dmesg sync md5sum sha256sum tar gzip less vi'''.split()
PROFILE = f'export PATH={PATH}\nexport PS1="sunfish27# "\n'
# Bluetooth (the dicts of tools/sunfish-install-btbridge.sh)
BT_JOB_KEY = '/System/Library/LaunchDaemons/org.iosonpixel.btbridge.plist'
BT_JOB = {
    'Label': 'org.iosonpixel.btbridge',
    'ProgramArguments': ['/var/local/bin/btbridge'],
    'RunAtLoad': True, 'UserName': 'root',
    'EnvironmentVariables': {'PATH': PATH},
}
BT_ENV = {'BT_HCI_TRANSPORT': 'H4BC:POSIX:com.apple.uart.bluetooth,115200', 'BT_BAUDRATE': '115200'}
BLUETOOL_ARGS = ['/usr/sbin/BlueTool', '-R']	# the 24B156 job, put back by --remove
BT_BINS = ['btbridge', 'bluetool-stub', 'btctl']
BT_FW = ['crbtfw21.tlv', 'crnv21.bin']
WIFI_JOB_KEY = '/System/Library/LaunchDaemons/org.iosonpixel.wland.plist'
WIFI_JOB = {	# tools/sunfish-install-wifi.sh's dict
    'Label': 'org.iosonpixel.wland',
    'ProgramArguments': ['/var/local/bin/wland', 'auto'],
    'RunAtLoad': True, 'UserName': 'root',
    'ProcessType': 'Interactive', 'POSIXSpawnType': 'Interactive',
    'EnvironmentVariables': {'PATH': PATH},
}
WIFI_BINS = ['wland', 'netsvc']
RMTFS = ['modemst1.img', 'modemst2.img', 'fsg.img', 'fsc.img']	# not .buffer: one per phone boot (rmtfs.c)
WIFI_FW_DIR = os.path.normpath(os.path.join(PORT, '../backup/ios16-var-20261113/var/local/fw'))
BT_FW_DIRS = [os.path.normpath(os.path.join(PORT, d)) for d in ('../backup/ios16-var-20261113/var/local/fw/bt', '../restore/fw/vendor/bt')]


def p(root, path):
    return os.path.join(root, path.lstrip('/'))


def mkdir(root, path, mode):
    d = p(root, path)
    os.makedirs(d, exist_ok=True)
    os.chown(d, 0, 0)
    os.chmod(d, mode)


def put(root, path, data, mode):
    f = p(root, path)
    if os.path.lexists(f):
        os.unlink(f)
    with open(f, 'wb') as out:
        out.write(data)
    os.chown(f, 0, 0)
    os.chmod(f, mode)


def symlink(root, target, path):
    f = p(root, path)
    if os.path.lexists(f):
        if not os.path.islink(f):
            return False
        os.unlink(f)
    os.symlink(target, f)
    os.lchown(f, 0, 0)
    return True


def by_label(jobs, label):
    for v in jobs.values():
        if isinstance(v, dict) and v.get('Label') == label:
            return v
    sys.exit(f'no {label} job in launchd.plist')


def edit_bt(jobs, remove):
    bt, d = by_label(jobs, 'com.apple.BlueTool'), by_label(jobs, 'com.apple.bluetoothd')
    env = d.setdefault('EnvironmentVariables', {})
    if remove:
        jobs.pop(BT_JOB_KEY, None)
        if bt.get('ProgramArguments') == ['/var/local/bin/bluetool-stub']:
            bt['ProgramArguments'] = BLUETOOL_ARGS
        for k in BT_ENV:
            env.pop(k, None)
        return 'bt jobs removed'
    bt['ProgramArguments'] = ['/var/local/bin/bluetool-stub']
    bt.pop('Program', None)
    env.update(BT_ENV)
    jobs[BT_JOB_KEY] = BT_JOB
    return f'BlueTool -> bluetool-stub (MachServices {list(bt.get("MachServices", {}))}), bluetoothd env {env}, btbridge job set'


def edit_launchd(root, backup, remove, ssh, bt, wifi):
    path = p(root, '/System/Library/xpc/launchd.plist')
    st = os.stat(path)
    raw = open(path, 'rb').read()
    fmt = plistlib.FMT_BINARY if raw.startswith(b'bplist00') else plistlib.FMT_XML
    plist = plistlib.loads(raw)
    if backup:
        os.makedirs(backup, exist_ok=True)
        b = os.path.join(backup, 'launchd.plist.pre-tweaks')
        if not os.path.exists(b) and JOB_KEY not in plist['LaunchDaemons'] and BT_JOB_KEY not in plist['LaunchDaemons'] \
                and WIFI_JOB_KEY not in plist['LaunchDaemons']:
            shutil.copy2(path, b)
    said = []
    if ssh:
        if remove:
            plist['LaunchDaemons'].pop(JOB_KEY, None)
        else:
            plist['LaunchDaemons'][JOB_KEY] = JOB
        said.append(f'dropbear job {"removed" if remove else "set"}')
    if wifi:
        if remove:
            plist['LaunchDaemons'].pop(WIFI_JOB_KEY, None)
        else:
            plist['LaunchDaemons'][WIFI_JOB_KEY] = WIFI_JOB
        said.append(f'wland job {"removed" if remove else "set"}')
    if bt:
        said.append(edit_bt(plist['LaunchDaemons'], remove))
    with open(path, 'wb') as f:
        plistlib.dump(plist, f, fmt=fmt)
    os.chown(path, st.st_uid, st.st_gid)
    os.chmod(path, st.st_mode & 0o7777)
    print(f'launchd.plist: {len(plist["LaunchDaemons"])} jobs; ' + '; '.join(said))


def install_ssh(root, bindir, keydir):
    bins = {}
    for name in ['dropbearmulti', 'dash', 'toybox']:
        f = os.path.join(bindir, name)
        if not os.path.isfile(f):
            sys.exit(f'missing {f}: run tools/build-userland-linux.sh')
        bins[name] = open(f, 'rb').read()
    pubs = sorted(n for n in os.listdir(keydir) if n.endswith('.pub'))
    if not pubs:
        sys.exit(f'no *.pub in {keydir} (tools/sunfish-install-ssh.sh makes id_ed25519)')
    keys = b''.join(open(os.path.join(keydir, n), 'rb').read().rstrip(b'\n') + b'\n' for n in pubs)

    mkdir(root, '/private/var/local', 0o755)
    mkdir(root, '/private/var/local/bin', 0o755)
    for name, data in bins.items():
        put(root, '/private/var/local/bin/' + name, data, 0o755)
    for name in DROPBEAR_LINKS:
        symlink(root, 'dropbearmulti', '/private/var/local/bin/' + name)
    applets = [n for n in TOYBOX_APPLETS if symlink(root, 'toybox', '/private/var/local/bin/' + n)]
    if not os.path.lexists(p(root, '/bin/sh')):
        put(root, '/bin/sh', bins['dash'], 0o755)
    mkdir(root, '/private/etc/dropbear', 0o700)
    mkdir(root, '/private/var/root/.ssh', 0o700)
    put(root, '/private/var/root/.ssh/authorized_keys', keys, 0o600)
    put(root, '/private/var/root/.profile', PROFILE.encode(), 0o644)
    print(f'/var/local/bin: dropbearmulti dash toybox + {len(DROPBEAR_LINKS)} dropbear links, {len(applets)} applets; '
          f'/bin/sh = dash; authorized_keys from {", ".join(pubs)}')



def install_bt(root, bindir, fwdir):
    data = {}
    for name in BT_BINS:
        f = os.path.join(bindir, name)
        if not os.path.isfile(f):
            sys.exit(f'missing {f}: run tools/build-userland-linux.sh')
        data[name] = open(f, 'rb').read()
    fw = {}
    for name in BT_FW:
        f = os.path.join(fwdir, name)
        if not os.path.isfile(f):
            sys.exit(f'missing {f}: the BT firmware (tools/sunfish-install-bt.sh extracts it from vendor.img)')
        fw[name] = open(f, 'rb').read()
    mkdir(root, '/private/var/local', 0o755)
    mkdir(root, '/private/var/local/bin', 0o755)
    mkdir(root, '/private/var/local/fw', 0o755)
    mkdir(root, '/private/var/local/fw/bt', 0o755)
    for name, b in data.items():
        put(root, '/private/var/local/bin/' + name, b, 0o755)
    for name, b in fw.items():
        put(root, '/private/var/local/fw/bt/' + name, b, 0o644)
    print(f'/var/local/bin: {" ".join(BT_BINS)}; /var/local/fw/bt: ' +
          ', '.join(f'{n} {len(b)} B' for n, b in fw.items()) + f' (from {fwdir}); btsnoop off')


def install_wifi(root, bindir, fwdir):
    data = {}
    for name in WIFI_BINS:
        f = os.path.join(bindir, name)
        if not os.path.isfile(f):
            sys.exit(f'missing {f}: run tools/build-userland-linux.sh')
        data[name] = open(f, 'rb').read()
    modem = sorted(n for n in os.listdir(os.path.join(fwdir, 'modem')) if os.path.isfile(os.path.join(fwdir, 'modem', n)))
    for n in ['modem.mdt', 'wlanmdsp.mbn', 'bdwlan-sunfish.bin']:
        if n not in modem:
            sys.exit(f'missing {fwdir}/modem/{n}')
    for n in RMTFS:
        if not os.path.isfile(os.path.join(fwdir, 'rmtfs', n)):
            sys.exit(f'missing {fwdir}/rmtfs/{n}')
    for d in ['/private/var/local', '/private/var/local/bin', '/private/var/local/fw', '/private/var/local/fw/modem',
              '/private/var/local/fw/rw']:
        mkdir(root, d, 0o755)
    mkdir(root, '/private/var/local/fw/rmtfs', 0o700)
    for name, b in data.items():
        put(root, '/private/var/local/bin/' + name, b, 0o755)
    size = 0
    for n in modem:
        b = open(os.path.join(fwdir, 'modem', n), 'rb').read()
        size += len(b)
        put(root, '/private/var/local/fw/modem/' + n, b, 0o644)
    for n in RMTFS:
        put(root, '/private/var/local/fw/rmtfs/' + n, open(os.path.join(fwdir, 'rmtfs', n), 'rb').read(), 0o600)
    print(f'/var/local/bin: {" ".join(WIFI_BINS)}; /var/local/fw/modem: {len(modem)} files {size} B, '
          f'/var/local/fw/rmtfs: {" ".join(RMTFS)} (from {fwdir}); no wlan.conf')


def remove_wifi(root):
    for f in ['/private/var/local/bin/' + n for n in WIFI_BINS] + ['/private/var/local/fw/rmtfs/' + n for n in RMTFS]:
        if os.path.lexists(p(root, f)):
            os.unlink(p(root, f))
    d = p(root, '/private/var/local/fw/modem')
    if os.path.isdir(d):
        shutil.rmtree(d)
    for d in ['/private/var/local/fw/rmtfs', '/private/var/local/fw/rw', '/private/var/local/fw']:
        if os.path.isdir(p(root, d)) and not os.listdir(p(root, d)):
            os.rmdir(p(root, d))


def remove_bt(root):
    for f in ['/private/var/local/bin/' + n for n in BT_BINS] + ['/private/var/local/fw/bt/' + n for n in BT_FW]:
        if os.path.lexists(p(root, f)):
            os.unlink(p(root, f))
    for d in ['/private/var/local/fw/bt', '/private/var/local/fw']:
        if os.path.isdir(p(root, d)) and not os.listdir(p(root, d)):
            os.rmdir(p(root, d))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--root', required=True, help='mounted root image')
    ap.add_argument('--bin', default=os.path.join(PORT, 'work/userland-linux/out'))
    ap.add_argument('--keys', default=os.path.join(PORT, 'work/userland/ssh'))
    ap.add_argument('--btfw', help='BT firmware directory (default: the first of %s)' % ', '.join(BT_FW_DIRS))
    ap.add_argument('--wififw', default=WIFI_FW_DIR, help='directory with modem/ and rmtfs/ (default: %(default)s)')
    ap.add_argument('--backup', help='host directory for launchd.plist.pre-tweaks (once)')
    ap.add_argument('--no-ssh', action='store_true', help='leave the SSH part alone')
    ap.add_argument('--no-bt', action='store_true', help='leave the Bluetooth part alone')
    ap.add_argument('--no-wifi', action='store_true', help='leave the Wi-Fi (wland) part alone')
    ap.add_argument('--remove', action='store_true', help='take the jobs and files out again')
    a = ap.parse_args()
    root = a.root
    if not os.path.isfile(p(root, '/System/Library/xpc/launchd.plist')):
        sys.exit(f'{root}: no /System/Library/xpc/launchd.plist (not a mounted root?)')
    if os.geteuid() != 0:
        sys.exit('run as root (sudo)')
    ssh, bt, wifi = not a.no_ssh, not a.no_bt, not a.no_wifi

    if a.remove:
        if ssh:
            for name in DROPBEAR_LINKS + TOYBOX_APPLETS + ['dropbearmulti', 'dash', 'toybox']:
                f = p(root, '/private/var/local/bin/' + name)
                if os.path.lexists(f):
                    os.unlink(f)
            for f in ['/bin/sh', '/private/var/root/.ssh/authorized_keys', '/private/var/root/.profile']:
                if os.path.lexists(p(root, f)):
                    os.unlink(p(root, f))
        if bt:
            remove_bt(root)
        if wifi:
            remove_wifi(root)
        edit_launchd(root, a.backup, True, ssh, bt, wifi)
        return

    if bt:
        fwdir = a.btfw or next((d for d in BT_FW_DIRS if os.path.isfile(os.path.join(d, BT_FW[0]))), BT_FW_DIRS[0])
        install_bt(root, a.bin, fwdir)
    if wifi:
        install_wifi(root, a.bin, a.wififw)
    if ssh:
        install_ssh(root, a.bin, a.keys)
    edit_launchd(root, a.backup, False, ssh, bt, wifi)


if __name__ == '__main__':
    main()
