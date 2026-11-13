#!/usr/bin/env python3
"""Write zeta's rewritten files back into a mounted root image, in place.

  apply-rewrites.py cache REPORT.json STAGING_DIR CACHE_DIR
  apply-rewrites.py tree  REPORT.json STAGING_DIR ROOT [--backup DIR]

cache: REPORT is rewrite-zeta-dyld-cache.py's --report, STAGING_DIR its --output.
Every file with edits or FIPS seals overwrites CACHE_DIR/NAME (the cryptex copy;
the /System/Library/Caches/com.apple.dyld name is a hard link to the same file),
after its SHA-256 is checked against the report's original_sha256. Unchanged
files are skipped.

tree: REPORT is rewrite-zeta-userland-tree.py's --report. Each image's paths
under ROOT must still hash to input_sha256; the first path is overwritten (hard
links share it), any other path that is a separate inode too. --backup keeps the
originals outside the image, under their root path.

Writes go into the existing inode (owner, mode and hard links stay). Run as
root (tools/mkiosroot27.sh does it with sudo). Prints counts as JSON.
"""
import hashlib, json, os, shutil, sys

CHUNK = 8 << 20


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        while block := f.read(CHUNK):
            h.update(block)
    return h.hexdigest()


def overwrite(target, source):
    with open(source, 'rb') as src, open(target, 'r+b') as dst:
        while block := src.read(CHUNK):
            dst.write(block)
        dst.truncate()


def cache(report, staging, cache_dir):
    done = skipped = 0
    for f in report['files']:
        if not f['edits'] and not f.get('fips_seals'):
            skipped += 1
            continue
        target = os.path.join(cache_dir, f['name'])
        have = sha256(target)
        if have == f['sha256']:
            skipped += 1          # already rewritten (re-run)
            continue
        if have != f['original_sha256']:
            sys.exit(f'{target}: not the file the rewrite read')
        overwrite(target, os.path.join(staging, f['name']))
        done += 1
        print(f'{f["name"]}: {f["edits"]} edits, {len(f.get("fips_seals", []))} FIPS seals', file=sys.stderr)
    return dict(cache_files_written=done, cache_files_unchanged=skipped, cache_edits=report['edits'])


def tree(report, staging, root, backup):
    files = paths = 0
    for image in report['images']:
        source = os.path.join(staging, image['output'].lstrip('/'))
        seen = set()
        for path in image['paths']:
            target = os.path.join(root, path.lstrip('/'))
            st = os.lstat(target)
            if (st.st_dev, st.st_ino) in seen:
                continue
            seen.add((st.st_dev, st.st_ino))
            have = sha256(target)
            if have == image['output_sha256']:
                continue
            if have != image['input_sha256']:
                sys.exit(f'{target}: not the file the rewrite read')
            if backup:
                keep = os.path.join(backup, path.lstrip('/'))
                os.makedirs(os.path.dirname(keep), exist_ok=True)
                shutil.copy2(target, keep)
            overwrite(target, source)
            files += 1
        paths += len(image['paths'])
    return dict(tree_files_written=files, tree_paths=paths, tree_images=len(report['images']),
                tree_failures=len(report['failures']), tree_edits=report['totals']['instruction_edits'])


def main():
    a = sys.argv[1:]
    backup = None
    if '--backup' in a:
        i = a.index('--backup')
        backup = a[i + 1]
        del a[i:i + 2]
    if len(a) != 4 or a[0] not in ('cache', 'tree'):
        sys.exit(__doc__)
    with open(a[1]) as f:
        report = json.load(f)
    result = cache(report, a[2], a[3]) if a[0] == 'cache' else tree(report, a[2], a[3], backup)
    print(json.dumps(result))


if __name__ == '__main__':
    main()
