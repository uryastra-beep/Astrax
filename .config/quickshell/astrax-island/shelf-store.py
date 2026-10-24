#!/usr/bin/env python3
"""Persistent copy-only shelf. Only managed copies are ever removed."""
import argparse, fcntl, json, os, shutil, subprocess, sys, tempfile, uuid
from pathlib import Path
from urllib.parse import urlparse, unquote

LIMIT = 8
PER_SLOT = 4

def local_path(uri):
    u = urlparse(uri)
    if u.scheme != 'file' or u.netloc not in ('', 'localhost'):
        raise ValueError('Only local files are supported')
    p = Path(unquote(u.path))
    if not p.is_absolute() or p.is_symlink() or not p.is_file():
        raise ValueError('Select a regular file, not a folder or link')
    return p

def run(root, command, values):
    root = Path(root)
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(root, 0o700)
    with (root / '.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        index = root / 'index.json'
        items = json.loads(index.read_text()) if index.exists() else []
        # Keep the flat manifest and managed file IDs, adding stable slot numbers.
        # Legacy files retain one original slot each; their copies never move.
        for position, item in enumerate(items):
            if "slot" not in item:
                item["slot"] = position
        # Keep groups packed from the top-left; managed copies and file IDs never move.
        def compact():
            slots = sorted({item['slot'] for item in items})
            positions = {slot: position for position, slot in enumerate(slots)}
            for item in items:
                item['slot'] = positions[item['slot']]
        compact()
        message = ''
        removed = []
        if command in ('add', 'add-to'):
            target = None
            if command == 'add-to':
                target = int(values[0])
                if not 0 <= target < LIMIT:
                    raise ValueError('Invalid slot')
                values = values[1:]
            else:
                occupied = {i['slot'] for i in items}
                target = next((slot for slot in range(LIMIT) if slot not in occupied), None)
                if target is None:
                    target = next((slot for slot in range(LIMIT) if sum(i['slot'] == slot for i in items) < PER_SLOT), None)

            added = 0; rejected = 0
            for uri in values:
                try:
                    p = local_path(uri)
                    if root.resolve() in p.resolve().parents:
                        continue
                    st = p.stat()
                    source = [str(p.resolve()), st.st_size, st.st_mtime_ns]
                    if any(i.get('source') == source for i in items):
                        continue
                    if target is None or sum(i['slot'] == target for i in items) >= PER_SLOT:
                        if command == 'add':
                            target = next((slot for slot in range(LIMIT) if sum(i['slot'] == slot for i in items) < PER_SLOT), None)
                        if target is None or sum(i['slot'] == target for i in items) >= PER_SLOT:
                            rejected += 1; continue
                    key = uuid.uuid4().hex
                    tmp = Path(tempfile.mkdtemp(prefix='.incoming-', dir=root))
                    try:
                        shutil.copy2(p, tmp / p.name)
                        os.replace(tmp, root / key)
                    except BaseException:
                        shutil.rmtree(tmp, ignore_errors=True)
                        raise
                    saved = root / key / p.name
                    items.append(dict(id=key, name=p.name, path=str(saved), uri=saved.as_uri(), size=saved.stat().st_size, source=source, slot=target))
                    added += 1
                except (OSError, ValueError):
                    rejected += 1
            message = ('Saved: ' + str(added)) if added else 'No files added'
            if rejected:
                message += ' · Maximum 4 per slot or file unavailable'
        elif command in ('remove', 'copy'):
            identifier = values[0]
            if identifier.startswith('group-'):
                first = next((i for i in items if i['id'] == identifier[6:]), None)
                selected = [i for i in items if first and i['slot'] == first['slot']]
            elif identifier.startswith('slot-'):
                slot = int(identifier[5:])
                selected = [i for i in items if i['slot'] == slot]
            else:
                selected = [i for i in items if i['id'] == identifier]
            if not selected:
                raise ValueError('File not found')
            for item in selected:
                key = item['id']
                if len(key) != 32 or any(c not in '0123456789abcdef' for c in key):
                    raise ValueError('Invalid identifier')
                managed = root / key
                p = Path(item['path'])
                if p.parent != managed or not p.is_file():
                    raise ValueError('The saved copy is unavailable')
            if command == 'remove':
                keys = {i['id'] for i in selected}
                items = [i for i in items if i['id'] not in keys]
                removed = [root / key for key in keys]
                message = 'Group removed from shelf'
            else:
                uris = ''.join(Path(i['path']).as_uri() + '\r\n' for i in selected)
                subprocess.run(['wl-copy', '--type', 'text/uri-list'], input=uris.encode(), check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                message = str(len(selected)) + ' file(s) copied · ready to paste'
        elif command != 'list':
            raise ValueError('Invalid operation')
        compact()
        temp = root / 'index.json.new'
        temp.write_text(json.dumps(items, ensure_ascii=False))
        os.chmod(temp, 0o600)
        os.replace(temp, index)
        for managed in removed:
            shutil.rmtree(managed, ignore_errors=True)
        groups = []
        for slot in range(LIMIT):
            files = [i for i in items if i['slot'] == slot]
            if files:
                groups.append(dict(id='group-' + files[0]['id'], slot=slot, files=files,
                                   name=files[0]['name'] if len(files) == 1 else str(len(files)) + ' files',
                                   uri=files[0]['uri']))
        return dict(items=groups, message=message)

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', default=str(Path(os.environ.get('XDG_DATA_HOME', str(Path.home()/'.local/share'))) / 'astrax-island' / 'shelf'))
    ap.add_argument('command', choices=['list','add','add-to','remove','copy'])
    ap.add_argument('values', nargs='*')
    args = ap.parse_args()
    try:
        result = run(args.root, args.command, args.values)
    except Exception as e:
        result = dict(error=str(e), message='Could not complete the operation')
    print(json.dumps(result, ensure_ascii=False))
