#!/usr/bin/env python3
"""SSH for the iOS 27 root (Gate C2): the iOS 16 setup (tools/sunfish-install-ssh.sh), applied offline to the
loop-mounted root image, as root (mkiosroot27.sh step "tweaks", docs/root27.md).

  sudo python3 -I tools/root27/tweaks27.py --root MNT [--bin DIR] [--keys DIR] [--backup DIR] [--remove]

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
No network job: the kernel brings ue0 up as 192.168.7.2/24 (patch 0075). --remove takes all of it out again.
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


def edit_launchd(root, backup, remove):
    path = p(root, '/System/Library/xpc/launchd.plist')
    st = os.stat(path)
    raw = open(path, 'rb').read()
    fmt = plistlib.FMT_BINARY if raw.startswith(b'bplist00') else plistlib.FMT_XML
    plist = plistlib.loads(raw)
    if backup:
        os.makedirs(backup, exist_ok=True)
        b = os.path.join(backup, 'launchd.plist.pre-tweaks')
        if not os.path.exists(b) and JOB_KEY not in plist['LaunchDaemons']:
            shutil.copy2(path, b)
    if remove:
        plist['LaunchDaemons'].pop(JOB_KEY, None)
    else:
        plist['LaunchDaemons'][JOB_KEY] = JOB
    with open(path, 'wb') as f:
        plistlib.dump(plist, f, fmt=fmt)
    os.chown(path, st.st_uid, st.st_gid)
    os.chmod(path, st.st_mode & 0o7777)
    print(f'launchd.plist: {len(plist["LaunchDaemons"])} jobs, dropbear job {"removed" if remove else "set"}')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--root', required=True, help='mounted root image')
    ap.add_argument('--bin', default=os.path.join(PORT, 'work/userland-linux/out'))
    ap.add_argument('--keys', default=os.path.join(PORT, 'work/userland/ssh'))
    ap.add_argument('--backup', help='host directory for launchd.plist.pre-tweaks (once)')
    ap.add_argument('--remove', action='store_true', help='take the SSH job and files out again')
    a = ap.parse_args()
    root = a.root
    if not os.path.isfile(p(root, '/System/Library/xpc/launchd.plist')):
        sys.exit(f'{root}: no /System/Library/xpc/launchd.plist (not a mounted root?)')
    if os.geteuid() != 0:
        sys.exit('run as root (sudo)')

    if a.remove:
        for name in DROPBEAR_LINKS + TOYBOX_APPLETS + ['dropbearmulti', 'dash', 'toybox']:
            f = p(root, '/private/var/local/bin/' + name)
            if os.path.lexists(f):
                os.unlink(f)
        for f in ['/bin/sh', '/private/var/root/.ssh/authorized_keys', '/private/var/root/.profile']:
            if os.path.lexists(p(root, f)):
                os.unlink(p(root, f))
        edit_launchd(root, a.backup, True)
        return

    bins = {}
    for name in ['dropbearmulti', 'dash', 'toybox']:
        f = os.path.join(a.bin, name)
        if not os.path.isfile(f):
            sys.exit(f'missing {f}: run tools/build-userland-linux.sh')
        bins[name] = open(f, 'rb').read()
    pubs = sorted(n for n in os.listdir(a.keys) if n.endswith('.pub'))
    if not pubs:
        sys.exit(f'no *.pub in {a.keys} (tools/sunfish-install-ssh.sh makes id_ed25519)')
    keys = b''.join(open(os.path.join(a.keys, n), 'rb').read().rstrip(b'\n') + b'\n' for n in pubs)

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
    edit_launchd(root, a.backup, False)


if __name__ == '__main__':
    main()
