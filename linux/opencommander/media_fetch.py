"""Read-only helper isolating slow FUSE reads from the Qt process."""
import json
import os
import sys


def fetch(source, target, limit, report):
    transferred = 0
    with open(source, 'rb') as inp, open(target, 'xb') as out:
        os.chmod(target, 0o600)
        while True:
            block = inp.read(min(1024 * 1024, limit - transferred + 1))
            if not block:
                break
            transferred += len(block)
            if transferred > limit:
                raise ValueError('Online media exceeds preview download limit')
            out.write(block)
            report(transferred)
    return transferred


if __name__ == '__main__':
    request = json.load(sys.stdin)
    def report(count):
        print(json.dumps({'bytes': count}), flush=True)
    try:
        count = fetch(request['source'], request['target'], request['limit'], report)
        print(json.dumps({'done': True, 'bytes': count}), flush=True)
    except Exception:
        # Never echo provider errors which could contain credentials.
        print(json.dumps({'error': 'Online-Medium konnte nicht geladen werden. Verbindung, Leserechte und Dateigröße prüfen. / Could not download online media.'}), flush=True)
        sys.exit(1)
